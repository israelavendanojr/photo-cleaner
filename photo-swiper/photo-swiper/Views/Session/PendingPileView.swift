import SwiftUI

/// Everything waiting to be cleared, all marked to delete. Tap the ones worth saving to unmark
/// them, then Keep sends those back to the library and Delete clears the marked ones now. With edits
/// waiting, the button clears the bin instead: it saves every edited copy, then deletes the marked
/// photos and the edited originals in one system prompt, keeping the screen awake while copies are made.
/// After a delete it says how much was freed, then closes. Videos waiting to be trimmed or compressed are
/// listed under Edits, with the space each saves; swiping one away cancels the edit and keeps the video
/// as it is.
///
/// Opens as a sheet from the feed's "to clear" counter, or pushed from the overview's Pending row.
/// Admin Tools' mock items can be in the pile too; deleting them only drops them, and never reaches the
/// library (see `FeedViewModel.deleteNow`).
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
    @Environment(\.tabBarInset) private var tabBarInset
    /// The bottom safe area this screen was given.
    @State private var bottomInset: CGFloat = 0

    private var count: Int { vm.pendingItems.count }
    private var selectedItems: [LibraryItem] { vm.pendingItems.filter { selected.contains($0.id) } }
    private var keptItems: [LibraryItem] { vm.pendingItems.filter { !selected.contains($0.id) } }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    /// Pushed inside the Library tab, the tab bar can cover the bottom without being in the safe area.
    private var tabBarOverlap: CGFloat { max(0, tabBarInset - bottomInset) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if vm.binCount == 0 {
                    Text("Nothing marked to clear.")
                        .font(.callout)
                        .foregroundStyle(DS.Palette.secondary)
                        .padding(.top, DS.Spacing.xl)
                }
                if !vm.pendingItems.isEmpty {
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
                if !vm.pendingEdits.isEmpty {
                    edits
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
            } else if !vm.pendingItems.isEmpty || !vm.pendingEdits.isEmpty {
                actions.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .safeAreaPadding(.bottom, tabBarOverlap)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .paperBackground()
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear {
            guard !didPreselect else { return }
            didPreselect = true
            selected = Set(vm.pendingItems.map(\.id))
        }
        .onChange(of: vm.pendingItems.map(\.id)) { _, ids in
            selected.formIntersection(ids)
        }
        .alert(confirmTitle, isPresented: $isConfirming) {
            Button(vm.pendingEdits.isEmpty ? "Delete" : "Clear", role: .destructive, action: deleteSelected)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
        // Making copies can take minutes; the screen stays on meanwhile.
        .onChange(of: vm.editProgress != nil) { _, isEditing in
            UIApplication.shared.isIdleTimerDisabled = isEditing
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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
            Text(Format.size(vm.binBytes))
                .dsSerif(48, relativeTo: .largeTitle)
                .foregroundStyle(DS.Palette.brick)
                .contentTransition(.numericText(value: Double(vm.binBytes)))
                .padding(.top, DS.Spacing.s)
                .accessibilityElement(children: .combine)
            HStack(alignment: .firstTextBaseline) {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(DS.Palette.secondary)
                Spacer()
                if !vm.pendingItems.isEmpty {
                    Button(selected.count == count ? "Deselect all" : "Select all", action: toggleAll)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DS.Palette.ink)
                }
            }
            if let limit = vm.pileLimitBytes {
                PileLimit(bytes: vm.pendingBytes, counted: vm.pileCountedBytes, limit: limit, isFull: vm.isPileFull)
                    .padding(.top, DS.Spacing.m)
            }
        }
        .padding(.top, showsDone ? DS.Spacing.xl : DS.Spacing.xs)
    }

    /// What clearing frees: the marked photos, plus what the edits save.
    private var clearBytes: Int64 { selectedBytes + vm.editSavedBytes }

    private var confirmTitle: String {
        guard !vm.pendingEdits.isEmpty else { return "Delete \(selected.count) \(selected.count == 1 ? "photo" : "photos")?" }
        return "Clear the bin?"
    }

    /// "Saves 2 edited videos, then deletes their originals and 12 photos. This frees about 1.2 GB. …"
    private var confirmMessage: String {
        let edits = vm.pendingEdits.count
        guard edits > 0 else { return "This frees \(Format.size(selectedBytes)). They'll stay in Recently Deleted for 30 days." }
        let videos = "\(edits) edited \(edits == 1 ? "video" : "videos")"
        let photos = selected.isEmpty ? "" : " and \(selected.count) \(selected.count == 1 ? "photo" : "photos")"
        return "Saves \(videos), then deletes \(edits == 1 ? "its original" : "their originals")\(photos). "
            + "This frees about \(Format.size(clearBytes)). Deleted items stay in Recently Deleted for 30 days."
    }

    /// Keep for the unmarked photos, above the bin the marked ones go to.
    private var actions: some View {
        VStack(spacing: DS.Spacing.s) {
            if let progress = vm.editProgress {
                EditProgressRow(progress: progress)
                    .transition(.opacity)
            }
            if !keptItems.isEmpty {
                Button("Keep \(keptItems.count)", action: keepUnmarked)
                    .buttonStyle(.pill(.outline))
                    .disabled(isDeleting)
                    .accessibilityHint("Takes the unmarked photos out of the pile")
                    .accessibilityIdentifier("keepButton")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !selected.isEmpty || !vm.pendingEdits.isEmpty {
                binRow.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, DS.Spacing.s)
        .padding(.bottom, DS.Spacing.m)
        // The same paper, lined up with the screen's, so the photos scroll under it without a seam.
        .background { PaperBackground(alignment: .bottom) }
    }

    /// The marked photos plus the edits, as the bin's badge counts them.
    private var binCount: Int { selected.count + vm.pendingEdits.count }

    /// The bin the marked photos go to: how many, and the button that deletes them now.
    private var binRow: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: "trash.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(DS.Palette.brick)
                .symbolEffect(.bounce, value: binCount)
                .frame(width: 52, height: 52)
                .background(DS.Palette.brickTint, in: Circle())
                .overlay(alignment: .topTrailing) {
                    Text("\(binCount)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(DS.Palette.brickFill, in: Capsule())
                        .contentTransition(.numericText(value: Double(binCount)))
                        .offset(x: 4, y: -4)
                }
                .accessibilityHidden(true)
            Button(vm.pendingEdits.isEmpty ? "Delete \(selected.count) · \(Format.size(selectedBytes))" : "Clear bin · \(Format.size(clearBytes))") {
                isConfirming = true
            }
            .buttonStyle(.pill(.brick))
            .disabled(isDeleting)
            .accessibilityIdentifier("binButton")
        }
    }

    /// "to clear from 12 photos and 2 edits"
    private var summary: String {
        var parts: [String] = []
        if count > 0 || vm.pendingEdits.isEmpty { parts.append("\(count) \(count == 1 ? "photo" : "photos")") }
        let editCount = vm.pendingEdits.count
        if editCount > 0 { parts.append("\(editCount) \(editCount == 1 ? "edit" : "edits")") }
        return "to clear from " + parts.joined(separator: " and ")
    }

    /// Videos waiting to be trimmed or compressed. Swiping one away cancels its edit.
    private var edits: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text("Edits")
                .font(.headline)
                .foregroundStyle(DS.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(vm.pendingEdits) { edited in
                EditRow(edited: edited) { cancelEdit(edited) }
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
            Text("Each video is replaced by its edited copy when you clear the bin. Swipe one away to keep it as it is.")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DS.Spacing.xl)
    }

    private func cancelEdit(_ edited: EditedItem) {
        withAnimation(DS.Motion.calm) { vm.setEdit(nil, for: edited.item) }
        AccessibilityNotification.Announcement("Edit cancelled. The video stays as it is.").post()
    }

    private var hasDeleteNotice: Binding<Bool> {
        Binding(get: { vm.deleteNotice != nil }, set: { if !$0 { vm.dismissDeleteNotice() } })
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
            // Only now, so a review prompt or the unlock offer never covers the confirmation.
            vm.releaseReviewPrompt()
        }
    }
}

/// A free user's pile fills up: "320 MB / 1 GB" on a thin line, and what to do once it's full.
private struct PileLimit: View {
    /// The pile's real size, as shown.
    let bytes: Int64
    /// What counts toward the limit (unknown sizes count as a typical photo).
    let counted: Int64
    let limit: Int64
    let isFull: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.s) {
                Text("\(Format.size(bytes)) / \(Format.limit(limit))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isFull ? DS.Palette.brick : DS.Palette.ink)
                    .contentTransition(.numericText(value: Double(bytes)))
                BristleTicks(value: min(1, Double(counted) / Double(max(limit, 1))), tint: DS.Palette.brick, height: DS.Ticks.rowHeight)
            }
            if isFull {
                Text("Your pile is full. Delete these to keep clearing.")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Format.size(bytes)) of \(Format.limit(limit)) in the free pile\(isFull ? ". Full." : "")")
        .accessibilityIdentifier("pile.limit")
    }
}

/// "Saving edited video 1 of 2", with how far along it is.
private struct EditProgressRow: View {
    let progress: EditProgress

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Saving edited video \(progress.index) of \(progress.count)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.ink)
            BristleTicks(value: progress.fraction, height: DS.Ticks.rowHeight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pile.editProgress")
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
            .padding(.bottom, DS.Spacing.m)
            .accessibilityIdentifier("pile.freed")
            .onAppear {
                AccessibilityNotification.Announcement("Freed \(Format.size(bytes))").post()
            }
    }
}

/// A video waiting to be edited: its thumbnail, what's done to it (trimmed, compressed or both), its new
/// length and size, and the space that saves. Swiping it left past a threshold cancels the edit; VoiceOver
/// and the context menu offer the same.
private struct EditRow: View {
    let edited: EditedItem
    let onCancel: () -> Void

    @State private var offset: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var thumbSize: CGFloat = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far left a swipe has to go to cancel.
    private let threshold: CGFloat = 96

    private var edit: PendingEdit { edited.edit }

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Color.clear
                .frame(width: thumbSize, height: thumbSize)
                .overlay { ItemImage(edited.item.image) }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                marks
                Text(change)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("saves ~\(Format.size(edited.savedBytes))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.brick)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.s)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(DS.Palette.card)
                .softShadow()
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .offset(x: offset)
        .opacity(1 - min(Double(-offset / (threshold * 2)), 0.5))
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // Left only, and only once the drag is clearly sideways, so the list still scrolls.
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    offset = min(value.translation.width, 0)
                }
                .onEnded { _ in
                    if offset < -threshold {
                        onCancel()
                    } else {
                        withAnimation(reduceMotion ? nil : DS.Motion.snapBack) { offset = 0 }
                    }
                }
        )
        .contextMenu {
            Button("Cancel edit", systemImage: "xmark", action: onCancel)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAction(named: "Cancel edit", onCancel)
        .accessibilityIdentifier("pile.editRow")
    }

    /// "Trimmed · Compressed · Balanced", each with its symbol.
    private var marks: some View {
        HStack(spacing: DS.Spacing.s) {
            if edit.isTrimmed {
                Label("Trimmed", systemImage: "scissors")
            }
            if let level = edit.compression {
                Label("Compressed · \(level.title)", systemImage: "arrow.down.right.and.arrow.up.left")
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(DS.Palette.ink)
        .accessibilityIdentifier("pile.editMarks")
    }

    /// "1:42 → 0:12 · 380 MB → ~45 MB", or "1:42 · 380 MB → ~120 MB" when the length doesn't change.
    private var change: String {
        let length = edit.isTrimmed
            ? "\(Format.duration(edit.originalDuration)) → \(Format.duration(edit.newDuration))"
            : Format.duration(edit.originalDuration)
        return "\(length) · \(Format.size(edited.item.bytes)) → ~\(Format.size(edited.newBytes))"
    }

    private var accessibilityText: String {
        var what: [String] = []
        if edit.isTrimmed {
            what.append("trimmed from \(Format.duration(edit.originalDuration)) to \(Format.duration(edit.newDuration))")
        }
        if let level = edit.compression { what.append("compressed, \(level.title)") }
        return "Video \(what.joined(separator: " and ")), \(Format.size(edited.item.bytes)) to about \(Format.size(edited.newBytes)), saves about \(Format.size(edited.savedBytes))"
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
                .background(DS.Palette.brickFill, in: Circle())
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

#Preview("XXL") {
    PendingPileView(showsDone: true)
        .environment(FeedViewModel.mock(startingAt: .pending))
        .dynamicTypeSize(.xxLarge)
}

#Preview("Empty") {
    PendingPileView(showsDone: true)
        .environment(FeedViewModel.mock())
}
#endif
