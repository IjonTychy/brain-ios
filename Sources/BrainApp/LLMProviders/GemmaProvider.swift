import Foundation
import BrainCore
import os.log

#if canImport(llama)
import llama
#endif

// On-device LLM provider for downloadable GGUF models (Gemma family) running
// through llama.cpp. Which model is used is decided purely by availability
// (downloaded + fits device memory) — nothing is hardcoded; the catalog is
// runtime-extensible (see OnDeviceModelCatalog).
//
// Activation requires the llama.cpp Swift package (product "llama",
// https://github.com/ggml-org/llama.cpp) in the Xcode project. Until it is
// added, GemmaRuntime.isSupported is false, isAvailable stays false, and the
// app behaves exactly as before — same graceful pattern as FoundationModels
// in OnDeviceProvider.
final class GemmaProvider: LLMProvider, @unchecked Sendable {

    let name: String
    // complete() only for now — no token streaming or tool use.
    let supportsStreaming = false
    let isOnDevice = true
    let contextWindow: Int

    private let spec: OnDeviceModelSpec

    init(spec: OnDeviceModelSpec) {
        self.spec = spec
        self.name = "on-device-\(spec.id)"
        self.contextWindow = spec.contextWindow
    }

    // The best downloaded model that fits this device, or nil.
    static func bestAvailable() -> GemmaProvider? {
        guard GemmaRuntime.isSupported else { return nil }
        guard let spec = OnDeviceModelStore.bestDownloadedModel() else { return nil }
        return GemmaProvider(spec: spec)
    }

    var isAvailable: Bool {
        GemmaRuntime.isSupported
            && OnDeviceModelStore.isDownloaded(spec)
            && OnDeviceModelStore.deviceMeetsRequirements(spec)
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard isAvailable else { throw OnDeviceError.unavailable }

        let prompt = Self.buildPrompt(request: request, format: spec.promptFormat)
        let text = try await GemmaRuntime.shared.complete(
            modelURL: OnDeviceModelStore.localURL(for: spec),
            prompt: prompt,
            maxTokens: request.maxTokens ?? 512,
            contextLength: contextWindow
        )
        return LLMResponse(content: text, providerName: name, model: spec.id)
    }

    // Build a raw prompt in the model's expected chat format.
    // Gemma has no system role — the system prompt is merged into the first user turn.
    static func buildPrompt(request: LLMRequest, format: OnDeviceModelSpec.PromptFormat) -> String {
        switch format {
        case .gemma:
            var result = ""
            var pendingSystem = request.systemPrompt
            for message in request.messages {
                switch message.role {
                case "assistant":
                    result += "<start_of_turn>model\n\(message.content)<end_of_turn>\n"
                case "system":
                    pendingSystem = [pendingSystem, message.content]
                        .compactMap { $0 }.joined(separator: "\n\n")
                default:
                    var content = message.content
                    if let system = pendingSystem {
                        content = system + "\n\n" + content
                        pendingSystem = nil
                    }
                    result += "<start_of_turn>user\n\(content)<end_of_turn>\n"
                }
            }
            result += "<start_of_turn>model\n"
            return result

        case .chatml:
            var result = ""
            if let system = request.systemPrompt {
                result += "<|im_start|>system\n\(system)<|im_end|>\n"
            }
            for message in request.messages {
                let role = message.role == "assistant" ? "assistant" : message.role
                result += "<|im_start|>\(role)\n\(message.content)<|im_end|>\n"
            }
            result += "<|im_start|>assistant\n"
            return result

        case .plain:
            var result = request.systemPrompt.map { $0 + "\n\n" } ?? ""
            for message in request.messages {
                result += "\(message.role == "assistant" ? "Assistant" : "User"): \(message.content)\n"
            }
            result += "Assistant:"
            return result
        }
    }
}

// MARK: - Inference runtime (llama.cpp)

// Serialises access to the llama.cpp context. The loaded model is cached and
// reused across calls; loading a fresh model evicts the previous one.
actor GemmaRuntime {

    static let shared = GemmaRuntime()

    static var isSupported: Bool {
        #if canImport(llama)
        return true
        #else
        return false
        #endif
    }

    private let logger = Logger(subsystem: "com.example.brain-ios", category: "GemmaRuntime")

    #if canImport(llama)
    // NOTE: Written against the 2025/2026 llama.cpp C API
    // (llama_model_load_from_file / llama_init_from_model / llama_sampler_chain).
    // Verify against the pinned package revision on first device build.

    private var cachedModel: OpaquePointer?
    private var cachedModelPath: String?

    func complete(modelURL: URL, prompt: String, maxTokens: Int, contextLength: Int) async throws -> String {
        let model = try loadModel(at: modelURL)
        let vocab = llama_model_get_vocab(model)

        // Tokenize the prompt
        let utf8 = Array(prompt.utf8)
        var tokens = [llama_token](repeating: 0, count: utf8.count + 8)
        let tokenCount = llama_tokenize(
            vocab, prompt, Int32(utf8.count), &tokens, Int32(tokens.count),
            /*add_special*/ true, /*parse_special*/ true)
        guard tokenCount > 0 else { throw OnDeviceError.generationFailed("Tokenisierung fehlgeschlagen") }
        tokens.removeLast(tokens.count - Int(tokenCount))

        // Create an inference context sized for prompt + response
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(min(contextLength, Int(tokenCount) + maxTokens + 16))
        ctxParams.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
        ctxParams.n_threads_batch = ctxParams.n_threads
        guard let ctx = llama_init_from_model(model, ctxParams) else {
            throw OnDeviceError.generationFailed("Kontext konnte nicht erstellt werden")
        }
        defer { llama_free(ctx) }

        // Sampler chain: temperature + top-p + final distribution sample
        let samplerParams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(samplerParams) else {
            throw OnDeviceError.generationFailed("Sampler konnte nicht erstellt werden")
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: .min ... .max)))

        // Feed the prompt
        var batch = llama_batch_get_one(&tokens, Int32(tokens.count))
        guard llama_decode(ctx, batch) == 0 else {
            throw OnDeviceError.generationFailed("Prompt-Verarbeitung fehlgeschlagen")
        }

        // Generation loop
        var output = ""
        var pieceBuffer = [CChar](repeating: 0, count: 256)
        for _ in 0..<maxTokens {
            try Task.checkCancellation()

            var token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }

            let pieceLength = llama_token_to_piece(vocab, token, &pieceBuffer, Int32(pieceBuffer.count), 0, true)
            if pieceLength > 0 {
                let bytes = pieceBuffer.prefix(Int(pieceLength)).map { UInt8(bitPattern: $0) }
                output += String(decoding: bytes, as: UTF8.self)
            }

            batch = llama_batch_get_one(&token, 1)
            guard llama_decode(ctx, batch) == 0 else { break }
        }

        // Gemma models sometimes emit the turn terminator as plain text
        return output
            .replacingOccurrences(of: "<end_of_turn>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadModel(at url: URL) throws -> OpaquePointer {
        if let cachedModel, cachedModelPath == url.path {
            return cachedModel
        }
        if let cachedModel {
            llama_model_free(cachedModel)
            self.cachedModel = nil
            self.cachedModelPath = nil
        }

        llama_backend_init()
        var params = llama_model_default_params()
        // Offload everything to Metal where possible; llama.cpp falls back to CPU.
        params.n_gpu_layers = 99
        guard let model = llama_model_load_from_file(url.path, params) else {
            throw OnDeviceError.generationFailed("Modell konnte nicht geladen werden: \(url.lastPathComponent)")
        }
        cachedModel = model
        cachedModelPath = url.path
        logger.info("Loaded GGUF model \(url.lastPathComponent)")
        return model
    }

    #else

    // Compiled without the llama.cpp package — inference is unavailable,
    // but catalog, downloads and settings UI keep working.
    func complete(modelURL: URL, prompt: String, maxTokens: Int, contextLength: Int) async throws -> String {
        throw OnDeviceError.unavailable
    }

    #endif
}
