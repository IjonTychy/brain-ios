import SwiftUI
import BrainCore

// Input render functions and binding helpers for SkillRenderer.
// Split from SkillRenderer.swift to speed up Swift compilation.
// All render functions return AnyView for type erasure to avoid compile timeouts.

extension SkillRenderer {

    func renderTextField(_ node: ScreenNode) -> AnyView {
        let placeholder = resolveString(node, "placeholder") ?? ""
        let bindingKey = bindingVariable(node, "value")
        return AnyView(
            TextField(placeholder, text: stringBinding(bindingKey, current: resolveString(node, "value") ?? ""))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(placeholder)
        )
    }

    func renderTextEditor(_ node: ScreenNode) -> AnyView {
        let bindingKey = bindingVariable(node, "value")
        return AnyView(
            TextEditor(text: stringBinding(bindingKey, current: resolveString(node, "value") ?? ""))
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        )
    }

    func renderToggle(_ node: ScreenNode) -> AnyView {
        let label = resolveString(node, "label") ?? ""
        let bindingKey = bindingVariable(node, "value")
        return AnyView(
            Toggle(label, isOn: boolBinding(bindingKey, current: resolveBool(node, "value") ?? false))
                .accessibilityLabel(label)
        )
    }

    func renderPicker(_ node: ScreenNode) -> AnyView {
        let label = resolveString(node, "label") ?? ""
        let bindingKey = bindingVariable(node, "value")
        let options = resolveStringArray(node, "options")
        let style = resolveString(node, "style") ?? "menu"

        let binding = stringBinding(bindingKey, current: resolveString(node, "value") ?? (options.first ?? ""))

        return AnyView(
            Group {
                if style == "segmented" {
                    Picker(label, selection: binding) {
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } else if style == "wheel" {
                    Picker(label, selection: binding) {
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.wheel)
                } else {
                    Picker(label, selection: binding) {
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .accessibilityLabel(label)
        )
    }

    func renderSlider(_ node: ScreenNode) -> AnyView {
        let bindingKey = bindingVariable(node, "value")
        let min = resolveDouble(node, "min") ?? 0
        let max = resolveDouble(node, "max") ?? 100
        let step = resolveDouble(node, "step") ?? 1
        let label = resolveString(node, "label") ?? ""

        return AnyView(
            VStack(alignment: .leading) {
                if !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary) }
                Slider(
                    value: doubleBinding(bindingKey, current: resolveDouble(node, "value") ?? min),
                    in: min...max,
                    step: step
                )
            }
            .accessibilityLabel(label)
        )
    }

    func renderStepper(_ node: ScreenNode) -> AnyView {
        let bindingKey = bindingVariable(node, "value")
        let label = resolveString(node, "label") ?? ""
        let min = resolveDouble(node, "min").map { Int($0) } ?? 0
        let max = resolveDouble(node, "max").map { Int($0) } ?? 100
        let current = resolveDouble(node, "value").map { Int($0) } ?? min

        return AnyView(
            Stepper(
                value: intBinding(bindingKey, current: current),
                in: min...max
            ) {
                HStack {
                    Text(label)
                    Spacer()
                    Text("\(current)").foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(label)
        )
    }

    func renderDatePicker(_ node: ScreenNode) -> AnyView {
        let label = resolveString(node, "label") ?? ""
        let bindingKey = bindingVariable(node, "value")
        let mode = resolveString(node, "mode") ?? "date"

        let components: DatePickerComponents = {
            switch mode {
            case "time": return .hourAndMinute
            case "dateAndTime": return [.date, .hourAndMinute]
            default: return .date
            }
        }()

        return AnyView(
            DatePicker(label, selection: dateBinding(bindingKey, current: Date()), displayedComponents: components)
                .accessibilityLabel(label)
        )
    }

    func renderColorPicker(_ node: ScreenNode) -> AnyView {
        let label = resolveString(node, "label") ?? "Farbe"
        let bindingKey = bindingVariable(node, "value")
        return AnyView(
            ColorPicker(label, selection: colorBinding(bindingKey, current: .blue))
                .accessibilityLabel(label)
        )
    }

    func renderSearchField(_ node: ScreenNode) -> AnyView {
        let placeholder = resolveString(node, "placeholder") ?? "Suchen..."
        let bindingKey = bindingVariable(node, "value")
        return AnyView(
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(placeholder, text: stringBinding(bindingKey, current: resolveString(node, "value") ?? ""))
            }
            .padding(8)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel(placeholder)
        )
    }

    func renderSecureField(_ node: ScreenNode) -> AnyView {
        let placeholder = resolveString(node, "placeholder") ?? ""
        let bindingKey = bindingVariable(node, "value")
        return AnyView(
            SecureField(placeholder, text: stringBinding(bindingKey, current: resolveString(node, "value") ?? ""))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(placeholder)
        )
    }

    func renderPasteButton(_ node: ScreenNode) -> AnyView {
        let label = resolveString(node, "label") ?? "Einfügen"
        let action = node.onTap ?? resolveString(node, "action") ?? ""
        return AnyView(
            PasteButton(payloadType: String.self) { strings in
                if let text = strings.first {
                    if let key = bindingVariable(node, "value") {
                        onSetVariable(key, .string(text))
                    }
                    if !action.isEmpty { onAction(action, context) }
                }
            }
            .accessibilityLabel(label)
        )
    }

    func renderMultiPicker(_ node: ScreenNode) -> AnyView {
        let options = resolveStringArray(node, "options")
        let label = resolveString(node, "label") ?? ""

        return AnyView(
            VStack(alignment: .leading) {
                if !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary) }
                ForEach(options, id: \.self) { option in
                    let isSelected = isOptionSelected(node, option: option)
                    Button {
                        toggleMultiPickerOption(node, option: option)
                    } label: {
                        HStack {
                            Text(option)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        )
    }

    // MARK: - Binding helpers

    func bindingVariable(_ node: ScreenNode, _ key: String) -> String? {
        guard let prop = node.properties?[key], case .string(let s) = prop else { return nil }
        if s.hasPrefix("{{") && s.hasSuffix("}}") {
            return s.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    func stringBinding(_ key: String?, current: String) -> Binding<String> {
        guard let key else { return .constant(current) }
        return Binding(
            get: {
                if let val = context.resolve(key) { return val.stringRepresentation }
                return current
            },
            set: { newValue in onSetVariable(key, .string(newValue)) }
        )
    }

    func boolBinding(_ key: String?, current: Bool) -> Binding<Bool> {
        guard let key else { return .constant(current) }
        return Binding(
            get: {
                if let val = context.resolve(key), case .bool(let b) = val { return b }
                return current
            },
            set: { newValue in onSetVariable(key, .bool(newValue)) }
        )
    }

    func doubleBinding(_ key: String?, current: Double) -> Binding<Double> {
        guard let key else { return .constant(current) }
        return Binding(
            get: {
                if let val = context.resolve(key) {
                    switch val {
                    case .double(let d): return d
                    case .int(let i): return Double(i)
                    default: return current
                    }
                }
                return current
            },
            set: { newValue in onSetVariable(key, .double(newValue)) }
        )
    }

    func intBinding(_ key: String?, current: Int) -> Binding<Int> {
        guard let key else { return .constant(current) }
        return Binding(
            get: {
                if let val = context.resolve(key) {
                    switch val {
                    case .int(let i): return i
                    case .double(let d): return Int(d)
                    default: return current
                    }
                }
                return current
            },
            set: { newValue in onSetVariable(key, .int(newValue)) }
        )
    }

    func dateBinding(_ key: String?, current: Date) -> Binding<Date> {
        guard let key else { return .constant(current) }
        return Binding(
            get: {
                if let val = context.resolve(key), case .string(let s) = val {
                    return ISO8601DateFormatter().date(from: s) ?? current
                }
                return current
            },
            set: { newValue in
                onSetVariable(key, .string(ISO8601DateFormatter().string(from: newValue)))
            }
        )
    }

    func colorBinding(_ key: String?, current: Color) -> Binding<Color> {
        guard let key else { return .constant(current) }
        return Binding(
            get: { current },
            set: { _ in onSetVariable(key, .string("")) }
        )
    }

    // MARK: - Multi-picker helpers

    func isOptionSelected(_ node: ScreenNode, option: String) -> Bool {
        if let key = bindingVariable(node, "selection"),
           let val = context.resolve(key),
           case .array(let arr) = val {
            return arr.contains(where: { $0.stringRepresentation == option })
        }
        return false
    }

    func toggleMultiPickerOption(_ node: ScreenNode, option: String) {
        guard let key = bindingVariable(node, "selection") else { return }
        var current: [ExpressionValue] = []
        if let val = context.resolve(key), case .array(let arr) = val {
            current = arr
        }
        if let idx = current.firstIndex(where: { $0.stringRepresentation == option }) {
            current.remove(at: idx)
        } else {
            current.append(.string(option))
        }
        onSetVariable(key, .array(current))
    }
}
