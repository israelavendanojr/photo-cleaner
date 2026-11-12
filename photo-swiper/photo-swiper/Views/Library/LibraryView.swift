import SwiftUI
import UIKit

/// The Library tab, a dashboard: space cleared, the library's makeup, then the pile. The numbers come from `DashboardController`'s cached snapshot, shown at once
/// and refreshed when stale or pulled. The gear opens Settings. Confetti falls the first time it's seen at 100%.
struct LibraryView: View {
    /// The tab is on screen. Both tabs stay mounted, so this says when the confetti can be seen.
    var isActive = true

    @Environment(FeedViewModel.self) private var vm
    @State private var isSettingsPresented = false
    /// The confetti burst playing, if one is. A new value starts a new burst.
    @State private var celebration: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    dashboard
                        .padding(.top, DS.Spacing.l)
                    pile
                        .padding(.top, DS.Spacing.xl)
                }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The navigation bar is hidden, so paper fills the status bar's strip as the sections scroll under it.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0).background(DS.Palette.paper)
            }
            .refreshable {
                await vm.refreshDashboard()
                Haptics.refreshed()
                AccessibilityNotification.Announcement("Dashboard updated").post()
            }
            .background(DS.Palette.paper)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Destination.self) { _ in
                PendingPileView()
                    .toolbarBackground(DS.Palette.paper, for: .navigationBar)
            }
        }
        .tint(DS.Palette.ink)
        .overlay {
            if let celebration {
                ConfettiView(message: "Every photo in your library is reviewed") { self.celebration = nil }
                    .id(celebration)
                    .accessibilityIdentifier("library.confetti")
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
                .presentationDragIndicator(.visible)
                .presentationBackground(DS.Palette.paper)
                .presentationCornerRadius(DS.Radius.card)
        }
        .task(id: isActive) {
            guard isActive else { return }
            await vm.refreshDashboardIfStale()
        }
        .onAppear(perform: celebrateIfDue)
        .onChange(of: isActive) { celebrateIfDue() }
        .onChange(of: isSettingsPresented) { celebrateIfDue() }
        .onChange(of: vm.isCompleteCelebrationDue) { celebrateIfDue() }
        .onChange(of: vm.celebrationRequest) { playCelebration() }
        #if DEBUG
        // `-showSettings YES` opens Settings at launch, for screenshots.
        .task { if UserDefaults.standard.bool(forKey: "showSettings") { isSettingsPresented = true } }
        #endif
    }

    /// Plays the confetti once per 100%, only where it can be seen.
    private func celebrateIfDue() {
        guard isActive, !isSettingsPresented, vm.isCompleteCelebrationDue else { return }
        vm.markCompleteCelebrated()
        playCelebration()
    }

    private func playCelebration() {
        celebration = (celebration ?? 0) + 1
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.s) {
            Text("Your library")
                .dsSerif(34, relativeTo: .largeTitle, weight: .medium)
                .foregroundStyle(DS.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            CircleIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {
                isSettingsPresented = true
            }
            .accessibilityIdentifier("library.settings")
        }
        .padding(.top, DS.Spacing.l)
    }

    /// Before the first numbers on a new install, the sections show stand-in shapes, redacted and still.
    private var dashboard: some View {
        let snapshot = vm.dashboardSnapshot
        let shown = snapshot ?? .placeholder()
        let isLoading = snapshot == nil
        let cleared = max(vm.freedBytes, snapshot?.totalCleared ?? 0)
        return VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            HeroSection(snapshot: shown, isLoading: isLoading, clearedBytes: cleared)
            Group {
                if let composition = shown.composition, !composition.isEmpty {
                    CompositionSection(slices: composition)
                }
                // Only once there's something to show; before the first cleanup the hero says what to do.
                if cleared > 0, let activity = shown.activity {
                    ActivitySection(activity: activity)
                }
            }
            .redacted(reason: isLoading ? .placeholder : [])
            .disabled(isLoading)
        }
    }

    private var pile: some View {
        VStack(spacing: 0) {
            NavigationLink(value: Destination.pending) {
                OverviewRow(
                    icon: "trash",
                    title: "Pending",
                    value: "\(vm.pendingItems.count) to clear · \(Format.size(vm.pendingBytes))",
                    isAccent: true,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows what's waiting to be cleared")
            if vm.access == .limited {
                Divider()
                    .overlay(DS.Palette.line)
                    .padding(.leading, 52)
                Button {
                    Task { await vm.addMorePhotos() }
                } label: {
                    OverviewRow(icon: "plus.circle", title: "Add more photos", value: "", showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Choose more photos for \(AppInfo.name) to look through")
                Divider()
                    .overlay(DS.Palette.line)
                    .padding(.leading, 52)
                OpenSettingsButton {
                    OverviewRow(icon: "lock", title: "Photo access", value: "Selected photos only")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Settings")
            }
        }
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        .softShadow()
    }

    private enum Destination: Hashable {
        case pending
    }
}

private struct OverviewRow: View {
    let icon: String
    let title: String
    let value: String
    var isAccent = false
    var showsChevron = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(isAccent ? DS.Palette.brick : DS.Palette.ink)
                .frame(width: 24)
            // Title over value at accessibility sizes, so neither breaks mid-word.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    titleText
                    if !value.isEmpty { valueText }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                titleText
                Spacer(minLength: DS.Spacing.xs)
                valueText
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.secondary)
            }
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(title)
            .foregroundStyle(DS.Palette.ink)
    }

    private var valueText: some View {
        Text(value)
            .font(.subheadline.weight(isAccent ? .semibold : .regular))
            .foregroundStyle(isAccent ? DS.Palette.brick : DS.Palette.secondary)
    }
}

#if DEBUG
#Preview {
    LibraryView()
        .environment(FeedViewModel.mock(startingAt: .batch))
}

#Preview("Large text") {
    LibraryView()
        .environment(FeedViewModel.mock(startingAt: .batch))
        .dynamicTypeSize(.accessibility2)
}
#endif
