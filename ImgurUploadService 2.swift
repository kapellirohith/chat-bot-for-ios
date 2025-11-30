//
//  ImgurUploadService 2.swift
//  chatgpt for iphone
//
//  Created by Rohith Kapelli on 26/08/25.
//


import Foundation
import UIKit

struct ImgurUploadService {
    private let clientID: String

    init(clientID: String) {
        self.clientID = clientID
    }

    func upload(image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "ImgurUpload", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get JPEG data"])
        }

        var request = URLRequest(url: URL(string: "https://api.imgur.com/3/image")!)
        request.httpMethod = "POST"
        request.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"upload.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (responseData, _) = try await URLSession.shared.data(for: request)

        let decoded = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if let data = decoded?["data"] as? [String: Any],
           let link = data["link"] as? String {
            return link
        }
        throw NSError(domain: "ImgurUpload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Imgur response"])
    }
}
