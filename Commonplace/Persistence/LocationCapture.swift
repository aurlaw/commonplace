import Foundation
import SwiftData
import SwiftUI

/// Location work that outlives the composer: a fix that arrives after Save, and place names
/// that couldn't be looked up when the entry was written.
///
/// All model writes happen on the main context; the service does its waiting elsewhere.
final class LocationCapture {
    private let service: any LocationService
    private let context: ModelContext
    private var lateFixes: [PersistentIdentifier: Task<Void, Never>] = [:]
    private var isBackfilling = false
    /// Entries geocoding found no name for, so one run doesn't ask about them twice.
    private var unnameable: Set<PersistentIdentifier> = []

    /// How many place names one backfill run looks up. Geocoding is rate-limited.
    static let backfillBatchSize = 5

    init(service: any LocationService, context: ModelContext) {
        self.service = service
        self.context = context
    }

    // MARK: Late fix

    /// Keeps locating for an entry that was saved while the composer was still waiting for a
    /// fix. Returns at once; the work runs for at most `timeout`.
    func startLateFix(for entryID: PersistentIdentifier, timeout: Duration) {
        lateFixes[entryID]?.cancel()
        lateFixes[entryID] = Task {
            await attachWhenLocated(to: entryID, timeout: timeout)
            lateFixes[entryID] = nil
        }
    }

    /// Waits for a fix and attaches it. If none arrives in time, the entry has no location.
    func attachWhenLocated(to entryID: PersistentIdentifier, timeout: Duration) async {
        guard let coordinate = try? await service.currentLocation(timeout: timeout),
            attach(coordinate, to: entryID)
        else {
            return
        }
        await fillPlaceName(for: entryID)
    }

    /// Sets the entry's coordinates, unless it has gained a location or been trashed since it
    /// was saved.
    ///
    /// - Returns: Whether the coordinates were written.
    @discardableResult
    func attach(_ coordinate: Coordinate, to entryID: PersistentIdentifier) -> Bool {
        guard let entry = entry(entryID), !entry.isTrashed, !entry.hasLocation else {
            return false
        }
        entry.latitude = coordinate.latitude
        entry.longitude = coordinate.longitude
        return context.saveOrRollback() == nil
    }

    // MARK: Place names

    /// Looks up the place name for one entry that has coordinates but no name. Does nothing
    /// when the lookup fails; the backfill tries again later.
    func fillPlaceName(for entryID: PersistentIdentifier) async {
        _ = try? await namePlace(for: entryID)
    }

    /// The same, without waiting: for an entry saved before its place name came back.
    func startFillingPlaceName(for entryID: PersistentIdentifier) {
        Task {
            await fillPlaceName(for: entryID)
        }
    }

    /// Names a few entries that were saved without a place name, one at a time. Call on launch
    /// and when the app returns to the foreground. Stops at the first failed lookup (offline,
    /// rate-limited) and leaves the rest for next time.
    func backfillPlaceNames() async {
        guard !isBackfilling else {
            return
        }
        isBackfilling = true
        defer { isBackfilling = false }

        let candidates = (try? context.fetch(Self.needsPlaceNameDescriptor)) ?? []
        let batch =
            candidates
            .filter { Self.needsPlaceName($0) && !unnameable.contains($0.persistentModelID) }
            .prefix(Self.backfillBatchSize)
        for entry in batch {
            do {
                try await namePlace(for: entry.persistentModelID)
            } catch {
                return
            }
        }
    }

    /// Whether an entry is waiting for a place name: live, in a live topic, with both
    /// coordinates and no name.
    static func needsPlaceName(_ entry: Entry) -> Bool {
        guard !entry.isTrashed, entry.hasLocation, entry.placeName == nil else {
            return false
        }
        return !(entry.topic?.isTrashed ?? false)
    }

    /// The store-side part of `needsPlaceName`, newest first: entries with a latitude and no
    /// place name. `needsPlaceName` applies the rest of the rule to the few that match.
    static var needsPlaceNameDescriptor: FetchDescriptor<Entry> {
        let predicate = #Predicate<Entry> { entry in
            entry.latitude != nil && entry.placeName == nil
        }
        return FetchDescriptor<Entry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
    }

    /// - Throws: When the lookup itself fails.
    private func namePlace(for entryID: PersistentIdentifier) async throws {
        guard let entry = entry(entryID), Self.needsPlaceName(entry),
            let latitude = entry.latitude, let longitude = entry.longitude
        else {
            return
        }
        let coordinate = Coordinate(latitude: latitude, longitude: longitude)
        guard let name = try await service.placeName(for: coordinate) else {
            unnameable.insert(entryID)
            return
        }
        // The entry may have changed while the lookup was in flight.
        guard let current = self.entry(entryID), Self.needsPlaceName(current),
            current.latitude == latitude, current.longitude == longitude
        else {
            return
        }
        current.placeName = name
        _ = context.saveOrRollback()
    }

    private func entry(_ id: PersistentIdentifier) -> Entry? {
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.persistentModelID == id })
        return try? context.fetch(descriptor).first
    }
}

extension EnvironmentValues {
    /// The app's location coordinator. `nil` in previews, where nothing outlives a sheet.
    @Entry var locationCapture: LocationCapture? = nil
}
