import SwiftUI

/// Developer mode's "Feature availability": what the free and paid plans each get of every `TierFeature`
/// (off, locked or unlocked), with each default beside it. Saved, and followed from the next page;
/// "Rebuild deck now" applies it straight away.
struct FeatureAvailabilityPanel: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var isRebuilding = false

    var body: some View {
        SettingsSection("Feature availability") {
            ForEach(TierFeature.allCases) { feature in
                FeatureRow(
                    feature: feature,
                    access: vm.features.planAccess(feature),
                    defaultAccess: vm.features.defaultPlanAccess(feature)
                ) { vm.admin.setFeatureAccess(feature, on: $0, $1) }
            }
            SettingsLabel(icon: vm.isUnlocked ? "lock.open" : "lock", title: vm.isUnlocked ? "Unlocked gets" : "Free gets",
                          detail: lockedSummary, value: summary(.unlocked) ?? "Nothing")
                .settingsRowPadding()
                .accessibilityIdentifier("settings.features.summary")
            Button {
                Task {
                    isRebuilding = true
                    await vm.admin.adminRebuildDeck()
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
                vm.admin.resetFeatureAvailability()
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

    /// "Similar shots, Duplicates": the features this user has at `access`, or nil for none.
    private func summary(_ access: FeatureAccess) -> String? {
        let titles = TierFeature.allCases.filter { vm.features.access($0, isUnlocked: vm.isUnlocked) == access }.map(\.title)
        return titles.isEmpty ? nil : titles.joined(separator: ", ")
    }

    private var lockedSummary: String? { summary(.locked).map { "Locked: \($0)" } }
}

/// One feature: its title, then an Off / Locked / Unlocked menu for each plan with that plan's default.
private struct FeatureRow: View {
    let feature: TierFeature
    let access: PlanAccess
    let defaultAccess: PlanAccess
    let onChange: @MainActor @Sendable (Plan, FeatureAccess) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
            Image(systemName: feature.icon)
                .font(.body)
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(feature.title)
                    .foregroundStyle(DS.Palette.ink)
                ForEach(Plan.allCases) { plan in
                    planRow(plan)
                }
            }
        }
        .settingsRowPadding()
    }

    private func planRow(_ plan: Plan) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            VStack(alignment: .leading, spacing: 0) {
                Text(plan.title)
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.ink)
                Text("default \(defaultAccess[plan].title)")
                    .font(.footnote)
                    .foregroundStyle(access[plan] == defaultAccess[plan] ? DS.Palette.secondary : DS.Palette.brick)
            }
            Spacer(minLength: DS.Spacing.xs)
            Picker("\(feature.title), \(plan.title)", selection: Binding(get: { access[plan] }, set: { onChange(plan, $0) })) {
                ForEach(FeatureAccess.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(DS.Palette.secondary)
            .accessibilityIdentifier("settings.features.\(feature.rawValue).\(plan.rawValue)")
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        FeatureAvailabilityPanel()
            .padding()
    }
    .paperBackground()
    .environment(FeedViewModel.mock())
}
#endif
