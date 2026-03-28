import LocalAuthentication
import BrainCore

// Concrete Face ID / Touch ID implementation using LocalAuthentication.
final class DeviceBiometricAuthenticator: BiometricAuthenticator {

    var canUseBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let error {
                throw mapError(error)
            }
            throw AuthenticationError.biometryNotAvailable
        }

        do {
            let result = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            // TODO: Secure Enclave proof — after successful biometric auth, sign a
            // server-provided nonce with a Secure Enclave private key (kSecAttrTokenIDSecureEnclave)
            // to produce a cryptographic proof that biometry succeeded on-device.
            // This prevents replay attacks and ensures the auth result is non-forgeable.
            // Implementation: create a SecKey in the Secure Enclave at first launch,
            // then call SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, nonce)
            // here and return the signature alongside the boolean result.

            return result
        } catch let laError as LAError {
            throw mapLAError(laError)
        }
    }

    private func mapError(_ error: NSError) -> AuthenticationError {
        guard let laError = error as? LAError else { return .biometryNotAvailable }
        return mapLAError(laError)
    }

    private func mapLAError(_ error: LAError) -> AuthenticationError {
        switch error.code {
        case .biometryNotAvailable: return .biometryNotAvailable
        case .biometryNotEnrolled: return .biometryNotEnrolled
        case .authenticationFailed: return .authenticationFailed
        case .userCancel: return .userCancelled
        case .passcodeNotSet: return .passcodeNotSet
        case .systemCancel: return .systemCancel
        default: return .authenticationFailed
        }
    }
}
