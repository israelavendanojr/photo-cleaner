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
#Preview {
    ScrollView {
        AdminUpsellPanel(onClose: {})
            .padding()
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock())
}
#endif
