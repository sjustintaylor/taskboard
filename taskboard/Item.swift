//
//  Item.swift
//  taskboard
//
//  Created by Justin Taylor on 15/10/2026.
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
