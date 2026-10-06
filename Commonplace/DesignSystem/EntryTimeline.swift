import Foundation

/// Pure ordering and labeling helpers for timelines.
nonisolated enum EntryTimeline {
    struct MonthSection: Identifiable {
        let monthStart: Date
        var entries: [Entry]

        var id: Date { monthStart }

        /// "October 2026"
        func title(calendar: Calendar = .current) -> String {
            monthStart.formatted(EntryTimeline.style(calendar).month(.wide).year())
        }
    }

    struct Neighbors {
        /// The entry before this one by date, if any.
        let previous: Entry?
        /// The entry after this one by date, if any.
        let next: Entry?
        /// 1-based position, oldest first.
        let position: Int
        let count: Int

        /// "15 of 23"
        var positionLabel: String { "\(position) of \(count)" }
    }

    // MARK: Ordering

    /// Month sections newest first, each with its entries newest first by `date`.
    static func groupByMonth(_ entries: [Entry], calendar: Calendar = .current) -> [MonthSection] {
        var sections: [MonthSection] = []
        for entry in entries.sorted(by: isNewer) {
            let monthStart = calendar.dateInterval(of: .month, for: entry.date)?.start ?? entry.date
            if let last = sections.indices.last, sections[last].monthStart == monthStart {
                sections[last].entries.append(entry)
            } else {
                sections.append(MonthSection(monthStart: monthStart, entries: [entry]))
            }
        }
        return sections
    }

    /// The entries either side of `entry` by `date`, or `nil` when it isn't in `entries`.
    static func neighbors(of entry: Entry, in entries: [Entry]) -> Neighbors? {
        let ordered = Array(entries.sorted(by: isNewer).reversed())
        guard let index = ordered.firstIndex(where: { $0 === entry }) else {
            return nil
        }
        return Neighbors(
            previous: index > 0 ? ordered[index - 1] : nil,
            next: index < ordered.count - 1 ? ordered[index + 1] : nil,
            position: index + 1,
            count: ordered.count
        )
    }

    private static func isNewer(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        return lhs.createdAt > rhs.createdAt
    }

    // MARK: Labels

    /// "Today", "Yesterday", "Sep 28", or "Sep 28, 2025" outside the current year.
    static func lastEntryLabel(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        return shortDate(date, now: now, calendar: calendar)
    }

    /// "Sep 28", or "Sep 28, 2025" outside the current year.
    static func shortDate(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let monthDay = style(calendar).month(.abbreviated).day()
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(monthDay)
        }
        return date.formatted(monthDay.year())
    }

    /// "Oct 2"
    static func monthDay(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(style(calendar).month(.abbreviated).day())
    }

    /// "2"
    static func dayNumber(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(style(calendar).day())
    }

    /// "Fri"
    static func weekday(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(style(calendar).weekday(.abbreviated))
    }

    /// "6:10 AM"
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(style(calendar).hour().minute())
    }

    /// "Friday, October 2, 2026"
    static func fullDate(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(style(calendar).weekday(.wide).month(.wide).day().year())
    }

    /// "Today, 6:42 AM" or "Oct 2, 2026, 7:48 AM"
    static func composerDate(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let day =
            calendar.isDate(date, inSameDayAs: now)
            ? "Today"
            : date.formatted(style(calendar).month(.abbreviated).day().year())
        return "\(day), \(time(date, calendar: calendar))"
    }

    /// "1 entry", "23 entries"
    static func entryCount(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }

    private static func style(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(
            locale: calendar.locale ?? .current,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
    }
}
