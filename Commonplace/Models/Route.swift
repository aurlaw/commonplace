import Foundation
import SwiftData

extension SchemaV2 {
    /// A GPX track attached to one entry. The original file is kept so the stats can be
    /// recomputed; everything shown is cached here, so nothing reparses the file for display.
    @Model
    final class Route {
        /// The original GPX file, synced as a CloudKit asset.
        @Attribute(.externalStorage)
        var gpxData: Data? = nil
        /// From `<trk><name>`, else the file name without its extension.
        var name: String = ""
        /// First and last timestamps; `nil` when the track has none.
        var startedAt: Date? = nil
        var endedAt: Date? = nil
        var distanceMeters: Double = 0
        /// `nil` when the file has no elevations.
        var elevationGainMeters: Double? = nil
        var minElevationMeters: Double? = nil
        var maxElevationMeters: Double? = nil
        /// The first point, offered as the entry's location when it has none.
        var startLatitude: Double? = nil
        var startLongitude: Double? = nil
        /// The simplified drawing path (`RoutePath`), binary property list. Small and inline.
        var pathData: Data? = nil
        /// Elevation against distance (`RouteProfile`), binary property list. Small and inline.
        var profileData: Data? = nil
        var createdAt: Date = Date.now
        var entry: Entry? = nil

        init(name: String = "", createdAt: Date = .now) {
            self.name = name
            self.createdAt = createdAt
        }
    }
}
