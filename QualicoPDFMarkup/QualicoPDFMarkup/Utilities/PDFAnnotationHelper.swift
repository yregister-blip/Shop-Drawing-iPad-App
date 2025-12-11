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

    init(bounds: CGRect, image: UIImage) {
        self.stampImage = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        // Don't call super - we handle all drawing ourselves

        guard let cgImage = stampImage.cgImage else { return }

        // IMPORTANT: Draw CGImage directly without any transforms.
        //
        // Why this works (and why other approaches fail):
        // - CGContext.draw() with CGImage draws correctly in PDF coordinate space
        // - UIImage.draw(in:) applies UIKit coordinate transforms that cause horizontal mirroring
        // - Manual transforms (scaleBy, translateBy) cause various flip/mirror issues
        //
        // The CGImage from UIGraphicsImageRenderer is already in the correct orientation.
        // Just draw it directly at the annotation bounds - no transforms needed.
        context.draw(cgImage, in: bounds)
    }
}
