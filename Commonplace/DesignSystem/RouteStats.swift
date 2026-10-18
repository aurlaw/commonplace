import Foundation

/// A route's stats as text, in the locale's units: miles and feet in the US, kilometers and
/// meters elsewhere (the UK uses miles for distance). Gain is left out when the track has no
/// elevations, time when it has no timestamps.
nonisolated struct RouteStats: Equatable {
    var distanceMeters: Double
    var elevationGainMeters: Double?
    var startedAt: Date?
    var endedAt: Date?

    /// Seconds from the first to the last timestamp; `nil` without both.
    var duration: TimeInterval? {
        guard let startedAt, let endedAt, endedAt > startedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    /// "3.0 mi", or "3.0 miles" for `.wide`.
    func distance(
        locale: Locale = .current,
        width: Measurement<UnitLength>.FormatStyle.UnitWidth = .abbreviated
    ) -> String {
        let unit: UnitLength = Self.usesMiles(locale) ? .miles : .kilometers
        return Measurement(value: distanceMeters, unit: UnitLength.meters).converted(to: unit)
            .formatted(Self.style(locale: locale, width: width, fractionDigits: 1))
    }

    /// "397 ft", or "397 feet" for `.wide`.
    func elevationGain(
        locale: Locale = .current,
        width: Measurement<UnitLength>.FormatStyle.UnitWidth = .abbreviated
    ) -> String? {
        elevationGainMeters.map { Self.elevation($0, locale: locale, width: width) }
    }

    /// "1h 36m", or "1 hour, 36 minutes" for `.wide`.
    func time(
        locale: Locale = .current, width: Duration.UnitsFormatStyle.UnitWidth = .narrow
    ) -> String? {
        guard let duration else { return nil }
        var style = Duration.UnitsFormatStyle(
            allowedUnits: [.hours, .minutes], width: width,
            fractionalPart: .hide(rounded: .toNearestOrEven))
        style.locale = locale
        return Duration.seconds(duration).formatted(style)
    }

    /// "3.0 miles, 397 feet gain, 1 hour, 36 minutes"
    func spokenSummary(locale: Locale = .current, includesTime: Bool = true) -> String {
        var parts = [distance(locale: locale, width: .wide)]
        if let gain = elevationGain(locale: locale, width: .wide) {
            parts.append("\(gain) gain")
        }
        if includesTime, let time = time(locale: locale, width: .wide) {
            parts.append(time)
        }
        return parts.joined(separator: ", ")
    }

    /// "4,282 ft"
    static func elevation(
        _ meters: Double, locale: Locale = .current,
        width: Measurement<UnitLength>.FormatStyle.UnitWidth = .abbreviated
    ) -> String {
        let unit: UnitLength = usesFeet(locale) ? .feet : .meters
        return Measurement(value: meters, unit: UnitLength.meters).converted(to: unit)
            .formatted(style(locale: locale, width: width, fractionDigits: 0))
    }

    /// "Elevation from 4,282 to 4,631 feet"
    static func elevationRange(min: Double, max: Double, locale: Locale = .current) -> String {
        let low = elevation(min, locale: locale, width: .wide)
        let high = elevation(max, locale: locale, width: .wide)
        // "4,282 feet" → "4,282": the unit is said once, after the high value.
        let lowNumber = low.split(separator: " ").first.map(String.init) ?? low
        return "Elevation from \(lowNumber) to \(high)"
    }

    /// The distance unit for the profile chart's axis: miles or kilometers.
    static func distanceUnit(locale: Locale = .current) -> UnitLength {
        usesMiles(locale) ? .miles : .kilometers
    }

    /// The elevation unit for the profile chart's axis: feet or meters.
    static func elevationUnit(locale: Locale = .current) -> UnitLength {
        usesFeet(locale) ? .feet : .meters
    }

    private static func usesMiles(_ locale: Locale) -> Bool {
        locale.measurementSystem == .us || locale.measurementSystem == .uk
    }

    private static func usesFeet(_ locale: Locale) -> Bool {
        locale.measurementSystem == .us
    }

    private static func style(
        locale: Locale, width: Measurement<UnitLength>.FormatStyle.UnitWidth, fractionDigits: Int
    ) -> Measurement<UnitLength>.FormatStyle {
        Measurement<UnitLength>.FormatStyle(
            width: width,
            locale: locale,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(fractionDigits))
        )
    }
}

extension Route {
    var stats: RouteStats {
        RouteStats(
            distanceMeters: distanceMeters, elevationGainMeters: elevationGainMeters,
            startedAt: startedAt, endedAt: endedAt)
    }

    var startCoordinate: Coordinate? {
        guard let startLatitude, let startLongitude else { return nil }
        return Coordinate(latitude: startLatitude, longitude: startLongitude)
    }
}

/// Text for the attach confirm sheet.
nonisolated enum RouteAttachText {
    /// "Recorded Oct 14 · entry dated Oct 15" when the track was recorded on another day than
    /// the entry's; `nil` when they match or the track has no timestamps. Attaching is allowed
    /// either way.
    static func dateNote(
        recorded: Date?, entryDate: Date, calendar: Calendar = .current
    ) -> String? {
        guard let recorded, !calendar.isDate(recorded, inSameDayAs: entryDate) else { return nil }
        let recordedDay = EntryTimeline.monthDay(recorded, calendar: calendar)
        let entryDay = EntryTimeline.monthDay(entryDate, calendar: calendar)
        return "Recorded \(recordedDay) · entry dated \(entryDay)"
    }

    /// "Afternoon hike at Broken Arrow Trail, recorded October 14, 3.0 miles, 397 feet gain,
    /// 1 hour, 36 minutes"
    static func spokenSummary(
        name: String, recorded: Date?, stats: RouteStats, calendar: Calendar = .current
    ) -> String {
        var parts = [name]
        if let recorded {
            let style = Date.FormatStyle(
                locale: calendar.locale ?? .current, calendar: calendar,
                timeZone: calendar.timeZone
            )
            parts.append("recorded \(recorded.formatted(style.month(.wide).day()))")
        }
        parts.append(stats.spokenSummary(locale: calendar.locale ?? .current))
        return parts.joined(separator: ", ")
    }
}
