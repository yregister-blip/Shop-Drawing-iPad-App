//
//  StampAnnotation.swift
//  QualicoPDFMarkup
//
//  Represents a stamp annotation on a PDF
//

import Foundation
import CoreGraphics

enum StampType: String, Codable, CaseIterable, Hashable {
    case fabricated = "FABRICATED"
    case hold = "HOLD"
    case fitOnly = "FIT ONLY"

    var imageName: String {
        switch self {
        case .fabricated:
            return "fabricated"
        case .hold:
            return "hold"
        case .fitOnly:
            return "fit_only"
        }
    }
}

struct StampAnnotation {
    let type: StampType
    let position: CGPoint
    let size: CGSize
    let pageIndex: Int
    let timestamp: Date

    init(type: StampType, position: CGPoint, size: CGSize = CGSize(width: 150, height: 50), pageIndex: Int) {
        self.type = type
        self.position = position
        self.size = size
        self.pageIndex = pageIndex
        self.timestamp = Date()
    }
}
