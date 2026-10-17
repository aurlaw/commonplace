import Foundation
import LinkPresentation

/// A `LinkMetadataService` with fixed answers, for tests and previews. Never touches the
/// network.
final class FakeLinkMetadataService: LinkMetadataService {
    /// Titles by URL; a URL that isn't here has no metadata (offline, or a failed fetch).
    var titles: [URL: String]
    /// How long a fetch takes. Long enough stands for "still loading".
    var delay: Duration

    init(titles: [URL: String] = FakeLinkMetadataService.sampleTitles, delay: Duration = .zero) {
        self.titles = titles
        self.delay = delay
    }

    static let sampleTitles: [URL: String] = [
        URL(string: "https://elotecafe.com")!: "Elote Cafe — Sedona, Arizona",
        URL(string: "https://www.fs.usda.gov/recarea/coconino/recarea/?recid=55291")!:
            "Cathedral Rock Trailhead — Coconino National Forest",
    ]

    func metadata(for url: URL) async -> LPLinkMetadata? {
        try? await Task.sleep(for: delay)
        guard let title = titles[url] else {
            return nil
        }
        let metadata = LPLinkMetadata()
        metadata.url = url
        metadata.originalURL = url
        metadata.title = title
        return metadata
    }
}
