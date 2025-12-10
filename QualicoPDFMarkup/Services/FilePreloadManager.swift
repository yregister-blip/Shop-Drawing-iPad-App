//
//  FilePreloadManager.swift
//  QualicoPDFMarkup
//
//  Preloads next file in folder for instant navigation (Phase 1)
//

import Foundation

@MainActor
class FilePreloadManager {
    private var preloadedFile: (itemId: String, data: Data)?
    private var preloadTask: Task<Void, Never>?
    private let graphService: GraphAPIService

    init(graphService: GraphAPIService) {
        self.graphService = graphService
    }

    func preloadNext(context: FolderContext) {
        // Cancel any existing preload task
        preloadTask?.cancel()

        guard context.hasNext else {
            preloadedFile = nil
            return
        }

        let nextFile = context.files[context.currentIndex + 1]

        preloadTask = Task {
            do {
                let data = try await graphService.downloadFile(itemId: nextFile.id)
                if !Task.isCancelled {
                    preloadedFile = (nextFile.id, data)
                }
            } catch {
                // Preload failure is non-critical; file will load on demand
                print("Preload failed for \(nextFile.name): \(error)")
            }
        }
    }

    func getPreloadedData(for itemId: String) -> Data? {
        if preloadedFile?.itemId == itemId {
            let data = preloadedFile?.data
            preloadedFile = nil // Clear after use
            return data
        }
        return nil
    }

    func cancelPreload() {
        preloadTask?.cancel()
        preloadedFile = nil
    }
}
