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
class PDFThumbnailService {
    static let shared = PDFThumbnailService()

    private var thumbnailCache: [String: UIImage] = [:]
    private var gridThumbnailCache: [String: UIImage] = [:]
    private var loadingTasks: [String: Task<UIImage?, Never>] = [:]
    private var gridLoadingTasks: [String: Task<UIImage?, Never>] = [:]

    // Thumbnail sizes
    static let listThumbnailSize = CGSize(width: 44, height: 56)
    static let gridThumbnailSize = CGSize(width: 200, height: 260)

    // Legacy compatibility
    static var thumbnailSize: CGSize { listThumbnailSize }

    private init() {}

    /// Gets a cached thumbnail or returns nil if not available
    func getCachedThumbnail(for fileId: String, targetSize: CGSize? = nil) -> UIImage? {
        let isGridSize = targetSize != nil && targetSize!.width > Self.listThumbnailSize.width
        return isGridSize ? gridThumbnailCache[fileId] : thumbnailCache[fileId]
    }

    /// Loads or generates a thumbnail for a PDF file
    /// Returns cached version if available, otherwise downloads and generates
    /// - Parameters:
    ///   - file: The DriveItem to load thumbnail for
    ///   - graphService: GraphAPIService for downloading
    ///   - targetSize: Optional target size (defaults to list size, use gridThumbnailSize for grid view)
    func loadThumbnail(for file: DriveItem, using graphService: GraphAPIService, targetSize: CGSize? = nil) async -> UIImage? {
        let effectiveSize = targetSize ?? Self.listThumbnailSize
        let isGridSize = effectiveSize.width > Self.listThumbnailSize.width
        let cache = isGridSize ? gridThumbnailCache : thumbnailCache
        let loadingTasksRef = isGridSize ? gridLoadingTasks : loadingTasks
        let cacheKey = file.id

        // Return cached thumbnail if available
        if let cached = cache[cacheKey] {
            return cached
        }

        // Check if we're already loading this thumbnail
        if let existingTask = loadingTasksRef[cacheKey] {
            return await existingTask.value
        }

        // Create a new loading task
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self = self else { return nil }

            do {
                // Download the PDF data
                let pdfData = try await graphService.downloadFile(itemId: file.id)

                // Generate thumbnail from PDF
                if let thumbnail = await self.generateThumbnail(from: pdfData, targetSize: effectiveSize) {
                    if isGridSize {
                        self.gridThumbnailCache[cacheKey] = thumbnail
                    } else {
                        self.thumbnailCache[cacheKey] = thumbnail
                    }
                    return thumbnail
                }
            } catch {
                // Silently fail - we'll show the icon fallback
                print("Failed to load thumbnail for \(file.name): \(error.localizedDescription)")
            }

            return nil
        }

        if isGridSize {
            gridLoadingTasks[file.id] = task
        } else {
            loadingTasks[file.id] = task
        }

        let result = await task.value

        if isGridSize {
            gridLoadingTasks.removeValue(forKey: file.id)
        } else {
            loadingTasks.removeValue(forKey: file.id)
        }

        return result
    }

    /// Generates a thumbnail from PDF data
    /// - Parameters:
    ///   - pdfData: PDF document data
    ///   - targetSize: Target size for the thumbnail
    private func generateThumbnail(from pdfData: Data, targetSize: CGSize? = nil) async -> UIImage? {
        guard let document = PDFDocument(data: pdfData),
              let page = document.page(at: 0) else {
            return nil
        }

        let effectiveSize = targetSize ?? Self.listThumbnailSize
        let pageRect = page.bounds(for: .mediaBox)
        let scale = min(
            effectiveSize.width / pageRect.width,
            effectiveSize.height / pageRect.height
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
        gridThumbnailCache.removeAll()
    }

    /// Removes a specific thumbnail from cache (e.g., after file is modified)
    func invalidateThumbnail(for fileId: String) {
        thumbnailCache.removeValue(forKey: fileId)
        gridThumbnailCache.removeValue(forKey: fileId)
    }
}
