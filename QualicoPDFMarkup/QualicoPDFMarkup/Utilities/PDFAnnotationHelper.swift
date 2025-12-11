//
//  PDFAnnotationHelper.swift
//  QualicoPDFMarkup
//
//  Helper for adding stamp annotations to PDF pages
//

import Foundation
import PDFKit
import UIKit

enum PDFAnnotationHelper {
    static let defaultStampSize = QualicoBranding.stampSize

    static func addStamp(
        to page: PDFPage,
        at screenPoint: CGPoint,
        in pdfView: PDFView,
        stampType: StampType = .fabricated
    ) -> Bool {
        // Convert screen coordinates to PDF page coordinates
        let pagePoint = pdfView.convert(screenPoint, to: page)

        // Center the stamp on the tap point
        let stampOrigin = CGPoint(
            x: pagePoint.x - defaultStampSize.width / 2,
            y: pagePoint.y - defaultStampSize.height / 2
        )

        return addStamp(to: page, at: stampOrigin, stampType: stampType)
    }

    static func addStamp(
        to page: PDFPage,
        at origin: CGPoint,
        stampType: StampType = .fabricated
    ) -> Bool {
        // Create stamp image
        guard let stampImage = createStampImage(type: stampType) else {
            return false
        }

        // Create PDF annotation
        let bounds = CGRect(origin: origin, size: defaultStampSize)
        let annotation = ImageStampAnnotation(bounds: bounds, image: stampImage)

        page.addAnnotation(annotation)
        return true
    }

    static func createStampImage(type: StampType) -> UIImage? {
        // For POC, create a simple text-based stamp
        // In production, would load from Resources/Stamps/
        let size = QualicoBranding.stampSize
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            // Draw Qualico Red border
            QualicoBranding.stampColor().setStroke()
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let path = UIBezierPath(rect: rect)
            path.lineWidth = QualicoBranding.stampBorderWidth
            path.stroke()

            // Draw text with Qualico branding
            let text = type.rawValue
            let attributes = QualicoBranding.stampTextAttributes()

            let textSize = (text as NSString).size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }

        return image
    }
}

// Custom annotation class to properly handle image stamps
class ImageStampAnnotation: PDFAnnotation {
    private let stampImage: UIImage
    private let pdfFlippedImage: UIImage

    init(bounds: CGRect, image: UIImage) {
        self.stampImage = image
        // Pre-flip the image for PDF coordinate system (PDF uses bottom-left origin)
        self.pdfFlippedImage = Self.createPDFFlippedImage(from: image) ?? image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Creates a vertically flipped version of the image for PDF coordinate system
    /// PDF uses bottom-left origin with Y increasing upward, while UIKit uses top-left origin
    private static func createPDFFlippedImage(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        // Create a bitmap context with the same dimensions
        guard let colorSpace = cgImage.colorSpace,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: cgImage.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: cgImage.bitmapInfo.rawValue
              ) else {
            return nil
        }

        // Apply vertical flip transform: scale Y by -1 and translate
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)

        // Draw the original image in the transformed context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Create the flipped image
        guard let flippedCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: flippedCGImage, scale: image.scale, orientation: .up)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        // Don't call super - we handle all drawing ourselves
        // super.draw would try to draw the default stamp appearance

        // Draw the pre-flipped image directly in PDF coordinates
        // The image is already flipped, so we just draw it at the bounds origin
        if let cgImage = pdfFlippedImage.cgImage {
            let drawRect = CGRect(origin: bounds.origin, size: bounds.size)
            context.draw(cgImage, in: drawRect)
        }
    }
}
