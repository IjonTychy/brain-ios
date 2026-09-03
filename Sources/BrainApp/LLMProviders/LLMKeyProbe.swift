import Foundation

// Validates an API key against the provider's model-list endpoint.
// A chat completion would tie the check to a model id that may have been
// retired since the app was built; listing models only needs a valid key.
enum LLMKeyProbe {

    enum Target {
        case anthropic
        case openAI
        case gemini
        /// xAI or a custom OpenAI-compatible endpoint; `baseURL` with or without "/v1".
        case openAICompatible(baseURL: String)
    }

    /// Throws `LLMProviderError.apiError` for a non-2xx answer (401 = invalid key)
    /// and the underlying URLError for transport failures.
    static func validate(_ target: Target, apiKey: String) async throws {
        var request = URLRequest(url: try endpoint(for: target))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        switch target {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .openAI, .openAICompatible:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await LLMURLSession.shared.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMProviderError.noResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMProviderError.apiError(statusCode: http.statusCode, body: String(body.prefix(300)))
        }
    }

    private static func endpoint(for target: Target) throws -> URL {
        let urlString: String
        switch target {
        case .anthropic:
            urlString = "https://api.anthropic.com/v1/models?limit=1"
        case .openAI:
            urlString = "https://api.openai.com/v1/models"
        case .gemini:
            urlString = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1"
        case .openAICompatible(let baseURL):
            var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            while base.hasSuffix("/") { base.removeLast() }
            urlString = base.hasSuffix("/v1") ? "\(base)/models" : "\(base)/v1/models"
        }
        guard let url = URL(string: urlString) else {
            throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige URL: \(urlString)")
        }
        return url
    }
}
