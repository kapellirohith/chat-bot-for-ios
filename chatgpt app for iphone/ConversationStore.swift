import Foundation
import SwiftUI
import Combine

@MainActor
final class ConversationStore: ObservableObject {
    // Explicit publisher to satisfy ObservableObject conformance across all targets
    public let objectWillChange = ObservableObjectPublisher()
    
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationID: Conversation.ID? = nil

    private let persistenceURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("conversations.json")
    }()

    init() {
        load()
        if conversations.isEmpty {
            let convo = Conversation()
            conversations = [convo]
            selectedConversationID = convo.id
        } else if selectedConversationID == nil {
            selectedConversationID = conversations.first?.id
        }
    }

    func newConversation() {
        let convo = Conversation()
        conversations.insert(convo, at: 0)
        selectedConversationID = convo.id
        save()
    }

    func deleteConversation(_ id: Conversation.ID) {
        conversations.removeAll { $0.id == id }
        if selectedConversationID == id { selectedConversationID = conversations.first?.id }
        save()
    }

    func appendMessage(_ message: ChatMessage, to id: Conversation.ID) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].messages.append(message)
        save()
    }

    func replaceMessages(_ messages: [ChatMessage], for id: Conversation.ID) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].messages = messages
        save()
    }

    func setTitle(_ title: String, for id: Conversation.ID) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].title = title
        save()
    }

    func setSummary(_ summary: String?, for id: Conversation.ID) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].summary = summary
        save()
    }

    func selectedConversation() -> Conversation? {
        guard let id = selectedConversationID else { return nil }
        return conversations.first(where: { $0.id == id })
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: persistenceURL)
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: persistenceURL)
            conversations = try JSONDecoder().decode([Conversation].self, from: data)
        } catch {
            conversations = []
        }
    }
}
