//
//  ImgurUploadService.swift
//  chatgpt app for iphone
//
//  Created by Rohith Kapelli on 02/10/25.
//


import Foundation
import SwiftUI

struct ImgurUploadService {
    let clientID: String

    func upload(image: PlatformImage) async throws -> String {
        guard let pngData = image.pngData() else {
            throw NSError(domain: "ImgurUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image to PNG"])
        }

        let url = URL(string: "https://api.imgur.com/3/image")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        
        // -- Boundary
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        // -- Part Headers
        body.append("Content-Disposition: form-data; name=\"image\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        // -- Part Data
        body.append(pngData)
        // -- Closing Boundary
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        req.httpBody = body

        let session = NetworkSessionFactory.make()
        let (data, response): (Data, URLResponse) = try await BackgroundTaskRunner.run(name: "ImgurUpload") {
            try await session.data(for: req)
        }
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Imgur upload failed"
            throw NSError(domain: "ImgurUpload", code: (response as? HTTPURLResponse)?.statusCode ?? -2, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let dataDict = json?["data"] as? [String: Any],
           let link = dataDict["link"] as? String {
            return link
        }

        throw NSError(domain: "ImgurUpload", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid Imgur response format"])
    }
}
