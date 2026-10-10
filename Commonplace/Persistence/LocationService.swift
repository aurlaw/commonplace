import CoreLocation
import Foundation
import MapKit
import SwiftUI

/// A point on the map. Defined here so the model files stay Foundation-only.
nonisolated struct Coordinate: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    /// In meters. `0` when unknown (a location read back from a saved entry).
    var horizontalAccuracy: Double = 0
}

nonisolated enum LocationError: Error, Equatable {
    /// Location access is denied or restricted for the app.
    case denied
    /// No fix arrived within the time allowed.
    case unavailable
}

/// What reverse geocoding found at a coordinate, reduced to what the place-name rule needs.
nonisolated struct PlaceCandidate: Sendable, Equatable {
    /// The result's own name, such as "Bear Rocks Trailhead" or a street address.
    var name: String?
    var isPointOfInterest = false
    /// "Sedona, AZ"
    var cityWithContext: String?
    /// "Sedona"
    var city: String?

    /// The name to store: the point of interest's name, otherwise the city with its state or
    /// province, otherwise the city alone, otherwise nothing (coordinates only).
    var placeName: String? {
        if isPointOfInterest, let name = Self.nonEmpty(name) {
            return name
        }
        return Self.nonEmpty(cityWithContext) ?? Self.nonEmpty(city)
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

/// One-shot location and reverse geocoding. Injected so tests and previews can use a fake.
nonisolated protocol LocationService: Sendable {
    /// The current location, asking for When In Use access the first time it's needed.
    ///
    /// Returns the first fix accurate to 100 m, or the best one seen within `timeout`. A fix
    /// with reduced (approximate) accuracy is returned as-is.
    ///
    /// - Throws: `LocationError.denied` or `LocationError.unavailable`.
    func currentLocation(timeout: Duration) async throws -> Coordinate

    /// The place name for a coordinate, or `nil` when nothing nameable is there. Throws when
    /// the lookup itself fails, such as offline.
    func placeName(for coordinate: Coordinate) async throws -> String?
}

nonisolated enum LocationCaptureRule {
    /// A fix this accurate, in meters, is taken at once.
    static let goodAccuracy = 100.0
    /// How long to wait for a fix, from when the composer starts locating.
    static let timeout = Duration.seconds(15)
}

/// CoreLocation for the fix, MapKit for the name.
///
/// The fix uses `CLLocationUpdate.liveUpdates()` with a `CLServiceSession`: both are `Sendable`
/// async APIs, so there is no delegate object to bridge. The name uses MapKit's
/// `MKReverseGeocodingRequest`, because `CLGeocoder` is deprecated in iOS 26.
nonisolated struct CoreLocationService: LocationService {
    func currentLocation(timeout: Duration) async throws -> Coordinate {
        // Holding the session is what asks for When In Use access, the first time.
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }

        // Wait out the permission prompt first, so reading it doesn't use up the time allowed.
        for try await update in CLLocationUpdate.liveUpdates() {
            if Self.isDenied(update) {
                throw LocationError.denied
            }
            if !update.authorizationRequestInProgress {
                break
            }
        }

        let best = BestFix()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if Self.isDenied(update) {
                        throw LocationError.denied
                    }
                    guard let location = update.location, location.horizontalAccuracy >= 0 else {
                        continue
                    }
                    let fix = Coordinate(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        horizontalAccuracy: location.horizontalAccuracy
                    )
                    await best.offer(fix)
                    if update.accuracyLimited
                        || fix.horizontalAccuracy <= LocationCaptureRule.goodAccuracy
                    {
                        return
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
            }
            try await group.next()
            group.cancelAll()
        }
        guard let fix = await best.value else {
            throw LocationError.unavailable
        }
        return fix
    }

    @MainActor
    func placeName(for coordinate: Coordinate) async throws -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
            let item = try await request.mapItems.first
        else {
            return nil
        }
        let candidate = PlaceCandidate(
            name: item.name,
            isPointOfInterest: item.pointOfInterestCategory != nil,
            cityWithContext: item.addressRepresentations?.cityWithContext(.short),
            city: item.addressRepresentations?.cityName
        )
        return candidate.placeName
    }

    private static func isDenied(_ update: CLLocationUpdate) -> Bool {
        update.authorizationDenied || update.authorizationDeniedGlobally
            || update.authorizationRestricted
    }

    /// The most accurate fix seen so far.
    private actor BestFix {
        private(set) var value: Coordinate?

        func offer(_ fix: Coordinate) {
            if value.map({ fix.horizontalAccuracy < $0.horizontalAccuracy }) ?? true {
                value = fix
            }
        }
    }
}

extension EnvironmentValues {
    /// Replaced with `FakeLocationService` in tests and previews.
    @Entry var locationService: any LocationService = CoreLocationService()
}

/// Text for a location.
nonisolated enum LocationLabel {
    /// "34.8697° N, 111.7610° W"
    static func coordinates(latitude: Double, longitude: Double) -> String {
        let northSouth = latitude < 0 ? "S" : "N"
        let eastWest = longitude < 0 ? "W" : "E"
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(4))
            .locale(Locale(identifier: "en_US_POSIX"))
        return "\(abs(latitude).formatted(style))° \(northSouth), "
            + "\(abs(longitude).formatted(style))° \(eastWest)"
    }

    /// The place name when there is one, otherwise the coordinates.
    static func text(placeName: String?, latitude: Double, longitude: Double) -> String {
        if let placeName, !placeName.isEmpty {
            return placeName
        }
        return coordinates(latitude: latitude, longitude: longitude)
    }
}
