//
//  SyncManager.swift
//  QualicoPDFMarkup
//
//  Handles eTag checking and overwrite-or-fork logic
//

import Foundation
import UIKit

enum SaveResult {
    case overwritten
    case savedAsCopy(fileName: String)
}

@MainActor
class SyncManager {
    private let graphService: GraphAPIService

    init(graphService: GraphAPIService) {
        self.graphService = graphService
    }

    // POC Version: Force overwrite without eTag checking
    func forceSave(itemId: String, pdfData: Data) async throws {
        try await graphService.uploadFile(itemId: itemId, data: pdfData)
    }

    // Phase 1 Version: eTag checking with overwrite-or-fork
    func saveWithETagCheck(
        itemId: String,
        originalETag: String,
        originalName: String,
        folderId: String,
        pdfData: Data
    ) async throws -> SaveResult {
        // Check current version
        let currentMeta = try await graphService.getItemMetadata(itemId: itemId)

        if currentMeta.eTag == originalETag {
            // Safe to overwrite
            try await graphService.uploadFileWithETag(itemId: itemId, data: pdfData, eTag: originalETag)
            return .overwritten
        } else {
            // Conflict - save as copy with device name
            let deviceName = UIDevice.current.name
            let timestamp = Self.fileSafeTimestamp()
            let baseName = originalName.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            let newName = "\(baseName) - MARKUP - \(deviceName) - \(timestamp).pdf"

            _ = try await graphService.uploadNewFile(folderId: folderId, fileName: newName, data: pdfData)
            return .savedAsCopy(fileName: newName)
        }
    }

    private static func fileSafeTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
