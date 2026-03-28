import AuthenticationServices
import CryptoKit
import Foundation

// Google OAuth2 authentication for Gemini API.
// Uses Authorization Code Flow with PKCE (RFC 7636) via ASWebAuthenticationSession.
// This is the correct flow for native iOS apps (public clients).
//
// SETUP: The Google Cloud Console iOS client ID is hardcoded below.
// The reversed client ID is used as the URL scheme for the OAuth callback.

// Errors that can occur during the Google OAuth flow.
enum GoogleOAuthError: Error, LocalizedError {
    case clientIdNotConfigured
    case authSessionFailed(Error)
    case userCancelled
    case noCallbackURL
    case noAuthorizationCode
    case tokenExchangeFailed(String)
    case refreshFailed(String)
    case noRefreshToken
    case invalidResponse
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .clientIdNotConfigured:
            return "Google OAuth Client-ID nicht konfiguriert. Bitte in den Einstellungen hinterlegen."
        case .authSessionFailed(let error):
            return "Authentifizierung fehlgeschlagen: \(error.localizedDescription)"
        case .userCancelled:
            return "Anmeldung abgebrochen."
        case .noCallbackURL:
            return "Keine Callback-URL erhalten."
        case .noAuthorizationCode:
            return "Kein Autorisierungscode erhalten."
        case .tokenExchangeFailed(let detail):
            return "Token-Austausch fehlgeschlagen: \(detail)"
        case .refreshFailed(let detail):
            return "Token-Erneuerung fehlgeschlagen: \(detail)"
        case .noRefreshToken:
            return "Kein Refresh-Token vorhanden. Bitte erneut anmelden."
        case .invalidResponse:
            return "Ungültige Antwort vom Google-Server."
        case .networkError(let error):
            return "Netzwerkfehler: \(error.localizedDescription)"
        }
    }
}

// Google OAuth2 service for Gemini API authentication.
// Manages the full OAuth lifecycle: authorization (with PKCE), token exchange, refresh, and logout.
@MainActor
final class GoogleOAuthService {

    // MARK: - Constants

    private static let authorizationURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenURL = "https://oauth2.googleapis.com/token"
    private static let scope = "https://www.googleapis.com/auth/generative-language.retriever"

    // The hardcoded iOS OAuth client ID from Google Cloud Console.
    private static let placeholderClientID = "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"

    // Buffer before actual expiry to avoid edge-case failures (5 minutes).
    private static let expiryBuffer: TimeInterval = 300

    // MARK: - PKCE State

    // Stored between authorization and token exchange within a single flow.
    private var codeVerifier: String?

    // MARK: - Dependencies

    private let keychain = KeychainService()

    // MARK: - Computed Properties

    // Derive the reversed client ID for use as URL scheme.
    // e.g. "888144865127-xxx.apps.googleusercontent.com" → "com.googleusercontent.apps.888144865127-xxx"
    private var callbackScheme: String {
        let clientId = (try? resolveClientId()) ?? Self.placeholderClientID
        return reversedClientId(clientId)
    }

    private var redirectURI: String {
        "\(callbackScheme):/oauth2callback"
    }

    // MARK: - Public API

    // Whether the user has a stored refresh token (i.e. has authenticated before).
    var isAuthenticated: Bool {
        keychain.read(key: GoogleOAuthKeys.refreshToken) != nil
    }

    // Start the full OAuth2 authorization flow with PKCE.
    // Opens a web-based login via ASWebAuthenticationSession, exchanges the
    // authorization code for tokens, and stores them in Keychain.
    func startOAuthFlow() async throws -> (accessToken: String, refreshToken: String) {
        let clientId = try resolveClientId()

        // Generate PKCE pair
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        codeVerifier = verifier

        let authCode = try await performAuthSession(clientId: clientId, codeChallenge: challenge)
        let tokens = try await exchangeCodeForTokens(code: authCode, clientId: clientId, codeVerifier: verifier)

        codeVerifier = nil
        storeTokens(tokens)

        return (tokens.accessToken, tokens.refreshToken)
    }

    // Refresh the access token using the stored refresh token.
    func refreshAccessToken() async throws -> String {
        let clientId = try resolveClientId()

        guard let refreshToken = keychain.read(key: GoogleOAuthKeys.refreshToken) else {
            throw GoogleOAuthError.noRefreshToken
        }

        let tokens = try await performTokenRefresh(refreshToken: refreshToken, clientId: clientId)

        try? keychain.save(key: GoogleOAuthKeys.accessToken, value: tokens.accessToken)
        if let newRefresh = tokens.refreshToken {
            try? keychain.save(key: GoogleOAuthKeys.refreshToken, value: newRefresh)
        }
        storeExpiry(tokens.expiresIn)

        return tokens.accessToken
    }

    // Get a valid access token, refreshing automatically if expired.
    func getValidToken() async throws -> String {
        if let accessToken = keychain.read(key: GoogleOAuthKeys.accessToken),
           !isTokenExpired()
        {
            return accessToken
        }
        return try await refreshAccessToken()
    }

    // Clear all stored OAuth tokens from Keychain.
    func logout() {
        keychain.delete(key: GoogleOAuthKeys.accessToken)
        keychain.delete(key: GoogleOAuthKeys.refreshToken)
        keychain.delete(key: GoogleOAuthKeys.expiresAt)
    }

    // MARK: - PKCE Helpers (RFC 7636)

    // Generate a cryptographically random code verifier (43-128 chars, URL-safe).
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    // Generate SHA-256 code challenge from the verifier.
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncoded()
    }

    // MARK: - Private Helpers

    // Return the fixed OAuth client ID. No user configuration needed.
    private func resolveClientId() throws -> String {
        // Always use the hardcoded client ID — user-configurable override removed.
        return Self.placeholderClientID
    }

    // Reverse a Google client ID into a URL scheme.
    // "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
    private func reversedClientId(_ clientId: String) -> String {
        clientId.split(separator: ".").reversed().joined(separator: ".")
    }

    // Open ASWebAuthenticationSession for Google sign-in with PKCE.
    private func performAuthSession(clientId: String, codeChallenge: String) async throws -> String {
        let scheme = reversedClientId(clientId)
        let redirect = "\(scheme):/oauth2callback"

        var components = URLComponents(string: Self.authorizationURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            // PKCE parameters
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let authURL = components?.url else {
            throw GoogleOAuthError.clientIdNotConfigured
        }

        // ASWebAuthenticationSession requires a presentationContextProvider to show the login window.
        let contextProvider = OAuthPresentationContext()

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: scheme
            ) { callbackURL, error in
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GoogleOAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: GoogleOAuthError.authSessionFailed(error))
                    }
                    return
                }

                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: GoogleOAuthError.noCallbackURL)
                    return
                }

                let urlComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
                guard let code = urlComponents?.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: GoogleOAuthError.noAuthorizationCode)
                    return
                }

                continuation.resume(returning: code)
            }

            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    // Exchange the authorization code for access + refresh tokens (with PKCE verifier).
    private func exchangeCodeForTokens(code: String, clientId: String, codeVerifier: String) async throws -> TokenResponse {
        guard let url = URL(string: Self.tokenURL) else {
            throw GoogleOAuthError.tokenExchangeFailed("Invalid token URL")
        }

        let scheme = reversedClientId(clientId)
        let redirect = "\(scheme):/oauth2callback"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier,
        ]
        request.httpBody = body
            .map { "\($0.key)=\(urlEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleOAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw GoogleOAuthError.tokenExchangeFailed(detail)
        }

        return try parseTokenResponse(data)
    }

    // Refresh an expired access token using the refresh token.
    private func performTokenRefresh(
        refreshToken: String,
        clientId: String
    ) async throws -> RefreshResponse {
        guard let url = URL(string: Self.tokenURL) else {
            throw GoogleOAuthError.refreshFailed("Invalid token URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "grant_type": "refresh_token",
        ]
        request.httpBody = body
            .map { "\($0.key)=\(urlEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleOAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw GoogleOAuthError.refreshFailed(detail)
        }

        return try parseRefreshResponse(data)
    }

    // Perform a URLSession request with error wrapping.
    // Uses URLSession.shared intentionally — Google OAuth endpoints (accounts.google.com,
    // oauth2.googleapis.com) rotate certificates frequently and are not in the pin list.
    // Standard TLS validation is sufficient for OAuth token exchange.
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw GoogleOAuthError.networkError(error)
        }
    }

    // Store tokens in Keychain after successful auth.
    private func storeTokens(_ tokens: TokenResponse) {
        try? keychain.save(key: GoogleOAuthKeys.accessToken, value: tokens.accessToken)
        try? keychain.save(key: GoogleOAuthKeys.refreshToken, value: tokens.refreshToken)
        storeExpiry(tokens.expiresIn)
    }

    // Store the expiry timestamp (now + expiresIn seconds).
    private func storeExpiry(_ expiresIn: Int) {
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        let timestamp = String(expiresAt.timeIntervalSince1970)
        try? keychain.save(key: GoogleOAuthKeys.expiresAt, value: timestamp)
    }

    // Check if the cached access token has expired (with a 5-minute buffer).
    private func isTokenExpired() -> Bool {
        guard let expiresAtString = keychain.read(key: GoogleOAuthKeys.expiresAt),
              let expiresAt = Double(expiresAtString)
        else {
            return true
        }
        return Date().timeIntervalSince1970 >= (expiresAt - Self.expiryBuffer)
    }

    // URL-encode a string for form-urlencoded POST body.
    private func urlEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }

    // MARK: - Token Response Models

    private struct TokenResponse {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
    }

    private struct RefreshResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
    }

    private func parseTokenResponse(_ data: Data) throws -> TokenResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String
        else {
            throw GoogleOAuthError.invalidResponse
        }
        let expiresIn = json["expires_in"] as? Int ?? 3600
        return TokenResponse(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
    }

    private func parseRefreshResponse(_ data: Data) throws -> RefreshResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String
        else {
            throw GoogleOAuthError.invalidResponse
        }
        let refreshToken = json["refresh_token"] as? String
        let expiresIn = json["expires_in"] as? Int ?? 3600
        return RefreshResponse(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
    }
}

// MARK: - Presentation Context for ASWebAuthenticationSession

/// Provides the window anchor for the OAuth login sheet.
/// Without this, ASWebAuthenticationSession silently fails to present.
private class OAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Find the key window from the active scene
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

// MARK: - Base64URL Encoding (for PKCE)

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
