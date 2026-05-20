//
//  SubscriptionTier.swift
//  Payam
//

import Foundation

enum SubscriptionTier: String, Codable {
    case free
    case premium
    case founding

    var isPremium: Bool {
        self != .free
    }
}
