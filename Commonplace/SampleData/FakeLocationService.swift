import Foundation

/// A `LocationService` with fixed answers, for tests and previews. Never touches CoreLocation.
nonisolated struct FakeLocationService: LocationService {
    /// Cathedral Rock, Sedona.
    static let sampleCoordinate = Coordinate(
        latitude: 34.8253, longitude: -111.7885, horizontalAccuracy: 12
    )

    var location: Result<Coordinate, LocationError> = .success(sampleCoordinate)
    /// How long the fix takes. Longer than the timeout means no fix arrives.
    var delay = Duration.zero
    /// `nil` stands for a place with no name.
    var placeName: String? = "Cathedral Rock Trailhead"
    /// Stands for being offline.
    var failsGeocoding = false

    func currentLocation(timeout: Duration) async throws -> Coordinate {
        guard delay <= timeout else {
            try await Task.sleep(for: timeout)
            throw LocationError.unavailable
        }
        try await Task.sleep(for: delay)
        return try location.get()
    }

    func placeName(for coordinate: Coordinate) async throws -> String? {
        if failsGeocoding {
            throw URLError(.notConnectedToInternet)
        }
        return placeName
    }
}
