//
//  OpenAIService.swift
//  chatgpt for iphone
//
//  Created by Rohith Kapelli on 26/08/25.
//


import Foundation

struct OpenAIService {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func sendMessage(messages: [Message]) async throws -> String {
        let mappedMessages = messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": mappedMessages
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, _) = try await URLSession.shared.data(for: request)

        let decoded = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        let choices = decoded?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String

        return content ?? "No reply"
    }
}
