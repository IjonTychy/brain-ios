import Testing
import Foundation
@testable import BrainApp

// MARK: - LLMAuthMode Tests

@Suite("LLMAuthMode")
struct LLMAuthModeTests {

    @Test("apiKey case stores the key string")
    func apiKeyCase() {
        let mode = LLMAuthMode.apiKey("sk-ant-test-key-123")
        if case .apiKey(let key) = mode {
            #expect(key == "sk-ant-test-key-123")
        } else {
            Issue.record("Expected .apiKey case")
        }
    }

    @Test("proxy case stores URL and optional bearer token")
    func proxyCaseWithToken() {
        let mode = LLMAuthMode.proxy(url: "https://my-proxy.example.com", bearerToken: "jwt-token-abc")
        if case .proxy(let url, let token) = mode {
            #expect(url == "https://my-proxy.example.com")
            #expect(token == "jwt-token-abc")
        } else {
            Issue.record("Expected .proxy case")
        }
    }

    @Test("proxy case works without bearer token")
    func proxyCaseWithoutToken() {
        let mode = LLMAuthMode.proxy(url: "https://open-proxy.local", bearerToken: nil)
        if case .proxy(let url, let token) = mode {
            #expect(url == "https://open-proxy.local")
            #expect(token == nil)
        } else {
            Issue.record("Expected .proxy case")
        }
    }

    @Test("googleOAuth case stores access and refresh tokens")
    func googleOAuthWithRefresh() {
        let mode = LLMAuthMode.googleOAuth(accessToken: "ya29.access", refreshToken: "1//refresh")
        if case .googleOAuth(let access, let refresh) = mode {
            #expect(access == "ya29.access")
            #expect(refresh == "1//refresh")
        } else {
            Issue.record("Expected .googleOAuth case")
        }
    }

    @Test("googleOAuth case works without refresh token")
    func googleOAuthWithoutRefresh() {
        let mode = LLMAuthMode.googleOAuth(accessToken: "ya29.access", refreshToken: nil)
        if case .googleOAuth(let access, let refresh) = mode {
            #expect(access == "ya29.access")
            #expect(refresh == nil)
        } else {
            Issue.record("Expected .googleOAuth case")
        }
    }

    @Test("LLMAuthMode is Sendable")
    func sendableConformance() {
        // Compile-time check: if this function compiles, LLMAuthMode is Sendable
        let mode: any Sendable = LLMAuthMode.apiKey("test")
        _ = mode  // Suppress unused variable warning
    }
}

// MARK: - AuthModeType Tests

@Suite("AuthModeType")
struct AuthModeTypeTests {

    @Test("AuthModeType.apiKey has expected rawValue")
    func apiKeyRawValue() {
        #expect(AuthModeType.apiKey.rawValue == "API-Key")
    }

    @Test("AuthModeType.proxy has expected rawValue")
    func proxyRawValue() {
        #expect(AuthModeType.proxy.rawValue == "Proxy / VPS")
    }

    @Test("AuthModeType.googleOAuth has expected rawValue")
    func googleOAuthRawValue() {
        #expect(AuthModeType.googleOAuth.rawValue == "Google-Konto")
    }

    @Test("AuthModeType.allCases contains all three modes")
    func allCasesCount() {
        #expect(AuthModeType.allCases.count == 3)
        #expect(AuthModeType.allCases.contains(.apiKey))
        #expect(AuthModeType.allCases.contains(.proxy))
        #expect(AuthModeType.allCases.contains(.googleOAuth))
    }

    @Test("AuthModeType can be constructed from rawValue")
    func constructFromRawValue() {
        #expect(AuthModeType(rawValue: "API-Key") == .apiKey)
        #expect(AuthModeType(rawValue: "Proxy / VPS") == .proxy)
        #expect(AuthModeType(rawValue: "Google-Konto") == .googleOAuth)
    }

    @Test("AuthModeType returns nil for invalid rawValue")
    func invalidRawValue() {
        #expect(AuthModeType(rawValue: "invalid") == nil)
        #expect(AuthModeType(rawValue: "") == nil)
        #expect(AuthModeType(rawValue: "api-key") == nil)  // Case-sensitive
    }

    @Test("AuthModeType rawValues are user-facing German strings")
    func rawValuesAreGerman() {
        // All rawValues should be display-friendly (used in UI pickers)
        for mode in AuthModeType.allCases {
            #expect(!mode.rawValue.isEmpty)
            #expect(mode.rawValue.count >= 5, "RawValue '\(mode.rawValue)' seems too short for a UI label")
        }
    }

    @Test("AuthModeType is Sendable")
    func sendableConformance() {
        let mode: any Sendable = AuthModeType.apiKey
        _ = mode
    }

    @Test("All AuthModeType cases have unique rawValues")
    func uniqueRawValues() {
        let rawValues = AuthModeType.allCases.map(\.rawValue)
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count, "AuthModeType rawValues should be unique")
    }
}

// MARK: - GoogleOAuthKeys Tests

@Suite("GoogleOAuthKeys")
struct GoogleOAuthKeysTests {

    @Test("OAuth key constants are non-empty and distinct")
    func keysAreDistinct() {
        let keys = [
            GoogleOAuthKeys.accessToken,
            GoogleOAuthKeys.refreshToken,
            GoogleOAuthKeys.expiresAt,
            GoogleOAuthKeys.clientId,
        ]
        for key in keys {
            #expect(!key.isEmpty, "OAuth key constant should not be empty")
        }
        let uniqueKeys = Set(keys)
        #expect(keys.count == uniqueKeys.count, "All OAuth key constants should be unique")
    }

    @Test("OAuth keys follow naming convention")
    func keysFollowConvention() {
        #expect(GoogleOAuthKeys.accessToken.hasPrefix("google-oauth-"))
        #expect(GoogleOAuthKeys.refreshToken.hasPrefix("google-oauth-"))
        #expect(GoogleOAuthKeys.expiresAt.hasPrefix("google-oauth-"))
        #expect(GoogleOAuthKeys.clientId.hasPrefix("google-oauth-"))
    }
}
