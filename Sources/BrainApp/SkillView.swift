import SwiftUI
import BrainCore

// Complete skill view: wraps SkillRenderer with a ViewModel for state management.
// This is what gets displayed when a user opens an installed skill.
struct SkillView: View {
    @State private var viewModel: SkillViewModel

    init(
        definition: SkillDefinition,
        initialVariables: [String: ExpressionValue] = [:],
        handlers: [any ActionHandler] = []
    ) {
        _viewModel = State(initialValue: SkillViewModel(
            definition: definition,
            initialVariables: initialVariables,
            additionalHandlers: handlers
        ))
    }

    var body: some View {
        Group {
            if let node = viewModel.currentScreenNode {
                ScrollView {
                    SkillRenderer(
                        node: node,
                        context: viewModel.context,
                        onAction: { actionName, actionContext in
                            viewModel.executeAction(actionName, actionContext: actionContext)
                        },
                        onSetVariable: { key, value in
                            viewModel.setVariable(key, value: value)
                        }
                    )
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Screen nicht gefunden",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Screen '\(viewModel.currentScreen)' existiert nicht in diesem Skill.")
                )
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BrainTheme.Radius.md))
                    .pulseEffect()
            }
        }
        // Show error messages as banner (fixes LOW finding: errorMessage not shown)
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(BrainTheme.Colors.error.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: BrainTheme.Radius.md))
                    .padding()
                    .transition(.move(edge: .bottom))
                    .onTapGesture {
                        viewModel.errorMessage = nil
                    }
                    .accessibilityLabel("Fehler: \(error)")
            }
        }
        .animation(.easeInOut, value: viewModel.errorMessage)
    }
}
