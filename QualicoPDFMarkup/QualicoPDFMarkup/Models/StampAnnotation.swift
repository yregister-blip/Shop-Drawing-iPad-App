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
    case fit = "FIT"         // Dynamic: Fit + ID + Date
    case qcFit = "QC FIT"    // Dynamic: QC Fit + Inspector + Fit ID + Date

    var imageName: String {
        switch self {
        case .fabricated:
            return "fabricated"
        case .hold:
            return "hold"
        case .fitOnly:
            return "fit_only"
        case .fit:
            return "fit"
        case .qcFit:
            return "qc_fit"
        }
    }

    /// Returns true if the stamp content is generated dynamically based on user input/time
    var isDynamic: Bool {
        return self == .fit || self == .qcFit
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
