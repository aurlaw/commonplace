import Foundation
import LocalAuthentication
import SwiftUI
import Testing

@testable import Commonplace

@MainActor
final class AppLockTests {
    private let suiteName = "AppLockTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func makeLock(
        enabled: Bool = false,
        prompted: Bool = false,
        authenticator: FakeBiometricAuthenticator = FakeBiometricAuthenticator()
    ) -> AppLock {
        defaults.set(enabled, forKey: AppLock.enabledKey)
        defaults.set(prompted, forKey: AppLock.promptedKey)
        return AppLock(
            defaults: defaults, authenticator: authenticator, now: { [unowned self] in clock })
    }

    /// Leaves for `seconds` and comes back, the way the scene reports it.
    private func leave(_ lock: AppLock, for seconds: TimeInterval) {
        lock.sceneChanged(to: .inactive)
        lock.sceneChanged(to: .background)
        clock.addTimeInterval(seconds)
        lock.sceneChanged(to: .inactive)
        lock.sceneChanged(to: .active)
    }

    // MARK: Transitions

    @Test func coldLaunchWithTheLockOnIsLockedBeforeAnything() {
        let lock = makeLock(enabled: true)

        #expect(lock.isLocked)
        #expect(lock.isObscured)
        #expect(lock.isCovering)
    }

    @Test func coldLaunchWithTheLockOffIsOpen() {
        let lock = makeLock(enabled: false)

        #expect(!lock.isLocked)
        #expect(!lock.isCovering)
    }

    @Test func inactiveObscuresOnlyWhenEnabled() async {
        let off = makeLock(enabled: false)
        off.sceneChanged(to: .inactive)
        #expect(!off.isObscured)

        let on = makeLock(enabled: true)
        on.sceneChanged(to: .active)
        await on.unlock()
        on.sceneChanged(to: .inactive)
        #expect(on.isObscured)
        #expect(!on.isLocked)
    }

    @Test func backgroundRecordsTheTimeAndStaysObscured() async {
        let lock = makeLock(enabled: true)
        lock.sceneChanged(to: .active)
        await lock.unlock()

        lock.sceneChanged(to: .inactive)
        lock.sceneChanged(to: .background)

        #expect(lock.backgroundedAt == clock)
        #expect(lock.isObscured)
    }

    @Test func returningWithinTheGracePeriodOnlyUncovers() async {
        let lock = makeLock(enabled: true)
        lock.sceneChanged(to: .active)
        await lock.unlock()

        leave(lock, for: 59)

        #expect(!lock.isLocked)
        #expect(!lock.isObscured)
        #expect(lock.backgroundedAt == nil)
    }

    @Test func returningAfterTheGracePeriodLocks() async {
        let lock = makeLock(enabled: true)
        lock.sceneChanged(to: .active)
        await lock.unlock()

        leave(lock, for: 60)

        #expect(lock.isLocked)
        #expect(lock.isCovering)
    }

    @Test func inactiveAndBackWithoutBackgroundingDoesNotLock() async {
        let lock = makeLock(enabled: true)
        lock.sceneChanged(to: .active)
        await lock.unlock()

        lock.sceneChanged(to: .inactive)
        clock.addTimeInterval(600)
        lock.sceneChanged(to: .active)

        #expect(!lock.isLocked)
        #expect(!lock.isObscured)
    }

    @Test func disabledIsNeverLockedOrObscured() {
        let lock = makeLock(enabled: false)

        leave(lock, for: 3_600)

        #expect(!lock.isLocked)
        #expect(!lock.isObscured)
    }

    @Test func successfulUnlockUncovers() async {
        let lock = makeLock(enabled: true)
        lock.sceneChanged(to: .active)

        await lock.unlock()

        #expect(!lock.isLocked)
        #expect(!lock.isObscured)
    }

    @Test func cancelledOrFailedUnlockStaysLocked() async {
        for result in [AuthenticationResult.cancelled, .failed] {
            let lock = makeLock(
                enabled: true, authenticator: FakeBiometricAuthenticator(result: result))
            lock.sceneChanged(to: .active)

            await lock.unlock()

            #expect(lock.isLocked)
            #expect(lock.isEnabled)
        }
    }

    @Test func autoUnlockRunsOncePerLockAndOnlyWhenActive() async {
        let lock = makeLock(
            enabled: true, authenticator: FakeBiometricAuthenticator(result: .cancelled))

        await lock.autoUnlockIfNeeded()  // not active yet: nothing asked
        lock.sceneChanged(to: .active)
        await lock.autoUnlockIfNeeded()  // asks, cancelled
        #expect(lock.isLocked)

        let lockCount = lock.lockCount
        await lock.autoUnlockIfNeeded()  // not again for the same lock
        #expect(lock.lockCount == lockCount)
    }

    // MARK: One-time offer

    @Test func offerIsShownOnlyWhenNotPromptedAndAvailable() {
        #expect(makeLock().shouldOffer)
        #expect(!makeLock(prompted: true).shouldOffer)
        #expect(!makeLock(enabled: true).shouldOffer)
        #expect(
            !makeLock(authenticator: FakeBiometricAuthenticator(availability: .passcodeNotSet))
                .shouldOffer)
        #expect(
            !makeLock(authenticator: FakeBiometricAuthenticator(availability: .unavailable))
                .shouldOffer)
    }

    @Test func turnOnWithSuccessEnables() async {
        let lock = makeLock()

        await lock.answerOffer(turnOn: true)

        #expect(lock.isEnabled)
        #expect(lock.hasPrompted)
        #expect(defaults.bool(forKey: AppLock.enabledKey))
        #expect(defaults.bool(forKey: AppLock.promptedKey))
        // Turning it on doesn't lock you out of the session you're in.
        #expect(!lock.isLocked)
    }

    @Test func turnOnWithFailureOrNotNowStaysOff() async {
        let failed = makeLock(authenticator: FakeBiometricAuthenticator(result: .failed))
        await failed.answerOffer(turnOn: true)
        #expect(!failed.isEnabled)
        #expect(failed.hasPrompted)

        let cancelled = makeLock(authenticator: FakeBiometricAuthenticator(result: .cancelled))
        await cancelled.answerOffer(turnOn: true)
        #expect(!cancelled.isEnabled)
        #expect(cancelled.hasPrompted)

        let notNow = makeLock()
        await notNow.answerOffer(turnOn: false)
        #expect(!notNow.isEnabled)
        #expect(notNow.hasPrompted)
        #expect(defaults.bool(forKey: AppLock.promptedKey))
    }

    // MARK: Settings toggle

    @Test func enablingAndDisablingEachRequireSuccess() async {
        let lock = makeLock()
        #expect(await lock.setEnabled(true))
        #expect(lock.isEnabled)

        #expect(await lock.setEnabled(false))
        #expect(!lock.isEnabled)
        #expect(!defaults.bool(forKey: AppLock.enabledKey))
    }

    @Test func failedAuthenticationLeavesTheToggleUnchanged() async {
        for result in [AuthenticationResult.cancelled, .failed] {
            let off = makeLock(authenticator: FakeBiometricAuthenticator(result: result))
            #expect(!(await off.setEnabled(true)))
            #expect(!off.isEnabled)

            let on = makeLock(
                enabled: true, authenticator: FakeBiometricAuthenticator(result: result))
            #expect(!(await on.setEnabled(false)))
            #expect(on.isEnabled)
        }
    }

    // MARK: Losing the ability to authenticate

    @Test func unavailableWhileEnabledUnlocksAndTurnsOff() {
        let lock = makeLock(
            enabled: true,
            authenticator: FakeBiometricAuthenticator(availability: .passcodeNotSet))

        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
        #expect(!lock.isCovering)
        #expect(lock.wasTurnedOffUnavailable)
        #expect(!defaults.bool(forKey: AppLock.enabledKey))
    }

    @Test func authenticationReportingUnavailableTurnsOff() async {
        let lock = makeLock(
            enabled: true, authenticator: FakeBiometricAuthenticator(result: .unavailable))
        lock.sceneChanged(to: .active)

        await lock.unlock()

        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
        #expect(lock.wasTurnedOffUnavailable)
    }

    @Test func turningOnAgainClearsTheExplanation() async {
        defaults.set(true, forKey: AppLock.turnedOffKey)
        let lock = makeLock()
        #expect(lock.wasTurnedOffUnavailable)

        await lock.setEnabled(true)

        #expect(!lock.wasTurnedOffUnavailable)
    }
}

// MARK: Labels

struct BiometryLabelTests {
    @Test func namesFollowTheHardware() {
        #expect(LocalAuthenticator.kind(of: .faceID) == .faceID)
        #expect(LocalAuthenticator.kind(of: .touchID) == .touchID)
        #expect(LocalAuthenticator.kind(of: .opticID) == .opticID)
        #expect(LocalAuthenticator.kind(of: .none) == .passcode)

        #expect(BiometryKind.faceID.name == "Face ID")
        #expect(BiometryKind.touchID.name == "Touch ID")
        #expect(BiometryKind.passcode.name == "Passcode")
        #expect(BiometryKind.faceID.offerTitle == "Protect your journal with Face ID?")
        #expect(BiometryKind.passcode.offerTitle == "Protect your journal with your passcode?")
    }

    @Test func errorCodesMapToResults() {
        #expect(LocalAuthenticator.result(for: .userCancel) == .cancelled)
        #expect(LocalAuthenticator.result(for: .systemCancel) == .cancelled)
        #expect(LocalAuthenticator.result(for: .appCancel) == .cancelled)
        #expect(LocalAuthenticator.result(for: .userFallback) == .cancelled)
        #expect(LocalAuthenticator.result(for: .notInteractive) == .cancelled)
        #expect(LocalAuthenticator.result(for: .authenticationFailed) == .failed)
        #expect(LocalAuthenticator.result(for: .passcodeNotSet) == .unavailable)
    }
}
