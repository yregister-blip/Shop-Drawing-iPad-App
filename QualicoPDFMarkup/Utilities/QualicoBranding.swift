//
//  QualicoBranding.swift
//  QualicoPDFMarkup
//
//  Qualico Steel branding colors and constants
//

import UIKit
import SwiftUI

enum QualicoBranding {
    // MARK: - Colors

    /// Qualico Red - Primary brand color
    /// TODO: Replace with exact RGB values from brand guidelines
    static let qualicoRed = UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1.0)

    /// Qualico Red for SwiftUI
    static let qualicoRedSwiftUI = Color(red: 0.8, green: 0.1, blue: 0.1)

    // MARK: - Stamp Configuration

    /// Default stamp size in points
    static let stampSize = CGSize(width: 150, height: 50)

    /// Stamp border width
    static let stampBorderWidth: CGFloat = 3.0

    /// Stamp font size
    static let stampFontSize: CGFloat = 20.0

    // MARK: - Helper Methods

    static func stampColor() -> UIColor {
        return qualicoRed
    }

    static func stampTextAttributes() -> [NSAttributedString.Key: Any] {
        // TODO: Confirm with marketing whether Qualico has a brand font requirement.
        // Currently using system bold font as placeholder.
        return [
            .font: UIFont.boldSystemFont(ofSize: stampFontSize),
            .foregroundColor: qualicoRed
        ]
    }
}

// MARK: - Production Color Values (Placeholder)

/*
 TODO: Update with actual Qualico Steel brand colors from marketing/engineering

 Current values are placeholders. To update:
 1. Obtain official RGB values from Qualico brand guidelines
 2. Convert to 0-1 scale (divide by 255)
 3. Update the static let values above

 Example:
 If Qualico Red is RGB(204, 25, 25):
 static let qualicoRed = UIColor(red: 204/255, green: 25/255, blue: 25/255, alpha: 1.0)
 static let qualicoRedSwiftUI = Color(red: 204/255, green: 25/255, blue: 25/255)
 */
