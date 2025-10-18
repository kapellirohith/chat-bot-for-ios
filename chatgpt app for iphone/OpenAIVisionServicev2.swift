import Foundation
import SwiftUI

final class OpenAIVisionServicev2 {
    private let apiKey: String
    private let imgurClientID: String?

    private let chatEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String, imgurClientID: String?) {
        self.apiKey = apiKey
        self.imgurClientID = imgurClientID
    }

    // Public entry
    func describe(
        image: PlatformImage,
        prompt: String,
        model: String = "gpt-4o",
        temperature: Double = 0.5
    ) async throws -> String {
        if let cid = imgurClientID, !cid.isEmpty {
            let uploader = ImgurUploadService(clientID: cid)
            let url = try await uploader.upload(image: image)
            return try await callChatCompletionsWithImageURL(
                imageURL: url,
                prompt: prompt,
                model: model,
                temperature: temperature
            )
        }
        // Fallback to base64 encoding if no Imgur ID
        return try await chatWithEmbeddedImage(messages: [], image: image, prompt: prompt, model: model, temperature: temperature)
    }
    
    // Public: send up to 10 images with an accompanying prompt. Prefers uploading to URLs when Imgur client ID is set to reduce token usage; otherwise embeds base64 JPEGs with downscaling and compression.
    func describe(
        images: [PlatformImage],
        prompt: String,
        model: String = "gpt-4o",
        temperature: Double = 0.5
    ) async throws -> String {
        let capped = Array(images.prefix(10))
        guard !capped.isEmpty else { return try await describe(image: PlatformImage(), prompt: prompt, model: model, temperature: temperature) }

        // If we have an Imgur Client ID, upload each image to get a URL to save tokens.
        if let cid = imgurClientID, !cid.isEmpty {
            let uploader = ImgurUploadService(clientID: cid)
            var urlStrings: [String] = []
            for img in capped {
                let url = try await uploader.upload(image: img)
                urlStrings.append(url)
            }
            return try await callChatCompletionsWithImageURLs(imageURLs: urlStrings, prompt: prompt, model: model, temperature: temperature)
        }

        // Fallback: embed images as base64 data URLs (token heavier). Downscale to 1024px max side and compress to ~0.7 quality.
        var contents: [[String: Any]] = [["type": "text", "text": prompt]]
        for img in capped {
            let processed = img.downscaled(toMaxDimension: 1024) ?? img
            guard let data = processed.jpegData(compressionQuality: 0.7) else { continue }
            let base64 = data.base64EncodedString()
            contents.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]])
        }
        return try await callChatCompletions(messages: [["role": "user", "content": contents]], model: model, temperature: temperature)
    }
    
    // Chat with image_url
    private func callChatCompletionsWithImageURL(
        imageURL: String,
        prompt: String,
        model: String,
        temperature: Double
    ) async throws -> String {
        var req = URLRequest(url: chatEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let temp = requiresFixedTemperature(model) ? 1.0 : temperature
        let messages: [[String: Any]] = [
            ["role": "user", "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": imageURL]]
            ]]
        ]

        let payload: [String: Any] = ["model": model, "messages": messages, "temperature": temp]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? "OpenAI error"
            throw NSError(domain: "OpenAI", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: txt])
        }

        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        return String(data: data, encoding: .utf8) ?? "(no response)"
    }

    // Chat with multiple image URLs
    private func callChatCompletionsWithImageURLs(
        imageURLs: [String],
        prompt: String,
        model: String,
        temperature: Double
    ) async throws -> String {
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        for url in imageURLs { content.append(["type": "image_url", "image_url": ["url": url]]) }
        return try await callChatCompletions(messages: [["role": "user", "content": content]], model: model, temperature: temperature)
    }

    // Core chat call used by the multi-image paths
    private func callChatCompletions(
        messages: [[String: Any]],
        model: String,
        temperature: Double
    ) async throws -> String {
        var req = URLRequest(url: chatEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let temp = requiresFixedTemperature(model) ? 1.0 : temperature
        let payload: [String: Any] = ["model": model, "messages": messages, "temperature": temp]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? "OpenAI error"
            throw NSError(domain: "OpenAI", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: txt])
        }
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        return String(data: data, encoding: .utf8) ?? "(no response)"
    }

    // Legacy base64 inline embedding
    private func chatWithEmbeddedImage(
        messages: [Message],
        image: PlatformImage,
        prompt: String,
        model: String = "gpt-4o",
        temperature: Double = 0.3
    ) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { // iOS compatible
            throw NSError(domain: "Vision", code: -20, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }
        let base64 = imageData.base64EncodedString()
        var requestMessages: [[String: Any]] = messages.map { ["role": $0.role, "content": $0.content] }

        requestMessages.append([
            "role": "user",
            "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
            ]
        ])
        
        let temp = requiresFixedTemperature(model) ? 1.0 : temperature
        let payload: [String: Any] = ["model": model, "messages": requestMessages, "temperature": temp]
        var req = URLRequest(url: chatEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (respData, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let txt = String(data: respData, encoding: .utf8) ?? "OpenAI error"
            throw NSError(domain: "OpenAI", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: txt])
        }

        if let root = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
           let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        // CORRECTED LINE: Use respData instead of data
        return String(data: respData, encoding: .utf8) ?? "(no response)"
    }

    private func requiresFixedTemperature(_ model: String) -> Bool {
        return model.contains("gpt-4o")
    }
}
