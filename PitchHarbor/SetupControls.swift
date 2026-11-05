// Shared formation and jersey-number inputs used by setup and roster forms.
// Keep validation here consistent with Formation, JerseyNumber, and archive validation.

import SwiftUI

/// Chooses compatible shapes for the team size, preserving readable legacy options.
struct FormationPicker: View {
    @Environment(\.positionNames) private var names
    var format: Int
    @Binding var selection: String?
    private var selectedID: String { Formation.resolvedID(for: format, id: selection) }
    var body: some View {
        Picker("Formation", selection: Binding(get: { selectedID }, set: { selection = $0 })) {
            ForEach(
                Formation.options(for: format).filter {
                    $0.shapeID != "4-3-3" || $0.id == selectedID
                        || $0.id == "4-3-3:wide" && !Formation.hasMidfieldOptions(format: format, id: selectedID)
                }
            ) { option in
                Text(option.title).tag(option.id)
            }
            if let legacy = Formation.option(for: format, id: selectedID),
                !Formation.options(for: format).contains(where: { $0.id == selectedID })
            {
                Text("\(legacy.title) · Previous Roles").tag(legacy.id)
            }
        }.pickerStyle(.navigationLink).accessibilityIdentifier("formationPicker")
            .onChange(of: format) { _, newValue in
                if Formation.option(for: newValue, id: selection) == nil {
                    selection = Formation.defaultID(for: newValue)
                }
            }
        if Formation.hasMidfieldOptions(format: format, id: selection) { MidfieldSetupPicker(selection: $selection) }
        Text(
            format <= 4
                ? "No Goalkeeper · Numbers Run from Defense to Attack"
                : "Includes 1 Goalkeeper · Formation Numbers Show Outfield Players"
        )
        .font(.caption).foregroundStyle(Palette.secondaryText)
        DisclosureGroup("Preview Formation") {
            if let option = Formation.option(for: format, id: selectedID) {
                GeometryReader { geometry in
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Palette.green)
                        RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.35), lineWidth: 1).padding(8)
                        Rectangle().fill(.white.opacity(0.3)).frame(height: 1)
                        ForEach(Array(option.positions.enumerated()), id: \.offset) { index, point in
                            Text(names[option.roles[index]] ?? option.roles[index]).font(
                                .system(size: 10, weight: .bold)
                            )
                            .frame(width: 28, height: 22).foregroundStyle(Palette.green)
                            .background(.white, in: Capsule())
                            .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                        }
                    }
                }.frame(height: 170).accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(option.title) Formation. Positions: \(option.roles.joined(separator:", "))")
            }
        }
    }
}

/// Selects a 4–3–3 role variant while keeping formation slots and field geometry aligned.
struct MidfieldSetupPicker: View {
    @Binding var selection: String?
    var body: some View {
        Picker("Midfield Setup", selection: Binding(get: { selection ?? "4-3-3:wide" }, set: { selection = $0 })) {
            ForEach(Formation.midfieldOptions) { option in Text(option.midfieldName).tag(option.id) }
        }.pickerStyle(.menu).accessibilityIdentifier("midfieldSetupPicker")
            .accessibilityLabel("Midfield Setup")
            .accessibilityValue(
                Formation.option(for: 11, id: selection ?? "4-3-3:wide")?.midfieldName ?? "Wide · LM / CM / RM")
    }
}

/// Keeps raw editing text separate from the last valid number so blank/invalid input cannot save.
struct JerseyNumberField: View {
    @Binding var number: Int
    @Binding var isValid: Bool
    @State private var text: String
    @State private var textSelection: TextSelection?
    @FocusState private var focused: Bool
    init(number: Binding<Int>, isValid: Binding<Bool>) {
        _number = number
        _isValid = isValid
        _text = State(initialValue: String(number.wrappedValue))
    }
    var body: some View {
        HStack {
            Text("Jersey Number")
            Spacer()
            TextField(
                "0–99",
                text: Binding(
                    get: { text },
                    set: { value in
                        text = value
                        let parsed = JerseyNumber.parse(value)
                        isValid = parsed != nil
                        if let parsed { number = parsed }
                    }), selection: $textSelection
            )
            .keyboardType(.numberPad).textInputAutocapitalization(.never).autocorrectionDisabled()
            .multilineTextAlignment(.trailing).frame(width: 70).frame(minHeight: 44)
            .focused($focused).accessibilityLabel("Jersey Number").accessibilityIdentifier("jerseyNumber")
            .onChange(of: focused) { _, editing in
                if editing { textSelection = TextSelection(range: text.startIndex..<text.endIndex) }
            }
            if focused {
                Button("Done") { focused = false }.buttonStyle(.borderless).frame(minHeight: 44)
                    .accessibilityIdentifier("jerseyNumberDone")
            }
        }
        if !isValid {
            Text("Enter a Number from 0 to 99.").font(.caption).foregroundStyle(.red)
        }
    }
}
