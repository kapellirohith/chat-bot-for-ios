import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

final class OpenAIService {
    private let apiKey: String
    private let chatEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let imageEndpoint = URL(string: "https://api.openai.com/v1/images/generations")! // New endpoint for DALL-E

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // This is your working chat function. It remains unchanged.
    func chat(messages: [Message], model: String, temperature: Double) async throws -> String {
        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiMessages = messages.map { ["role": $0.role, "content": $0.content] }

        let payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": temperature
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await withRetry(times: 1) {
            try await self.session.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "API Error"
            throw NSError(domain: "OpenAIService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        guard let content = apiResponse.choices.first?.message.content else {
            throw NSError(domain: "OpenAIService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return content
    }

    // MARK: - New Image Generation Function
    func generateImage(prompt: String, model: String) async throws -> String {
        var request = URLRequest(url: imageEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Determine the model to use and set payload accordingly.
        // Supported models: "dall-e-2", "dall-e-3", "gpt-image-1"
        // Fall back to "dall-e-3" for unsupported models.
        let usedModel: String
        let size: String
        
        switch model {
        case "dall-e-2":
            usedModel = "dall-e-2"
            size = "512x512" // DALL·E 2 supports only 512x512
        case "gpt-image-1":
            usedModel = "gpt-image-1"
            size = "1024x1024" // Use 1024x1024 similar to DALL·E 3, ready for future tweaks
        default:
            usedModel = "dall-e-3"
            size = "1024x1024" // DALL·E 3 standard size
        }

        // Build payload with a safe 'quality' value. Some providers expect one of: low, medium, high, auto.
        // We'll default to 'auto' for widest compatibility and retry without 'quality' if rejected.
        var payload: [String: Any] = [
            "model": usedModel,
            "prompt": prompt,
            "n": 1,
            "size": size
        ]
        // Prefer 'auto' for gpt-image-1; omit for others unless needed
        if usedModel == "gpt-image-1" {
            payload["quality"] = "auto"
        }

        func sendRequest(with payload: [String: Any]) async throws -> (Data, URLResponse) {
            var req = URLRequest(url: imageEndpoint)
            req.httpMethod = "POST"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return try await withRetry(times: 1) { try await self.session.data(for: req) }
        }

        // First attempt (possibly with quality)
        var (data, response) = try await sendRequest(with: payload)

        // If the server rejects 'quality', retry without it once
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.lowercased().contains("param\": \"quality\"") || (body.lowercased().contains("invalid") && body.lowercased().contains("quality")) {
                var retryPayload = payload
                retryPayload.removeValue(forKey: "quality")
                (data, response) = try await sendRequest(with: retryPayload)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Image Generation API Error"
            throw NSError(domain: "OpenAIService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        // Decode the response to get the URL of the generated image
        let imageResponse = try JSONDecoder().decode(ImageResponse.self, from: data)
        guard let imageUrl = imageResponse.data.first?.url, URL(string: imageUrl) != nil else {
            throw NSError(domain: "OpenAIService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Invalid image URL in response"])
        }
        
        return imageUrl
    }
    
    // MARK: - Image-to-Image (Edits)
    // Uses multipart/form-data to send a source image and a prompt to the images/edits endpoint.
    // Falls back by removing 'quality' if the server rejects it.
    func generateImageFromImage(prompt: String, model: String, imageData: Data) async throws -> String {
        let editsEndpoint = URL(string: "https://api.openai.com/v1/images/edits")!

        // Build multipart body
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: editsEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        func makeBody(includeQuality: Bool) -> Data {
            var body = Data()
            func append(_ string: String) { body.append(string.data(using: .utf8)!) }

            // model
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
            append("\(model)\r\n")

            // prompt
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            append("\(prompt)\r\n")

            // size (keep consistent with generation)
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"size\"\r\n\r\n")
            append("1024x1024\r\n")

            if includeQuality {
                append("--\(boundary)\r\n")
                append("Content-Disposition: form-data; name=\"quality\"\r\n\r\n")
                append("auto\r\n")
            }

            // image file
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n")
            append("Content-Type: image/jpeg\r\n\r\n")
            body.append(imageData)
            append("\r\n")

            append("--\(boundary)--\r\n")
            return body
        }

        // First attempt: include quality=auto for gpt-image-1
        var includeQuality = (model == "gpt-image-1")
        request.httpBody = makeBody(includeQuality: includeQuality)

        func send(_ req: URLRequest) async throws -> (Data, URLResponse) {
            return try await withRetry(times: 1) { try await self.session.data(for: req) }
        }

        var (data, response) = try await send(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.lowercased().contains("param\": \"quality\"") || (body.lowercased().contains("invalid") && body.lowercased().contains("quality")) {
                includeQuality = false
                request.httpBody = makeBody(includeQuality: includeQuality)
                (data, response) = try await send(request)
            }
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Image Edit API Error"
            throw NSError(domain: "OpenAIService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        // Reuse the same response model as generations (url field)
        let imageResponse = try JSONDecoder().decode(ImageResponse.self, from: data)
        guard let imageUrl = imageResponse.data.first?.url, URL(string: imageUrl) != nil else {
            throw NSError(domain: "OpenAIService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Invalid image URL in response"])
        }
        return imageUrl
    }
    
    // MARK: - Helper Structs for Decoding API Responses
    
    // For chat responses
    private struct APIResponse: Decodable {
        struct Choice: Decodable {
            let message: MessageContent
        }
        let choices: [Choice]
    }
    
    private struct MessageContent: Decodable {
        let role: String
        let content: String?
    }
    
    // For image generation responses
    private struct ImageResponse: Decodable {
        struct ImageData: Decodable {
            let url: String
        }
        let data: [ImageData]
    }
}

private func withRetry<T>(times: Int, _ block: @escaping () async throws -> T) async throws -> T {
    var attempts = 0
    while true {
        do { return try await block() }
        catch {
            attempts += 1
            if attempts > times { throw error }
            if (error as? URLError)?.code == .timedOut {
                continue
            } else {
                throw error
            }
        }
    }
}
