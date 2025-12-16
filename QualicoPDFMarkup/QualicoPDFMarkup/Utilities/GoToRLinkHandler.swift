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
    /// Uses brute-force dictionary parsing to handle various key formats
    static func extractTargetFilename(from annotation: PDFAnnotation) -> String? {
        // Method 1: Check annotation's native action object (fastest path)
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

        // Method 2: BRUTE FORCE Dictionary Parsing
        // We iterate the raw [AnyHashable: Any] dictionary to find the /A (Action) entry,
        // handling both String and PDFAnnotationKey key types
        let keys = annotation.annotationKeyValues
        var actionDict: [AnyHashable: Any]?

        // Find the action dictionary (key could be "/A", "A", or PDFAnnotationKey("/A"))
        for (key, value) in keys {
            // Clean up the key string (remove quotes from debug description)
            let keyString = String(describing: key).replacingOccurrences(of: "\"", with: "")
            if keyString == "/A" || keyString == "A" || keyString.hasSuffix("A") {
                actionDict = value as? [AnyHashable: Any]
                break
            }
        }

        if let actionDict = actionDict {
            if let filename = extractFilenameFromActionDict(actionDict) {
                return filename
            }
        }

        // Method 3: Try value(forAnnotationKey:) with explicit key
        if let annotDict = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/A")) {
            if let filename = extractFilenameFromActionDict(annotDict) {
                return filename
            }
        }

        // Method 4: Check if there's a direct file specification at the annotation level
        if let fileSpec = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/F")) {
            return extractFilenameFromFileSpec(fileSpec)
        }

        // Method 5: Brute force check for /F in annotation keys
        for (key, value) in keys {
            let keyString = String(describing: key).replacingOccurrences(of: "\"", with: "")
            if keyString == "/F" || keyString == "F" || keyString == "/File" || keyString == "File" {
                if let filename = extractFilenameFromFileSpec(value) {
                    return filename
                }
            }
        }

        // Method 6: Try to access via action property paths (with safe KVC)
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

    /// Extracts filename from an action dictionary (handles various dictionary types)
    private static func extractFilenameFromActionDict(_ actionDict: Any) -> String? {
        // Handle various dictionary types (Swift dictionary or NSDictionary)
        guard let dict = actionDict as? [AnyHashable: Any] else { return nil }

        // First, check if this is indeed a GoToR action by looking for /S key
        var isGoToR = false
        for (key, value) in dict {
            let keyStr = String(describing: key).replacingOccurrences(of: "\"", with: "")
            if keyStr == "/S" || keyStr == "S" {
                let valStr = String(describing: value)
                if valStr.contains("GoToR") {
                    isGoToR = true
                    break
                }
            }
        }

        // Proceed even if /S isn't explicitly found, as some incomplete dicts might just have /F

        // Look for /F or /File keys
        for (key, value) in dict {
            let keyStr = String(describing: key).replacingOccurrences(of: "\"", with: "")
            // The file spec is usually under /F or /File
            if keyStr == "/F" || keyStr == "F" || keyStr == "/File" || keyStr == "File" {
                if let filename = extractFilenameFromFileSpec(value) {
                    return filename
                }
            }
        }

        return nil
    }

    /// Extracts filename from a file specification object
    private static func extractFilenameFromFileSpec(_ fileSpec: Any) -> String? {
        // Case A: Simple String
        if let filename = fileSpec as? String {
            return filename.replacingOccurrences(of: "file://", with: "")
        }

        // Case B: Dictionary (Full FileSpec)
        if let dict = fileSpec as? [AnyHashable: Any] {
            // Priority: /UF (Unicode), then /F (ASCII)
            let targetKeys = ["/UF", "UF", "/F", "F"]
            for targetKey in targetKeys {
                for (key, value) in dict {
                    let keyStr = String(describing: key).replacingOccurrences(of: "\"", with: "")
                    if keyStr == targetKey, let filename = value as? String {
                        return filename.replacingOccurrences(of: "file://", with: "")
                    }
                }
            }
        }

        // Case C: Try String dictionary
        if let dict = fileSpec as? [String: Any] {
            // /UF is Unicode filename (preferred)
            if let uf = dict["UF"] as? String {
                return uf.replacingOccurrences(of: "file://", with: "")
            }
            if let uf = dict["/UF"] as? String {
                return uf.replacingOccurrences(of: "file://", with: "")
            }
            // /F is ASCII filename
            if let f = dict["F"] as? String {
                return f.replacingOccurrences(of: "file://", with: "")
            }
            if let f = dict["/F"] as? String {
                return f.replacingOccurrences(of: "file://", with: "")
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
    /// Uses brute-force dictionary iteration to handle various key formats.
    /// Returns the number of links fixed.
    @discardableResult
    static func fixBrokenBluebeamLinks(in document: PDFDocument) -> Int {
        var fixedCount = 0

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            for annotation in page.annotations {
                // We only care about Links or Widgets
                guard annotation.type == "Link" || annotation.type == "Widget" else { continue }

                // 1. Try to find the target filename from the raw dictionary
                // We use brute-force iteration to handle various key formats
                var targetFilename: String?
                let keys = annotation.annotationKeyValues

                // Check /A dictionary using brute-force key matching
                for (key, value) in keys {
                    let keyString = String(describing: key).replacingOccurrences(of: "\"", with: "")
                    if keyString == "/A" || keyString == "A" || keyString.hasSuffix("A") {
                        if let actionDict = value as? [AnyHashable: Any] {
                            targetFilename = extractFilenameFromActionDict(actionDict)
                            break
                        }
                    }
                }

                // Also try the standard way
                if targetFilename == nil,
                   let annotDict = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/A")) {
                    targetFilename = extractFilenameFromActionDict(annotDict)
                }

                // If not found, check /F directly using brute-force
                if targetFilename == nil {
                    for (key, value) in keys {
                        let keyString = String(describing: key).replacingOccurrences(of: "\"", with: "")
                        if keyString == "/F" || keyString == "F" || keyString == "/File" || keyString == "File" {
                            targetFilename = extractFilenameFromFileSpec(value)
                            break
                        }
                    }
                }

                // Also try standard way for /F
                if targetFilename == nil,
                   let fileSpec = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/F")) {
                    targetFilename = extractFilenameFromFileSpec(fileSpec)
                }

                // 2. If we found a filename in the dictionary, we MUST ensure the action is valid.
                if let foundFilename = targetFilename {

                    // Check if the current action is already valid and points to this file
                    var needsRepair = true

                    if let currentAction = annotation.action as? PDFActionRemoteGoTo {
                        let currentURL = currentAction.url
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

                        // Extract destination page if available from the raw dictionary (brute-force)
                        var destPageIndex = 0
                        for (key, value) in keys {
                            let keyString = String(describing: key).replacingOccurrences(of: "\"", with: "")
                            if keyString == "/A" || keyString == "A" || keyString.hasSuffix("A") {
                                if let actionDict = value as? [AnyHashable: Any] {
                                    for (aKey, aValue) in actionDict {
                                        let aKeyStr = String(describing: aKey).replacingOccurrences(of: "\"", with: "")
                                        if aKeyStr == "/D" || aKeyStr == "D" {
                                            if let dest = aValue as? [Any], let pageNum = dest.first as? Int {
                                                destPageIndex = pageNum
                                            }
                                        }
                                    }
                                }
                                break
                            }
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
