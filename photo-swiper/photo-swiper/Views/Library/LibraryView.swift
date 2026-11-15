import SwiftUI
import UIKit

/// The Library tab, a dashboard laid straight on the paper: the wordmark, space cleared and photos reviewed
/// (the hero), the bin, then two ruled lists, what's ready to clear and what else the library holds. The numbers come from `DashboardController`'s cached snapshot, shown at once
/// and refreshed when stale or pulled. The gear opens Settings. Confetti falls the first time it's seen at 100%.
struct LibraryView: View {
    /// The tab is on screen. Both tabs stay mounted, so this says when the confetti can be seen.
    var isActive = true

    @Environment(FeedViewModel.self) private var vm
    @State private var isSettingsPresented = false
    /// The confetti burst playing, if one is. A new value starts a new burst.
    @State private var celebration: Int?
    /// The lists' rows have had their entrance. The tab stays mounted, so this is once per launch.
    @State private var rowsEntered = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    dashboard
                        .padding(.top, DS.Spacing.l)
                }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            #if DEBUG
            // `-libraryScrollToBottom YES` opens scrolled to the library card, for screenshots.
            .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "libraryScrollToBottom") ? .bottom : .top)
            #endif
            // The navigation bar is hidden. A hair of padding stops the scroll view reaching under the status
            // bar, so the sections are clipped below it rather than sliding under the clock.
            .padding(.top, DS.Rule.thickness)
            .refreshable {
                await vm.refreshDashboard()
                Haptics.refreshed()
                AccessibilityNotification.Announcement("Dashboard updated").post()
            }
            .paperBackground()
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
                .presentationBackground { PaperBackground() }
                .presentationCornerRadius(DS.Radius.card)
        }
        .task(id: isActive) {
            guard isActive else { return }
            await vm.refreshDashboardIfStale()
        }
        // The rows come in once there are numbers to show and the tab is up to show them.
        .onChange(of: isActive && vm.dashboardSnapshot != nil, initial: true) { _, ready in
            if ready { rowsEntered = true }
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
            HStack(alignment: .center, spacing: DS.Spacing.xs) {
                BristleMark()
                Text(AppInfo.name)
                    .dsSerif(24, relativeTo: .title2, weight: .medium)
                    .tracking(-0.3)
                    .foregroundStyle(DS.Palette.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(AppInfo.name), your library")
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            CircleIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {
                isSettingsPresented = true
            }
            .accessibilityIdentifier("library.settings")
        }
        .padding(.top, DS.Spacing.xs)
    }

    /// Before the first numbers on a new install, the sections show stand-in shapes, redacted and still.
    private var dashboard: some View {
        let snapshot = vm.dashboardSnapshot
        let shown = snapshot ?? .placeholder()
        let isLoading = snapshot == nil
        let cleared = max(vm.freedBytes, snapshot?.totalCleared ?? 0)
        return VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            HeroSection(snapshot: shown, isLoading: isLoading, clearedBytes: cleared, isActive: isActive)
            bin
            LibraryList(snapshot: shown, isLoading: isLoading, entered: rowsEntered)
        }
    }

    /// The pile as a bin, opening the pile screen, and under limited access the ways to show the app more.
    private var bin: some View {
        VStack(spacing: 0) {
            // Empty, there's nothing to open; a disabled link would also dim the row's text.
            if vm.binCount == 0 {
                binCard
                    .accessibilityIdentifier("library.bin")
            } else {
                NavigationLink(value: Destination.pending) {
                    binCard
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows what's waiting to be cleared")
                .accessibilityIdentifier("library.bin")
            }
            if vm.access == .limited {
                limitedAccess
            }
        }
    }

    private var binCard: some View {
        BinRow(
            count: vm.binCount,
            bytes: vm.binBytes,
            limit: vm.pileLimitBytes.map { (counted: vm.pileCountedBytes, bytes: $0) }
        )
    }

    private var limitedAccess: some View {
        VStack(spacing: 0) {
            Button {
                Task { await vm.addMorePhotos() }
            } label: {
                OverviewRow(icon: "plus.circle", title: "Add more photos", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose more photos for \(AppInfo.name) to look through")
            Rule()
            OpenSettingsButton {
                OverviewRow(icon: "lock", title: "Photo access", value: "Selected photos only")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Settings")
            Rule()
        }
    }

    private enum Destination: Hashable {
        case pending
    }
}

private struct OverviewRow: View {
    let icon: String
    let title: String
    let value: String
    var showsChevron = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(DS.Palette.ink)
                .accessibilityHidden(true)
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
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DS.Palette.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, DS.Spacing.s)
        .frame(minHeight: DS.Tally.minHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(title)
            .font(.callout)
            .foregroundStyle(DS.Palette.ink)
    }

    private var valueText: some View {
        Text(value)
            .font(.subheadline)
            .foregroundStyle(DS.Palette.secondary)
    }
}

#if DEBUG
#Preview {
    LibraryView()
        .environment(FeedViewModel.mock(startingAt: .batch))
}

#Preview("Dark") {
    LibraryView()
        .environment(FeedViewModel.mock(startingAt: .batch))
        .preferredColorScheme(.dark)
}

#Preview("Large text") {
    LibraryView()
        .environment(FeedViewModel.mock(startingAt: .batch))
        .dynamicTypeSize(.accessibility2)
}
#endif
