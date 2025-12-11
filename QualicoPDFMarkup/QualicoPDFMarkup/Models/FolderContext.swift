//
//  FolderContext.swift
//  QualicoPDFMarkup
//
//  Tracks current position in folder for in-viewer navigation
//

import Foundation

struct FolderContext: Hashable {
    let folderId: String
    let files: [DriveItem]
    var currentIndex: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(folderId)
        hasher.combine(currentIndex)
    }

    static func == (lhs: FolderContext, rhs: FolderContext) -> Bool {
        lhs.folderId == rhs.folderId && lhs.currentIndex == rhs.currentIndex
    }

    var currentFile: DriveItem {
        files[currentIndex]
    }

    var hasNext: Bool {
        currentIndex < files.count - 1
    }

    var hasPrevious: Bool {
        currentIndex > 0
    }

    var positionDisplay: String {
        "\(currentIndex + 1) of \(files.count)"
    }

    mutating func goNext() -> DriveItem? {
        guard hasNext else { return nil }
        currentIndex += 1
        return currentFile
    }

    mutating func goPrevious() -> DriveItem? {
        guard hasPrevious else { return nil }
        currentIndex -= 1
        return currentFile
    }

    init(folderId: String, files: [DriveItem], currentFileId: String) {
        self.folderId = folderId
        self.files = files.naturallySorted()
        self.currentIndex = files.firstIndex(where: { $0.id == currentFileId }) ?? 0
    }
}
