import SwiftUI
import UIKit

/// Library-wide progress, what's pending, and feed preferences.
struct OverviewSheet: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var vm = vm

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                stats
                    .padding(.top, DS.Spacing.l)
                pile
                    .padding(.top, DS.Spacing.xl)
                Toggle(isOn: $vm.skipFavorites) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip favorites")
                            .foregroundStyle(DS.Palette.ink)
                        Text("Favorites stay out of your feed, starting next session.")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.secondary)
                    }
                }
                .tint(DS.Palette.ink)
                .padding(DS.Spacing.m)
                .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
                .softShadow()
                .padding(.top, DS.Spacing.m)
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DS.Palette.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DS.Palette.paper)
        .presentationCornerRadius(DS.Radius.card)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your library")
                .dsSerif(34, relativeTo: .largeTitle, weight: .medium)
                .foregroundStyle(DS.Palette.ink)
            Spacer()
            Button("Done") { dismiss() }
                .font(.headline)
                .foregroundStyle(DS.Palette.ink)
        }
        .padding(.top, DS.Spacing.xl)
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
            OverviewRow(
                icon: "trash",
                title: "Pending",
                value: "\(vm.pendingItems.count) to clear · \(Format.size(vm.pendingBytes))",
                isAccent: true
            )
            Divider()
                .overlay(DS.Palette.line)
                .padding(.leading, 52)
            OverviewRow(icon: "clock", title: "Saved for later", value: "\(vm.laterCount)")
            if vm.access == .limited {
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
}

private struct OverviewRow: View {
    let icon: String
    let title: String
    let value: String
    var isAccent = false

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
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            OverviewSheet()
                .environment(FeedViewModel.mock(startingAt: .batch))
        }
}
