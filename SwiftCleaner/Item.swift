//
//  Item.swift
//  SwiftCleaner
//
//  Created by Holger Krupp on 22.01.25.
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
