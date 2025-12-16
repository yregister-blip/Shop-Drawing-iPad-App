//
//  GoToRLinkHandler.swift
//  QualicoPDFMarkup
//
//  Handles GoToR (Go To Remote file) PDF hyperlinks
//  These links reference external PDF files and are not natively supported by PDFKit
//
//  Uses CGPDFDocument to access raw PDF data that PDFKit's high-level API destroys
//

import Foundation
import PDFKit
import CoreGraphics

/// Information about a GoToR link extracted from PDF annotation
struct GoToRLinkInfo {
    let annotation: PDFAnnotation
    let page: PDFPage
    let targetFilename: String
    let destinationPage: Int
    let destinationView: String
    let rect: CGRect
}

/// Stores pre-extracted link data from raw PDF parsing
struct RawLinkData {
    let rect: CGRect
    let targetFilename: String
    let pageIndex: Int
}

class GoToRLinkHandler {

    // MARK: - Raw Link Cache

    /// Cache of raw link data extracted via CGPDFDocument, keyed by "pageIndex_rectHash"
    private static var rawLinkCache: [String: RawLinkData] = [:]

    /// Creates a cache key from page index and rect
    private static func cacheKey(pageIndex: Int, rect: CGRect) -> String {
        // Use rounded values to handle floating point imprecision
        let x = Int(rect.origin.x)
        let y = Int(rect.origin.y)
        let w = Int(rect.size.width)
        let h = Int(rect.size.height)
        return "\(pageIndex)_\(x)_\(y)_\(w)_\(h)"
    }

    /// Pre-extracts all GoToR links from a document using CGPDFDocument (raw access)
    /// Call this immediately after loading the PDF to populate the cache
    static func preExtractLinks(from document: PDFDocument) {
        rawLinkCache.removeAll()

        guard let cgDocument = document.documentRef else {
            print("⚠️ CGPDFDocument: Could not get document reference")
            return
        }

        let pageCount = CGPDFDocumentGetNumberOfPages(cgDocument)
        print("📚 CGPDFDocument: Scanning \(pageCount) pages for GoToR links...")

        for pageIndex in 1...pageCount {
            guard let cgPage = CGPDFDocumentGetPage(cgDocument, pageIndex) else { continue }

            let pageDictionary = CGPDFPageGetDictionary(cgPage)
            guard let pageDictionary = pageDictionary else { continue }

            // Get Annots array from page
            var annotsArray: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotsArray), let annots = annotsArray {
                let annotCount = CGPDFArrayGetCount(annots)

                for i in 0..<annotCount {
                    var annotDict: CGPDFDictionaryRef?
                    if CGPDFArrayGetDictionary(annots, i, &annotDict), let dict = annotDict {
                        if let linkData = extractRawLinkData(from: dict, pageIndex: pageIndex - 1) {
                            let key = cacheKey(pageIndex: pageIndex - 1, rect: linkData.rect)
                            rawLinkCache[key] = linkData
                            print("✅ CGPDFDocument: Cached link on p\(pageIndex) -> \(linkData.targetFilename)")
                        }
                    }
                }
            }
        }

        print("📚 CGPDFDocument: Extracted \(rawLinkCache.count) GoToR links")
    }

    /// Extracts raw link data from a CGPDFDictionary annotation
    private static func extractRawLinkData(from annotDict: CGPDFDictionaryRef, pageIndex: Int) -> RawLinkData? {
        // Check if this is a Link annotation
        var subtypeRef: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(annotDict, "Subtype", &subtypeRef), let subtype = subtypeRef {
            let subtypeStr = String(cString: subtype)
            guard subtypeStr == "Link" else { return nil }
        } else {
            return nil
        }

        // Get the Rect
        var rectArray: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(annotDict, "Rect", &rectArray), let rect = rectArray else {
            return nil
        }

        var x1: CGPDFReal = 0, y1: CGPDFReal = 0, x2: CGPDFReal = 0, y2: CGPDFReal = 0
        CGPDFArrayGetNumber(rect, 0, &x1)
        CGPDFArrayGetNumber(rect, 1, &y1)
        CGPDFArrayGetNumber(rect, 2, &x2)
        CGPDFArrayGetNumber(rect, 3, &y2)
        let annotRect = CGRect(x: min(x1, x2), y: min(y1, y2),
                               width: abs(x2 - x1), height: abs(y2 - y1))

        // Get the Action dictionary (/A)
        var actionDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(annotDict, "A", &actionDict), let action = actionDict else {
            return nil
        }

        // Check if it's a GoToR action
        var actionTypeRef: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(action, "S", &actionTypeRef), let actionType = actionTypeRef {
            let actionTypeStr = String(cString: actionType)
            guard actionTypeStr == "GoToR" else { return nil }
        } else {
            return nil
        }

        // Extract the file specification from /F
        if let filename = extractFilenameFromAction(action) {
            return RawLinkData(rect: annotRect, targetFilename: filename, pageIndex: pageIndex)
        }

        return nil
    }

    /// Extracts filename from a GoToR action's /F key
    private static func extractFilenameFromAction(_ actionDict: CGPDFDictionaryRef) -> String? {
        // Try /F as string first (simple file spec)
        var stringRef: CGPDFStringRef?
        if CGPDFDictionaryGetString(actionDict, "F", &stringRef), let str = stringRef {
            if let cfString = CGPDFStringCopyTextString(str) {
                let filename = cfString as String
                print("   📄 CGPDFDocument: Found /F string: \(filename)")
                return cleanFilename(filename)
            }
        }

        // Try /F as dictionary (full file spec)
        var fileSpecDict: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(actionDict, "F", &fileSpecDict), let fileSpec = fileSpecDict {
            // Try /UF first (Unicode filename), then /F
            for key in ["UF", "F"] {
                var innerStringRef: CGPDFStringRef?
                if CGPDFDictionaryGetString(fileSpec, key, &innerStringRef), let str = innerStringRef {
                    if let cfString = CGPDFStringCopyTextString(str) {
                        let filename = cfString as String
                        print("   📄 CGPDFDocument: Found /\(key) in fileSpec: \(filename)")
                        return cleanFilename(filename)
                    }
                }
            }
        }

        // Try /F as name (rare but possible)
        var nameRef: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(actionDict, "F", &nameRef), let name = nameRef {
            let filename = String(cString: name)
            print("   📄 CGPDFDocument: Found /F name: \(filename)")
            return cleanFilename(filename)
        }

        return nil
    }

    // MARK: - Link Detection

    /// Checks if an annotation has a valid GoToR action (link to external file)
    static func hasGoToRAction(_ annotation: PDFAnnotation) -> Bool {
        return extractTargetFilename(from: annotation) != nil
    }

    /// Extracts the target filename from a GoToR link annotation using the annotation's page
    static func extractTargetFilename(from annotation: PDFAnnotation, on page: PDFPage, in document: PDFDocument) -> String? {
        // First try the cache (populated by CGPDFDocument extraction)
        if let pageIndex = document.index(for: page) as Int? {
            let key = cacheKey(pageIndex: pageIndex, rect: annotation.bounds)
            if let cached = rawLinkCache[key] {
                print("✅ CACHE HIT: Found filename: \(cached.targetFilename)")
                return cached.targetFilename
            }

            // Try nearby rects (in case of slight coordinate differences)
            for (cachedKey, data) in rawLinkCache where data.pageIndex == pageIndex {
                // Check if rects are close enough (within 5 points)
                let cachedRect = data.rect
                let annotRect = annotation.bounds
                if abs(cachedRect.origin.x - annotRect.origin.x) < 5 &&
                   abs(cachedRect.origin.y - annotRect.origin.y) < 5 &&
                   abs(cachedRect.width - annotRect.width) < 5 &&
                   abs(cachedRect.height - annotRect.height) < 5 {
                    print("✅ CACHE FUZZY MATCH: Found filename: \(data.targetFilename)")
                    return data.targetFilename
                }
            }
        }

        // Fall back to other strategies if cache miss
        return extractTargetFilename(from: annotation)
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
        // First, pre-extract all links using CGPDFDocument
        preExtractLinks(from: document)

        var fixedCount = 0

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            for annotation in page.annotations {
                guard annotation.type == "Link" || annotation.type == "Widget" else { continue }

                // 1. Try to extract filename using our aggressive logic (including cache)
                if let foundFilename = extractTargetFilename(from: annotation, on: page, in: document) {

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

    // MARK: - Cache Access for Overlay

    /// Returns the cached filename for an annotation if available
    static func getCachedFilename(for annotation: PDFAnnotation, on page: PDFPage, in document: PDFDocument) -> String? {
        guard let pageIndex = document.index(for: page) as Int? else { return nil }

        let key = cacheKey(pageIndex: pageIndex, rect: annotation.bounds)
        if let cached = rawLinkCache[key] {
            return cached.targetFilename
        }

        // Try fuzzy match
        for (_, data) in rawLinkCache where data.pageIndex == pageIndex {
            let cachedRect = data.rect
            let annotRect = annotation.bounds
            if abs(cachedRect.origin.x - annotRect.origin.x) < 5 &&
               abs(cachedRect.origin.y - annotRect.origin.y) < 5 &&
               abs(cachedRect.width - annotRect.width) < 5 &&
               abs(cachedRect.height - annotRect.height) < 5 {
                return data.targetFilename
            }
        }

        return nil
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
