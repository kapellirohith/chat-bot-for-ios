//
//  Message.swift
//  chatgpt for iphone
//
//  Created by Rohith Kapelli on 26/08/25.
//


import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    let role: String
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
