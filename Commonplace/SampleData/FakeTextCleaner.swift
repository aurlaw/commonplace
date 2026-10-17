import Foundation

/// A `TextCleaner` with scripted answers, for tests and previews. Never loads a model.
nonisolated struct FakeTextCleaner: TextCleaner {
    var availability = TextCleanerAvailability.available
    /// How long one chunk takes.
    var delay = Duration.zero
    /// The answer for each chunk; the default capitalizes it and adds a period.
    var transform: @Sendable (String) throws -> String = FakeTextCleaner.tidy

    func clean(_ text: String) async throws -> String {
        try await Task.sleep(for: delay)
        return try transform(text)
    }

    func prewarm() {}

    /// Removes "um" and "like," capitalizes the first letter, and ends with a period.
    static let tidy: @Sendable (String) throws -> String = { text in
        var result = text.replacingOccurrences(of: "um ", with: "")
            .replacingOccurrences(of: "like, ", with: "")
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        if let last = result.last, !".!?)".contains(last) {
            result += "."
        }
        return result
    }
}
