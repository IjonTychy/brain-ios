import Foundation

// Shared URLSession for all LLM API calls.
//
// Server trust is validated by the system trust store; there is deliberately
// no certificate pinning. The API hosts sit behind CDNs that rotate leaf keys
// every few weeks and switch issuing CAs, so a hardcoded pin set goes stale
// within months and then cuts the app off from every provider until an app
// update ships (this happened with the pins from March 2026). The app has no
// server of its own that could distribute fresh pins.
//
// @unchecked Sendable: the session is created once in init and never mutated.
final class LLMURLSession: @unchecked Sendable {

    static let shared = LLMURLSession()

    let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        // LLM calls can take several minutes (long completions, tool use).
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
    }
}
