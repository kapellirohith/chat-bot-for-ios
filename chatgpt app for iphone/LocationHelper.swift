import Foundation
import CoreLocation

final class LocationHelper: NSObject, CLLocationManagerDelegate {
    static let shared = LocationHelper()

    private var manager: CLLocationManager?
    private var completion: ((Result<CLLocation, Error>) -> Void)?

    enum LocationError: Error, LocalizedError {
        case denied, restricted, unknown
        var errorDescription: String? {
            switch self {
            case .denied: return "Location access denied."
            case .restricted: return "Location access restricted."
            case .unknown: return "Could not get location."
            }
        }
    }

    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        self.completion = completion
        let manager = CLLocationManager()
        manager.delegate = self
        self.manager = manager
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    // Returns a city or place name for the given location, if possible.
    // Constructs a string including city (locality), administrative area (state/region), and country if available.
    // Formats as "City, Country" or "City, State, Country" when all are present.
    // Falls back to using name or other available fields with country appended if possible.
    func reverseGeocode(location: CLLocation, completion: @escaping (Result<String, Error>) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                completion(.failure(error)); return
            }
            guard let placemark = placemarks?.first else {
                completion(.failure(LocationError.unknown)); return
            }
            
            let city = placemark.locality
            let state = placemark.administrativeArea
            let country = placemark.country
            let name = placemark.name
            
            // Build location string based on available components
            if let city = city, let country = country {
                if let state = state, !state.isEmpty {
                    completion(.success("\(city), \(state), \(country)"))
                } else {
                    completion(.success("\(city), \(country)"))
                }
            } else if let name = name, let country = country {
                completion(.success("\(name), \(country)"))
            } else if let name = name {
                completion(.success(name))
            } else if let city = city {
                completion(.success(city))
            } else if let country = country {
                completion(.success(country))
            } else {
                completion(.failure(LocationError.unknown))
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else {
            completion?(.failure(LocationError.unknown)); return
        }
        completion?(.success(loc))
        cleanup()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(.failure(error))
        cleanup()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied: completion?(.failure(LocationError.denied)); cleanup()
        case .restricted: completion?(.failure(LocationError.restricted)); cleanup()
        default: break
        }
    }

    private func cleanup() {
        manager?.delegate = nil
        manager = nil
        completion = nil
    }
}
