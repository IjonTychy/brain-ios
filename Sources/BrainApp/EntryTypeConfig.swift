import SwiftUI
import BrainCore

// SwiftUI Color extension for EntryType.
// Uses the colorName from the BrainCore model to provide platform-specific Color.
extension EntryType {
    var color: Color {
        switch self {
        case .thought: .yellow
        case .task: .blue
        case .note: .green
        case .event: .purple
        case .email: .orange
        case .document: .gray
        }
    }
}
