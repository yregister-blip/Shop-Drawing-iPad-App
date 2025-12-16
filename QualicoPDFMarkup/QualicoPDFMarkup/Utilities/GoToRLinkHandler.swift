//
//  GoToRLinkHandler.swift
//  QualicoPDFMarkup
//
//  Handles GoToR (Go To Remote file) PDF hyperlinks
//  These links reference external PDF files and are not natively supported by PDFKit
//
//  Uses "Scorched Earth" extraction strategies to handle Bluebeam's non-standard formats
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

    // MARK: - Link Detection

    /// Checks if an annotation has a valid GoToR action (link to external file)
    static func hasGoToRAction(_ annotation: PDFAnnotation) -> Bool {
        return extractTargetFilename(from: annotation) != nil
    }

    /// Extracts the target filename from a GoToR link annotation
    /// Uses aggressive strategies to find the filename even if PDFKit fails to parse the URL.
    static func extractTargetFilename(from annotation: PDFAnnotation) -> String? {

        // STRATEGY 1: Native PDFKit Action (The Happy Path)
        // Check if PDFKit successfully parsed a PDFActionRemoteGoTo with valid URL
        if let action = annotation.action as? PDFActionRemoteGoTo {
            // Use safe URL extraction to avoid crash on nil NSURL
            if let url = safeURL(from: action) {
                let filename = url.lastPathComponent
                print("✅ STRATEGY 1 (Native): Found filename via PDFKit URL: \(filename)")
                return filename
            }
        }

        // STRATEGY 2: Debug Description Scraping (The "Hidden Data" Path)
        // If PDFKit parsed the object but rejected the URL (common with relative paths),
        // the raw path often still exists in the debug description.
        if let action = annotation.action {
            let desc = String(describing: action)
            print("🔍 STRATEGY 2: Checking action description: \(desc.prefix(200))...")
            if let match = extractFilenameFromDescription(desc) {
                let cleaned = cleanFilename(match)
                print("✅ STRATEGY 2 (Description): Found filename: \(cleaned)")
                return cleaned
            }
        }

        // STRATEGY 3: Recursive Dictionary Search (The "Buried Treasure" Path)
        // We recursively search the entire raw annotation dictionary for any string ending in .pdf
        let keys = annotation.annotationKeyValues
        print("🔍 STRATEGY 3: Searching annotation keys: \(keys.keys)")
        if let match = recursiveSearchForPDF(in: keys) {
            let cleaned = cleanFilename(match)
            print("✅ STRATEGY 3 (Recursive): Found filename: \(cleaned)")
            return cleaned
        }

        // STRATEGY 4: Specific Key Probing
        // Sometimes the file spec is attached directly to the annotation (flattened)
        for key in ["/F", "F", "/File", "File", "/UF", "UF"] {
            if let val = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: key)) as? String {
                if val.lowercased().hasSuffix(".pdf") {
                    print("✅ STRATEGY 4 (Key Probe): Found filename via key '\(key)': \(val)")
                    return cleanFilename(val)
                }
            }
        }

        // STRATEGY 5: Check action's internal properties via reflection/description
        // Sometimes the action has properties that aren't exposed via the standard API
        if let action = annotation.action as? PDFActionRemoteGoTo {
            // Try to get the raw URL string even if URL property is nil
            let actionMirror = Mirror(reflecting: action)
            for child in actionMirror.children {
                if let value = child.value as? String, value.lowercased().hasSuffix(".pdf") {
                    print("✅ STRATEGY 5 (Mirror): Found filename: \(cleanFilename(value))")
                    return cleanFilename(value)
                }
                if let url = child.value as? URL {
                    let filename = url.lastPathComponent
                    if filename.lowercased().hasSuffix(".pdf") {
                        print("✅ STRATEGY 5 (Mirror URL): Found filename: \(filename)")
                        return filename
                    }
                }
            }
        }

        print("❌ All extraction strategies failed for annotation")
        return nil
    }

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

    // MARK: - Extraction Helpers

    private static func recursiveSearchForPDF(in dict: [AnyHashable: Any]) -> String? {
        for (key, value) in dict {
            // Log what we're examining
            let keyStr = String(describing: key)

            // If String, check extension
            if let str = value as? String {
                if str.lowercased().hasSuffix(".pdf") {
                    print("   📄 Found PDF string at key '\(keyStr)': \(str)")
                    return str
                }
            }

            // If URL, extract filename
            if let url = value as? URL {
                let filename = url.lastPathComponent
                if filename.lowercased().hasSuffix(".pdf") {
                    print("   📄 Found PDF URL at key '\(keyStr)': \(filename)")
                    return filename
                }
            }

            // If Dictionary, Recurse
            if let subDict = value as? [AnyHashable: Any] {
                if let match = recursiveSearchForPDF(in: subDict) {
                    return match
                }
            }

            // If Array, Iterate and Recurse
            if let array = value as? [Any] {
                for item in array {
                    if let str = item as? String, str.lowercased().hasSuffix(".pdf") {
                        return str
                    }
                    if let url = item as? URL {
                        let filename = url.lastPathComponent
                        if filename.lowercased().hasSuffix(".pdf") {
                            return filename
                        }
                    }
                    if let subDict = item as? [AnyHashable: Any] {
                        if let match = recursiveSearchForPDF(in: subDict) {
                            return match
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func extractFilenameFromDescription(_ description: String) -> String? {
        // Look for patterns in the debug description that might contain the filename
        // Common patterns from Bluebeam:
        // - /F (filename.pdf)
        // - /F <filename.pdf>
        // - /UF (filename.pdf)
        // - file: "filename.pdf"
        // - url: filename.pdf

        // Pattern 1: Standard PDF file spec format
        let patterns = [
            #"(?:/F|/UF|/File)\s*(?:[\(<])([^)>]+?\.pdf)(?:[\)>])"#,  // /F (file.pdf) or /F <file.pdf>
            #"(?:/F|/UF|/File)\s*[:\s]+([^\s\)>]+\.pdf)"#,            // /F: file.pdf
            #"file[:\s]*[\"']?([^\"'\s\)>]+\.pdf)[\"']?"#,            // file: "file.pdf"
            #"url[:\s]*[\"']?([^\"'\s\)>]+\.pdf)[\"']?"#,             // url: file.pdf
            #"path[:\s]*[\"']?([^\"'\s\)>]+\.pdf)[\"']?"#,            // path: file.pdf
            #"([A-Za-z0-9_\-\.\s]+\.pdf)"#                             // Any word ending in .pdf
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(location: 0, length: description.utf16.count)

            if let match = regex.firstMatch(in: description, options: [], range: range) {
                let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                if let swiftRange = Range(captureRange, in: description) {
                    let found = String(description[swiftRange])
                    // Skip if it looks like a type name or internal identifier
                    if !found.contains("PDFAction") && !found.contains("Swift") {
                        return found
                    }
                }
            }
        }

        return nil
    }

    private static func cleanFilename(_ raw: String) -> String {
        var clean = raw

        // Remove URL scheme
        clean = clean.replacingOccurrences(of: "file://", with: "")

        // Remove percent encoding if present
        if let decoded = clean.removingPercentEncoding {
            clean = decoded
        }

        // Handle path components - we usually just want the filename
        // Remove any leading/trailing whitespace
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it's a path, extract just the filename
        if clean.contains("/") || clean.contains("\\") {
            let url = URL(fileURLWithPath: clean)
            clean = url.lastPathComponent
        }

        return clean
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

                // 1. Try to extract filename using our aggressive logic
                if let foundFilename = extractTargetFilename(from: annotation) {

                    // 2. Check if the existing action is already VALID
                    var isBroken = true
                    if let currentAction = annotation.action as? PDFActionRemoteGoTo,
                       let currentURL = safeURL(from: currentAction) {
                        // If it has a URL and contains our filename, it's likely fine
                        if currentURL.lastPathComponent == foundFilename {
                            isBroken = false
                        }
                    }

                    // 3. If broken, REPLACE it with a working PDFAction
                    if isBroken {
                        print("🔧 Fixing Bluebeam link on p\(pageIndex + 1) -> \(foundFilename)")
                        let url = URL(fileURLWithPath: foundFilename)
                        // Note: Default to page 0, top-left
                        let newAction = PDFActionRemoteGoTo(pageIndex: 0, at: CGPoint.zero, fileURL: url)
                        annotation.action = newAction
                        fixedCount += 1
                    }
                }
            }
        }

        if fixedCount > 0 {
            print("✅ Repaired \(fixedCount) Bluebeam links.")
        } else {
            print("ℹ️ No repairable links found (or all were already valid).")
        }

        return fixedCount
    }

    // MARK: - Debug Helper

    /// Dumps all annotation data for debugging purposes
    static func dumpAnnotationData(_ annotation: PDFAnnotation) {
        print("📋 ========== ANNOTATION DUMP ==========")
        print("📋 Type: \(annotation.type ?? "nil")")
        print("📋 Bounds: \(annotation.bounds)")
        print("📋 URL: \(annotation.url?.absoluteString ?? "nil")")
        print("📋 Destination: \(annotation.destination?.description ?? "nil")")

        if let action = annotation.action {
            print("📋 Action Type: \(type(of: action))")
            print("📋 Action Description: \(String(describing: action))")

            if let remoteAction = action as? PDFActionRemoteGoTo {
                print("📋 RemoteGoTo pageIndex: \(remoteAction.pageIndex)")
                print("📋 RemoteGoTo point: \(remoteAction.point)")
                if let url = safeURL(from: remoteAction) {
                    print("📋 RemoteGoTo URL: \(url.absoluteString)")
                } else {
                    print("📋 RemoteGoTo URL: FAILED TO ACCESS (nil or invalid)")
                }
            }
        } else {
            print("📋 Action: nil")
        }

        print("📋 Annotation Keys:")
        for (key, value) in annotation.annotationKeyValues {
            print("   [\(key)]: \(value)")
        }
        print("📋 ========================================")
    }
}
