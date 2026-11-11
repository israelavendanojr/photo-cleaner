import SwiftUI

/// An upsell screen Admin Tools can show on demand.
enum AdminUpsell: String, CaseIterable, Identifiable {
    case postDelete, wall, onboarding, unlockSheet

    var id: Self { self }

    var title: String {
        switch self {
        case .postDelete: "Post-delete sheet"
        case .wall: "Swipe wall"
        case .onboarding: "Onboarding pitch"
        case .unlockSheet: "Unlock sheet"
        }
    }
}

/// Admin Tools' upsell controls: let the post-delete offer show again, and show any upsell screen now.
/// Each screen comes up over the Admin tab and closes back to it. The sheets and the onboarding pitch
/// are presented here; the wall is the real one, which RootView presents over any tab.
struct AdminUpsellPanel: View {
    @Environment(FeedViewModel.self) private var vm

    @AppStorage("admin.upsellScreen") private var screen = AdminUpsell.postDelete
    @State private var didReset = false
    /// The raised screen this panel presents itself. Never `.wall`.
    @State private var raised: AdminUpsell?

    var body: some View {
        SettingsSection("Upsell") {
            Button {
                vm.admin.adminResetDeleteUpsell()
                didReset = true
            } label: {
                SettingsLabel(icon: "arrow.uturn.backward", title: "Re-enable post-delete upsell",
                              detail: didReset ? "Done. The next delete shows it." : "The next delete shows it.")
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.admin.resetDeleteUpsell")
            Picker(selection: $screen) {
                ForEach(AdminUpsell.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsLabel(icon: "rectangle.stack", title: "Upsell screen")
            }
            .pickerStyle(.menu)
            .tint(DS.Palette.secondary)
            .settingsRowPadding()
            .accessibilityIdentifier("settings.admin.upsellScreen")
            Button(action: raise) {
                SettingsLabel(icon: "sparkles.rectangle.stack", title: "Raise upsell", detail: screen.title)
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.admin.raiseUpsell")
        }
        .sheet(isPresented: isRaised(.postDelete)) {
            UnlockSheet(title: "Freed \(Format.size(vm.upsellFreedBytes))", subtitle: RootView.deleteUpsellSubtitle)
                .presentationDragIndicator(.visible)
                .presentationBackground(DS.Palette.paper)
                .presentationCornerRadius(DS.Radius.card)
        }
        .sheet(isPresented: isRaised(.unlockSheet)) {
            UnlockSheet()
                .presentationDragIndicator(.visible)
                .presentationBackground(DS.Palette.paper)
                .presentationCornerRadius(DS.Radius.card)
        }
        .fullScreenCover(isPresented: isRaised(.onboarding)) {
            UpsellView { raised = nil }
                .background(DS.Palette.paper)
        }
    }

    private func raise() {
        vm.admin.adminRaiseUpsell(screen)
        if screen != .wall { raised = screen }
    }

    private func isRaised(_ screen: AdminUpsell) -> Binding<Bool> {
        Binding(get: { raised == screen }, set: { if !$0, raised == screen { raised = nil } })
    }
}

#if DEBUG
/// Admin Tools' mock cards: freshly randomized cards queued at the top of the deck in the order added,
/// without leaving the Admin tab. "Open feed" goes to them.
/// Debug builds only, since release builds leave out the mock images.
struct AdminMockCardsPanel: View {
    @Environment(FeedViewModel.self) private var vm
    /// Switches to the Feed tab.
    var onOpenFeed: () -> Void = {}

    var body: some View {
        SettingsSection("Mock cards") {
            ForEach(AdminMockKind.allCases) { kind in
                row("Add \(kind.title.lowercased())", icon: kind.icon, id: "settings.admin.mock.\(kind.rawValue)") {
                    add(kind)
                }
            }
            row("Add a random kind", icon: "dice", id: "settings.admin.mock.random") {
                add(AdminMockKind.allCases.randomElement()!)
            }
            SettingsLabel(icon: "tray.full", title: "Queued", value: "\(vm.adminQueuedMockCount)")
                .settingsRowPadding()
                .accessibilityIdentifier("settings.admin.mock.queued")
            row("Open feed", icon: "square.stack", id: "settings.admin.mock.openFeed", action: onOpenFeed)
            row("Remove mock cards", icon: "xmark.bin", id: "settings.admin.mock.remove",
                detail: "Mock cards never save a decision, fill the pile or cost a swipe.") {
                    vm.admin.adminRemoveMockCards()
                }
        }
    }

    private func add(_ kind: AdminMockKind) {
        var rng = SystemRandomNumberGenerator()
        vm.admin.adminInsertMockCard(AdminMockCards.card(kind, using: &rng))
    }

    private func row(_ title: String, icon: String, id: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsLabel(icon: icon, title: title, detail: detail)
                .settingsRowPadding()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: DS.Spacing.l) {
            AdminUpsellPanel()
            AdminMockCardsPanel()
        }
        .padding()
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock())
}
#endif
