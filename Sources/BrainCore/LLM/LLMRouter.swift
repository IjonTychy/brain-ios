// Routes LLM requests to the best available provider based on
// connectivity, data sensitivity, and task complexity.
// See ARCHITECTURE.md "Routing-Logik" for the decision tree.
public final class LLMRouter: Sendable {

    private let providers: [any LLMProvider]
    private let isConnected: @Sendable () -> Bool

    // Initialise with a list of providers and a connectivity check.
    public init(
        providers: [any LLMProvider],
        isConnected: @escaping @Sendable () -> Bool = { true }
    ) {
        self.providers = providers
        self.isConnected = isConnected
    }

    // Select the best provider for the given request.
    // Returns nil if no provider is available.
    public func route(_ request: LLMRequest) -> (any LLMProvider)? {
        let available = providers.filter(\.isAvailable)
        guard !available.isEmpty else { return nil }

        let onDevice = available.filter(\.isOnDevice)
        let cloud = available.filter { !$0.isOnDevice }

        // 0. Privacy Zone: on-device-only — data must NEVER leave the device.
        if request.privacyLevel == .onDeviceOnly {
            return bestOnDevice(onDevice)
        }

        // 0b. Privacy Zone: approved-cloud-only — use preferred cloud, no fallback to unknown.
        if request.privacyLevel == .approvedCloudOnly {
            return cloud.first ?? bestOnDevice(onDevice)
        }

        // 1. No internet? On-device only.
        if !isConnected() {
            return bestOnDevice(onDevice)
        }

        // 2. Sensitive data? Prefer on-device.
        if request.containsSensitiveData {
            return bestOnDevice(onDevice) ?? cloud.first
        }

        // 3. High complexity? Best cloud model.
        if request.complexity == .high {
            return cloud.first ?? bestOnDevice(onDevice)
        }

        // 4. Low complexity? On-device if available (faster, free).
        if request.complexity == .low {
            return bestOnDevice(onDevice) ?? cloud.first
        }

        // 5. Medium / default: prefer cloud.
        return cloud.first ?? bestOnDevice(onDevice)
    }

    // Select the on-device provider with the largest context window.
    private func bestOnDevice(_ onDevice: [any LLMProvider]) -> (any LLMProvider)? {
        onDevice.max(by: { $0.contextWindow < $1.contextWindow })
    }
}
