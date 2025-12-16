//
//  GoToRLinkHandler.swift
//  QualicoPDFMarkup
//
//  Handles GoToR (Go To Remote file) PDF hyperlinks
//  These links reference external PDF files and are not natively supported by PDFKit
//

import Foundation
import PDFKit

/// Information about a GoToR link extracted from PDF annotation
struct GoToRLinkInfo {
    let annotation: PDFAnnotation
    let page: PDFPage
    let targetFilename: String
    let destinationPage: Int
    let destinationView: String
    let rect: CGRect
}

/// Handles detection and extraction of GoToR (remote file) links from PDF annotations
class GoToRLinkHandler {

    // MARK: - Link Detection

    /// Checks if an annotation has a valid GoToR action (link to external file)
    /// PDFKit doesn't natively expose GoToR actions, so we parse the annotation dictionary
    static func hasGoToRAction(_ annotation: PDFAnnotation) -> Bool {
        return extractTargetFilename(from: annotation) != nil
    }

    /// Extracts the target filename from a GoToR link annotation
    /// Returns nil if this is not a GoToR link or if extraction fails
    static func extractTargetFilename(from annotation: PDFAnnotation) -> String? {
        // Method 1: Check annotation's action object
        if let action = annotation.action {
            // Try PDFActionRemoteGoTo (if available in this iOS version)
            // Note: PDFActionRemoteGoTo.url can crash due to nil NSURL bridging,
            // so we check responds(to:) and use performSelector for safety
            if let remoteAction = action as? PDFActionRemoteGoTo {
                let urlSelector = NSSelectorFromString("url")
                if remoteAction.responds(to: urlSelector),
                   let url = remoteAction.perform(urlSelector)?.takeUnretainedValue() as? URL {
                    return url.lastPathComponent
                }
            }
        }

        // Method 2: Parse the raw annotation dictionary
        // GoToR actions store the file reference in the /A dictionary with /S /GoToR
        if let annotDict = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/A")) {
            return extractFilenameFromActionDict(annotDict)
        }

        // Method 3: Try getting the action dictionary directly via annotationKeyValues
        // The action may be embedded or referenced
        if let keyValues = annotation.annotationKeyValues as? [PDFAnnotationKey: Any] {
            for (key, value) in keyValues {
                if key.rawValue == "/A" || key.rawValue == "A" {
                    if let filename = extractFilenameFromActionDict(value) {
                        return filename
                    }
                }
            }
        }

        // Method 4: Check if there's a direct file specification
        if let fileSpec = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/F")) {
            return extractFilenameFromFileSpec(fileSpec)
        }

        // Method 5: Try to access via action property paths (with safe KVC)
        if let action = annotation.action {
            // Use KVC to try to get file-related properties (safely)
            if action.responds(to: Selector(("URL"))) {
                if let urlValue = action.value(forKey: "URL") as? URL {
                    return urlValue.lastPathComponent
                }
            }
            if action.responds(to: Selector(("url"))) {
                if let urlValue = action.value(forKey: "url") as? URL {
                    return urlValue.lastPathComponent
                }
            }
        }

        return nil
    }

    /// Extracts filename from an action dictionary
    private static func extractFilenameFromActionDict(_ actionDict: Any) -> String? {
        // If it's a dictionary, look for /F (FileSpec) or /File
        if let dict = actionDict as? [String: Any] {
            // Check for /S /GoToR first to confirm it's a remote goto action
            if let actionType = dict["S"] as? String, actionType != "/GoToR" && actionType != "GoToR" {
                return nil
            }

            // Look for /F (file specification)
            if let fileSpec = dict["F"] {
                return extractFilenameFromFileSpec(fileSpec)
            }

            // Some PDFs use /File instead of /F
            if let fileSpec = dict["File"] {
                return extractFilenameFromFileSpec(fileSpec)
            }
        }

        // If it's a PDFKit dictionary representation
        if let dict = actionDict as? [AnyHashable: Any] {
            for (key, value) in dict {
                let keyStr = String(describing: key)
                if keyStr.contains("F") || keyStr.contains("File") {
                    if let filename = extractFilenameFromFileSpec(value) {
                        return filename
                    }
                }
            }
        }

        return nil
    }

    /// Extracts filename from a file specification object
    private static func extractFilenameFromFileSpec(_ fileSpec: Any) -> String? {
        // FileSpec can be a simple string (filename)
        if let filename = fileSpec as? String {
            return filename
        }

        // Or a dictionary with /F and /UF keys
        if let dict = fileSpec as? [String: Any] {
            // /UF is Unicode filename (preferred)
            if let uf = dict["UF"] as? String {
                return uf
            }
            // /F is ASCII filename
            if let f = dict["F"] as? String {
                return f
            }
        }

        if let dict = fileSpec as? [AnyHashable: Any] {
            for (key, value) in dict {
                let keyStr = String(describing: key)
                if keyStr.contains("UF") || keyStr == "F" || keyStr == "/F" {
                    if let str = value as? String {
                        return str
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Full Link Info Extraction

    /// Extracts complete GoToR link information from an annotation
    static func extractLinkInfo(from annotation: PDFAnnotation, on page: PDFPage) -> GoToRLinkInfo? {
        guard let targetFilename = extractTargetFilename(from: annotation) else {
            return nil
        }

        // Extract destination page (default to 0)
        var destinationPage = 0
        var destinationView = "Fit"

        if let action = annotation.action,
           let remoteAction = action as? PDFActionRemoteGoTo {
            destinationPage = remoteAction.pageIndex
        }

        // Try to get destination from action dictionary
        if let actionDict = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/A")) as? [String: Any] {
            if let dest = actionDict["D"] as? [Any] {
                if let pageNum = dest.first as? Int {
                    destinationPage = pageNum
                }
                if dest.count > 1, let view = dest[1] as? String {
                    destinationView = view.replacingOccurrences(of: "/", with: "")
                }
            }
        }

        return GoToRLinkInfo(
            annotation: annotation,
            page: page,
            targetFilename: targetFilename,
            destinationPage: destinationPage,
            destinationView: destinationView,
            rect: annotation.bounds
        )
    }

    // MARK: - Document Analysis

    /// Scans a PDF document and returns all GoToR links found
    static func findAllGoToRLinks(in document: PDFDocument) -> [GoToRLinkInfo] {
        var links: [GoToRLinkInfo] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            for annotation in page.annotations {
                // Only check Link annotations
                guard annotation.type == "Link" else { continue }

                if let linkInfo = extractLinkInfo(from: annotation, on: page) {
                    links.append(linkInfo)
                }
            }
        }

        return links
    }

    /// Checks if an annotation has ANY kind of destination (URL, internal, or GoToR)
    static func hasAnyDestination(_ annotation: PDFAnnotation) -> Bool {
        // Standard PDFKit checks
        if annotation.url != nil { return true }
        if annotation.destination != nil { return true }
        if annotation.action != nil {
            // Check if action is a valid action type
            let action = annotation.action
            if action is PDFActionURL { return true }
            if action is PDFActionGoTo { return true }
            if action is PDFActionNamed { return true }
            if action is PDFActionRemoteGoTo { return true }
        }

        // Check for GoToR link (external file)
        if hasGoToRAction(annotation) { return true }

        // Check annotation dictionary for any action
        if let _ = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/A")) {
            return true
        }

        return false
    }

    // MARK: - Repair Logic

    /// Scans for Bluebeam GoToR links and forces them into native PDFActionRemoteGoTo objects.
    /// This is aggressive - if we find a filename in the dictionary, we verify the existing action
    /// actually points to it. If not (or if the action is empty/broken), we replace it.
    /// Returns the number of links fixed.
    @discardableResult
    static func fixBrokenBluebeamLinks(in document: PDFDocument) -> Int {
        var fixedCount = 0

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            for annotation in page.annotations {
                // We only care about Links or Widgets
                guard annotation.type == "Link" || annotation.type == "Widget" else { continue }

                // 1. Try to find the target filename from the raw dictionary (Method 2, 3, 4)
                // We intentionally skip Method 1 (checking the Action) here because we want to know
                // what the dictionary *says* the file is, not what PDFKit *thinks* it is.
                var targetFilename: String?

                // Check /A dictionary directly
                if let annotDict = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/A")) {
                    targetFilename = extractFilenameFromActionDict(annotDict)
                }

                // If not found, check /F directly
                if targetFilename == nil, let fileSpec = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/F")) {
                    targetFilename = extractFilenameFromFileSpec(fileSpec)
                }

                // 2. If we found a filename in the dictionary, we MUST ensure the action is valid.
                if let foundFilename = targetFilename {

                    // Check if the current action is already valid and points to this file
                    var needsRepair = true

                    if let currentAction = annotation.action as? PDFActionRemoteGoTo,
                       let currentURL = currentAction.url {
                        // If the existing action has a URL that matches our filename, it's fine.
                        // We check for suffix because foundFilename might be relative
                        if currentURL.absoluteString.hasSuffix(foundFilename) ||
                           currentURL.path.hasSuffix(foundFilename) {
                            needsRepair = false
                        }
                    }

                    if needsRepair {
                        print("🔧 Fixing Bluebeam link on p\(pageIndex + 1) -> \(foundFilename)")

                        // Create a proper URL.
                        // Bluebeam links are often relative. We create a URL that preserves the string.
                        // Note: We use fileURLWithPath to ensure it's a valid file scheme URL,
                        // which PDFActionRemoteGoTo requires.
                        let url = URL(fileURLWithPath: foundFilename)

                        // Extract destination page if available from the raw dictionary
                        var destPageIndex = 0
                        if let actionDict = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/A")) as? [String: Any],
                           let dest = actionDict["D"] as? [Any],
                           let pageNum = dest.first as? Int {
                            destPageIndex = pageNum
                        }

                        // Force overwrite the action
                        let newAction = PDFActionRemoteGoTo(pageIndex: destPageIndex, at: CGPoint.zero, fileURL: url)
                        annotation.action = newAction
                        fixedCount += 1
                    }
                }
            }
        }

        if fixedCount > 0 {
            print("✅ Repaired \(fixedCount) Bluebeam links.")
        } else {
            print("ℹ️ No broken links found (or all were already valid).")
        }

        return fixedCount
    }

    // MARK: - Debug Logging

    /// Logs detailed information about link annotations for debugging
    static func logLinkDetails(_ annotation: PDFAnnotation, pageIndex: Int) {
        print("")
        print("🔗 Link Annotation on Page \(pageIndex + 1)")
        print("   Bounds: \(annotation.bounds)")
        print("   Type: \(annotation.type ?? "nil")")

        // Standard properties
        print("   URL: \(annotation.url?.absoluteString ?? "nil")")
        print("   Destination: \(annotation.destination?.page?.label ?? "nil")")
        print("   Action: \(annotation.action.map { String(describing: type(of: $0)) } ?? "nil")")

        // Check for GoToR
        if let filename = extractTargetFilename(from: annotation) {
            print("   ✅ GoToR Target: \(filename)")
        }

        // Raw dictionary
        if let keyValues = annotation.annotationKeyValues as? [PDFAnnotationKey: Any] {
            print("   Keys: \(keyValues.keys.map { $0.rawValue })")

            // Log action dictionary if present
            for (key, value) in keyValues {
                if key.rawValue.contains("A") {
                    print("   Action Dict: \(value)")
                }
            }
        }
    }
}
