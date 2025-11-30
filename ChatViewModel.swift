//
//  ChatViewModel.swift
//  chatgpt for iphone
//
//  Created by Rohith Kapelli on 26/08/25.
//


import Foundation
import SwiftUI
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = [
        Message(role: "system", content: "Hi! Paste your API key with the key button (🔑) and ask me anything."),
        Message(role: "system", content:
"""
TOOL_POLICY:
- Use OpenAI API for text
- Use OpenAI Vision API for images
- Use WebSearch API if needed
"""
        )
    ]

    @Published var isTyping = false
    @Published var showKeyEntry = false
    @Published var showSerpKeyEntry = false
    @Published var showImgurKeyEntry = false

    private var openAIService: OpenAIService?
    private var openAIVisionService: OpenAIVisionService?
    private var webSearchService: WebSearchService?

    // Store API keys
    private var apiKey: String? {
        didSet {
            if let key = apiKey {
                openAIService = OpenAIService(apiKey: key)
                openAIVisionService = OpenAIVisionService(apiKey: key, imgurClientID: imgurClientID)
            }
        }
    }
    private var serpKey: String? {
        didSet {
            if let key = serpKey {
                webSearchService = WebSearchService(apiKey: key)
            }
        }
    }
    private var imgurClientID: String? {
        didSet {
            if let apiKey = apiKey {
                openAIVisionService = OpenAIVisionService(apiKey: apiKey, imgurClientID: imgurClientID)
            }
        }
    }

    // MARK: - Init
    init() {
        apiKey = KeychainHelper.get("OpenAIKey")
        serpKey = KeychainHelper.get("SerpKey")
        imgurClientID = KeychainHelper.get("ImgurClientID")

        if let key = apiKey {
            openAIService = OpenAIService(apiKey: key)
            openAIVisionService = OpenAIVisionService(apiKey: key, imgurClientID: imgurClientID)
        }
        if let key = serpKey {
            webSearchService = WebSearchService(apiKey: key)
        }
    }

    // MARK: - Message sending
    func sendMessage(_ text: String) async {
        guard let service = openAIService else { return }
        let newMsg = Message(role: "user", content: text)
        messages.append(newMsg)
        isTyping = true
        do {
            let reply = try await service.sendMessage(messages: messages)
            messages.append(Message(role: "assistant", content: reply))
        } catch {
            messages.append(Message(role: "system", content: "Error: \(error.localizedDescription)"))
        }
        isTyping = false
    }

    func sendImageMessage(_ image: UIImage, prompt: String = "Describe this image.") async {
        guard let vision = openAIVisionService else { return }
        messages.append(Message(role: "user", content: prompt))
        isTyping = true
        do {
            let reply = try await vision.describe(image: image, prompt: prompt)
            messages.append(Message(role: "assistant", content: reply))
        } catch {
            messages.append(Message(role: "system", content: "Vision error: \(error.localizedDescription)"))
        }
        isTyping = false
    }

    func sendWebSearch(_ query: String) async {
        guard let service = webSearchService else { return }
        messages.append(Message(role: "user", content: query))
        isTyping = true
        do {
            let results = try await service.search(query: query)
            messages.append(Message(role: "assistant", content: results))
        } catch {
            messages.append(Message(role: "system", content: "Web search error: \(error.localizedDescription)"))
        }
        isTyping = false
    }

    // MARK: - Key handling
    func saveAPIKey(_ key: String) {
        KeychainHelper.save(key, service: "OpenAIKey")
        apiKey = key
    }

    func saveSerpKey(_ key: String) {
        KeychainHelper.save(key, service: "SerpKey")
        serpKey = key
    }

    func saveImgurClientID(_ id: String) {
        KeychainHelper.save(id, service: "ImgurClientID")
        imgurClientID = id
    }
}
