import Foundation
import LinkPresentation
import OSLog
import SwiftUI

/// Rich link previews and page titles. Injected so tests and previews can use a fake.
///
/// Main-actor because `LPLinkMetadata` isn't `Sendable`: it is created and read here only.
protocol LinkMetadataService {
    /// The page's metadata, from the cache when it's there. `nil` offline or on failure.
    func metadata(for url: URL) async -> LPLinkMetadata?
    /// The page's title, for the composer's Link sheet.
    func title(for url: URL) async -> String?
}

extension LinkMetadataService {
    func title(for url: URL) async -> String? {
        let title = await metadata(for: url)?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title : nil
    }
}

nonisolated enum LinkPreviewRule {
    /// Previews shown per entry.
    static let maximumPerEntry = 3
    /// How long one fetch may take.
    static let timeout: TimeInterval = 10
}

/// `LPMetadataProvider` behind an on-device cache.
///
/// Metadata is archived with `NSKeyedArchiver` (it supports secure coding) into the Caches
/// directory, one file per URL, so a cached preview shows instantly and offline. The system
/// may evict Caches; a missing file is fetched again. A URL that fails isn't fetched again in
/// the same session. Nothing here is synced or stored in SwiftData.
final class CachedLinkMetadataService: LinkMetadataService {
    /// Fetches one URL and returns its metadata archived, or `nil`.
    typealias Fetch = (URL) async -> Data?

    private let directory: URL
    private let fetch: Fetch
    private var memory: [URL: LPLinkMetadata] = [:]
    private var failed: Set<URL> = []

    /// - Parameters:
    ///   - directory: Where archives go; created when needed.
    ///   - fetch: Replaced in tests; the real one uses `LPMetadataProvider`.
    init(
        directory: URL = URL.cachesDirectory.appending(
            path: "LinkMetadata", directoryHint: .isDirectory),
        fetch: @escaping Fetch = CachedLinkMetadataService.fetchArchived
    ) {
        self.directory = directory
        self.fetch = fetch
    }

    func metadata(for url: URL) async -> LPLinkMetadata? {
        if let cached = memory[url] ?? readCache(for: url) {
            memory[url] = cached
            return cached
        }
        guard !failed.contains(url) else {
            return nil
        }
        guard let data = await fetch(url), let metadata = Self.unarchive(data) else {
            failed.insert(url)
            return nil
        }
        writeCache(data, for: url)
        memory[url] = metadata
        return metadata
    }

    /// The archive's file. Named by a stable hash of the URL.
    func cacheFile(for url: URL) -> URL {
        directory.appending(path: Self.key(for: url) + ".archive")
    }

    private func readCache(for url: URL) -> LPLinkMetadata? {
        guard let data = try? Data(contentsOf: cacheFile(for: url)) else {
            return nil
        }
        return Self.unarchive(data)
    }

    private func writeCache(_ data: Data, for url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try data.write(to: cacheFile(for: url), options: .atomic)
        } catch {
            Logger(subsystem: "com.aurlaw.commonplace", category: "links")
                .error("Link preview cache write failed: \(error, privacy: .public)")
        }
    }

    private static func unarchive(_ data: Data) -> LPLinkMetadata? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: data)
    }

    /// FNV-1a over the URL's bytes, as hex: stable across launches, unlike `hashValue`.
    nonisolated static func key(for url: URL) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    // MARK: LPMetadataProvider

    /// One provider per fetch: providers are single-use. Started on the main actor.
    static func fetchArchived(_ url: URL) async -> Data? {
        let provider = LPMetadataProvider()
        provider.timeout = LinkPreviewRule.timeout
        let data = await withCheckedContinuation { continuation in
            provider.startFetchingMetadata(
                for: url, completionHandler: archiving(into: continuation))
        }
        withExtendedLifetime(provider) {}
        return data
    }

    /// The completion handler. It runs on a background queue, so it is built outside the main
    /// actor; and it archives right there, because the fetched image files are deleted once it
    /// returns.
    private nonisolated static func archiving(
        into continuation: CheckedContinuation<Data?, Never>
    ) -> @Sendable (LPLinkMetadata?, (any Error)?) -> Void {
        { metadata, _ in
            let data = metadata.flatMap {
                try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
            }
            continuation.resume(returning: data)
        }
    }
}

extension EnvironmentValues {
    /// Replaced with `FakeLinkMetadataService` in tests and previews.
    @Entry var linkMetadataService: any LinkMetadataService = CachedLinkMetadataService()
}
