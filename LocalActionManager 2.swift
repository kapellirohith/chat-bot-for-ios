import Foundation
import SwiftUI
import Combine

#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(WeatherKit)
import WeatherKit
#endif

/// A small utility manager for common on-device actions like timers and (optional) weather.
/// - Features:
///   - `currentTimeString(locale:timeStyle:)`
///   - `startTimer(minutes:)` using AlarmKit on iOS 18+ (when available), else local notifications
///   - Optional WeatherKit integration scaffold (when WeatherKit is available)
@MainActor
public final class LocalActionManagerV2: NSObject, ObservableObject {

    // ObservableObject publisher (required when no @Published properties are present)
    public let objectWillChange = ObservableObjectPublisher()

    // MARK: - Configuration
    /// When true, the manager will attempt to use AlarmKit on supported platforms (iOS 18+).
    /// If AlarmKit isn't available, it will automatically fall back to local notifications.
    public var useAlarmKitIfAvailable: Bool = true

    // MARK: - Errors
    public enum LocalActionError: LocalizedError {
        case invalidDuration
        case notificationsNotAvailable
        case notificationsDenied
        case schedulingFailed(String)
        case locationServicesDisabled
        case locationDenied
        case locationRestricted
        case weatherNotAvailable
        case featureUnavailable

        public var errorDescription: String? {
            switch self {
            case .invalidDuration:
                return "Please provide a duration greater than zero."
            case .notificationsNotAvailable:
                return "Notifications are not available on this device."
            case .notificationsDenied:
                return "Notification permission was denied."
            case .schedulingFailed(let message):
                return "Failed to schedule timer: \(message)"
            case .locationServicesDisabled:
                return "Location services are disabled."
            case .locationDenied:
                return "Location permission was denied."
            case .locationRestricted:
                return "Location use is restricted."
            case .weatherNotAvailable:
                return "Weather is not available on this platform."
            case .featureUnavailable:
                return "This feature is not available on this platform."
            }
        }
    }

    // MARK: - Dependencies
    #if canImport(UserNotifications)
    private let notificationCenter = UNUserNotificationCenter.current()
    #endif

    #if canImport(CoreLocation)
    private var locationManager: CLLocationManager?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    #endif

    public override init() {
        super.init()
    }

    // MARK: - Time String
    /// Returns the current time formatted according to the provided locale and style.
    /// - Parameters:
    ///   - locale: The locale to use. Defaults to `.current`.
    ///   - timeStyle: The `DateFormatter.Style` (e.g., `.short`, `.medium`, `.long`). Defaults to `.short`.
    /// - Returns: A localized time string.
    public func currentTimeString(locale: Locale = .current, timeStyle: DateFormatter.Style = .short) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = timeStyle
        formatter.dateStyle = .none
        return formatter.string(from: Date())
    }

    // MARK: - Timer / Alarm
    /// Starts a countdown timer for the specified number of minutes.
    /// - Parameter minutes: The number of minutes until the timer fires. Must be > 0.
    /// - Throws: `LocalActionError` on permission or scheduling failure.
    public func startTimer(minutes: Int) async throws {
        guard minutes > 0 else { throw LocalActionError.invalidDuration }

        // Prefer AlarmKit if explicitly allowed and available on iOS 18+
        #if canImport(AlarmKit)
        if useAlarmKitIfAvailable {
            if #available(iOS 18.0, *) {
                do {
                    try await scheduleAlarmKitTimer(minutes: minutes)
                    return
                } catch {
                    // Fall back to notifications if AlarmKit path fails
                    // We'll continue below to notifications
                }
            }
        }
        #endif

        // Fallback: Local Notification
        try await scheduleLocalNotificationTimer(minutes: minutes)
    }

    #if canImport(AlarmKit)
    @available(iOS 18.0, *)
    private func scheduleAlarmKitTimer(minutes: Int) async throws {
        // NOTE: This implementation assumes AlarmKit APIs exist. Adjust to your app's specific API surface.
        // If the app doesn't link AlarmKit, this code is excluded at compile time.
        // Pseudocode-like implementation guarded by availability to avoid breaking builds.
        // Replace the following with the actual AlarmKit scheduling logic used in your project.

        // Example placeholder:
        // import AlarmKit
        // let authorization = try await AlarmCenter.shared.requestAuthorization()
        // guard authorization == .authorized else { throw LocalActionError.notificationsDenied }
        // let timer = AlarmTimer(duration: .minutes(minutes))
        // try await AlarmCenter.shared.schedule(timer)

        // Since we don't know the exact APIs at compile time, we throw featureUnavailable here by default.
        throw LocalActionError.featureUnavailable
    }
    #endif

    #if canImport(UserNotifications)
    private func scheduleLocalNotificationTimer(minutes: Int) async throws {
        let seconds = TimeInterval(minutes * 60)
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            throw LocalActionError.notificationsDenied
        case .notDetermined:
            let granted = try await requestNotificationPermission()
            if !granted { throw LocalActionError.notificationsDenied }
        @unknown default:
            break
        }

        let content = UNMutableNotificationContent()
        content.title = "Timer Finished"
        content.body = "Your \(minutes)-minute timer is complete."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let id = "local.timer.\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
        } catch {
            throw LocalActionError.schedulingFailed(String(describing: error))
        }
    }

    private func requestNotificationPermission() async throws -> Bool {
        do {
            return try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            throw LocalActionError.notificationsNotAvailable
        }
    }
    #else
    private func scheduleLocalNotificationTimer(minutes: Int) async throws {
        throw LocalActionError.notificationsNotAvailable
    }
    #endif

    // MARK: - WeatherKit (Optional Scaffold)
    public struct WeatherSummary {
        public let temperature: Measurement<UnitTemperature>
        public let conditionDescription: String
        public init(temperature: Measurement<UnitTemperature>, conditionDescription: String) {
            self.temperature = temperature
            self.conditionDescription = conditionDescription
        }
    }

    /// Fetches a lightweight current weather summary for a given location.
    /// - Parameter location: Optional explicit location. If nil, attempts to obtain the user's current location (with permission).
    /// - Returns: `WeatherSummary` when WeatherKit is available; throws otherwise.
    public func fetchCurrentWeather(for location: CLLocation? = nil) async throws -> WeatherSummary {
        #if canImport(WeatherKit)
        if #available(iOS 16.0, macOS 13.0, *) {
            let loc: CLLocation
            if let location { loc = location }
            else {
                #if canImport(CoreLocation)
                loc = try await requestOneShotLocation()
                #else
                throw LocalActionError.locationServicesDisabled
                #endif
            }

            let service = WeatherService.shared
            do {
                let weather = try await service.weather(for: loc)
                let temp = weather.currentWeather.temperature
                let desc = weather.currentWeather.condition.description
                return WeatherSummary(temperature: temp, conditionDescription: desc)
            } catch {
                throw LocalActionError.schedulingFailed("Weather fetch failed: \(error)")
            }
        } else {
            throw LocalActionError.weatherNotAvailable
        }
        #else
        throw LocalActionError.weatherNotAvailable
        #endif
    }

    // MARK: - Location Helpers
    #if canImport(CoreLocation)
    private func requestOneShotLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocalActionError.locationServicesDisabled
        }
        let manager = CLLocationManager()
        self.locationManager = manager
        manager.delegate = self

        let status = manager.authorizationStatus
        switch status {
        case .denied:
            throw LocalActionError.locationDenied
        case .restricted:
            throw LocalActionError.locationRestricted
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
            locationManager?.stopUpdatingLocation()
            locationManager = nil
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
        locationManager = nil
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied:
            locationContinuation?.resume(throwing: LocalActionError.locationDenied)
            locationContinuation = nil
        case .restricted:
            locationContinuation?.resume(throwing: LocalActionError.locationRestricted)
            locationContinuation = nil
        default:
            break
        }
    }
    #endif
}

#if canImport(CoreLocation)
extension LocalActionManagerV2: CLLocationManagerDelegate {}
#endif

// MARK: - SwiftUI convenience
public extension View {
    /// Presents a simple toast-like banner using a local notification as a fallback when app is backgrounded.
    /// This is a convenience to demonstrate interacting with LocalActionManager from SwiftUI.
    func onAppearScheduleDemoTimer(using manager: LocalActionManagerV2, minutes: Int) -> some View {
        self.onAppear {
            Task { try? await manager.startTimer(minutes: minutes) }
        }
    }
}

