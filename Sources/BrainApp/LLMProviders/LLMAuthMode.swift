import Foundation

// F1: Authentication mode abstraction for LLM providers.
// Decouples auth method from provider implementation.
// Currently supported: API key, proxy, Google OAuth2.
// Designed for future expansion when Anthropic/OpenAI add OAuth.
enum LLMAuthMode: Sendable {
    /// Direct API key authentication (e.g. sk-ant-..., sk-..., AIza...).
    case apiKey(String)

    /// OpenAI-compatible proxy (self-hosted LLMs on VPS, LiteLLM, etc.).
    /// bearerToken is optional JWT for authenticated proxies.
    case proxy(url: String, bearerToken: String?)

    /// Google OAuth2 (for Gemini API via user's Google account).
    /// Uses ASWebAuthenticationSession for the OAuth flow.
    case googleOAuth(accessToken: String, refreshToken: String?)
}

// Provider-level auth capabilities.
// Each provider declares which auth modes it supports.
protocol AuthCapableProvider {
    static var supportedAuthModes: [AuthModeType] { get }
}

enum AuthModeType: String, CaseIterable, Sendable {
    case apiKey = "API-Key"
    case proxy = "Proxy / VPS"
    case googleOAuth = "Google-Konto"
}

// F1: Google OAuth2 token management.
// Tokens are stored in Keychain; access tokens auto-refresh via refresh token.
enum GoogleOAuthKeys {
    static let accessToken = "google-oauth-access-token"
    static let refreshToken = "google-oauth-refresh-token"
    static let expiresAt = "google-oauth-expires-at"
    // Registered OAuth client for brain-ios (installed app flow)
    // NOTE: These must be replaced with actual registered client credentials
    // from Google Cloud Console before production use.
    static let clientId = "google-oauth-client-id"
}
