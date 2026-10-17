import Foundation
import LocalAuthentication

/// What unlocks the app on this device.
nonisolated enum BiometryKind: Sendable, Equatable {
    case faceID
    case touchID
    case opticID
    /// No biometry enrolled, but a device passcode is set.
    case passcode

    /// "Face ID", for "Require Face ID" and "Unlock with Face ID".
    var name: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .passcode: "Passcode"
        }
    }

    /// The one-time prompt's title.
    var offerTitle: String {
        switch self {
        case .passcode: "Protect your journal with your passcode?"
        default: "Protect your journal with \(name)?"
        }
    }
}

nonisolated enum AuthenticationAvailability: Sendable, Equatable {
    case available(BiometryKind)
    /// No device passcode is set, so nothing can be enforced.
    case passcodeNotSet
    /// Any other reason the policy can't be evaluated.
    case unavailable

    var kind: BiometryKind? {
        if case .available(let kind) = self { kind } else { nil }
    }
}

nonisolated enum AuthenticationResult: Sendable, Equatable {
    case success
    /// Cancelled by the user or the system; trying again is fine.
    case cancelled
    case failed
    /// Authentication is no longer possible (the passcode was removed).
    case unavailable
}

/// Face ID or Touch ID, falling back to the device passcode. Injected so tests and previews
/// can use a fake.
nonisolated protocol BiometricAuthenticator: Sendable {
    func canAuthenticate() -> AuthenticationAvailability
    func authenticate(reason: String) async -> AuthenticationResult
}

/// `LAContext` with `.deviceOwnerAuthentication`. A fresh context for every check and attempt:
/// a context that has succeeded once doesn't ask again.
nonisolated struct LocalAuthenticator: BiometricAuthenticator {
    func canAuthenticate() -> AuthenticationAvailability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error, error.code == LAError.Code.passcodeNotSet.rawValue {
                return .passcodeNotSet
            }
            return .unavailable
        }
        // `biometryType` is only filled in by a check of a biometric policy.
        var biometryError: NSError?
        guard
            context.canEvaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics, error: &biometryError)
        else {
            return .available(.passcode)
        }
        return .available(Self.kind(of: context.biometryType))
    }

    func authenticate(reason: String) async -> AuthenticationResult {
        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: reason)
            return success ? .success : .failed
        } catch let error as LAError {
            return Self.result(for: error.code)
        } catch {
            return .failed
        }
    }

    static func kind(of biometryType: LABiometryType) -> BiometryKind {
        switch biometryType {
        case .faceID: .faceID
        case .touchID: .touchID
        case .opticID: .opticID
        default: .passcode
        }
    }

    static func result(for code: LAError.Code) -> AuthenticationResult {
        switch code {
        case .userCancel, .systemCancel, .appCancel, .userFallback, .notInteractive:
            .cancelled
        case .passcodeNotSet:
            .unavailable
        default:
            .failed
        }
    }
}
