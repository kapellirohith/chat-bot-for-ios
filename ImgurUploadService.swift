//
//  ImgurUploadService.swift
//  chatgpt for iphone
//
//  Created by Rohith Kapelli on 26/08/25.
//


import Foundation
import UIKit

struct ImgurUploadService {
    let clientID: String

    init(clientID: String) {
        self.clientID = clientID
    }

    /// Uploads `image` to Imgur and returns the public image URL (link).
    /// Uses application/x-www-form-urlencoded with `image=<base64>`.
    func upload(image: UIImage) async throws -> String {
        guard let pngData = image.pngData() else {
            throw NSError(domain: "ImgurUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }

        let url = URL(string: "https://api.imgur.com/3/image")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Request body: image=<base64>&type=base64
        let base64 = pngData.base64EncodedString()
        // Percent encode the base64 so it safely goes in x-www-form-urlencoded
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encoded = base64.addingPercentEncoding(withAllowedCharacters: allowed) ?? base64
        let bodyString = "image=\(encoded)&type=base64"
        req.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "ImgurUpload", code: -2, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        guard (200...299).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? "Imgur upload failed"
            throw NSError(domain: "ImgurUpload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: txt])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let dataDict = json?["data"] as? [String: Any],
           let link = dataDict["link"] as? String {
            return link
        }

        throw NSError(domain: "ImgurUpload", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid Imgur response"])
    }
}
