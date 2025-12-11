//
//  PDFThumbnailService.swift
//  QualicoPDFMarkup
//
//  Service for generating and caching PDF thumbnails
//

import Foundation
import PDFKit
import UIKit

@MainActor
class PDFThumbnailService: ObservableObject {
    static let shared = PDFThumbnailService()

    private var thumbnailCache: [String: UIImage] = [:]
    private var loadingTasks: [String: Task<UIImage?, Never>] = [:]

    // Thumbnail size for file list rows
    static let thumbnailSize = CGSize(width: 44, height: 56)

    private init() {}

    /// Gets a cached thumbnail or returns nil if not available
    func getCachedThumbnail(for fileId: String) -> UIImage? {
        return thumbnailCache[fileId]
    }

    /// Loads or generates a thumbnail for a PDF file
    /// Returns cached version if available, otherwise downloads and generates
    func loadThumbnail(for file: DriveItem, using graphService: GraphAPIService) async -> UIImage? {
        // Return cached thumbnail if available
        if let cached = thumbnailCache[file.id] {
            return cached
        }

        // Check if we're already loading this thumbnail
        if let existingTask = loadingTasks[file.id] {
            return await existingTask.value
        }

        // Create a new loading task
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self = self else { return nil }

            do {
                // Download the PDF data
                let pdfData = try await graphService.downloadFile(itemId: file.id)

                // Generate thumbnail from PDF
                if let thumbnail = await self.generateThumbnail(from: pdfData) {
                    self.thumbnailCache[file.id] = thumbnail
                    return thumbnail
                }
            } catch {
                // Silently fail - we'll show the icon fallback
                print("Failed to load thumbnail for \(file.name): \(error.localizedDescription)")
            }

            return nil
        }

        loadingTasks[file.id] = task
        let result = await task.value
        loadingTasks.removeValue(forKey: file.id)

        return result
    }

    /// Generates a thumbnail from PDF data
    private func generateThumbnail(from pdfData: Data) async -> UIImage? {
        guard let document = PDFDocument(data: pdfData),
              let page = document.page(at: 0) else {
            return nil
        }

        let pageRect = page.bounds(for: .mediaBox)
        let scale = min(
            Self.thumbnailSize.width / pageRect.width,
            Self.thumbnailSize.height / pageRect.height
        )

        let thumbnailRect = CGRect(
            x: 0,
            y: 0,
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: thumbnailRect.size)
        let thumbnail = renderer.image { context in
            // Fill with white background
            UIColor.white.setFill()
            context.fill(thumbnailRect)

            // Draw the PDF page
            context.cgContext.translateBy(x: 0, y: thumbnailRect.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }

        return thumbnail
    }

    /// Clears the thumbnail cache
    func clearCache() {
        thumbnailCache.removeAll()
    }

    /// Removes a specific thumbnail from cache (e.g., after file is modified)
    func invalidateThumbnail(for fileId: String) {
        thumbnailCache.removeValue(forKey: fileId)
    }
}
