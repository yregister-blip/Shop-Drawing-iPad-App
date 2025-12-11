//
//  AnnotationTool.swift
//  QualicoPDFMarkup
//
//  Annotation tool modes and drawing path models for PDF markup
//

import Foundation
import CoreGraphics
import UIKit

/// Available annotation tools in the PDF viewer
enum AnnotationTool: String, CaseIterable, Identifiable {
    case none = "None"
    case stamp = "Stamp"
    case pen = "Pen"
    case highlight = "Highlight"
    case text = "Text"

    var id: String { rawValue }

    /// SF Symbol icon for the tool
    var iconName: String {
        switch self {
        case .none:
            return "hand.point.up.left"
        case .stamp:
            return "hand.tap"
        case .pen:
            return "pencil.tip"
        case .highlight:
            return "highlighter"
        case .text:
            return "textformat"
        }
    }

    /// Icon when the tool is active
    var activeIconName: String {
        switch self {
        case .none:
            return "hand.point.up.left.fill"
        case .stamp:
            return "hand.tap.fill"
        case .pen:
            return "pencil.tip"
        case .highlight:
            return "highlighter"
        case .text:
            return "textformat"
        }
    }

    /// Display label for the tool
    var label: String {
        rawValue
    }

    /// Whether this tool requires pan gesture (vs tap)
    var requiresPanGesture: Bool {
        switch self {
        case .pen, .highlight:
            return true
        case .none, .stamp, .text:
            return false
        }
    }
}

/// Represents a drawing path for pen or highlight annotations
struct DrawingPath: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: UIColor
    var lineWidth: CGFloat
    var isHighlight: Bool
    var pageIndex: Int
    var timestamp: Date

    init(
        points: [CGPoint] = [],
        color: UIColor = .black,
        lineWidth: CGFloat = 2.0,
        isHighlight: Bool = false,
        pageIndex: Int = 0
    ) {
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.isHighlight = isHighlight
        self.pageIndex = pageIndex
        self.timestamp = Date()
    }

    /// Returns the bounding rect for this path
    var boundingRect: CGRect {
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
        let padding = lineWidth / 2 + 2
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2,
            height: maxY - minY + padding * 2
        )
    }
}

/// Represents a text annotation
struct TextAnnotationData: Identifiable {
    let id = UUID()
    var text: String
    var position: CGPoint
    var fontSize: CGFloat
    var color: UIColor
    var pageIndex: Int
    var timestamp: Date

    init(
        text: String = "",
        position: CGPoint = .zero,
        fontSize: CGFloat = 16.0,
        color: UIColor = .black,
        pageIndex: Int = 0
    ) {
        self.text = text
        self.position = position
        self.fontSize = fontSize
        self.color = color
        self.pageIndex = pageIndex
        self.timestamp = Date()
    }
}

/// Custom stamp configuration
struct CustomStamp: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var text: String
    var borderColor: CodableColor
    var textColor: CodableColor
    var size: CGSize
    var isCustom: Bool

    init(
        id: UUID = UUID(),
        name: String,
        text: String,
        borderColor: UIColor = QualicoBranding.qualicoRed,
        textColor: UIColor = QualicoBranding.qualicoRed,
        size: CGSize = QualicoBranding.stampSize,
        isCustom: Bool = true
    ) {
        self.id = id
        self.name = name
        self.text = text
        self.borderColor = CodableColor(color: borderColor)
        self.textColor = CodableColor(color: textColor)
        self.size = size
        self.isCustom = isCustom
    }

    /// Convert StampType to CustomStamp for unified handling
    static func from(_ stampType: StampType) -> CustomStamp {
        CustomStamp(
            name: stampType.rawValue,
            text: stampType.rawValue,
            borderColor: QualicoBranding.qualicoRed,
            textColor: QualicoBranding.qualicoRed,
            size: QualicoBranding.stampSize,
            isCustom: false
        )
    }
}

/// Wrapper for encoding UIColor in Codable structs
struct CodableColor: Codable, Hashable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(color: UIColor) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = r
        self.green = g
        self.blue = b
        self.alpha = a
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// Pen/highlight color options
enum DrawingColor: String, CaseIterable, Identifiable {
    case black = "Black"
    case red = "Red"
    case blue = "Blue"
    case green = "Green"
    case orange = "Orange"
    case purple = "Purple"
    case yellow = "Yellow"

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .black:
            return .black
        case .red:
            return UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1.0)
        case .blue:
            return UIColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)
        case .green:
            return UIColor(red: 0.0, green: 0.6, blue: 0.2, alpha: 1.0)
        case .orange:
            return UIColor(red: 0.9, green: 0.5, blue: 0.0, alpha: 1.0)
        case .purple:
            return UIColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1.0)
        case .yellow:
            return UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        }
    }

    /// Color with highlight alpha for highlight tool
    var highlightColor: UIColor {
        uiColor.withAlphaComponent(0.35)
    }
}

/// Line width presets
enum LineWidth: CGFloat, CaseIterable, Identifiable {
    case thin = 1.0
    case medium = 2.0
    case thick = 4.0
    case extraThick = 6.0

    var id: CGFloat { rawValue }

    var displayName: String {
        switch self {
        case .thin:
            return "Thin"
        case .medium:
            return "Medium"
        case .thick:
            return "Thick"
        case .extraThick:
            return "Extra Thick"
        }
    }

    /// Highlight width is larger than pen width
    var highlightWidth: CGFloat {
        rawValue * 6
    }
}
