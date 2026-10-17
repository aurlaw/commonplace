import Foundation

/// A `BiometricAuthenticator` with fixed answers, for tests, previews, and shell mode. Never
/// shows the system prompt.
nonisolated struct FakeBiometricAuthenticator: BiometricAuthenticator {
    var availability = AuthenticationAvailability.available(.faceID)
    var result = AuthenticationResult.success

    func canAuthenticate() -> AuthenticationAvailability {
        availability
    }

    func authenticate(reason: String) async -> AuthenticationResult {
        guard availability.kind != nil else {
            return .unavailable
        }
        return result
    }
}
