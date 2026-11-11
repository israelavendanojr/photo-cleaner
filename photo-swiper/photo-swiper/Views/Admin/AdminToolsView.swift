import SwiftUI

/// The Admin tab, shown only while Developer mode is on (see `DevMode`, `AppTab.visible`).
///
/// Debug switches, upsell and notification raising, mock cards (debug builds), the free-tier tuning
/// panel and feature availability. It's a tab rather than part of Settings so anything it raises comes
/// up over it and closes back to it. Settings keeps only the Developer mode switch and the version-row taps.
struct AdminToolsView: View {
    @Environment(FeedViewModel.self) private var vm
    /// Switches to the Feed tab.
    var onOpenFeed: () -> Void = {}
    /// Switches to the Library tab, where the 100% confetti plays.
    var onOpenLibrary: () -> Void = {}

    @State private var isConfirmingClear = false
    @State private var didResetOnboarding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                Text("Admin Tools")
                    .dsSerif(34, relativeTo: .largeTitle, weight: .medium)
                    .foregroundStyle(DS.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("admin.title")
                    .padding(.top, DS.Spacing.l)
                debugSection
                AdminUpsellPanel {}
                #if DEBUG
                AdminMockCardsPanel(onClose: onOpenFeed)
                #endif
                FreeLimitsPanel()
                FeatureAvailabilityPanel()
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.paper)
    }

    private var debugSection: some View {
        SettingsSection("Swipes and progress") {
            SettingsLabel(icon: "hand.draw", title: "Swipes left",
                          value: vm.swipesLeft.map { "\($0)" } ?? "Unlimited")
                .settingsRowPadding()
                .accessibilityIdentifier("settings.debug.swipesLeft")
            debugButton("Reset swipes to full", icon: "arrow.counterclockwise", id: "settings.debug.resetSwipes") {
                vm.admin.debugSetSwipes(nil)
            }
            debugButton("Set swipes to 0", icon: "0.circle", id: "settings.debug.zeroSwipes") {
                vm.admin.debugSetSwipes(0)
            }
            debugUnlocked
            Toggle(isOn: Binding(get: { vm.debugSimulatesComplete }, set: { vm.admin.debugSetSimulatesComplete($0) })) {
                SettingsLabel(icon: "checkmark.circle", title: "Simulate 100% complete",
                              detail: "Only what the Library shows. Nothing is saved.")
            }
            .tint(DS.Palette.ink)
            .settingsRowPadding()
            .accessibilityIdentifier("settings.debug.simulateComplete")
            debugButton("Play 100% confetti", icon: "party.popper", id: "settings.debug.playConfetti") {
                // It plays over the Library tab.
                onOpenLibrary()
                vm.admin.debugPlayCelebration()
            }
            debugButton("Reset 100% celebration", icon: "arrow.uturn.backward", id: "settings.debug.resetCelebration") {
                vm.admin.debugResetCelebration()
            }
            Button {
                vm.admin.debugResetOnboarding()
                didResetOnboarding = true
            } label: {
                SettingsLabel(icon: "sparkles", title: "Reset onboarding",
                              detail: didResetOnboarding ? "Done. Shows on next launch." : "Shows on next launch.")
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.debug.resetOnboarding")
            Button {
                isConfirmingClear = true
            } label: {
                SettingsLabel(icon: "trash", title: "Clear all saved decisions", isDestructive: true)
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.debug.clearDecisions")
            .confirmationDialog("Clear all saved decisions?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button("Clear everything", role: .destructive) {
                    Task { await vm.admin.debugClearAllDecisions() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Forgets every keep, delete, and later, the pile, and preferences. Nothing is deleted from your library.")
            }
        }
    }

    /// The real store gets a three-way override with StoreKit's own answer beside it; mocks a plain switch.
    @ViewBuilder
    private var debugUnlocked: some View {
        if let override = vm.admin.debugUnlockOverride {
            Picker(selection: Binding(get: { override }, set: { vm.admin.debugSetUnlockOverride($0) })) {
                ForEach(UnlockOverride.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsLabel(icon: "lock.open", title: "Unlocked",
                              detail: vm.admin.debugStoreKitUnlocked == true ? "StoreKit: purchased" : "StoreKit: not purchased")
            }
            .pickerStyle(.menu)
            .tint(DS.Palette.secondary)
            .settingsRowPadding()
            .accessibilityIdentifier("settings.debug.unlocked")
        } else {
            #if DEBUG
            Toggle(isOn: Binding(get: { vm.isUnlocked }, set: { vm.admin.debugSetUnlocked($0) })) {
                SettingsLabel(icon: "lock.open", title: "Unlocked")
            }
            .tint(DS.Palette.ink)
            .settingsRowPadding()
            .accessibilityIdentifier("settings.debug.unlocked")
            #endif
        }
    }

    private func debugButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsLabel(icon: icon, title: title)
                .settingsRowPadding()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

#if DEBUG
#Preview {
    AdminToolsView()
        .environment(FeedViewModel.mock())
}
#endif
