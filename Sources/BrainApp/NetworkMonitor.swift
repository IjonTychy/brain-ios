import Network
import SwiftUI
import os.log

// E1: Tracks network connectivity status for offline indicator.
// Uses NWPathMonitor to observe real-time connectivity changes.
// Published as @Observable so SwiftUI views react to status changes.
@MainActor
@Observable
final class NetworkMonitor {

    static let shared = NetworkMonitor()

    var isConnected: Bool = true
    var connectionType: ConnectionType = .unknown

    enum ConnectionType: String {
        case wifi, cellular, wired, unknown
    }

    private let monitor = NWPathMonitor()
    private let logger = Logger(subsystem: "com.example.brain-ios", category: "Network")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied

                if path.usesInterfaceType(.wifi) {
                    self.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionType = .wired
                } else {
                    self.connectionType = .unknown
                }

                if wasConnected != self.isConnected {
                    self.logger.info("Netzwerkstatus: \(self.isConnected ? "online" : "offline") (\(self.connectionType.rawValue))")
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.example.brain-ios.network-monitor"))
    }
}

// Compact offline banner for embedding in views.
struct OfflineBanner: View {
    @State private var monitor = NetworkMonitor.shared

    var body: some View {
        if !monitor.isConnected {
            HStack(spacing: 6) {
                Image(systemName: "icloud.slash")
                    .font(.caption)
                Text("Offline — nur On-Device LLM verfügbar")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.orange.gradient))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// Toolbar icon that shows connectivity status.
struct NetworkStatusIcon: View {
    @State private var monitor = NetworkMonitor.shared

    var body: some View {
        Image(systemName: monitor.isConnected ? "cloud" : "icloud.slash")
            .font(.caption)
            .foregroundStyle(monitor.isConnected ? Color.secondary : Color.orange)
            .symbolEffect(.pulse, isActive: !monitor.isConnected)
    }
}
