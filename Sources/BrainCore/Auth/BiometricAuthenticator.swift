// Protocol for biometric authentication (Face ID / Touch ID).
// This lives in BrainCore (pure Swift, no iOS imports) so it can be
// referenced from services and tested on Linux.
// The concrete implementation using LocalAuthentication.framework
// will live in the BrainUI target (iOS only).

// Type of biometric hardware available.
public enum BiometricType: String, Codable, Sendable {
    case faceID
    case touchID
    case none
}

// Errors that can occur during authentication.
public enum AuthenticationError: Error, Sendable {
    case biometryNotAvailable
    case biometryNotEnrolled
    case authenticationFailed
    case userCancelled
    case passcodeNotSet
    case systemCancel
}

// Protocol for biometric authentication.
// Concrete implementation will use LocalAuthentication on iOS.
public protocol BiometricAuthenticator: Sendable {

    // Whether the device supports and has enrolled biometric authentication.
    var canUseBiometrics: Bool { get }

    // The type of biometric hardware available.
    var biometricType: BiometricType { get }

    // Authenticate the user. Shows the system biometric prompt.
    // `reason` is displayed in the dialog (e.g. "Unlock Brain").
    func authenticate(reason: String) async throws -> Bool
}
