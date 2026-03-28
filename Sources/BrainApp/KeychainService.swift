import Foundation
import Security
import LocalAuthentication

// Secure storage for API keys and secrets using the iOS Keychain.
// API keys are NEVER stored in code, UserDefaults, or the database.
struct KeychainService: Sendable {

    private let serviceName = "com.example.brain-ios"

    /// Keys that hold API credentials and should be protected with biometry.
    static let biometryProtectedKeys: Set<String> = [
        KeychainKeys.anthropicAPIKey,
        KeychainKeys.openAIAPIKey,
        KeychainKeys.geminiAPIKey,
    ]

    // Save a value to the keychain with biometric protection (Face ID / Touch ID).
    // Uses `.biometryCurrentSet` so the item is invalidated when biometrics change
    // (e.g. a new fingerprint is enrolled), preventing access by a different person.
    func saveWithBiometry(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encodingFailed }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Create access control requiring biometry (current set only).
        // K1: Secure Enclave (kSecAttrTokenIDSecureEnclave) only works with
        // kSecClassKey, not kSecClassGenericPassword. For generic password items,
        // biometryCurrentSet + thisDeviceOnly provides the best protection.
        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &accessControlError
        ) else {
            throw KeychainError.accessControlCreationFailed
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // Save a value to the keychain (no biometric gate — for non-sensitive items).
    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encodingFailed }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // Read a value from the keychain.
    func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // Delete a value from the keychain.
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Check if a key exists WITHOUT triggering biometry.
    // Uses LAContext with interactionNotAllowed=true so biometry-protected items
    // return errSecInteractionNotAllowed (item exists) instead of prompting Face ID.
    func exists(key: String) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecUseAuthenticationContext as String: context,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        // errSecSuccess = item exists (no biometry needed)
        // errSecInteractionNotAllowed = item exists but is biometry-protected
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}

// Well-known keychain keys for brain-ios.
enum KeychainKeys {
    static let anthropicAPIKey = "anthropic-api-key"
    static let openAIAPIKey = "openai-api-key"
    static let geminiAPIKey = "gemini-api-key"
    // User-configurable proxy URL (e.g. https://my-vps:8082 for self-hosted LLMs)
    static let xaiAPIKey = "xai-api-key"
    // Claude Max session key (from browser cookie, ~30 days valid)
    static let anthropicMaxSessionKey = "anthropic-max-session-key"
    // User-configurable proxy URL
    static let anthropicProxyURL = "anthropic-proxy-url"
    // brain-api JWT auth for proxy access
    static let brainAPIAccessToken = "brain-api-access-token"
    static let brainAPIRefreshToken = "brain-api-refresh-token"
    static let brainAPIBaseURL = "brain-api-base-url"
    static let brainAPIDisplayName = "brain-api-display-name"
}

// K3: API key format validation before storage.
enum APIKeyValidator {

    enum Provider {
        case anthropic, openAI, gemini
    }

    static func validate(_ key: String, provider: Provider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch provider {
        case .anthropic: return trimmed.hasPrefix("sk-ant-") || trimmed.hasPrefix("sk-") || trimmed.count >= 40  // Session keys from claude.ai Max plan
        case .openAI: return trimmed.hasPrefix("sk-") && !trimmed.hasPrefix("sk-ant-")
        case .gemini: return trimmed.count >= 20
        }
    }

    static func errorMessage(for provider: Provider) -> String {
        switch provider {
        case .anthropic: return "API-Key muss mit 'sk-ant-' oder 'sk-' beginnen."
        case .openAI: return "API-Key muss mit 'sk-' beginnen."
        case .gemini: return "API-Key ist zu kurz (mindestens 20 Zeichen)."
        }
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case encodingFailed
    case accessControlCreationFailed
}

