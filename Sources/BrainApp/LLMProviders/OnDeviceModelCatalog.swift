import Foundation

// Describes a downloadable on-device LLM in GGUF format.
// The default catalog ships with the app, but selection is availability-based,
// never hardcoded: entries can be overridden or extended at runtime via
// UserDefaults ("onDeviceModelCatalog" as JSON array of OnDeviceModelSpec),
// so newer models (e.g. a future Gemma release) work without an app update.
struct OnDeviceModelSpec: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    let family: String            // e.g. "gemma"
    let fileName: String          // stored under Application Support/OnDeviceModels/
    let downloadURLString: String // default source; user-adjustable in settings
    let approximateSizeMB: Int
    let minPhysicalMemoryGB: Int  // availability gate for this device
    let contextWindow: Int
    let promptFormat: PromptFormat

    enum PromptFormat: String, Codable, Sendable {
        case gemma   // <start_of_turn>user ... <end_of_turn>
        case chatml  // <|im_start|>user ... <|im_end|>
        case plain
    }

    var downloadURL: URL? { URL(string: downloadURLString) }
}

enum OnDeviceModelCatalog {

    static let overrideDefaultsKey = "onDeviceModelCatalog"

    // Gemma 4 (Google, April 2026, Apache 2.0). E2B/E4B are the edge variants
    // with per-layer embeddings — effective 2B/4B footprint at inference time.
    // Q4_K_M GGUF quantizations from the community mirror; the URLs are
    // defaults only and can be replaced per model in the settings UI.
    static let gemma4E2B = OnDeviceModelSpec(
        id: "gemma-4-e2b-q4",
        displayName: "Gemma 4 E2B (Q4, ~1.3 GB)",
        family: "gemma",
        fileName: "gemma-4-E2B-it-Q4_K_M.gguf",
        downloadURLString: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf",
        approximateSizeMB: 1350,
        minPhysicalMemoryGB: 6,
        contextWindow: 8192,
        promptFormat: .gemma
    )

    static let gemma4E4B = OnDeviceModelSpec(
        id: "gemma-4-e4b-q4",
        displayName: "Gemma 4 E4B (Q4, ~2.5 GB)",
        family: "gemma",
        fileName: "gemma-4-E4B-it-Q4_K_M.gguf",
        downloadURLString: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf",
        approximateSizeMB: 2550,
        minPhysicalMemoryGB: 8,
        contextWindow: 8192,
        promptFormat: .gemma
    )

    // Runtime override wins over the bundled defaults.
    static var models: [OnDeviceModelSpec] {
        if let data = UserDefaults.standard.data(forKey: overrideDefaultsKey),
           let custom = try? JSONDecoder().decode([OnDeviceModelSpec].self, from: data),
           !custom.isEmpty {
            return custom
        }
        return [gemma4E2B, gemma4E4B]
    }

    static func spec(id: String) -> OnDeviceModelSpec? {
        models.first { $0.id == id }
    }

    // Per-model download URL override (user-pasted in settings).
    static func downloadURL(for spec: OnDeviceModelSpec) -> URL? {
        if let custom = UserDefaults.standard.string(forKey: "onDeviceModelURL.\(spec.id)"),
           let url = URL(string: custom), !custom.isEmpty {
            return url
        }
        return spec.downloadURL
    }
}
