import AVFoundation
import Foundation
import Speech
import SwiftUI

/// Whether dictation can start now, and if not, what stands in the way.
nonisolated enum TranscriptionAvailability: Sendable, Equatable {
    case available
    /// Microphone access hasn't been asked for yet.
    case needsPermission
    /// The speech model for the language isn't installed; `installModel()` downloads it.
    case needsModel
    /// No on-device model exists for the device's language.
    case unsupportedLocale
    /// The device can't run on-device transcription at all.
    case unsupportedDevice
    case permissionDenied
}

nonisolated enum TranscriptionError: Error, Equatable {
    /// Audio couldn't be captured or the analyzer couldn't start.
    case failed
    /// The model download failed, most likely offline.
    case downloadFailed
}

nonisolated enum TranscriptionEvent: Sendable, Equatable {
    /// The unconfirmed tail of the transcript. Each one replaces the last.
    case volatile(String)
    /// Confirmed text, in order. Clears the volatile tail.
    case final(String)
    /// The input level, 0…1.
    case level(Float)
    /// The last event. `nil` for a normal stop or an interruption.
    case ended(TranscriptionError?)
}

/// On-device speech-to-text. Injected so tests and previews can use a fake.
nonisolated protocol TranscriptionService: Sendable {
    func availability() async -> TranscriptionAvailability

    /// Asks for microphone access (and speech recognition, if it turns out to be required).
    ///
    /// - Returns: Whether access was granted.
    func requestPermission() async -> Bool

    /// Downloads and installs the speech model, reporting progress 0…1.
    ///
    /// - Throws: `TranscriptionError.downloadFailed`.
    func installModel() -> AsyncThrowingStream<Double, any Error>

    /// Starts listening. The stream ends after `.ended`; ending the stream early (cancelling
    /// the task reading it) stops listening and discards anything not yet final.
    func start() async throws -> AsyncStream<TranscriptionEvent>

    /// Stops listening, finalizes so the last volatile text arrives as `.final`, then ends the
    /// stream.
    func stop() async
}

nonisolated enum DictationRule {
    /// How long a stop (or Save while listening) waits for the last words to become final.
    static let finishTimeout = Duration.seconds(2)
}

/// Turns buffer RMS into a meter value: decibels mapped to 0…1, smoothed, and throttled.
nonisolated struct AudioLevelMeter: Sendable {
    /// Quieter than this reads as silence.
    static let floorDecibels: Float = -50
    /// How much of each new reading is kept; the rest is the previous value.
    static let smoothing: Float = 0.4
    /// About 20 updates a second.
    static let minimumInterval: TimeInterval = 0.05

    private(set) var value: Float = 0
    private var lastReport: TimeInterval?

    /// Maps an RMS amplitude to 0…1 on a decibel scale.
    static func normalized(rms: Float) -> Float {
        guard rms.isFinite, rms > 0 else {
            return 0
        }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels - floorDecibels) / -floorDecibels))
    }

    /// Takes a reading. Returns the smoothed level when it is time to report one.
    mutating func update(rms: Float, at time: TimeInterval) -> Float? {
        value += Self.smoothing * (Self.normalized(rms: rms) - value)
        value = min(1, max(0, value))
        if let lastReport, time - lastReport < Self.minimumInterval {
            return nil
        }
        lastReport = time
        return value
    }
}

/// `SpeechAnalyzer` with a `SpeechTranscriber` module, fed from an `AVAudioEngine` input tap.
///
/// Everything stays on the device; the only network use is the system's one-time model
/// download. Audio is never written to disk.
actor SpeechTranscriptionService: TranscriptionService {
    /// Whether `SFSpeechRecognizer` authorization is requested as well as microphone access.
    /// The Speech headers don't say whether `SpeechTranscriber` needs it; turn this on if a
    /// device shows that it does.
    static let requestsSpeechRecognitionAuthorization = false

    private struct Session {
        let id = UUID()
        let engine: AVAudioEngine
        let analyzer: SpeechAnalyzer
        let input: AsyncStream<AnalyzerInput>.Continuation
        let events: AsyncStream<TranscriptionEvent>.Continuation
        let tasks: [Task<Void, Never>]
    }

    private var session: Session?

    // MARK: Availability

    func availability() async -> TranscriptionAvailability {
        guard SpeechTranscriber.isAvailable else {
            return .unsupportedDevice
        }
        guard let locale = await Self.locale() else {
            return .unsupportedLocale
        }
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            return .permissionDenied
        case .undetermined:
            return .needsPermission
        default:
            break
        }
        if Self.requestsSpeechRecognitionAuthorization {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .denied, .restricted:
                return .permissionDenied
            case .notDetermined:
                return .needsPermission
            default:
                break
            }
        }
        switch await AssetInventory.status(forModules: [Self.transcriber(for: locale)]) {
        case .installed:
            return .available
        case .unsupported:
            return .unsupportedLocale
        default:
            return .needsModel
        }
    }

    func requestPermission() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else {
            return false
        }
        guard Self.requestsSpeechRecognitionAuthorization else {
            return true
        }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return status == .authorized
    }

    nonisolated func installModel() -> AsyncThrowingStream<Double, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let locale = await Self.locale(),
                        let request = try await AssetInventory.assetInstallationRequest(
                            supporting: [Self.transcriber(for: locale)]
                        )
                    else {
                        // Nothing to install.
                        continuation.finish()
                        return
                    }
                    let progress = Task {
                        while !Task.isCancelled {
                            continuation.yield(request.progress.fractionCompleted)
                            try? await Task.sleep(for: .milliseconds(200))
                        }
                    }
                    defer { progress.cancel() }
                    try await request.downloadAndInstall()
                    continuation.yield(1)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: TranscriptionError.downloadFailed)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Listening

    func start() async throws -> AsyncStream<TranscriptionEvent> {
        if let session {
            await teardown(session.id)
        }
        guard let locale = await Self.locale() else {
            throw TranscriptionError.failed
        }
        let transcriber = Self.transcriber(for: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard
            let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber]
            )
        else {
            throw TranscriptionError.failed
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            do {
                try audioSession.setCategory(.record, mode: .spokenAudio)
            } catch {
                try audioSession.setCategory(.record, mode: .default)
            }
            try audioSession.setActive(true)
        } catch {
            throw TranscriptionError.failed
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let micFormat = inputNode.outputFormat(forBus: 0)
        // The microphone's format usually differs from the analyzer's, and a mismatch fails
        // silently: every buffer is converted.
        guard micFormat.sampleRate > 0,
            let converter = AVAudioConverter(from: micFormat, to: analyzerFormat)
        else {
            Self.deactivate(audioSession)
            throw TranscriptionError.failed
        }

        let (inputStream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let (events, eventsContinuation) = AsyncStream.makeStream(of: TranscriptionEvent.self)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: micFormat,
            block: Self.makeTap(
                converter: converter, format: analyzerFormat, input: input,
                events: eventsContinuation)
        )

        do {
            try await analyzer.start(inputSequence: inputStream)
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            input.finish()
            await analyzer.cancelAndFinishNow()
            Self.deactivate(audioSession)
            throw TranscriptionError.failed
        }

        let results = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    eventsContinuation.yield(result.isFinal ? .final(text) : .volatile(text))
                }
            } catch {
                // The analyzer was cancelled; whatever was final has been delivered.
            }
        }
        let interruptions = Task { [weak self] in
            await Self.firstInterruption()
            await self?.stop()
        }
        let session = Session(
            engine: engine, analyzer: analyzer, input: input, events: eventsContinuation,
            tasks: [results, interruptions]
        )
        self.session = session
        let sessionID = session.id
        eventsContinuation.onTermination = { [weak self] _ in
            Task { await self?.teardown(sessionID) }
        }
        return events
    }

    func stop() async {
        guard let session else {
            return
        }
        self.session = nil
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
        session.input.finish()
        session.tasks.last?.cancel()
        do {
            // Turns the trailing volatile text into finals before the results end.
            try await session.analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            await session.analyzer.cancelAndFinishNow()
        }
        // Let the results task deliver the last finals.
        await session.tasks.first?.value
        Self.deactivate(AVAudioSession.sharedInstance())
        session.events.yield(.ended(nil))
        session.events.finish()
    }

    /// Stops at once, without finalizing: the reader has gone away. Does nothing if that
    /// session has already ended.
    private func teardown(_ id: UUID) async {
        guard let session, session.id == id else {
            return
        }
        self.session = nil
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
        session.input.finish()
        for task in session.tasks {
            task.cancel()
        }
        await session.analyzer.cancelAndFinishNow()
        Self.deactivate(AVAudioSession.sharedInstance())
        session.events.finish()
    }

    // MARK: Helpers

    /// The device's language, mapped to one the transcriber supports.
    private static func locale() async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
    }

    private static func transcriber(for locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    /// Lets audio that dictation paused, such as music, resume.
    private static func deactivate(_ audioSession: AVAudioSession) {
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The input tap. It runs on a real-time audio thread, so it is built here, outside the
    /// actor, and captures only what it is given: no actor or main-actor state. Buffers reach
    /// the analyzer through its input stream and levels reach the UI through the event stream.
    private nonisolated static func makeTap(
        converter: AVAudioConverter,
        format: AVAudioFormat,
        input: AsyncStream<AnalyzerInput>.Continuation,
        events: AsyncStream<TranscriptionEvent>.Continuation
    ) -> AVAudioNodeTapBlock {
        var meter = AudioLevelMeter()
        return { buffer, _ in
            if let level = meter.update(
                rms: rms(of: buffer), at: ProcessInfo.processInfo.systemUptime)
            {
                events.yield(.level(level))
            }
            if let converted = convert(buffer, with: converter, to: format) {
                input.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    private nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else {
            return nil
        }
        return output
    }

    /// The RMS amplitude of the first channel.
    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return 0
        }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            sum += samples[index] * samples[index]
        }
        return (sum / Float(count)).squareRoot()
    }

    /// Returns at the first thing that should stop dictation: an interruption (a call, Siri,
    /// another app taking the microphone), the input device going away, or the engine's
    /// configuration changing underneath it.
    private nonisolated static func firstInterruption() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await notification in NotificationCenter.default.notifications(
                    named: AVAudioSession.interruptionNotification)
                {
                    let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                    if type == AVAudioSession.InterruptionType.began.rawValue {
                        return
                    }
                }
            }
            group.addTask {
                for await notification in NotificationCenter.default.notifications(
                    named: AVAudioSession.routeChangeNotification)
                {
                    let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                    if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                        || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
                    {
                        return
                    }
                }
            }
            group.addTask {
                for await _ in NotificationCenter.default.notifications(
                    named: .AVAudioEngineConfigurationChange)
                {
                    return
                }
            }
            await group.next()
            group.cancelAll()
        }
    }
}

extension EnvironmentValues {
    /// Replaced with `FakeTranscriptionService` in tests and previews.
    @Entry var transcriptionService: any TranscriptionService = SpeechTranscriptionService()
}
