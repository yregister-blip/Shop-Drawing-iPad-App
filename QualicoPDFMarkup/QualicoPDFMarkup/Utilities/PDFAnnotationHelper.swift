//
//  PDFAnnotationHelper.swift
//  QualicoPDFMarkup
//
//  Helper for adding annotations to PDF pages (stamps, pen, highlight, text)
//

import Foundation
import PDFKit
import UIKit

enum PDFAnnotationHelper {
    static let defaultStampSize = QualicoBranding.stampSize

    // MARK: - Stamp Annotations

    static func addStamp(
        to page: PDFPage,
        at screenPoint: CGPoint,
        in pdfView: PDFView,
        stampType: StampType = .fabricated
    ) -> PDFAnnotation? {
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
    ) -> PDFAnnotation? {
        // Create stamp image
        guard let stampImage = createStampImage(type: stampType) else {
            return nil
        }

        // Create PDF annotation
        let bounds = CGRect(origin: origin, size: defaultStampSize)
        let annotation = ImageStampAnnotation(bounds: bounds, image: stampImage)

        page.addAnnotation(annotation)
        return annotation
    }

    /// Add a custom stamp with custom text and colors
    static func addCustomStamp(
        to page: PDFPage,
        at screenPoint: CGPoint,
        in pdfView: PDFView,
        customStamp: CustomStamp
    ) -> PDFAnnotation? {
        let pagePoint = pdfView.convert(screenPoint, to: page)

        let stampOrigin = CGPoint(
            x: pagePoint.x - customStamp.size.width / 2,
            y: pagePoint.y - customStamp.size.height / 2
        )

        guard let stampImage = createCustomStampImage(stamp: customStamp) else {
            return nil
        }

        let bounds = CGRect(origin: stampOrigin, size: customStamp.size)
        let annotation = ImageStampAnnotation(bounds: bounds, image: stampImage)

        page.addAnnotation(annotation)
        return annotation
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

    /// Create stamp image with custom parameters
    static func createCustomStampImage(stamp: CustomStamp) -> UIImage? {
        let size = stamp.size
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            // Draw border with custom color
            stamp.borderColor.uiColor.setStroke()
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let path = UIBezierPath(rect: rect)
            path.lineWidth = QualicoBranding.stampBorderWidth
            path.stroke()

            // Draw text with custom color
            let text = stamp.text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: QualicoBranding.stampFontSize),
                .foregroundColor: stamp.textColor.uiColor
            ]

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

    // MARK: - Pen/Ink Annotations

    /// Add an ink annotation from a drawing path
    static func addInkAnnotation(
        to page: PDFPage,
        path: DrawingPath,
        pdfView: PDFView
    ) -> PDFAnnotation? {
        guard path.points.count >= 2 else { return nil }

        // Convert screen points to PDF page coordinates
        let pdfPoints = path.points.map { screenPoint in
            pdfView.convert(screenPoint, to: page)
        }

        // Calculate bounds from points
        let bounds = calculateBounds(for: pdfPoints, lineWidth: path.lineWidth)

        // Create ink annotation
        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)

        // Create UIBezierPath for the ink
        let bezierPath = UIBezierPath()
        bezierPath.move(to: pdfPoints[0])
        for point in pdfPoints.dropFirst() {
            bezierPath.addLine(to: point)
        }

        // Set annotation properties
        annotation.color = path.color
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = path.lineWidth

        // Add the path to the annotation
        annotation.add(bezierPath)

        page.addAnnotation(annotation)
        return annotation
    }

    /// Add a smooth ink annotation using quadratic curves
    static func addSmoothInkAnnotation(
        to page: PDFPage,
        path: DrawingPath,
        pdfView: PDFView
    ) -> PDFAnnotation? {
        guard path.points.count >= 2 else { return nil }

        // Convert screen points to PDF page coordinates
        let pdfPoints = path.points.map { screenPoint in
            pdfView.convert(screenPoint, to: page)
        }

        // Calculate bounds from points
        let bounds = calculateBounds(for: pdfPoints, lineWidth: path.lineWidth)

        // Create ink annotation
        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)

        // Create smooth UIBezierPath
        let bezierPath = createSmoothPath(from: pdfPoints)

        // Set annotation properties
        annotation.color = path.color
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = path.lineWidth

        // Add the path to the annotation
        annotation.add(bezierPath)

        page.addAnnotation(annotation)
        return annotation
    }

    // MARK: - Highlight Annotations

    /// Add a highlight annotation from a drawing path
    static func addHighlightAnnotation(
        to page: PDFPage,
        path: DrawingPath,
        pdfView: PDFView
    ) -> PDFAnnotation? {
        guard path.points.count >= 2 else { return nil }

        // Convert screen points to PDF page coordinates
        let pdfPoints = path.points.map { screenPoint in
            pdfView.convert(screenPoint, to: page)
        }

        // Calculate bounds with extra padding for highlight width
        let highlightWidth = path.lineWidth * 6  // Highlights are wider
        let bounds = calculateBounds(for: pdfPoints, lineWidth: highlightWidth)

        // Create a custom highlight annotation using ink with transparency
        let annotation = HighlightPathAnnotation(
            bounds: bounds,
            points: pdfPoints,
            color: path.color.withAlphaComponent(0.35),
            lineWidth: highlightWidth
        )

        page.addAnnotation(annotation)
        return annotation
    }

    // MARK: - Text Annotations

    /// Add a free text annotation
    static func addTextAnnotation(
        to page: PDFPage,
        at screenPoint: CGPoint,
        in pdfView: PDFView,
        text: String,
        fontSize: CGFloat = 16,
        color: UIColor = .black
    ) -> PDFAnnotation? {
        guard !text.isEmpty else { return nil }

        let pagePoint = pdfView.convert(screenPoint, to: page)

        // Calculate text size to determine bounds
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize)
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)

        // Add padding
        let padding: CGFloat = 4
        let bounds = CGRect(
            x: pagePoint.x,
            y: pagePoint.y - textSize.height - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )

        // Create free text annotation
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = UIFont.systemFont(ofSize: fontSize)
        annotation.fontColor = color
        annotation.color = .clear  // Transparent background

        // Optional: add a subtle border
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = 0

        page.addAnnotation(annotation)
        return annotation
    }

    /// Add a text annotation with background
    static func addTextAnnotationWithBackground(
        to page: PDFPage,
        at screenPoint: CGPoint,
        in pdfView: PDFView,
        text: String,
        fontSize: CGFloat = 16,
        textColor: UIColor = .black,
        backgroundColor: UIColor = UIColor.white.withAlphaComponent(0.9)
    ) -> PDFAnnotation? {
        guard !text.isEmpty else { return nil }

        let pagePoint = pdfView.convert(screenPoint, to: page)

        // Calculate text size
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize)
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)

        let padding: CGFloat = 8
        let bounds = CGRect(
            x: pagePoint.x,
            y: pagePoint.y - textSize.height - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )

        // Create custom text annotation with background
        let annotation = TextBoxAnnotation(
            bounds: bounds,
            text: text,
            font: UIFont.systemFont(ofSize: fontSize),
            textColor: textColor,
            backgroundColor: backgroundColor
        )

        page.addAnnotation(annotation)
        return annotation
    }

    // MARK: - Helper Methods

    /// Calculate bounding rect from points array
    private static func calculateBounds(for points: [CGPoint], lineWidth: CGFloat) -> CGRect {
        guard !points.isEmpty else { return .zero }

        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity

        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        // Add padding for line width
        let padding = lineWidth / 2 + 5
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2,
            height: maxY - minY + padding * 2
        )
    }

    /// Create a smooth bezier path from points using quadratic curves
    private static func createSmoothPath(from points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard points.count >= 2 else { return path }

        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            for i in 1..<points.count {
                let midPoint = CGPoint(
                    x: (points[i - 1].x + points[i].x) / 2,
                    y: (points[i - 1].y + points[i].y) / 2
                )

                if i == 1 {
                    path.addLine(to: midPoint)
                } else {
                    path.addQuadCurve(to: midPoint, controlPoint: points[i - 1])
                }
            }

            path.addLine(to: points.last!)
        }

        return path
    }
}

// MARK: - Custom Annotation Classes

/// Custom annotation class to properly handle image stamps
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

/// Custom annotation for highlight paths with transparency
class HighlightPathAnnotation: PDFAnnotation {
    private let points: [CGPoint]
    private let highlightColor: UIColor
    private let strokeWidth: CGFloat

    init(bounds: CGRect, points: [CGPoint], color: UIColor, lineWidth: CGFloat) {
        self.points = points
        self.highlightColor = color
        self.strokeWidth = lineWidth
        super.init(bounds: bounds, forType: .ink, withProperties: nil)

        // Set basic properties
        self.color = color
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard points.count >= 2 else { return }

        context.saveGState()

        // Set up drawing properties for highlight effect
        context.setStrokeColor(highlightColor.cgColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setBlendMode(.multiply)  // Multiply blend for highlight effect

        // Draw the path
        context.move(to: points[0])
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()

        context.restoreGState()
    }
}

/// Custom annotation for text with background
class TextBoxAnnotation: PDFAnnotation {
    private let displayText: String
    private let textFont: UIFont
    private let textColor: UIColor
    private let bgColor: UIColor

    init(bounds: CGRect, text: String, font: UIFont, textColor: UIColor, backgroundColor: UIColor) {
        self.displayText = text
        self.textFont = font
        self.textColor = textColor
        self.bgColor = backgroundColor
        super.init(bounds: bounds, forType: .freeText, withProperties: nil)

        self.contents = text
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()

        // Draw background
        context.setFillColor(bgColor.cgColor)
        let bgRect = bounds.insetBy(dx: 1, dy: 1)
        context.fill(bgRect)

        // Draw border
        context.setStrokeColor(UIColor.gray.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(0.5)
        context.stroke(bgRect)

        // Draw text
        // Note: We need to flip context for text drawing in PDF coordinate system
        context.textMatrix = .identity

        let attributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textColor
        ]

        let textSize = (displayText as NSString).size(withAttributes: attributes)
        let textRect = CGRect(
            x: bounds.minX + (bounds.width - textSize.width) / 2,
            y: bounds.minY + (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        // Push UIKit graphics context for text drawing
        UIGraphicsPushContext(context)
        (displayText as NSString).draw(in: textRect, withAttributes: attributes)
        UIGraphicsPopContext()

        context.restoreGState()
    }
}
