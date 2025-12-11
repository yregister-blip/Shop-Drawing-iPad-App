//
//  DriveItem.swift
//  QualicoPDFMarkup
//
//  Represents a file or folder in OneDrive with eTag support
//

import Foundation

struct DriveItem: Identifiable, Codable, Hashable {
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

    enum LocalStatus: Hashable {
        case none
        case stamped
        case uploading
        case conflict
    }

    struct FolderFacet: Codable, Hashable {
        let childCount: Int?
    }

    struct FileFacet: Codable, Hashable {
        let mimeType: String?
        let hashes: Hashes?
    }

    struct Hashes: Codable, Hashable {
        let quickXorHash: String?
        let sha1Hash: String?
    }

    // Custom Hashable implementation (hash only by id for identity)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DriveItem, rhs: DriveItem) -> Bool {
        lhs.id == rhs.id
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
