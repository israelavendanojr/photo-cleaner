import SwiftUI

/// One tunable: a number field and a stepper, with the default under the title.
struct TunableRow<Tunable: AdminTunable>: View {
    let tunable: Tunable
    let value: Int
    let defaultValue: Int
    /// UI tests find the field as "<prefix>.<rawValue>".
    var identifierPrefix = "settings.tuning"
    let onChange: @MainActor @Sendable (Int) -> Void

    @State private var text = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tunable.title)
                    .foregroundStyle(DS.Palette.ink)
                Text("default \(defaultValue) \(tunable.unit)")
                    .font(.footnote)
                    .foregroundStyle(value == defaultValue ? DS.Palette.secondary : DS.Palette.brick)
            }
            Spacer(minLength: DS.Spacing.xs)
            TextField("\(defaultValue)", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                .focused($isEditing)
                .accessibilityLabel("\(tunable.title), \(tunable.unit)")
                .accessibilityIdentifier("\(identifierPrefix).\(tunable.rawValue)")
            Stepper("\(tunable.title)", value: Binding(get: { value }, set: onChange),
                    in: tunable.range, step: tunable.step)
                .labelsHidden()
        }
        .settingsRowPadding()
        .onAppear { text = "\(value)" }
        .onChange(of: value) { _, new in
            if !isEditing || Int(text) != new { text = "\(new)" }
        }
        .onChange(of: text) { _, new in
            // Applies as soon as it's a number in range; out of range waits for the edit to end.
            guard let number = Int(new), tunable.range.contains(number), number != value else { return }
            onChange(number)
        }
        .onChange(of: isEditing) { _, editing in
            guard !editing else { return }
            if let number = Int(text) { onChange(number) }
            text = "\(value)"
        }
    }
}
