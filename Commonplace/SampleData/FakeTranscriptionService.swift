import Foundation

/// A `TranscriptionService` that plays a script, for tests and previews. Never touches the
/// microphone or the Speech framework.
actor FakeTranscriptionService: TranscriptionService {
    /// A few words of dictation: volatile text firming up into finals.
    static let sampleScript: [TranscriptionEvent] = [
        .level(0.4), .volatile("The wind"), .level(0.7), .volatile("The wind at the saddle"),
        .final("The wind at the saddle was strong."), .level(0.5), .volatile("We turned"),
        .volatile("We turned back early"),
    ]

    private let initialAvailability: TranscriptionAvailability
    private let grantsPermission: Bool
    private let installProgress: [Double]
    private let failsInstall: Bool
    private let failsStart: Bool
    private let script: [TranscriptionEvent]
    private let eventDelay: Duration

    private var permissionGranted = false
    private var modelInstalled = false
    private var events: AsyncStream<TranscriptionEvent>.Continuation?
    private var player: Task<Void, Never>?
    /// The volatile text not yet finalized; `stop()` delivers it as a final.
    private var pending = ""

    /// How many times `start()` and `stop()` were called.
    private(set) var startCount = 0
    private(set) var stopCount = 0

    /// - Parameters:
    ///   - availability: What `availability()` reports at first. `.needsPermission` and
    ///     `.needsModel` turn into `.available` once permission is granted or the model is
    ///     installed.
    ///   - script: Played after `start()`, one event per `eventDelay`. Listening then
    ///     continues until `stop()`.
    init(
        availability: TranscriptionAvailability = .available,
        grantsPermission: Bool = true,
        installProgress: [Double] = [0.25, 0.5, 0.75, 1],
        failsInstall: Bool = false,
        failsStart: Bool = false,
        script: [TranscriptionEvent] = FakeTranscriptionService.sampleScript,
        eventDelay: Duration = .milliseconds(400)
    ) {
        initialAvailability = availability
        self.grantsPermission = grantsPermission
        self.installProgress = installProgress
        self.failsInstall = failsInstall
        self.failsStart = failsStart
        self.script = script
        self.eventDelay = eventDelay
    }

    func availability() async -> TranscriptionAvailability {
        switch initialAvailability {
        case .needsPermission where permissionGranted:
            return .available
        case .needsModel where modelInstalled:
            return .available
        default:
            return initialAvailability
        }
    }

    func requestPermission() async -> Bool {
        permissionGranted = grantsPermission
        return grantsPermission
    }

    nonisolated func installModel() -> AsyncThrowingStream<Double, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for fraction in installProgress {
                    try? await Task.sleep(for: eventDelay)
                    continuation.yield(fraction)
                }
                if failsInstall {
                    continuation.finish(throwing: TranscriptionError.downloadFailed)
                } else {
                    await markInstalled()
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func start() async throws -> AsyncStream<TranscriptionEvent> {
        startCount += 1
        if failsStart {
            throw TranscriptionError.failed
        }
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptionEvent.self)
        events = continuation
        pending = ""
        player = Task {
            for event in script {
                try? await Task.sleep(for: eventDelay)
                guard !Task.isCancelled else {
                    return
                }
                deliver(event)
            }
        }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.cancelPlayer() }
        }
        return stream
    }

    func stop() async {
        stopCount += 1
        player?.cancel()
        player = nil
        guard let events else {
            return
        }
        self.events = nil
        if !pending.isEmpty {
            events.yield(.final(pending))
            pending = ""
        }
        events.yield(.ended(nil))
        events.finish()
    }

    private func deliver(_ event: TranscriptionEvent) {
        switch event {
        case .volatile(let text):
            pending = text
        case .final:
            pending = ""
        default:
            break
        }
        events?.yield(event)
    }

    private func markInstalled() {
        modelInstalled = true
    }

    private func cancelPlayer() {
        player?.cancel()
        player = nil
        events = nil
    }
}
