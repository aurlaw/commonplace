import Foundation
import Observation
import SwiftUI

/// The optional Face ID lock and the app-switcher privacy cover.
///
/// Settings are per device, in `UserDefaults`, never synced. The clock is injected so the
/// grace period can be tested.
@Observable
final class AppLock {
    static let enabledKey = "appLock.isEnabled"
    static let promptedKey = "appLock.hasPrompted"
    /// Set when the lock was turned off because the device could no longer authenticate, so
    /// Settings can say why. Cleared when it is turned on again.
    static let turnedOffKey = "appLock.turnedOffUnavailable"
    /// Coming back sooner than this after leaving doesn't lock.
    static let gracePeriod: TimeInterval = 60

    private(set) var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }
    /// Whether the one-time offer has been answered.
    private(set) var hasPrompted: Bool {
        didSet { defaults.set(hasPrompted, forKey: Self.promptedKey) }
    }
    private(set) var wasTurnedOffUnavailable: Bool {
        didSet { defaults.set(wasTurnedOffUnavailable, forKey: Self.turnedOffKey) }
    }
    /// The lock screen is up; only authentication takes it down.
    private(set) var isLocked = false
    /// The privacy cover is up, for the app switcher.
    private(set) var isObscured = false
    /// When the app last went to the background; `nil` once it's back.
    private(set) var backgroundedAt: Date?
    private(set) var availability: AuthenticationAvailability
    /// Counts locks, so the lock screen prompts automatically once per lock.
    private(set) var lockCount = 0
    private(set) var isSceneActive = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let authenticator: any BiometricAuthenticator
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var autoUnlockedLock: Int?
    /// While the system prompt is up the scene goes inactive and back; that isn't leaving.
    @ObservationIgnored private var isAuthenticating = false

    /// Reads the stored settings and applies the cold-launch rule, so a locked app is locked
    /// before its first frame.
    init(
        defaults: UserDefaults = .standard,
        authenticator: any BiometricAuthenticator,
        now: @escaping () -> Date = { .now }
    ) {
        self.defaults = defaults
        self.authenticator = authenticator
        self.now = now
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        hasPrompted = defaults.bool(forKey: Self.promptedKey)
        wasTurnedOffUnavailable = defaults.bool(forKey: Self.turnedOffKey)
        availability = authenticator.canAuthenticate()
        if isEnabled, availability.kind == nil {
            turnOffUnavailable()
        }
        if isEnabled {
            lock()
        }
    }

    /// Something is covering the app: the lock screen or the privacy cover.
    var isCovering: Bool {
        isLocked || isObscured
    }

    /// The one-time offer: not yet answered, lock off, and the device can authenticate.
    var shouldOffer: Bool {
        !hasPrompted && !isEnabled && availability.kind != nil
    }

    // MARK: Scene phase

    func sceneChanged(to phase: ScenePhase) {
        isSceneActive = phase == .active
        guard !isAuthenticating else {
            return
        }
        switch phase {
        case .inactive:
            if isEnabled {
                isObscured = true
            }
        case .background:
            backgroundedAt = backgroundedAt ?? now()
            if isEnabled {
                isObscured = true
            }
        case .active:
            refreshAvailability()
            if isEnabled, !isLocked, let backgroundedAt,
                now().timeIntervalSince(backgroundedAt) >= Self.gracePeriod
            {
                lock()
            }
            backgroundedAt = nil
            isObscured = false
        @unknown default:
            break
        }
    }

    // MARK: Unlocking

    /// The lock screen's automatic attempt: once per lock, and only while the app is active
    /// (the system can't show its prompt otherwise).
    func autoUnlockIfNeeded() async {
        guard isLocked, isSceneActive, autoUnlockedLock != lockCount else {
            return
        }
        autoUnlockedLock = lockCount
        await unlock()
    }

    /// The Unlock button, and the automatic attempt. Cancelled or failed leaves the lock up.
    func unlock() async {
        guard isLocked else {
            return
        }
        switch await authenticate(reason: "Unlock your journal.") {
        case .success:
            isLocked = false
            isObscured = false
            backgroundedAt = nil
        case .unavailable:
            turnOffUnavailable()
        case .cancelled, .failed:
            break
        }
    }

    // MARK: Turning it on and off

    /// The one-time offer's answer. Turn On authenticates first; only success turns the lock
    /// on. The offer is never shown again either way.
    func answerOffer(turnOn: Bool) async {
        hasPrompted = true
        guard turnOn else {
            return
        }
        if await authenticate(reason: "Turn on the lock for your journal.") == .success {
            isEnabled = true
            wasTurnedOffUnavailable = false
        }
    }

    /// The Settings toggle. Both directions authenticate first; anything but success leaves
    /// the setting as it was.
    ///
    /// - Returns: Whether the setting changed.
    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isEnabled else {
            return false
        }
        let reason =
            enabled ? "Turn on the lock for your journal." : "Turn off the lock for your journal."
        switch await authenticate(reason: reason) {
        case .success:
            isEnabled = enabled
            hasPrompted = true
            wasTurnedOffUnavailable = false
            return true
        case .unavailable:
            turnOffUnavailable()
            return false
        case .cancelled, .failed:
            return false
        }
    }

    // MARK: Helpers

    private func lock() {
        isLocked = true
        isObscured = true
        lockCount += 1
    }

    private func authenticate(reason: String) async -> AuthenticationResult {
        isAuthenticating = true
        defer { isAuthenticating = false }
        return await authenticator.authenticate(reason: reason)
    }

    /// The lock can't be enforced without a passcode: unlock, and turn the setting off.
    private func refreshAvailability() {
        availability = authenticator.canAuthenticate()
        if isEnabled, availability.kind == nil {
            turnOffUnavailable()
        }
    }

    private func turnOffUnavailable() {
        isEnabled = false
        isLocked = false
        isObscured = false
        wasTurnedOffUnavailable = true
    }
}
