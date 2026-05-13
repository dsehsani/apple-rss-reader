//
//  ChatMessage.swift
//  OpenRSS
//

import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String

    enum Role {
        case user
        case assistant
    }
}
