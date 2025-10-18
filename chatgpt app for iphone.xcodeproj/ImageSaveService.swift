// ImageSaveService.swift
// Fast, reliable saving of UIImages to Photos with a success notification.

import Foundation
import Photos
import UserNotifications
import UIKit

enum ImageSaveError: Error, LocalizedError {
    case authorizationDenied
    case encodingFailed
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied: return "Photos access denied. Enable it in Settings."
        case .encodingFailed: return "Failed to encode image for saving."
        case .saveFailed(let message): return message
        }
    }
}

struct ImageSaveService {
    /// Saves a UIImage to the Photos app efficiently and posts a local notification on success.
    /// - Parameters:
    ///   - image: The image to save
    ///   - quality: JPEG compression quality (0.0 - 1.0). Defaults to 0.92 for speed/size balance.
    /// - Returns: The local identifier of the created PHAsset
    @discardableResult
    static func saveToPhotos(_ image: UIImage, quality: CGFloat = 0.92) async throws -> String {
        // Do encoding off the main thread for speed
        let jpegData: Data = try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                if let data = image.jpegData(compressionQuality: quality) {
                    continuation.resume(returning: data)
                } else if let data = image.pngData() { // fallback
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ImageSaveError.encodingFailed)
                }
            }
        }

        // Ensure Photos authorization
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ImageSaveError.authorizationDenied
        }

        // Run under a background task so saving isn't interrupted when the screen locks
        return try await BackgroundTaskRunner.run(name: "SavePhoto") {
            try await withCheckedThrowingContinuation { continuation in
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    // Hint the uniform type if we can guess JPEG vs PNG
                    if jpegData.isLikelyJPEG {
                        options.uniformTypeIdentifier = "public.jpeg"
                    }
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: jpegData, options: options)
                }, completionHandler: { success, error in
                    if let error { continuation.resume(throwing: ImageSaveError.saveFailed(error.localizedDescription)) }
                    else if success {
                        // Fetch the most recent asset's local identifier in a safe way
                        let fetchOptions = PHFetchOptions()
                        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                        fetchOptions.fetchLimit = 1
                        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                        let localID = assets.firstObject?.localIdentifier ?? ""
                        Task { await Self.postSavedNotification() }
                        continuation.resume(returning: localID)
                    } else {
                        continuation.resume(throwing: ImageSaveError.saveFailed("Unknown error while saving image."))
                    }
                })
            }
        }
    }

    @MainActor
    private static func postSavedNotification() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await requestNotificationAuthorization(center: center)
        }
        let content = UNMutableNotificationContent()
        content.title = "Photo Saved"
        content.body = "Your image was saved to Photos."
        #if canImport(UIKit)
        content.sound = .default
        #endif
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    private static func requestNotificationAuthorization(center: UNUserNotificationCenter) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }
}

private extension Data {
    var isLikelyJPEG: Bool {
        // JPEG magic: FF D8 at start
        return count >= 2 && self[0] == 0xFF && self[1] == 0xD8
    }
}
