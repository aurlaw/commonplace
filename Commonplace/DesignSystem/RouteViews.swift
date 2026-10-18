import Accessibility
import Charts
import MapKit
import SwiftUI

/// The route glyph, used in menus and on timeline rows.
enum RouteSymbol {
    static let name = "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath"
}

/// Distance · Elev. gain · Time, one accessibility element. Gain and time are left out when the
/// route doesn't have them.
struct RouteStatsRow: View {
    let stats: RouteStats

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            item("Distance", stats.distance())
            if let gain = stats.elevationGain() {
                item("Elev. gain", gain)
            }
            if let time = stats.time() {
                item("Time", time)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stats.spokenSummary())
    }

    private func item(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }
}

/// A route's drawing path, decoded from the cached `pathData` off the main actor. Never reads
/// the GPX file.
enum RoutePathDecoder {
    @concurrent
    static func coordinates(from data: Data?) async -> [[Coordinate]] {
        guard let data, let path = try? RoutePath.decode(data) else { return [] }
        return path.coordinates
    }

    @concurrent
    static func profile(from data: Data?) async -> RouteProfile? {
        guard let data else { return nil }
        return try? RouteProfile.decode(data)
    }
}

/// One `MapPolyline` per segment, so gaps aren't drawn, in the topic's color.
struct RoutePolylines: MapContent {
    let segments: [[Coordinate]]
    let tint: Color
    var lineWidth: CGFloat = 4

    var body: some MapContent {
        ForEach(segments.indices, id: \.self) { index in
            MapPolyline(coordinates: segments[index].map(\.clLocation))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

enum RouteCamera {
    /// Fits the route and the entry's pin, with padding.
    static func region(segments: [[Coordinate]], pin: Coordinate?) -> MKCoordinateRegion? {
        let points = segments.flatMap { $0 } + (pin.map { [$0] } ?? [])
        return TopicMapModel.fittingRegion(
            for: points.map(\.clLocation), minimumMeters: 500)
    }
}

extension Coordinate {
    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Entry {
    /// Both coordinates as a value, or `nil` (see `hasLocation`).
    var locationCoordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

/// Elevation against distance, in the locale's units, with a spoken summary of the range.
struct RouteElevationChart: View {
    let profile: RouteProfile
    let tint: Color

    var body: some View {
        let distanceUnit = RouteStats.distanceUnit()
        let elevationUnit = RouteStats.elevationUnit()
        let points = profile.points.map {
            (
                distance: Measurement(value: $0.distance, unit: UnitLength.meters)
                    .converted(to: distanceUnit).value,
                elevation: Measurement(value: $0.elevation, unit: UnitLength.meters)
                    .converted(to: elevationUnit).value
            )
        }
        let low = points.map(\.elevation).min() ?? 0
        let high = points.map(\.elevation).max() ?? 0
        let margin = max((high - low) * 0.15, 5)

        Chart(points.indices, id: \.self) { index in
            AreaMark(
                x: .value("Distance", points[index].distance),
                yStart: .value("Floor", low - margin),
                yEnd: .value("Elevation", points[index].elevation)
            )
            .foregroundStyle(tint.opacity(0.18))
            LineMark(
                x: .value("Distance", points[index].distance),
                y: .value("Elevation", points[index].elevation)
            )
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYScale(domain: (low - margin)...(high + margin))
        .chartXAxisLabel(distanceUnit.symbol)
        .chartYAxisLabel(elevationUnit.symbol)
        .accessibilityChartDescriptor(
            ElevationChartDescriptor(
                points: points, distanceUnit: distanceUnit, elevationUnit: elevationUnit,
                summary: summary)
        )
    }

    /// "Elevation from 4,282 to 4,631 feet"
    private var summary: String {
        let elevations = profile.points.map(\.elevation)
        guard let low = elevations.min(), let high = elevations.max() else { return "" }
        return RouteStats.elevationRange(min: low, max: high)
    }
}

/// The audio graph for the elevation profile.
private struct ElevationChartDescriptor: AXChartDescriptorRepresentable {
    let points: [(distance: Double, elevation: Double)]
    let distanceUnit: UnitLength
    let elevationUnit: UnitLength
    let summary: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let distances = points.map(\.distance)
        let elevations = points.map(\.elevation)
        let distanceSymbol = distanceUnit.symbol
        let elevationSymbol = elevationUnit.symbol
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Distance",
            range: (distances.min() ?? 0)...(distances.max() ?? 1),
            gridlinePositions: []
        ) { value in
            "\(value.formatted(.number.precision(.fractionLength(1)))) \(distanceSymbol)"
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Elevation",
            range: (elevations.min() ?? 0)...(elevations.max() ?? 1),
            gridlinePositions: []
        ) { value in
            "\(value.formatted(.number.precision(.fractionLength(0)))) \(elevationSymbol)"
        }
        let series = AXDataSeriesDescriptor(
            name: "Elevation", isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.distance, y: $0.elevation) })
        return AXChartDescriptor(
            title: "Elevation profile", summary: summary, xAxis: xAxis, yAxis: yAxis,
            additionalAxes: [], series: [series])
    }
}
