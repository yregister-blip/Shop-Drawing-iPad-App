//
//  QualicoBranding.swift
//  QualicoPDFMarkup
//
//  Qualico Steel branding colors and stamp configuration
//  Uses official brand colors from BrandColors.swift
//

import UIKit
import SwiftUI

enum QualicoBranding {
    // MARK: - Colors (using official brand values)

    /// Qualico Red - Primary brand color (#D32127)
    static let qualicoRed = BrandColors.primaryRedUI

    /// Qualico Red for SwiftUI
    static let qualicoRedSwiftUI = BrandColors.primaryRed

    /// Dark Gray for text and icons (#525050)
    static let darkGray = BrandColors.darkGrayUI
    static let darkGraySwiftUI = BrandColors.darkGray

    /// Light Gray for secondary elements (#A6A3A3)
    static let lightGray = BrandColors.lightGrayUI
    static let lightGraySwiftUI = BrandColors.lightGray

    /// Off-White for backgrounds (#F8F6F6)
    static let offWhite = BrandColors.offWhiteUI
    static let offWhiteSwiftUI = BrandColors.offWhite

    // MARK: - Stamp Configuration

    /// Default stamp size in points
    static let stampSize = CGSize(width: 150, height: 50)

    /// Stamp border width
    static let stampBorderWidth: CGFloat = 3.0

    /// Stamp font size
    static let stampFontSize: CGFloat = 20.0

    // MARK: - Font Names

    /// Montserrat Bold - for headings and buttons
    static let fontBold = "Montserrat-Bold"

    /// Montserrat Regular - for body text
    static let fontRegular = "Montserrat-Regular"

    // MARK: - Helper Methods

    static func stampColor() -> UIColor {
        return qualicoRed
    }

    static func stampFont(size: CGFloat = stampFontSize) -> UIFont {
        // Try to use Montserrat Bold, fallback to system bold
        return UIFont(name: fontBold, size: size) ?? UIFont.boldSystemFont(ofSize: size)
    }

    static func bodyFont(size: CGFloat = 16.0) -> UIFont {
        // Try to use Montserrat Regular, fallback to system font
        return UIFont(name: fontRegular, size: size) ?? UIFont.systemFont(ofSize: size)
    }

    static func stampTextAttributes() -> [NSAttributedString.Key: Any] {
        return [
            .font: stampFont(),
            .foregroundColor: qualicoRed
        ]
    }

    /// Create a FABRICATED stamp image
    static func createFabricatedStampImage() -> UIImage? {
        let size = stampSize
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // Transparent background (no fill)

            // Draw border
            let borderRect = CGRect(x: stampBorderWidth/2,
                                   y: stampBorderWidth/2,
                                   width: size.width - stampBorderWidth,
                                   height: size.height - stampBorderWidth)
            qualicoRed.setStroke()
            let borderPath = UIBezierPath(rect: borderRect)
            borderPath.lineWidth = stampBorderWidth
            borderPath.stroke()

            // Draw text
            let text = "FABRICATED"
            let font = stampFont(size: 24)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: qualicoRed
            ]

            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            text.draw(in: textRect, withAttributes: attributes)
        }
    }
}
