//
//  OpenAIVisionService.swift
//  chatgpt for iphone
//
//  Created by Rohith Kapelli on 26/08/25.
//


import Foundation
import UIKit

/// Multipart upload to /v1/responses by default.
/// If an Imgur Client ID is configured, uploads the image to Imgur first and then
/// calls /v1/chat/completions with an `image_url` (avoids huge base64 in messages).
final class OpenAIVisionService {
    private let apiKey: String
    private let imgurClientID: String?

    private let responsesEndpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let chatEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let imgurEndpoint = URL(string: "https://api.imgur.com/3/image")!

    init(apiKey: String, imgurClientID: String?) {
        self.apiKey = apiKey
        self.imgurClientID = imgurClientID
    }

    // MARK: - Public
    func describe(image: UIImage, prompt: String, model: String = "gpt-4o-mini") async throws -> String {
        // If Imgur Client ID exists -> use Imgur + chat/completions (image_url)
        if let cid = imgurClientID, !cid.isEmpty {
            let url = try await uploadToImgur(image: image, clientID: cid)
            return try await callChatCompletionsWithImageURL(imageURL: url, prompt: prompt, model: model)
        }

        // Fallback -> multipart /responses with real file attachment
        return try await callResponsesMultipart(image: image, prompt: prompt, model: model)
    }

    // MARK: - Imgur upload
    private func uploadToImgur(image: UIImage, clientID: String) async throws -> String {
        guard let pngData = image.pngData() else {
            throw NSError(domain: "Vision", code: -10, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image for Imgur"])
        }

        var req = URLRequest(url: imgurEndpoint)
        req.httpMethod = "POST"
        req.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Imgur accepts base64 body: image=<base64>&type=base64
        let base64 = pngData.base64EncodedString()
        let bodyString = "image=\(percentEncode(base64))&type=base64"
        req.httpBody = bodyString.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? "Imgur upload error"
            throw NSError(domain: "Imgur", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: txt])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let d = json?["data"] as? [String: Any], let link = d["link"] as? String {
            return link
        }
        throw NSError(domain: "Imgur", code: -11, userInfo: [NSLocalizedDescriptionKey: "Imgur response missing link"])
    }

    private func percentEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    // MARK: - OpenAI chat with image_url
    private func callChatCompletionsWithImageURL(imageURL: String, prompt: String, model: String) async throws -> String {
        var req = URLRequest(url: chatEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": imageURL]]
                ]
            ]
        ]

        let payload: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.3
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? "OpenAI error"
            throw NSError(domain: "OpenAI", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: txt])
        }

        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = root["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        return String(data: data, encoding: .utf8) ?? "(no response)"
    }

    // MARK: - OpenAI /v1/responses multipart (fallback)
    private func callResponsesMultipart(image: UIImage, prompt: String, model: String) async throws -> String {
        guard let fileData = image.pngData() else {
            throw NSError(domain: "Vision", code: -13, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }

        let filename = "upload.png"
        let boundary = "Boundary-\(UUID().uuidString)"

        let input: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt],
                        ["type": "input_image", "image_url": "attachment://\(filename)"]
                    ]
                ]
            ]
        ]

        let inputData = try JSONSerialization.data(withJSONObject: input, options: [])

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"input\"\r\n")
        append("Content-Type: application/json\r\n\r\n")
        body.append(inputData)
        append("\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: image/png\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")

        var req = URLRequest(url: responsesEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "OpenAI", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: txt])
        }

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let outText = root?["output_text"] as? String, !outText.isEmpty { return outText }
        if let output = root?["output"] as? [[String: Any]],
           let first = output.first,
           let content = first["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String {
            return text
        }
        if let choices = root?["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let text = message["content"] as? String {
            return text
        }

        return String(data: data, encoding: .utf8) ?? "(no response)"
    }
}
