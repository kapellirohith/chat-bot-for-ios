import Foundation
import Combine
import SwiftUI
import UserNotifications

@MainActor
public final class LocalActionManager: ObservableObject {
    @Published public private(set) var statusMessage: String = ""

    public init() {}

    // MARK: - Time / Date (fully on-device)

    public func currentTimeString(timeStyle: DateFormatter.Style = .short, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let df = DateFormatter()
        df.locale = locale
        df.timeZone = timeZone
        df.dateStyle = .none
        df.timeStyle = timeStyle
        return df.string(from: Date())
    }

    public func currentDateString(dateStyle: DateFormatter.Style = .medium, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let df = DateFormatter()
        df.locale = locale
        df.timeZone = timeZone
        df.dateStyle = dateStyle
        df.timeStyle = .none
        return df.string(from: Date())
    }

    // MARK: - Timers (on-device via local notifications)
    // Schedules a one-shot local notification as a timer. Returns the identifier used.
    // Notes:
    // - Requires the app to request notification permission.
    // - Works in foreground/background; notification delivers when time elapses.
    // - If you need exact alarm UI on iOS 18+, you can integrate AlarmKit separately.
    @discardableResult
    public func startLocalTimer(seconds: TimeInterval,
                                title: String = "Timer Finished",
                                body: String? = nil,
                                identifier: String = UUID().uuidString) async throws -> String {
        let clamped = max(1.0, seconds)
        try await ensureNotificationAuthorization()

        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        #if canImport(UIKit)
        content.sound = .default
        #endif

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: clamped, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        return try await withCheckedThrowingContinuation { continuation in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    self.statusMessage = "Timer scheduled for \(Int(clamped))s."
                    continuation.resume(returning: identifier)
                }
            }
        }
    }

    // Cancels a previously scheduled local timer by identifier.
    public func cancelLocalTimer(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        statusMessage = "Timer cancelled."
    }

    // MARK: - Permissions
    private func ensureNotificationAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            throw NSError(domain: "LocalActionManager", code: -3001, userInfo: [NSLocalizedDescriptionKey: "Notifications are denied. Enable them in Settings to use timers."])
        case .notDetermined:
            let granted = try await requestNotificationAuthorization()
            if !granted {
                throw NSError(domain: "LocalActionManager", code: -3000, userInfo: [NSLocalizedDescriptionKey: "Notification permission not granted."])
            }
        @unknown default:
            return
        }
    }

    private func requestNotificationAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
