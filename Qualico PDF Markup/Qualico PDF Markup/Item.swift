//
//  Item.swift
//  Qualico PDF Markup
//
//  Created by Yancey Register on 12/11/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
