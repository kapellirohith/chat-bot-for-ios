import Foundation
import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(Photos)
import Photos
#endif

@MainActor
public final class ImageGenerationManager: ObservableObject {
    #if canImport(UIKit)
    public typealias PlatformImage = UIImage
    #elseif canImport(AppKit)
    public typealias PlatformImage = NSImage
    #else
    public typealias PlatformImage = Any
    #endif

    // Last successfully generated image
    @Published public private(set) var generatedImage: PlatformImage? = nil

    // Configuration
    public var maxAttempts: Int = 3
    public var requestTimeout: TimeInterval = 120 // seconds (increase to reduce spurious timeouts)

    @Published public var isGenerating: Bool = false
    @Published public var statusMessage: String = ""

    // Last request context for easy retry
    private var lastPrompt: String?
    private var lastOperationNoPrompt: (() async throws -> PlatformImage)?
    private var lastOperationWithPrompt: ((_ prompt: String) async throws -> PlatformImage)?

    public init() {}

    public func generateImage(
        for prompt: String,
        timeout: TimeInterval? = nil,
        operation: @escaping () async throws -> PlatformImage
    ) async -> Result<PlatformImage, Error> {
        isGenerating = true
        statusMessage = "Generating an actual image for your prompt…"

        lastPrompt = prompt
        lastOperationNoPrompt = operation
        lastOperationWithPrompt = nil

        let attempts = max(1, maxAttempts)
        let timeoutSeconds = timeout ?? requestTimeout
        var attempt = 0
        var lastError: Error?

        while attempt < attempts {
            attempt += 1
            do {
                try Task.checkCancellation()
                let image: PlatformImage = try await withTimeout(timeoutSeconds) {
                    try await operation()
                }
                try Task.checkCancellation()
                generatedImage = image
                isGenerating = false
                statusMessage = ""
                return .success(image)
            } catch is CancellationError {
                isGenerating = false
                statusMessage = "Cancelled."
                return .failure(CancellationError())
            } catch {
                lastError = error
                if attempt < attempts {
                    // Exponential backoff with jitter (0.5, 1.0, 2.0, ...) +/- 20%
                    let base = 0.5 * pow(2.0, Double(attempt - 1))
                    let jitter = base * (Double.random(in: -0.2...0.2))
                    let backoffSeconds = max(0.25, base + jitter)
                    statusMessage = "Still working… retrying (attempt \(attempt + 1) of \(attempts))"
                    try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                    continue
                } else {
                    break
                }
            }
        }

        isGenerating = false
        statusMessage = "We couldn't generate the image right now. Please try again."
        return .failure(lastError ?? NSError(domain: "ImageGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
    }

    // Overload that passes the (possibly sanitized) prompt to the operation.
    public func generateImage(
        for prompt: String,
        timeout: TimeInterval? = nil,
        operation: @escaping (_ prompt: String) async throws -> PlatformImage
    ) async -> Result<PlatformImage, Error> {
        lastPrompt = prompt
        lastOperationWithPrompt = operation
        lastOperationNoPrompt = nil

        // First try with the original prompt
        let firstAttempt = await generateImage(for: prompt, timeout: timeout) {
            try await operation(prompt)
        }
        // If it worked, return early
        if case .success = firstAttempt { return firstAttempt }

        // If failure looks like a policy error, try a safer prompt variant once
        if case .failure(let error) = firstAttempt, looksLikePolicyError(error) {
            let safe = sanitizePrompt(prompt)
            statusMessage = "Adjusting your prompt for safety and retrying…"
            return await generateImage(for: safe, timeout: timeout) {
                try await operation(safe)
            }
        }

        // Otherwise just return the first failure
        return firstAttempt
    }

    // Heuristic for detecting policy-related errors from upstream services
    private func looksLikePolicyError(_ error: Error) -> Bool {
        let msg = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? String(describing: error)
        let lower = msg.lowercased()
        return lower.contains("policy") || lower.contains("content_policy_violation") || lower.contains("safety system")
    }

    // Produces a conservative, family-friendly prompt variant to avoid tripping safety filters
    private func sanitizePrompt(_ prompt: String) -> String {
        var cleaned = prompt
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = "pleasant subject" }
        return "A wholesome, family-friendly, non-violent, non-sensitive illustration of \(cleaned). No text, no logos, no watermarks, suitable for all ages."
    }

    private func withTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try Task.checkCancellation()
                return try await operation()
            }
            group.addTask {
                let ns = UInt64(max(0, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw NSError(domain: "ImageGeneration", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Request timed out"])
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw NSError(domain: "ImageGeneration", code: -1002, userInfo: [NSLocalizedDescriptionKey: "No result"])
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Export / Save

    public enum ImageFormat {
        case png
        case jpeg(quality: Double)
    }

    public func exportLastImage(to format: ImageFormat = .png, suggestedName: String = "GeneratedImage") throws -> URL {
        guard let image = generatedImage else {
            throw NSError(domain: "ImageGeneration", code: -2000, userInfo: [NSLocalizedDescriptionKey: "No generated image to export"]) }
        let data = try data(from: image, format: format)
        let ext: String = {
            switch format { case .png: return "png"; case .jpeg: return "jpg" }
        }()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suggestedName)-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension(ext)
        try data.write(to: url, options: .atomic)
        return url
    }

    #if canImport(UIKit)
    // Save to Photos on iOS/tvOS (requires NSPhotoLibraryAddUsageDescription in Info.plist)
    public func saveLastImageToPhotoLibrary(format: ImageFormat = .png) async throws {
        guard let image = generatedImage else {
            throw NSError(domain: "ImageGeneration", code: -2001, userInfo: [NSLocalizedDescriptionKey: "No generated image to save"]) }
        #if canImport(Photos)
        try await PHPhotoLibrary.shared().performChanges {
            let data = try? self.data(from: image, format: format)
            if let data, let uiImage = UIImage(data: data) {
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            }
        }
        #else
        // Fallback: write to temporary file so UI can share/save
        _ = try exportLastImage(to: format)
        #endif
    }
    #endif

    #if canImport(AppKit)
    // Save to Downloads on macOS
    @discardableResult
    public func saveLastImageToDownloads(format: ImageFormat = .png, suggestedName: String = "GeneratedImage") throws -> URL {
        guard let image = generatedImage else {
            throw NSError(domain: "ImageGeneration", code: -2002, userInfo: [NSLocalizedDescriptionKey: "No generated image to save"]) }
        let data = try data(from: image, format: format)
        let ext: String = {
            switch format { case .png: return "png"; case .jpeg: return "jpg" }
        }()
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let url = downloads.appendingPathComponent("\(suggestedName)-\(Int(Date().timeIntervalSince1970))).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }
    #endif

    // MARK: - Data conversion
    private func data(from image: PlatformImage, format: ImageFormat) throws -> Data {
        #if canImport(UIKit)
        switch format {
        case .png:
            guard let data = image.pngData() else { throw NSError(domain: "ImageGeneration", code: -2100, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"]) }
            return data
        case .jpeg(let quality):
            guard let data = image.jpegData(compressionQuality: max(0.0, min(1.0, quality))) else { throw NSError(domain: "ImageGeneration", code: -2101, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JPEG"]) }
            return data
        }
        #elseif canImport(AppKit)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            throw NSError(domain: "ImageGeneration", code: -2102, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap rep"]) }
        switch format {
        case .png:
            guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "ImageGeneration", code: -2103, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"]) }
            return data
        case .jpeg(let quality):
            let q = max(0.0, min(1.0, quality))
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: q]) else { throw NSError(domain: "ImageGeneration", code: -2104, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JPEG"]) }
            return data
        }
        #else
        throw NSError(domain: "ImageGeneration", code: -2199, userInfo: [NSLocalizedDescriptionKey: "Unsupported platform for image encoding"]) 
        #endif
    }

    // MARK: - Retry helpers
    public func canRetry() -> Bool { lastOperationNoPrompt != nil || lastOperationWithPrompt != nil }

    @discardableResult
    public func retryLast(timeout: TimeInterval? = nil) async -> Result<PlatformImage, Error> {
        guard let prompt = lastPrompt else {
            return .failure(NSError(domain: "ImageGeneration", code: -2300, userInfo: [NSLocalizedDescriptionKey: "No previous request to retry"]))
        }
        if let op = lastOperationNoPrompt {
            return await generateImage(for: prompt, timeout: timeout, operation: op)
        } else if let op = lastOperationWithPrompt {
            return await generateImage(for: prompt, timeout: timeout, operation: op)
        } else {
            return .failure(NSError(domain: "ImageGeneration", code: -2301, userInfo: [NSLocalizedDescriptionKey: "Missing operation for retry"]))
        }
    }

    // Retries but if a policy-like failure occurs, it will sanitize the prompt and retry once automatically.
    @discardableResult
    public func retryLastWithSanitization(timeout: TimeInterval? = nil) async -> Result<PlatformImage, Error> {
        guard let prompt = lastPrompt else {
            return .failure(NSError(domain: "ImageGeneration", code: -2302, userInfo: [NSLocalizedDescriptionKey: "No previous request to retry"]))
        }
        if let op = lastOperationNoPrompt {
            // Wrap the op to ignore the sanitized prompt and just call the op
            return await generateImage(for: prompt, timeout: timeout) {
                try await op()
            }
        } else if let op = lastOperationWithPrompt {
            return await generateImage(for: prompt, timeout: timeout, operation: op)
        } else {
            return .failure(NSError(domain: "ImageGeneration", code: -2303, userInfo: [NSLocalizedDescriptionKey: "Missing operation for retry"]))
        }
    }
}
