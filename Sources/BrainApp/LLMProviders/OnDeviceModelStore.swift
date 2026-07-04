import Foundation
import os.log

// Manages download, storage and availability of on-device model files (GGUF).
// Files live in Application Support/OnDeviceModels/ (excluded from iCloud backup).
@MainActor @Observable
final class OnDeviceModelStore {

    static let shared = OnDeviceModelStore()

    enum DownloadState: Equatable {
        case idle
        case downloading
        case failed(String)
    }

    private(set) var states: [String: DownloadState] = [:]

    private let logger = Logger(subsystem: "com.example.brain-ios", category: "OnDeviceModels")

    // MARK: - Paths & availability (nonisolated: used from provider code)

    nonisolated static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("OnDeviceModels", isDirectory: true)
    }

    nonisolated static func localURL(for spec: OnDeviceModelSpec) -> URL {
        modelsDirectory.appendingPathComponent(spec.fileName)
    }

    nonisolated static func isDownloaded(_ spec: OnDeviceModelSpec) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: spec).path)
    }

    // The device qualifies when its physical memory (with a small tolerance for
    // marketing sizes like "5.66 GB usable of 6 GB") covers the model's needs.
    nonisolated static func deviceMeetsRequirements(_ spec: OnDeviceModelSpec) -> Bool {
        let physicalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return physicalGB + 0.5 >= Double(spec.minPhysicalMemoryGB)
    }

    // Best model that is downloaded AND fits this device — availability decides,
    // nothing is hardcoded. Largest context window wins.
    nonisolated static func bestDownloadedModel() -> OnDeviceModelSpec? {
        OnDeviceModelCatalog.models
            .filter { isDownloaded($0) && deviceMeetsRequirements($0) }
            .max { $0.contextWindow < $1.contextWindow }
    }

    func state(for spec: OnDeviceModelSpec) -> DownloadState {
        states[spec.id] ?? .idle
    }

    // MARK: - Download & delete

    func download(_ spec: OnDeviceModelSpec) async {
        guard states[spec.id] != .downloading else { return }
        guard let url = OnDeviceModelCatalog.downloadURL(for: spec) else {
            states[spec.id] = .failed("Ungueltige Download-URL")
            return
        }

        states[spec.id] = .downloading
        do {
            try FileManager.default.createDirectory(
                at: Self.modelsDirectory, withIntermediateDirectories: true)

            let (tempURL, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw OnDeviceModelError.badResponse(code)
            }

            // Sanity check: a GGUF model is never tiny. This catches HTML error
            // pages or truncated downloads before they shadow a real model file.
            let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
            guard size > 100_000_000 else {
                throw OnDeviceModelError.implausiblySmall(bytes: size)
            }

            let destination = Self.localURL(for: spec)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
            try Self.excludeFromBackup(destination)

            states[spec.id] = .idle
            logger.info("Model \(spec.id) downloaded (\(size) bytes)")
        } catch {
            states[spec.id] = .failed(error.localizedDescription)
            logger.error("Model download failed for \(spec.id): \(error)")
        }
    }

    func delete(_ spec: OnDeviceModelSpec) {
        try? FileManager.default.removeItem(at: Self.localURL(for: spec))
        states[spec.id] = .idle
    }

    nonisolated static func downloadedBytes(_ spec: OnDeviceModelSpec) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: localURL(for: spec).path)[.size] as? Int64) ?? 0
    }

    private nonisolated static func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }
}

enum OnDeviceModelError: Error, LocalizedError {
    case badResponse(Int)
    case implausiblySmall(bytes: Int64)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "Download fehlgeschlagen (HTTP \(code)). Pruefe die Modell-URL in den Einstellungen."
        case .implausiblySmall(let bytes):
            return "Heruntergeladene Datei ist zu klein (\(bytes) Bytes) — vermutlich keine Modelldatei. Pruefe die Modell-URL."
        }
    }
}
