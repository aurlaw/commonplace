import Foundation
import SwiftData
import SwiftUI

/// Everything a `Route` stores, computed from a GPX file and ready to insert. A value, so it can
/// be made off the main actor and shown in the confirm sheet before anything is saved.
nonisolated struct RouteDraft: Sendable, Equatable {
    var gpxData: Data
    var name: String
    var startedAt: Date?
    var endedAt: Date?
    var distanceMeters: Double
    var elevationGainMeters: Double?
    var minElevationMeters: Double?
    var maxElevationMeters: Double?
    var startLatitude: Double?
    var startLongitude: Double?
    var pathData: Data
    var profileData: Data?

    /// Computes the stats, the simplified path, and the profile.
    ///
    /// - Parameter fileName: The picked file's name; without its extension, it names a track
    ///   that has no `<name>`.
    init(track: ParsedTrack, gpxData: Data, fileName: String) throws {
        let segments = track.segments
        let start = RouteMetrics.startCoordinate(segments: segments)
        self.gpxData = gpxData
        name = Self.name(track: track.name, fileName: fileName)
        startedAt = RouteMetrics.startTime(segments: segments)
        endedAt = RouteMetrics.endTime(segments: segments)
        distanceMeters = RouteMetrics.distance(segments: segments)
        elevationGainMeters = RouteMetrics.elevationGain(segments: segments)
        minElevationMeters = RouteMetrics.minElevation(segments: segments)
        maxElevationMeters = RouteMetrics.maxElevation(segments: segments)
        startLatitude = start?.latitude
        startLongitude = start?.longitude
        pathData = try RouteMetrics.simplifiedPath(segments: segments).encoded()
        profileData = try RouteMetrics.profile(segments: segments)?.encoded()
    }

    /// The track's own name, else the file name without its extension, else "Route".
    static func name(track: String?, fileName: String) -> String {
        if let track = track?.trimmingCharacters(in: .whitespacesAndNewlines), !track.isEmpty {
            return track
        }
        let base = (fileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "Route" : base
    }

    var stats: RouteStats {
        RouteStats(
            distanceMeters: distanceMeters, elevationGainMeters: elevationGainMeters,
            startedAt: startedAt, endedAt: endedAt)
    }

    var startCoordinate: Coordinate? {
        guard let startLatitude, let startLongitude else { return nil }
        return Coordinate(latitude: startLatitude, longitude: startLongitude)
    }

    /// A new, uninserted `Route` with every field set.
    func makeRoute(createdAt: Date = .now) -> Route {
        let route = Route(name: name, createdAt: createdAt)
        route.gpxData = gpxData
        route.startedAt = startedAt
        route.endedAt = endedAt
        route.distanceMeters = distanceMeters
        route.elevationGainMeters = elevationGainMeters
        route.minElevationMeters = minElevationMeters
        route.maxElevationMeters = maxElevationMeters
        route.startLatitude = startLatitude
        route.startLongitude = startLongitude
        route.pathData = pathData
        route.profileData = profileData
        return route
    }
}

/// Turns a picked GPX file into a `RouteDraft`. Injected so previews and tests can use a fake.
nonisolated protocol RouteImporter: Sendable {
    /// Parses and computes off the main actor.
    ///
    /// - Throws: `GPXError` for a file that can't be used.
    func makeRoute(from data: Data, fileName: String) async throws -> RouteDraft
}

/// `GPXParser` and `RouteMetrics`. No device dependencies, so the app always uses it.
nonisolated struct GPXRouteImporter: RouteImporter {
    @concurrent
    func makeRoute(from data: Data, fileName: String) async throws -> RouteDraft {
        let track = try GPXParser.parse(data)
        return try RouteDraft(track: track, gpxData: data, fileName: fileName)
    }
}

extension EnvironmentValues {
    /// Replaced with `FakeRouteImporter` in previews.
    @Entry var routeImporter: any RouteImporter = GPXRouteImporter()
}

/// Attaching and removing an entry's route. Each operation saves and returns the error message
/// on failure, after rolling back.
struct RouteOperations {
    let context: ModelContext

    /// Gives the entry the draft's route, deleting the one it had (one route per entry).
    ///
    /// With `useStartAsLocation`, an entry that has no location gets the route's first point
    /// (the place name is filled in by the I6 backfill); an existing location is never
    /// replaced.
    func attach(_ draft: RouteDraft, to entry: Entry, useStartAsLocation: Bool) -> String? {
        let previous = entry.route
        let route = draft.makeRoute()
        context.insert(route)
        entry.route = route
        if let previous {
            context.delete(previous)
        }
        if useStartAsLocation, !entry.hasLocation, let start = draft.startCoordinate {
            entry.latitude = start.latitude
            entry.longitude = start.longitude
            entry.placeName = nil
        }
        return context.saveOrRollback()
    }

    /// Deletes the entry's route outright: like removing a photo, there is no Trash for it.
    func removeRoute(from entry: Entry) -> String? {
        guard let route = entry.route else { return nil }
        entry.route = nil
        context.delete(route)
        return context.saveOrRollback()
    }
}
