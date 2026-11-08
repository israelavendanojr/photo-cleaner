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
/// `onClose` closes Settings so the screen can come up over the app.
struct AdminUpsellPanel: View {
    @Environment(FeedViewModel.self) private var vm
    let onClose: () -> Void

    @AppStorage("admin.upsellScreen") private var screen = AdminUpsell.postDelete
    @State private var didReset = false

    var body: some View {
        SettingsSection("Admin Tools · Upsell") {
            Button {
                vm.adminResetDeleteUpsell()
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
            Button {
                vm.adminRaiseUpsell(screen)
                onClose()
            } label: {
                SettingsLabel(icon: "sparkles.rectangle.stack", title: "Raise upsell", detail: screen.title)
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.admin.raiseUpsell")
        }
    }
}

#if DEBUG
/// Admin Tools' mock cards: one freshly randomized card of a kind on top of the deck, then the feed.
/// Debug builds only, since release builds leave out the mock images.
struct AdminMockCardsPanel: View {
    @Environment(FeedViewModel.self) private var vm
    let onClose: () -> Void

    var body: some View {
        SettingsSection("Admin Tools · Mock cards") {
            ForEach(AdminMockKind.allCases) { kind in
                row("Add \(kind.title.lowercased())", icon: kind.icon, id: "settings.admin.mock.\(kind.rawValue)") {
                    add(kind)
                }
            }
            row("Add a random kind", icon: "dice", id: "settings.admin.mock.random") {
                add(AdminMockKind.allCases.randomElement()!)
            }
            row("Remove mock cards", icon: "xmark.bin", id: "settings.admin.mock.remove",
                detail: "Mock cards never save a decision, fill the pile or cost a swipe.") {
                vm.adminRemoveMockCards()
            }
        }
    }

    private func add(_ kind: AdminMockKind) {
        var rng = SystemRandomNumberGenerator()
        vm.adminInsertMockCard(AdminMockCards.card(kind, using: &rng))
        onClose()
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
            AdminUpsellPanel(onClose: {})
            AdminMockCardsPanel(onClose: {})
        }
        .padding()
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock())
}
#endif
