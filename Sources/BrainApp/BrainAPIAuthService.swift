import Foundation

// Authenticates against brain-api (JWT) for proxy access.
// Handles login, 2FA, token refresh, and secure storage.
// Access token (15 min) + refresh token (30 days) in Keychain.
@MainActor
final class BrainAPIAuthService {
    static let shared = BrainAPIAuthService()

    private let keychain = KeychainService()
    // Mutable flag is safe via @MainActor isolation
    private var isRefreshing = false

    private init() {}

    // MARK: - Public API

    /// Login to brain-api. Returns user info on success.
    /// If 2FA is required, throws `AuthError.requires2FA` with the temp token.
    func login(baseURL: String, username: String, password: String) async throws -> LoginResult {
        guard let url = URL(string: "\(baseURL)/api/auth/login") else {
            throw AuthError.serverError(statusCode: 0, message: "Ungültige URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password,
        ])

        let (data, response) = try await PinnedURLSession.shared.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        switch http.statusCode {
        case 200:
            // Check if 2FA is required
            if json["requires2FA"] as? Bool == true {
                let tempToken = json["tempToken"] as? String ?? ""
                throw AuthError.requires2FA(tempToken: tempToken)
            }

            // Successful login — store tokens
            try storeTokens(json: json, baseURL: baseURL)

            return LoginResult(
                user: json["user"] as? String ?? "",
                displayName: json["displayName"] as? String ?? ""
            )

        case 401:
            throw AuthError.invalidCredentials
        case 429:
            throw AuthError.tooManyAttempts(message: json["error"] as? String ?? "Zu viele Versuche")
        default:
            throw AuthError.serverError(statusCode: http.statusCode, message: json["error"] as? String ?? "")
        }
    }

    /// Complete 2FA login with TOTP code.
    func login2FA(baseURL: String, tempToken: String, code: String) async throws -> LoginResult {
        guard let url = URL(string: "\(baseURL)/api/auth/login/2fa") else {
            throw AuthError.serverError(statusCode: 0, message: "Ungültige URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "tempToken": tempToken,
            "code": code,
        ])

        let (data, response) = try await PinnedURLSession.shared.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard http.statusCode == 200 else {
            if http.statusCode == 401 {
                throw AuthError.invalid2FACode(message: json["error"] as? String ?? "Ungültiger Code")
            }
            throw AuthError.serverError(statusCode: http.statusCode, message: json["error"] as? String ?? "")
        }

        try storeTokens(json: json, baseURL: baseURL)

        return LoginResult(
            user: json["user"] as? String ?? "",
            displayName: json["displayName"] as? String ?? ""
        )
    }

    /// Returns a valid access token, refreshing if needed.
    /// Returns nil if not logged in.
    func getValidToken() async -> String? {
        guard let token = keychain.read(key: KeychainKeys.brainAPIAccessToken) else {
            return nil
        }

        // Check if token is still valid (with 60s safety margin)
        if let expiry = tokenExpiry(token), expiry > Date().addingTimeInterval(60) {
            return token
        }

        // Token expired or expiring soon — try refresh
        return await refreshAccessToken()
    }

    /// Whether the user is logged in (has a refresh token).
    var isLoggedIn: Bool {
        keychain.exists(key: KeychainKeys.brainAPIRefreshToken)
    }

    /// The currently stored display name.
    var displayName: String? {
        keychain.read(key: KeychainKeys.brainAPIDisplayName)
    }

    /// Logout — clear all tokens.
    func logout() {
        keychain.delete(key: KeychainKeys.brainAPIAccessToken)
        keychain.delete(key: KeychainKeys.brainAPIRefreshToken)
        keychain.delete(key: KeychainKeys.brainAPIDisplayName)
        // Keep baseURL so the user doesn't have to re-enter it
    }

    // MARK: - Token Refresh

    private func refreshAccessToken() async -> String? {
        // Prevent concurrent refreshes
        if isRefreshing {
            // Wait briefly and check again
            try? await Task.sleep(nanoseconds: 500_000_000)
            return keychain.read(key: KeychainKeys.brainAPIAccessToken)
        }
        isRefreshing = true

        defer {
            isRefreshing = false
        }

        guard let refreshToken = keychain.read(key: KeychainKeys.brainAPIRefreshToken),
              let baseURL = keychain.read(key: KeychainKeys.brainAPIBaseURL) else {
            return nil
        }

        guard let url = URL(string: "\(baseURL)/api/auth/refresh") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "refresh_token": refreshToken,
        ])

        do {
            let (data, response) = try await PinnedURLSession.shared.session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // Refresh failed — session expired, user must re-login
                logout()
                return nil
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if let newAccessToken = json["token"] as? String {
                try? keychain.save(key: KeychainKeys.brainAPIAccessToken, value: newAccessToken)
                if let newRefresh = json["refresh_token"] as? String {
                    try? keychain.save(key: KeychainKeys.brainAPIRefreshToken, value: newRefresh)
                }
                return newAccessToken
            }
        } catch {
            // Network error during refresh — return nil but don't logout
            // (might be temporary connectivity issue)
        }

        return nil
    }

    // MARK: - Helpers

    private func storeTokens(json: [String: Any], baseURL: String) throws {
        guard let accessToken = json["token"] as? String,
              let refreshToken = json["refresh_token"] as? String else {
            throw AuthError.invalidResponse
        }

        try keychain.save(key: KeychainKeys.brainAPIAccessToken, value: accessToken)
        try keychain.save(key: KeychainKeys.brainAPIRefreshToken, value: refreshToken)
        try keychain.save(key: KeychainKeys.brainAPIBaseURL, value: baseURL)

        if let displayName = json["displayName"] as? String {
            try? keychain.save(key: KeychainKeys.brainAPIDisplayName, value: displayName)
        }
    }

    /// Decode JWT expiry without external libraries.
    private func tokenExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
        // Pad base64url to valid base64
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        base64 = base64.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }
}

// MARK: - Types

struct LoginResult {
    let user: String
    let displayName: String
}

enum AuthError: Error, LocalizedError {
    case invalidCredentials
    case requires2FA(tempToken: String)
    case invalid2FACode(message: String)
    case tooManyAttempts(message: String)
    case serverError(statusCode: Int, message: String)
    case networkError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Benutzername oder Passwort falsch"
        case .requires2FA:
            return "2FA-Code erforderlich"
        case .invalid2FACode(let msg):
            return msg
        case .tooManyAttempts(let msg):
            return msg
        case .serverError(let code, let msg):
            return "Server-Fehler (\(code)): \(msg)"
        case .networkError:
            return "Netzwerkfehler — Server nicht erreichbar"
        case .invalidResponse:
            return "Unerwartete Server-Antwort"
        }
    }
}
