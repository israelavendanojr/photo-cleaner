import SwiftUI

/// Session summary, the one confirmed delete, and the celebration that follows.
struct EndOfSessionView: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var isConfirming = false
    @State private var isDeleting = false

    private var celebration: FeedViewModel.Celebration? { vm.celebration }
    private var isCelebrated: Bool { celebration != nil }
    private var pendingCount: Int { vm.pendingItems.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                undoRow
                summary
                if isCelebrated {
                    CelebrationBurst()
                        .frame(height: 96)
                        .padding(.top, DS.Spacing.l)
                } else {
                    pendingDetails
                }
                libraryProgress
                    .padding(.top, DS.Spacing.xl)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, DS.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { actions }
        .background(DS.Palette.paper)
        .alert("Delete \(pendingCount) \(pendingCount == 1 ? "photo" : "photos")?", isPresented: $isConfirming) {
            Button("Delete", role: .destructive, action: confirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(Format.size(vm.pendingBytes)). They'll stay in Recently Deleted for 30 days.")
        }
        .alert(vm.deleteNotice ?? "", isPresented: hasDeleteNotice) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: Sections

    private var undoRow: some View {
        Button {
            withAnimation(DS.Motion.calm) { vm.undo() }
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DS.Palette.secondary)
                .frame(width: 40, height: 40)
                .overlay { Circle().strokeBorder(DS.Palette.line, lineWidth: 1.5) }
        }
        .buttonStyle(PressScaleStyle())
        .opacity(vm.canUndo ? 1 : 0)
        .disabled(!vm.canUndo)
        .accessibilityLabel("Undo last card")
        .padding(.top, DS.Spacing.xs)
        .padding(.bottom, DS.Spacing.xl)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Session complete · \(vm.cards.count) photos")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
            Text(isCelebrated ? "Lighter already." : "A little lighter.")
                .dsSerif(40, relativeTo: .largeTitle, weight: .medium)
                .foregroundStyle(DS.Palette.ink)
                .padding(.top, DS.Spacing.xxs)
                .id(isCelebrated)
                .transition(.opacity)
            Text(Format.size(celebration?.bytes ?? vm.pendingBytes))
                .dsSerif(76, relativeTo: .largeTitle)
                .foregroundStyle(DS.Palette.brick)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, DS.Spacing.m)
                .id(isCelebrated)
                .transition(.scale(scale: 0.92, anchor: .leading).combined(with: .opacity))
            Text(isCelebrated
                 ? "freed from \(celebration?.count ?? 0) photos"
                 : "ready to clear from \(pendingCount) photos")
                .font(.callout)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, DS.Spacing.xs)
                .contentTransition(.opacity)
        }
    }

    @ViewBuilder private var pendingDetails: some View {
        if vm.pendingItems.isEmpty {
            Text("Nothing marked to clear this time.")
                .font(.callout)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, DS.Spacing.l)
        } else {
            PendingThumbnailGrid(items: vm.pendingItems)
                .padding(.top, DS.Spacing.l)
        }
        HStack(spacing: DS.Spacing.l) {
            count(pendingCount, "to delete")
            count(vm.keptCount, "kept")
            count(vm.laterCount, "for later")
        }
        .font(.subheadline)
        .foregroundStyle(DS.Palette.secondary)
        .padding(.top, DS.Spacing.l)
    }

    private var libraryProgress: some View {
        VStack(spacing: DS.Spacing.xs) {
            HStack {
                Text("Library reviewed")
                Spacer()
                Text("\(Int((vm.libraryReviewedFraction * 100).rounded()))%")
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Palette.ink)
            }
            .font(.subheadline)
            .foregroundStyle(DS.Palette.secondary)
            ProgressLine(value: vm.libraryReviewedFraction, tint: DS.Palette.brick, height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: DS.Spacing.s) {
            Text(isCelebrated
                 ? "Nicely done. The rest of your library will wait."
                 : "They'll rest in Recently Deleted for 30 days, just in case.")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
                .multilineTextAlignment(.center)
            if !isCelebrated {
                Button("Delete \(pendingCount) \(pendingCount == 1 ? "Photo" : "Photos")") { isConfirming = true }
                    .buttonStyle(.pill(.brick))
                    .disabled(pendingCount == 0 || isDeleting)
            }
            HStack(spacing: DS.Spacing.s) {
                Button("Keep going") {
                    Task { await vm.startNewSession() }
                }
                .buttonStyle(.pill(.outline))
                Button("Done for now", action: vm.finishForNow)
                    .buttonStyle(.pill(.ghost))
            }
            .disabled(isDeleting)
        }
        .padding(.horizontal, 26)
        .padding(.top, DS.Spacing.s)
        .padding(.bottom, DS.Spacing.xs)
        .background(DS.Palette.paper)
    }

    // MARK: Helpers

    private var hasDeleteNotice: Binding<Bool> {
        Binding(get: { vm.deleteNotice != nil }, set: { if !$0 { vm.deleteNotice = nil } })
    }

    private func count(_ value: Int, _ label: String) -> Text {
        Text("\(Text("\(value)").fontWeight(.semibold).foregroundStyle(DS.Palette.ink)) \(label)")
    }

    private func confirm() {
        isDeleting = true
        Task {
            if await vm.confirmDelete() {
                Haptics.confirm()
            }
            isDeleting = false
        }
    }
}

#Preview("Ready to clear") {
    EndOfSessionView()
        .environment(FeedViewModel.mock(startingAt: .end))
}

#Preview("Celebrated") {
    EndOfSessionView()
        .environment(FeedViewModel.mock(startingAt: .celebrated))
}
