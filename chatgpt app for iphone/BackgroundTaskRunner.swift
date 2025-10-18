// BackgroundTaskRunner.swift
// Keeps critical async operations (like OpenAI requests) alive when the app goes to background
// by using a background task assertion.

import Foundation
import UIKit

public enum BackgroundTaskRunner {
    /// Run an async operation under a background task assertion so it can continue briefly
    /// after the app moves to the background (e.g., when the display turns off).
    ///
    /// Usage:
    ///   await BackgroundTaskRunner.run(name: "OpenAIRequest") {
    ///       try await apiClient.sendMessage(...)
    ///   }
    @discardableResult
    public static func run<T>(name: String = "BackgroundOperation",
                              expirationHandler: (() -> Void)? = nil,
                              operation: @escaping () async throws -> T) async rethrows -> T {
        let identifier = await begin(name: name, expirationHandler: expirationHandler)
        defer { end(identifier: identifier) }
        return try await operation()
    }

    /// Fire-and-forget variant for non-throwing operations.
    public static func run(name: String = "BackgroundOperation",
                           expirationHandler: (() -> Void)? = nil,
                           operation: @escaping () async -> Void) {
        Task {
            let identifier = await begin(name: name, expirationHandler: expirationHandler)
            defer { end(identifier: identifier) }
            await operation()
        }
    }

    @MainActor
    private static func begin(name: String, expirationHandler: (() -> Void)?) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name) {
            expirationHandler?()
        }
    }

    private static func end(identifier: UIBackgroundTaskIdentifier) {
        // Ensure end is called on main since UIApplication is main-thread-affine.
        DispatchQueue.main.async {
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }
}

// MARK: - URLSession helper tuned for flaky/background networks
public enum NetworkSessionFactory {
    /// A default URLSession tuned for AI requests.
    /// - Uses waitsForConnectivity to pause instead of failing when temporarily offline
    /// - Allows constrained/expensive networks
    /// - Bumps request timeouts for long generations
    public static func make() -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }
}
