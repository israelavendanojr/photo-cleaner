import SwiftUI

/// Developer mode's "Free limits": every `FreeTierTunable` with its default beside it, applied live
/// and saved. Also the live refill countdown and what the values add up to per day.
struct FreeLimitsPanel: View {
    @Environment(FeedViewModel.self) private var vm

    var body: some View {
        SettingsSection("Admin Tools · Free limits") {
            ForEach(FreeTierTunable.allCases) { tunable in
                TunableRow(
                    tunable: tunable,
                    value: vm.freeTier.value(tunable),
                    defaultValue: vm.freeTier.defaultValue(tunable)
                ) { vm.admin.setFreeTierValue(tunable, $0) }
            }
            SettingsLabel(icon: "calendar", title: "Per day", value: perDay)
                .settingsRowPadding()
                .accessibilityIdentifier("settings.tuning.perDay")
            refillCountdown
            Button {
                vm.admin.resetFreeTierToDefaults()
            } label: {
                SettingsLabel(icon: "arrow.counterclockwise", title: "Reset to defaults",
                              detail: vm.freeTier.isCustomized ? nil : "Using the defaults.")
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .disabled(!vm.freeTier.isCustomized)
            .accessibilityIdentifier("settings.tuning.reset")
        }
    }

    /// "≈ 40 swipes/day".
    private var perDay: String {
        "≈ \(Int(vm.allowanceTunables.swipesPerDay.rounded())) swipes/day"
    }

    private var refillCountdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            SettingsLabel(icon: "timer", title: "Next refill", value: countdown(at: context.date))
                .monospacedDigit()
                .settingsRowPadding()
        }
        .accessibilityIdentifier("settings.tuning.countdown")
    }

    private func countdown(at now: Date) -> String {
        guard let left = vm.swipesLeft else { return "Unlocked" }
        guard let next = vm.nextRefillAt else { return "Full (\(left) left)" }
        return "+\(vm.allowanceTunables.refillAmount) in \(Format.countdown(next.timeIntervalSince(now))) (\(left) left)"
    }
}

/// One tunable: a number field and a stepper, with the default under the title.
private struct TunableRow: View {
    let tunable: FreeTierTunable
    let value: Int
    let defaultValue: Int
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
                .accessibilityIdentifier("settings.tuning.\(tunable.rawValue)")
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

#if DEBUG
#Preview {
    ScrollView {
        FreeLimitsPanel()
            .padding()
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock())
}
#endif
