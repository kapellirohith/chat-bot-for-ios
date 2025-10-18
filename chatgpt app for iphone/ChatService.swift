import Foundation

protocol ChatService {
    func send(messages: [ChatMessage], summary: String?) async throws -> (assistantMessage: ChatMessage, newSummary: String?)
}

// A simple mock service that echoes and summarizes to demonstrate plumbing.
struct MockChatService: ChatService {
    func send(messages: [ChatMessage], summary: String?) async throws -> (assistantMessage: ChatMessage, newSummary: String?) {
        // Simulate token control by summarizing older content and keeping last N messages
        let lastUser = messages.last(where: { $0.role == .user })?.text ?? ""
        let replyText = "You said: \(lastUser)\n(Images: \(messages.last?.imageURLs?.count ?? 0))"
        let msg = ChatMessage(role: .assistant, text: replyText)
        let newSummary = "Summary: \(summary ?? "") + \(lastUser.prefix(100))"
        return (msg, newSummary)
    }
}
