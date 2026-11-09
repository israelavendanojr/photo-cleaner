import SwiftUI
import UIKit

/// The Library tab: library-wide progress and what's pending. The gear opens Settings.
/// Confetti falls the first time it's seen at 100%.
struct LibraryView: View {
    /// The tab is on screen. Both tabs stay mounted, so this says when the confetti can be seen.
    var isActive = true

    @Environment(FeedViewModel.self) private var vm
    @Environment(\.openURL) private var openURL
    @State private var isSettingsPresented = false
    /// The confetti burst playing, if one is. A new value starts a new burst.
    @State private var celebration: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    stats
                        .padding(.top, DS.Spacing.l)
                    pile
                        .padding(.top, DS.Spacing.xl)
                }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
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

    private var stats: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                    Text("\(Int((vm.libraryReviewedFraction * 100).rounded()))%")
                        .dsSerif(64, relativeTo: .largeTitle)
                        .foregroundStyle(DS.Palette.ink)
                    Text("reviewed")
                        .font(.callout)
                        .foregroundStyle(DS.Palette.secondary)
                }
                Spacer(minLength: DS.Spacing.xs)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.size(vm.freedBytes))
                        .dsSerif(24, relativeTo: .title2)
                        .foregroundStyle(DS.Palette.brick)
                    Text("freed so far")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            ProgressLine(value: vm.libraryReviewedFraction, height: 4)
                .padding(.top, DS.Spacing.s)
            Text("\(Format.count(vm.libraryReviewedCount)) of \(Format.count(vm.stats.totalItems)) photos reviewed")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, DS.Spacing.xs)
        }
        .accessibilityElement(children: .combine)
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
            Divider()
                .overlay(DS.Palette.line)
                .padding(.leading, 52)
            OverviewRow(icon: "clock", title: "Saved for later", value: "\(vm.laterCount)")
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
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
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

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(isAccent ? DS.Palette.brick : DS.Palette.ink)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(DS.Palette.ink)
            Spacer(minLength: DS.Spacing.xs)
            Text(value)
                .font(.subheadline.weight(isAccent ? .semibold : .regular))
                .foregroundStyle(isAccent ? DS.Palette.brick : DS.Palette.secondary)
                .multilineTextAlignment(.trailing)
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
}

#if DEBUG
#Preview {
    LibraryView()
        .environment(FeedViewModel.mock(startingAt: .batch))
}
#endif
