import SwiftUI

/// Admin Tools' notifications: pick a refill reminder and raise a test copy of it, with the real body
/// text, a few seconds later. It shows as a banner even with the app open, and a tap routes like the
/// real one. The real reminders' schedule and opt-in are left alone (see `AdminController.raiseNotification`).
struct AdminNotificationsPanel: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.scenePhase) private var scenePhase
    /// The Admin tab is on screen. Permission and the estimate are only read then.
    var isActive = true

    @AppStorage("admin.notification") private var kind = AdminNotification.refill
    @State private var permission: AdminNotificationPermission?
    @State private var raised: AdminNotification?

    var body: some View {
        if vm.admin.canRaiseNotifications {
            SettingsSection("Notifications") {
                Picker(selection: $kind) {
                    ForEach(AdminNotification.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsLabel(icon: "bell.badge", title: "Notification")
                }
                .pickerStyle(.menu)
                .tint(DS.Palette.secondary)
                .settingsRowPadding()
                .accessibilityIdentifier("settings.admin.notification")
                permissionRow
                Button(action: raise) {
                    SettingsLabel(icon: "bell.and.waves.left.and.right", title: "Raise notification",
                                  detail: raiseDetail)
                        .settingsRowPadding()
                }
                .buttonStyle(.plain)
                .disabled(permission != .granted)
                .opacity(permission == .granted ? 1 : 0.45)
                .accessibilityIdentifier("settings.admin.raiseNotification")
            }
            .task(id: isActive) {
                guard isActive else { return }
                await refresh()
                await vm.admin.refreshNotificationBody()
            }
            .onChange(of: scenePhase) { _, phase in
                // Back from the Settings app, maybe with notifications allowed.
                if phase == .active, isActive { Task { await refresh() } }
            }
            .onChange(of: kind) { raised = nil }
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch permission {
        case .notAsked:
            Button {
                Task { permission = await vm.admin.requestNotificationPermission() }
            } label: {
                SettingsLabel(icon: "bell", title: "Notifications aren't allowed yet",
                              detail: "Ask for permission", showsChevron: true)
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.admin.notificationPermission")
        case .denied:
            OpenSettingsButton {
                SettingsLabel(icon: "bell.slash", title: "Notifications are off for \(AppInfo.name)",
                              detail: "Turn them on in Settings to raise one.", showsChevron: true)
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.admin.notificationPermission")
        case .granted, nil:
            EmptyView()
        }
    }

    private var raiseDetail: String {
        let body = vm.admin.notificationBody(kind)
        guard raised == kind else { return body }
        return "Arrives in \(Int(AdminController.notificationDelay)) seconds: \(body)"
    }

    private func refresh() async {
        permission = await vm.admin.notificationPermission()
    }

    private func raise() {
        let raising = kind
        Task {
            guard await vm.admin.raiseNotification(raising) != nil else { return }
            raised = raising
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        AdminNotificationsPanel()
            .padding()
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock())
}
#endif
