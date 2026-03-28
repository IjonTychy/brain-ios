import SwiftUI

// E3: Inline field validation modifier.
// Shows a red error message below a TextField when validation fails.
// Usage: TextField("Name", text: $name).validated(error: nameError)
struct ValidatedField: ViewModifier {
    let error: String?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if let error, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: error)
    }
}

extension View {
    /// Shows inline validation error below this view.
    func validated(error: String?) -> some View {
        modifier(ValidatedField(error: error))
    }
}
