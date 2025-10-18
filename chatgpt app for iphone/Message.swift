import Foundation
import SwiftUI // Using SwiftUI for PlatformImage

public struct Message: Identifiable, Codable, Hashable {
    public let id: UUID
    public var role: String
    public var content: String
    public var toolCallId: String?
    public var imageData: Data? // Use Data for Codable support

    // Computed property to easily get a UIImage for the UI
    public var image: PlatformImage? {
        guard let data = imageData else { return nil }
        return PlatformImage(data: data)
    }

    // Custom initializer to handle creating a message with an image
    public init(id: UUID = UUID(), role: String, content: String, toolCallId: String? = nil, image: PlatformImage? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        // Convert the PlatformImage (UIImage on iOS) to Data for storage
        self.imageData = image?.jpegData(compressionQuality: 0.8)
    }
    
    // Required for Codable conformance since we have a non-standard property
    enum CodingKeys: String, CodingKey {
        case id, role, content, toolCallId, imageData
    }
}


