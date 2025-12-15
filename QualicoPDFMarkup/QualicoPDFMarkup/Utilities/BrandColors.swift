//
//  BrandColors.swift
//  QualicoPDFMarkup
//
//  Qualico Steel official brand colors
//  Based on Qualico Brand Style Guide
//

import SwiftUI
import UIKit

/// Qualico Steel brand color constants
/// Reference: Qualico Logo Brand Style Guide Sheet
enum BrandColors {
    // MARK: - Primary Colors

    /// Qualico Red - Primary brand color
    /// Hex: #D32127
    /// Use for: stamps, primary buttons, accents, highlights
    static let primaryRed = Color(red: 211/255, green: 33/255, blue: 39/255)
    static let primaryRedUI = UIColor(red: 211/255, green: 33/255, blue: 39/255, alpha: 1.0)

    // MARK: - Secondary Colors

    /// Dark Gray - For text and icons
    /// Hex: #525050
    static let darkGray = Color(red: 82/255, green: 80/255, blue: 80/255)
    static let darkGrayUI = UIColor(red: 82/255, green: 80/255, blue: 80/255, alpha: 1.0)

    /// Light Gray - For secondary elements
    /// Hex: #A6A3A3
    static let lightGray = Color(red: 166/255, green: 163/255, blue: 163/255)
    static let lightGrayUI = UIColor(red: 166/255, green: 163/255, blue: 163/255, alpha: 1.0)

    /// Off-White - For backgrounds
    /// Hex: #F8F6F6
    static let offWhite = Color(red: 248/255, green: 246/255, blue: 246/255)
    static let offWhiteUI = UIColor(red: 248/255, green: 246/255, blue: 246/255, alpha: 1.0)

    // MARK: - Semantic Colors

    /// Primary action color (same as primaryRed)
    static let primaryAction = primaryRed
    static let primaryActionUI = primaryRedUI

    /// Text color (same as darkGray)
    static let text = darkGray
    static let textUI = darkGrayUI

    /// Icon color (same as darkGray)
    static let icon = darkGray
    static let iconUI = darkGrayUI

    /// Secondary UI elements (same as lightGray)
    static let secondary = lightGray
    static let secondaryUI = lightGrayUI

    /// Background color (same as offWhite)
    static let background = offWhite
    static let backgroundUI = offWhiteUI

    // MARK: - Hex Values for Reference

    enum HexValues {
        static let primaryRed = "#D32127"
        static let darkGray = "#525050"
        static let lightGray = "#A6A3A3"
        static let offWhite = "#F8F6F6"
    }
}

// MARK: - SwiftUI View Extensions

extension View {
    /// Apply Qualico red foreground color
    func qualicoRedForeground() -> some View {
        self.foregroundColor(BrandColors.primaryRed)
    }

    /// Apply Qualico off-white background
    func qualicoBackground() -> some View {
        self.background(BrandColors.offWhite)
    }
}

// MARK: - Button Style

struct QualicoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? BrandColors.primaryRed.opacity(0.8) : BrandColors.primaryRed)
            .cornerRadius(10)
    }
}

struct QualicoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(BrandColors.primaryRed)
            .padding()
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? BrandColors.lightGray.opacity(0.3) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(BrandColors.primaryRed, lineWidth: 2)
            )
            .cornerRadius(10)
    }
}

extension ButtonStyle where Self == QualicoPrimaryButtonStyle {
    static var qualicoPrimary: QualicoPrimaryButtonStyle { QualicoPrimaryButtonStyle() }
}

extension ButtonStyle where Self == QualicoSecondaryButtonStyle {
    static var qualicoSecondary: QualicoSecondaryButtonStyle { QualicoSecondaryButtonStyle() }
}
