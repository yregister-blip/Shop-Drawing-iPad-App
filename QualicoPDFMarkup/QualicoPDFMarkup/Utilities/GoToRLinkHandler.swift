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

class GoToRLinkHandler {

    // MARK: - Safe URL Access

    /// Safely extracts URL from PDFActionRemoteGoTo without crashing on nil NSURL
    private static func safeURL(from action: PDFActionRemoteGoTo) -> URL? {
        // Use performSelector to safely access URL - avoids crash when underlying NSURL is nil
        let urlSelector = NSSelectorFromString("url")
        guard action.responds(to: urlSelector),
              let result = action.perform(urlSelector),
              let url = result.takeUnretainedValue() as? URL else {
            return nil
        }
        return url
    }

    // MARK: - Link Detection

    /// Checks if an annotation has a valid GoToR action (link to external file)
    static func hasGoToRAction(_ annotation: PDFAnnotation) -> Bool {
        return extractTargetFilename(from: annotation) != nil
    }

    /// Extracts the target filename from a GoToR link annotation
    static func extractTargetFilename(from annotation: PDFAnnotation) -> String? {

        // 1. Check Native Action (Fastest) - use safe accessor to avoid nil NSURL crash
        if let action = annotation.action as? PDFActionRemoteGoTo,
           let url = safeURL(from: action) {
            return url.lastPathComponent
        }

        // 2. Brute Force Dictionary Parsing
        // We look for the /A dictionary using raw keys to avoid PDFAnnotationKey bridging issues
        let keys = annotation.annotationKeyValues
        var actionDict: [AnyHashable: Any]? = nil

        for (key, value) in keys {
            let keyStr = String(describing: key).replacingOccurrences(of: "\"", with: "")
            if keyStr == "/A" || keyStr == "A" {
                actionDict = value as? [AnyHashable: Any]
                break
            }
        }

        if let actionDict = actionDict {
            return extractFilenameFromActionDict(actionDict)
        }

        return nil
    }

    /// Extracts filename from an action dictionary (Recursive-ish)
    private static func extractFilenameFromActionDict(_ actionDict: Any) -> String? {
        guard let dict = actionDict as? [AnyHashable: Any] else { return nil }

        // Look for /F or /File
        for (key, value) in dict {
            let keyStr = String(describing: key).replacingOccurrences(of: "\"", with: "")
            // The file spec is usually under /F or /File
            if keyStr == "/F" || keyStr == "F" || keyStr == "/File" || keyStr == "File" {
                return extractFilenameFromFileSpec(value)
            }
        }

        return nil
    }

    /// Extracts filename from a file specification object
    private static func extractFilenameFromFileSpec(_ fileSpec: Any) -> String? {
        // Case A: Simple String
        if let filename = fileSpec as? String {
            return cleanFilename(filename)
        }

        // Case B: Dictionary (Full FileSpec)
        if let dict = fileSpec as? [AnyHashable: Any] {
            // Priority: /UF (Unicode), then /F (ASCII)
            for targetKey in ["/UF", "UF", "/F", "F"] {
                for (key, value) in dict {
                    let keyStr = String(describing: key).replacingOccurrences(of: "\"", with: "")
                    if keyStr == targetKey, let filename = value as? String {
                         return cleanFilename(filename)
                    }
                }
            }
        }

        return nil
    }

    private static func cleanFilename(_ raw: String) -> String {
        return raw.replacingOccurrences(of: "file://", with: "")
    }

    // MARK: - Full Link Info Extraction

    static func extractLinkInfo(from annotation: PDFAnnotation, on page: PDFPage) -> GoToRLinkInfo? {
        guard let targetFilename = extractTargetFilename(from: annotation) else {
            return nil
        }

        return GoToRLinkInfo(
            annotation: annotation,
            page: page,
            targetFilename: targetFilename,
            destinationPage: 0,
            destinationView: "Fit",
            rect: annotation.bounds
        )
    }

    // MARK: - Document Analysis & Repair

    static func hasAnyDestination(_ annotation: PDFAnnotation) -> Bool {
        if annotation.url != nil { return true }
        if annotation.destination != nil { return true }
        if annotation.action != nil { return true }
        if hasGoToRAction(annotation) { return true }

        // Check raw /A existence
        let keys = annotation.annotationKeyValues
        for (key, _) in keys {
            let keyStr = String(describing: key).replacingOccurrences(of: "\"", with: "")
            if keyStr == "/A" || keyStr == "A" { return true }
        }
        return false
    }

    @discardableResult
    static func fixBrokenBluebeamLinks(in document: PDFDocument) -> Int {
        var fixedCount = 0

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            for annotation in page.annotations {
                guard annotation.type == "Link" || annotation.type == "Widget" else { continue }

                // 1. Try to find the filename using our brute force method
                if let foundFilename = extractTargetFilename(from: annotation) {

                    // 2. Check if the existing action is already valid - use safe accessor
                    var needsRepair = true
                    if let currentAction = annotation.action as? PDFActionRemoteGoTo,
                       let currentURL = safeURL(from: currentAction) {
                        let currentPath = currentURL.path
                        if currentPath.contains(foundFilename) {
                            needsRepair = false
                        }
                    }

                    // 3. If broken or missing action, force it
                    if needsRepair {
                        print("🔧 Fixing Bluebeam link on p\(pageIndex + 1) -> \(foundFilename)")
                        let url = URL(fileURLWithPath: foundFilename)
                        let newAction = PDFActionRemoteGoTo(pageIndex: 0, at: CGPoint.zero, fileURL: url)
                        annotation.action = newAction
                        fixedCount += 1
                    }
                }
            }
        }

        if fixedCount > 0 {
            print("✅ Repaired \(fixedCount) Bluebeam links.")
        }
        return fixedCount
    }
}
