import SwiftUI

/// Everything waiting to be cleared, all marked to delete. Tap the ones worth saving to unmark
/// them, then Keep sends those back to the library and Delete clears the marked ones now.
/// After a delete it says how much was freed, then closes.
///
/// Opens as a sheet from the feed's "to clear" counter, or pushed from the overview's Pending row.
struct PendingPileView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    /// True when presented on its own as a sheet; pushed, the navigation bar's back button closes it.
    var showsDone = false

    @State private var selected: Set<LibraryItem.ID> = []
    @State private var isConfirming = false
    @State private var isDeleting = false
    /// Everything starts marked, once; after that the marks are the user's.
    @State private var didPreselect = false
    /// Bytes the last delete freed, shown briefly before the pile closes.
    @State private var freed: Int64?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var count: Int { vm.pendingItems.count }
    private var selectedItems: [LibraryItem] { vm.pendingItems.filter { selected.contains($0.id) } }
    private var keptItems: [LibraryItem] { vm.pendingItems.filter { !selected.contains($0.id) } }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if vm.pendingItems.isEmpty {
                    Text("Nothing marked to clear.")
                        .font(.callout)
                        .foregroundStyle(DS.Palette.secondary)
                        .padding(.top, DS.Spacing.xl)
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(vm.pendingItems) { item in
                            Button { toggle(item) } label: {
                                PendingTile(item: item, isSelected: selected.contains(item.id))
                            }
                            .buttonStyle(PressScaleStyle())
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .padding(.top, DS.Spacing.l)
                    Text("Everything's marked to delete. Tap the ones you want to keep, then Keep them.")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.secondary)
                        .padding(.top, DS.Spacing.l)
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            if let freed {
                FreedConfirmation(bytes: freed)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            } else if !vm.pendingItems.isEmpty {
                actions.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(DS.Palette.paper)
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear {
            guard !didPreselect else { return }
            didPreselect = true
            selected = Set(vm.pendingItems.map(\.id))
        }
        .onChange(of: vm.pendingItems.map(\.id)) { _, ids in
            selected.formIntersection(ids)
        }
        .alert("Delete \(selected.count) \(selected.count == 1 ? "photo" : "photos")?", isPresented: $isConfirming) {
            Button("Delete", role: .destructive, action: deleteSelected)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(Format.size(selectedBytes)). They'll stay in Recently Deleted for 30 days.")
        }
        .alert(vm.deleteNotice ?? "", isPresented: hasDeleteNotice) {
            Button("OK", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pending")
                    .dsSerif(34, relativeTo: .largeTitle, weight: .medium)
                    .foregroundStyle(DS.Palette.ink)
                Spacer()
                if showsDone {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                }
            }
            Text(Format.size(vm.pendingBytes))
                .dsSerif(48, relativeTo: .largeTitle)
                .foregroundStyle(DS.Palette.brick)
                .contentTransition(.numericText(value: Double(vm.pendingBytes)))
                .padding(.top, DS.Spacing.s)
                .accessibilityElement(children: .combine)
            HStack(alignment: .firstTextBaseline) {
                Text("to clear from \(count) \(count == 1 ? "photo" : "photos")")
                    .font(.callout)
                    .foregroundStyle(DS.Palette.secondary)
                Spacer()
                if !vm.pendingItems.isEmpty {
                    Button(selected.count == count ? "Deselect all" : "Select all", action: toggleAll)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DS.Palette.ink)
                }
            }
            if let limit = vm.pileLimit {
                PileLimit(count: count, limit: limit)
                    .padding(.top, DS.Spacing.m)
            }
        }
        .padding(.top, showsDone ? DS.Spacing.xl : DS.Spacing.xs)
    }

    /// Keep for the unmarked photos, above the bin the marked ones go to.
    private var actions: some View {
        VStack(spacing: DS.Spacing.s) {
            if !keptItems.isEmpty {
                Button("Keep \(keptItems.count)", action: keepUnmarked)
                    .buttonStyle(.pill(.outline))
                    .disabled(isDeleting)
                    .accessibilityHint("Takes the unmarked photos out of the pile")
                    .accessibilityIdentifier("keepButton")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !selected.isEmpty {
                binRow.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, DS.Spacing.s)
        .padding(.bottom, DS.Spacing.xs)
        .background(DS.Palette.paper)
    }

    /// The bin the marked photos go to: how many, and the button that deletes them now.
    private var binRow: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: "trash.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(DS.Palette.brick)
                .symbolEffect(.bounce, value: selected.count)
                .frame(width: 52, height: 52)
                .background(DS.Palette.brickTint, in: Circle())
                .overlay(alignment: .topTrailing) {
                    Text("\(selected.count)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(DS.Palette.brick, in: Capsule())
                        .contentTransition(.numericText(value: Double(selected.count)))
                        .offset(x: 4, y: -4)
                }
                .accessibilityHidden(true)
            Button("Delete \(selected.count) · \(Format.size(selectedBytes))") { isConfirming = true }
                .buttonStyle(.pill(.brick))
                .disabled(isDeleting)
                .accessibilityIdentifier("binButton")
        }
    }

    private var hasDeleteNotice: Binding<Bool> {
        Binding(get: { vm.deleteNotice != nil }, set: { if !$0 { vm.deleteNotice = nil } })
    }

    private func toggle(_ item: LibraryItem) {
        withAnimation(DS.Motion.snapBack) {
            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
        }
    }

    private func toggleAll() {
        withAnimation(DS.Motion.snapBack) {
            selected = selected.count == count ? [] : Set(vm.pendingItems.map(\.id))
        }
    }

    private func keepUnmarked() {
        withAnimation(DS.Motion.calm) { vm.keep(keptItems) }
    }

    private func deleteSelected() {
        let items = selectedItems
        isDeleting = true
        Task {
            guard let bytes = await vm.deleteNow(items) else {
                isDeleting = false
                return
            }
            Haptics.confirm()
            withAnimation(DS.Motion.calm) {
                selected.removeAll()
                freed = bytes
            }
            try? await Task.sleep(for: .seconds(1.5))
            isDeleting = false
            dismiss()
            // Only now, so a review prompt never covers the confirmation.
            vm.releaseReviewPrompt()
        }
    }
}

/// A free user's pile fills up: "12/50 photos" on a thin line, and what to do once it's full.
private struct PileLimit: View {
    let count: Int
    let limit: Int

    private var isFull: Bool { count >= limit }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.s) {
                Text("\(count)/\(limit) photos")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isFull ? DS.Palette.brick : DS.Palette.ink)
                    .contentTransition(.numericText(value: Double(count)))
                ProgressLine(value: Double(count) / Double(limit), tint: DS.Palette.brick, height: 4)
            }
            if isFull {
                Text("Your pile is full. Delete these to keep clearing, or unlock for no limit.")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of \(limit) photos in the free pile\(isFull ? ". Full." : "")")
        .accessibilityIdentifier("pile.limit")
    }
}

/// "Freed 412 MB", and where the photos went.
private struct FreedConfirmation: View {
    let bytes: Int64

    var body: some View {
        Text("\(Text("Freed \(Format.size(bytes))").fontWeight(.semibold).foregroundStyle(DS.Palette.brick)) · they stay in Recently Deleted for 30 days")
            .font(.callout)
            .foregroundStyle(DS.Palette.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.m)
            .background(DS.Palette.brickTint, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.xs)
            .accessibilityIdentifier("pile.freed")
            .onAppear {
                AccessibilityNotification.Announcement("Freed \(Format.size(bytes))").post()
            }
    }
}

private struct PendingTile: View {
    let item: LibraryItem
    let isSelected: Bool

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { ItemImage(item.image) }
            .overlay {
                if isSelected { DS.Palette.brick.opacity(0.35) }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if let duration = item.duration {
                        Image(systemName: "play.fill")
                        Text(Format.duration(duration))
                    } else {
                        Text(Format.size(item.bytes))
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .padding(6)
            }
            .overlay(alignment: .topTrailing) { mark.padding(6) }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                        .strokeBorder(DS.Palette.brick, lineWidth: 3)
                }
            }
            .scaleEffect(isSelected ? 0.94 : 1)
            .animation(DS.Motion.snapBack, value: isSelected)
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
            .accessibilityValue(isSelected ? "Marked to delete" : "Keeping")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint("Double tap to toggle")
            .accessibilityIdentifier("pendingTile")
    }

    /// Same mark as the similar-shots picker.
    @ViewBuilder private var mark: some View {
        if isSelected {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(DS.Palette.brick, in: Circle())
                .transition(.scale.combined(with: .opacity))
        } else {
            Circle()
                .fill(DS.Palette.card.opacity(0.4))
                .strokeBorder(.white, lineWidth: 1.5)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.25), radius: 2)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var accessibilityText: String {
        [item.isVideo ? "Video" : "Photo", Format.size(item.bytes), Format.day(item.date)].joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Sheet") {
    PendingPileView(showsDone: true)
        .environment(FeedViewModel.mock(startingAt: .pending))
}

#Preview("Empty") {
    PendingPileView(showsDone: true)
        .environment(FeedViewModel.mock())
}
#endif
