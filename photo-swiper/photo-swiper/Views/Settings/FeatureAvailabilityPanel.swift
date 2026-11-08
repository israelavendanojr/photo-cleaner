import SwiftUI

/// Developer mode's "Feature availability": who gets each `TierFeature`, with its default beside it.
/// Saved, and followed from the next page; "Rebuild deck now" applies it straight away.
struct FeatureAvailabilityPanel: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var isRebuilding = false

    var body: some View {
        SettingsSection("Admin Tools · Feature availability") {
            ForEach(TierFeature.allCases) { feature in
                FeatureRow(
                    feature: feature,
                    availability: vm.features.availability(feature),
                    defaultAvailability: vm.features.defaultAvailability(feature)
                ) { vm.setFeatureAvailability(feature, $0) }
            }
            SettingsLabel(icon: vm.isUnlocked ? "lock.open" : "lock", title: vm.isUnlocked ? "Unlocked gets" : "Free gets",
                          value: enabledSummary)
                .settingsRowPadding()
                .accessibilityIdentifier("settings.features.summary")
            Button {
                Task {
                    isRebuilding = true
                    await vm.adminRebuildDeck()
                    isRebuilding = false
                }
            } label: {
                SettingsLabel(icon: "arrow.triangle.2.circlepath", title: "Rebuild deck now",
                              detail: "Changes otherwise start with the next page.", isWorking: isRebuilding)
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .disabled(isRebuilding)
            .accessibilityIdentifier("settings.features.rebuild")
            Button {
                vm.resetFeatureAvailability()
            } label: {
                SettingsLabel(icon: "arrow.counterclockwise", title: "Reset to defaults",
                              detail: vm.features.isCustomized ? nil : "Using the defaults.")
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .disabled(!vm.features.isCustomized)
            .accessibilityIdentifier("settings.features.reset")
        }
    }

    /// "Similar shots, Duplicates", or "No bundles".
    private var enabledSummary: String {
        let enabled = vm.features.enabled(isUnlocked: vm.isUnlocked)
        let titles = TierFeature.allCases.filter(enabled.contains).map(\.title)
        return titles.isEmpty ? "No bundles" : titles.joined(separator: ", ")
    }
}

/// One feature: its title, the default under it, and a Free only / Paid only / Universal menu.
private struct FeatureRow: View {
    let feature: TierFeature
    let availability: FeatureAvailability
    let defaultAvailability: FeatureAvailability
    let onChange: (FeatureAvailability) -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            Image(systemName: feature.icon)
                .font(.body)
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .foregroundStyle(DS.Palette.ink)
                Text("default \(defaultAvailability.title)")
                    .font(.footnote)
                    .foregroundStyle(availability == defaultAvailability ? DS.Palette.secondary : DS.Palette.brick)
            }
            Spacer(minLength: DS.Spacing.xs)
            Picker(feature.title, selection: Binding(get: { availability }, set: onChange)) {
                ForEach(FeatureAvailability.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(DS.Palette.secondary)
            .accessibilityIdentifier("settings.features.\(feature.rawValue)")
        }
        .settingsRowPadding()
    }
}

#if DEBUG
#Preview {
    ScrollView {
        FeatureAvailabilityPanel()
            .padding()
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock())
}
#endif
