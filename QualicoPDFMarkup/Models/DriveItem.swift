//
//  DriveItem.swift
//  QualicoPDFMarkup
//
//  Represents a file or folder in OneDrive with eTag support
//

import Foundation

struct DriveItem: Identifiable, Codable {
    let id: String
    let name: String
    let size: Int?
    let webUrl: String?
    let createdDateTime: String?
    let lastModifiedDateTime: String?
    let eTag: String?
    let folder: FolderFacet?
    let file: FileFacet?

    var isFolder: Bool {
        folder != nil
    }

    var isPDF: Bool {
        file?.mimeType == "application/pdf" || name.lowercased().hasSuffix(".pdf")
    }

    // Local UI state (not persisted to OneDrive)
    var localStatus: LocalStatus = .none

    enum LocalStatus {
        case none
        case stamped
        case uploading
        case conflict
    }

    struct FolderFacet: Codable {
        let childCount: Int?
    }

    struct FileFacet: Codable {
        let mimeType: String?
        let hashes: Hashes?
    }

    struct Hashes: Codable {
        let quickXorHash: String?
        let sha1Hash: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, name, size, webUrl, createdDateTime, lastModifiedDateTime, eTag, folder, file
    }
}

// Natural sorting extension
extension Array where Element == DriveItem {
    func naturallySorted() -> [DriveItem] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// Response wrapper for paginated results
struct DriveItemListResponse: Codable {
    let value: [DriveItem]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}
