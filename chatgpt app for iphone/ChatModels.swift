import Foundation
import SwiftUI

public struct ChatMessage: Identifiable, Codable, Equatable {
    public enum Role: String, Codable { case user, assistant, system }
    public let id: UUID
    public var role: Role
    public var text: String
    public var imageURLs: [URL]?
    public var date: Date

    public init(id: UUID = UUID(), role: Role, text: String, imageURLs: [URL]? = nil, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.imageURLs = imageURLs
        self.date = date
    }
}

public struct Conversation: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var messages: [ChatMessage]
    public var summary: String? // rolling summary to control tokens

    public init(id: UUID = UUID(), title: String = "New Chat", messages: [ChatMessage] = [], summary: String? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.summary = summary
    }
}
