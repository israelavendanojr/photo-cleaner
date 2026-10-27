import SwiftUI
import UIKit

/// Settings, opened from the gear on the Library tab: the purchase, feed preferences, support,
/// the legal pages, and what the app does with photos.
///
/// Rows for launch values still unset in `AppInfo` are hidden. Debug builds show them greyed out
/// with "Not set yet", so the layout can be checked.
struct SettingsView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var safariLink: SafariLink?
    @State private var isUnlockPresented = false
    /// "Email address copied", shown briefly when mail can't open.
    @State private var copiedNotice = false
    #if DEBUG
    @State private var isConfirmingClear = false
    @State private var didResetOnboarding = false
    #endif

    var body: some View {
        @Bindable var vm = vm

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    purchase
                    SettingsSection("Feed") {
                        Toggle(isOn: $vm.skipFavorites) {
                            SettingsLabel(icon: "heart", title: "Skip favorites",
                                          detail: "Favorites stay out of your feed.")
                        }
                        .tint(DS.Palette.ink)
                        .settingsRowPadding()
                        .accessibilityIdentifier("settings.skipFavorites")
                        if vm.canRemind {
                            reminders
                            if vm.areRemindersDenied {
                                Button {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                } label: {
                                    SettingsLabel(icon: "gear", title: "Open Settings", showsChevron: true)
                                        .settingsRowPadding()
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Turn on notifications for \(AppInfo.name)")
                                .accessibilityIdentifier("settings.openSystemSettings")
                            }
                        }
                    }
                    SettingsSection("Support") {
                        launchRow(AppInfo.supportEmail, icon: "envelope", title: "Contact support", id: "settings.support") {
                            contactSupport($0)
                        }
                        launchRow(AppInfo.writeReviewURL, icon: "star", title: "Rate \(AppInfo.name)", id: "settings.rate") {
                            openURL($0)
                        }
                    }
                    SettingsSection("Legal") {
                        launchRow(AppInfo.privacyPolicyURL, icon: "hand.raised", title: "Privacy policy", id: "settings.privacy") {
                            safariLink = SafariLink(url: $0)
                        }
                        launchRow(AppInfo.termsURL, icon: "doc.text", title: "Terms of use", id: "settings.terms") {
                            safariLink = SafariLink(url: $0)
                        }
                    }
                    about
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.top, DS.Spacing.s)
                .padding(.bottom, DS.Spacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(DS.Palette.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .dsSerif(19, relativeTo: .headline, weight: .medium)
                        .foregroundStyle(DS.Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("settings.title")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                        .accessibilityIdentifier("settings.done")
                }
            }
            .toolbarBackground(DS.Palette.paper, for: .navigationBar)
            .overlay(alignment: .bottom) {
                if copiedNotice {
                    Text("Email address copied")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Spacing.m)
                        .padding(.vertical, DS.Spacing.s)
                        .background(DS.Palette.ink, in: Capsule())
                        .padding(.bottom, DS.Spacing.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityIdentifier("settings.copied")
                }
            }
        }
        .tint(DS.Palette.ink)
        .safariSheet($safariLink)
        .sheet(isPresented: $isUnlockPresented) {
            UnlockSheet()
                .presentationDragIndicator(.visible)
                .presentationBackground(DS.Palette.paper)
                .presentationCornerRadius(DS.Radius.card)
        }
        .onAppear { vm.resetPurchaseStatus() }
        .task { await vm.refreshReminderPermission() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the Settings app, maybe with notifications turned on.
            if phase == .active { Task { await vm.refreshReminderPermission() } }
        }
    }

    // MARK: Sections

    private var purchase: some View {
        SettingsSection("Purchase") {
            if vm.isUnlocked {
                SettingsLabel(icon: "checkmark.seal", title: "Unlocked · thanks for supporting \(AppInfo.name)")
                    .settingsRowPadding()
                    .accessibilityIdentifier("settings.unlocked")
            } else {
                Button {
                    vm.resetPurchaseStatus()
                    isUnlockPresented = true
                } label: {
                    SettingsLabel(icon: "lock.open", title: "Unlock for \(vm.displayPrice)",
                                  detail: "One-time purchase. No subscription.", showsChevron: true)
                        .settingsRowPadding()
                }
                .buttonStyle(.plain)
                .disabled(vm.isPurchaseBusy)
                .accessibilityIdentifier("settings.unlock")
            }
            Button {
                Task {
                    if await vm.restorePurchases() { Haptics.unlocked() }
                }
            } label: {
                SettingsLabel(icon: "arrow.clockwise",
                              title: vm.paywallStatus == .restoring ? "Restoring…" : "Restore Purchases",
                              detail: restoreMessage,
                              isWorking: vm.paywallStatus == .restoring)
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .disabled(vm.isPurchaseBusy)
            .animation(DS.Motion.calm, value: vm.paywallStatus)
            .accessibilityIdentifier("settings.restore")
        }
    }

    private var restoreMessage: String? {
        switch vm.paywallStatus {
        case .restored: "Purchase restored"
        case .nothingToRestore: "Nothing to restore"
        case .restoreFailed: "Couldn't reach the App Store. Try again."
        default: nil
        }
    }

    /// On only while opted in and allowed. Off in the Settings app shows the switch off, with a way there.
    private var reminders: some View {
        Toggle(isOn: Binding(
            get: { vm.isRemindersOptedIn && !vm.areRemindersDenied },
            set: { on in Task { await vm.setRemindersEnabled(on) } }
        )) {
            SettingsLabel(icon: "bell", title: "Refill reminders",
                          detail: vm.areRemindersDenied
                              ? "Notifications are off for \(AppInfo.name)"
                              : "A heads-up when free swipes are back.")
        }
        .tint(DS.Palette.ink)
        .disabled(vm.areRemindersDenied)
        .settingsRowPadding()
        .accessibilityIdentifier("settings.reminders")
    }

    private var about: some View {
        SettingsSection("About") {
            SettingsLabel(icon: "iphone", title: "Your photos are analyzed on this iPhone and never uploaded.")
                .settingsRowPadding()
            SettingsLabel(icon: "info.circle", title: "Version \(AppInfo.version) (build \(AppInfo.build))")
                .settingsRowPadding()
                .accessibilityIdentifier("settings.version")
        }
    }

    #if DEBUG
    private var debugSection: some View {
        SettingsSection("Debug") {
            SettingsLabel(icon: "hand.draw", title: "Swipes left",
                          value: vm.swipesLeft.map { "\($0)" } ?? "Unlimited")
                .settingsRowPadding()
                .accessibilityIdentifier("settings.debug.swipesLeft")
            debugButton("Reset swipes to full", icon: "arrow.counterclockwise", id: "settings.debug.resetSwipes") {
                vm.debugSetSwipes(nil)
            }
            debugButton("Set swipes to 0", icon: "0.circle", id: "settings.debug.zeroSwipes") {
                vm.debugSetSwipes(0)
            }
            Toggle(isOn: Binding(get: { vm.isUnlocked }, set: { vm.debugSetUnlocked($0) })) {
                SettingsLabel(icon: "lock.open", title: "Unlocked")
            }
            .tint(DS.Palette.ink)
            .settingsRowPadding()
            .accessibilityIdentifier("settings.debug.unlocked")
            Button {
                vm.debugResetOnboarding()
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
                    Task { await vm.debugClearAllDecisions() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Forgets every keep, delete, and later, the pile, and preferences. Nothing is deleted from your library.")
            }
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
    #endif

    // MARK: Rows

    /// A row for a launch value: tappable when set; hidden when nil, except debug builds show it
    /// greyed out with "Not set yet".
    @ViewBuilder
    private func launchRow<Value>(
        _ value: Value?,
        icon: String,
        title: String,
        id: String,
        action: @escaping (Value) -> Void
    ) -> some View {
        if let value {
            Button { action(value) } label: {
                SettingsLabel(icon: icon, title: title, showsChevron: true)
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
        } else {
            #if DEBUG
            SettingsLabel(icon: icon, title: title, value: "Not set yet")
                .settingsRowPadding()
                .opacity(0.45)
                .accessibilityIdentifier(id)
            #endif
        }
    }

    // MARK: Actions

    /// Opens a prefilled email. Without a mail app, copies the address instead.
    private func contactSupport(_ email: String) {
        guard let url = SupportMail.url(email: email) else { return copy(email) }
        openURL(url) { accepted in
            if !accepted { copy(email) }
        }
    }

    private func copy(_ email: String) {
        UIPasteboard.general.string = email
        AccessibilityNotification.Announcement("Email address copied").post()
        withAnimation(DS.Motion.calm) { copiedNotice = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(DS.Motion.calm) { copiedNotice = false }
        }
    }
}

// MARK: - Building blocks

/// A titled card of rows with hairlines between them. Hidden entirely when every row is.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Group(subviews: content) { rows in
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Palette.secondary)
                        .padding(.leading, DS.Spacing.m)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                            if offset > 0 {
                                Divider()
                                    .overlay(DS.Palette.line)
                                    .padding(.leading, 52)
                            }
                            row
                        }
                    }
                    // The shadow is the card's alone, so faded rows don't cast one through it.
                    .background {
                        RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous)
                            .fill(DS.Palette.card)
                            .softShadow()
                    }
                }
            }
        }
    }
}

/// Icon, title, and an optional detail line or trailing value. At large text sizes the value
/// moves under the title instead of truncating.
struct SettingsLabel: View {
    let icon: String
    let title: String
    var detail: String?
    var value: String?
    var showsChevron = false
    var isDestructive = false
    /// A spinner at the trailing edge, e.g. while restoring.
    var isWorking = false

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(isDestructive ? DS.Palette.brick : DS.Palette.ink)
                .frame(width: 24)
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Spacing.xs) {
                    titleAndDetail
                    Spacer(minLength: DS.Spacing.xs)
                    valueText
                }
                VStack(alignment: .leading, spacing: 2) {
                    titleAndDetail
                    valueText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .tint(DS.Palette.secondary)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.secondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var titleAndDetail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(isDestructive ? DS.Palette.brick : DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var valueText: some View {
        if let value {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(DS.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// The inset every settings row uses inside its card.
    func settingsRowPadding() -> some View {
        padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environment(FeedViewModel.mock())
}

#Preview("XXL") {
    SettingsView()
        .environment(FeedViewModel.mock())
        .dynamicTypeSize(.xxLarge)
}
#endif
