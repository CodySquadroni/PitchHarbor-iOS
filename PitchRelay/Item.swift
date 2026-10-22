//
//  Item.swift
//  PitchRelay
//
//  Created by Cody Squadroni on 10/22/26.
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
