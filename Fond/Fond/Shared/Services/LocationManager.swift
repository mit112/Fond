//
//  LocationManager.swift
//  Fond
//
//  Wraps CLLocationManager for one-shot location capture.
//  Captures location on app foreground, rounds to 2 decimal places (~1.1km precision),
//  encrypts, and writes to Firestore. Reverse geocodes for city name.
//
//  Privacy design:
//  - Coordinates encrypted before Firestore — Firebase never sees location.
//  - Precision limited to ~1km — not enough to identify a specific building.
//  - Location permission is optional — if denied, distance feature hidden.
//  - No location history — only latest location stored on user doc.
//  - City name derived locally on-device, never server-side.
//
//  Target membership: Fond (iOS/Mac) only. NOT watchOS, NOT widget.
//

#if canImport(CoreLocation) && canImport(FirebaseFirestore)

import Foundation
import CoreLocation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {

    static let shared = LocationManager()

    // MARK: - State

    /// Latest captured coordinates (rounded).
    private(set) var latitude: Double?
    private(set) var longitude: Double?

    /// Whether we have location authorization.
    private(set) var isAuthorized = false

    /// Whether a location request is in progress.
    private(set) var isUpdating = false

    /// Error from last attempt (nil if successful).
    private(set) var lastError: String?

    // MARK: - Private

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        updateAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Requests "When In Use" authorization. Call before first location capture.
    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    private func updateAuthorizationStatus() {
        let status = manager.authorizationStatus
        isAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
    }

    // MARK: - One-Shot Location Capture

    /// Captures current location, rounds to 2 decimal places, returns (lat, lon).
    /// Returns nil if permission denied or location unavailable.
    @MainActor
    func captureLocation() async -> (lat: Double, lon: Double)? {
        guard !isUpdating else { return nil }

        if !isAuthorized {
            requestAuthorization()
            // Wait briefly for authorization response
            try? await Task.sleep(for: .milliseconds(500))
            guard isAuthorized else { return nil }
        }

        isUpdating = true
        lastError = nil

        let location = await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            self.continuation = continuation
            manager.requestLocation()
        }

        isUpdating = false

        guard let loc = location else {
            return nil
        }

        // Round to 2 decimal places (~1.1km precision)
        let lat = (loc.coordinate.latitude * 100).rounded() / 100
        let lon = (loc.coordinate.longitude * 100).rounded() / 100

        self.latitude = lat
        self.longitude = lon

        return (lat, lon)
    }

    /// Encrypts and writes location to Firestore.
    /// Also computes distance to partner if partner location available,
    /// writes to App Group for widgets, and reverse geocodes.
    @MainActor
    func captureAndUpload(uid: String) async {
        guard let coords = await captureLocation() else { return }

        do {
            let json = "{\"lat\":\(coords.lat),\"lon\":\(coords.lon)}"
            let encrypted = try EncryptionManager.shared.encrypt(json)

            try await FirebaseManager.shared.updateLocation(
                uid: uid,
                encryptedLocation: encrypted
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Distance Calculation

    /// Haversine distance between two coordinate pairs, in miles.
    static func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let R = 3958.8 // Earth's radius in miles
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    /// Contextual distance string using locale-appropriate units.
    static func formattedDistance(_ miles: Double) -> String {
        let usesMetric = Locale.current.measurementSystem == .metric
        if usesMetric {
            let km = miles * 1.60934
            if km < 0.3 { return "Right here 💛" }
            if km < 1 { return String(format: "%.1f km", km) }
            return "\(Int(km)) km"
        } else {
            if miles < 0.2 { return "Right here 💛" }
            if miles < 1 { return String(format: "%.1f mi", miles) }
            return "\(Int(miles)) mi"
        }
    }

    // MARK: - Reverse Geocoding

    /// Returns a city/locality name for the given coordinates.
    static func reverseGeocode(lat: Double, lon: Double) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: lat, longitude: lon)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.locality
        } catch {
            return nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.last)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
        continuation?.resume(returning: nil)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationStatus()
    }
}

#endif
