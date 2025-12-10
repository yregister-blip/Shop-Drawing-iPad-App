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

        // Set appearance stream
        self.setImageAsAppearanceStream(image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setImageAsAppearanceStream(_ image: UIImage) {
        // Create appearance stream from image
        let imageData = image.pngData()
        if let imageData = imageData {
            // Store image data in annotation
            self.setValue(NSData(data: imageData), forAnnotationKey: PDFAnnotationKey(rawValue: "AP"))
        }
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        super.draw(with: box, in: context)

        // Draw the stamp image
        UIGraphicsPushContext(context)
        stampImage.draw(in: self.bounds)
        UIGraphicsPopContext()
    }
}
