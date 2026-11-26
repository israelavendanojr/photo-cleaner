import SwiftUI

/// Which of the top bar's menus is open. Only one is at a time.
enum FeedMenuKind: Hashable {
    case filter
    case sort
}

/// A top-bar pill that opens a `FeedMenu`: "Everything ⌄" or "Recommended ⌄", a `.plain` `Chip`. Where the
/// name doesn't fit (accessibility sizes), `fallbackSystemImage` stands in for it so the counter keeps its
/// room; VoiceOver and Voice Control still get the name. Shared by the filter and sort pills.
struct FeedPill: View {
    let title: String
    let fallbackSystemImage: String
    let isOpen: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
    /// What Voice Control answers to, besides the title.
    let inputLabel: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                Chip(text: title, trailingSystemImage: "chevron.down", style: .plain, size: .caption)
                    .lineLimit(1)
                // The trailing symbol takes the text color (ink); a leading one would be brick.
                Chip(text: "", trailingSystemImage: fallbackSystemImage, style: .plain, size: .caption)
            }
            .softShadow()
            .frame(minHeight: DS.Tap.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityValue(isOpen ? "Open" : "")
        .accessibilityInputLabels([title, inputLabel])
        .accessibilityIdentifier(identifier)
    }
}

/// One choice in a `FeedMenu`.
struct FeedMenuOption: Identifiable {
    /// Ends the row's accessibility identifier, e.g. "everything" in "feed.filter.option.everything".
    let id: String
    let title: String
    /// A short line under the title, e.g. why the choice isn't complete yet.
    var subtitle: String?
    let isCurrent: Bool
    /// Runs after the menu closes. Not called for the current choice, which only closes the menu.
    let choose: () -> Void
}

/// The top bar's paper dropdown, rather than a system `Menu`: a card under the top bar, over the deck, with
/// ruled rows and an ink checkmark on the current one. It scrolls when it doesn't fit (accessibility sizes).
/// FeedView closes it on a tap outside, and VoiceOver's escape closes it too. VoiceOver starts on the
/// current choice. Identifiers are `<identifier>.menu` and `<identifier>.option.<id>`.
struct FeedMenu: View {
    let identifier: String
    let options: [FeedMenuOption]
    @Binding var isOpen: Bool
    @AccessibilityFocusState private var focusedRow: String?

    var body: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: DS.Popup.maxWidth)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        .softShadow(raised: true)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
        .accessibilityIdentifier("\(identifier).menu")
        .onAppear { focusedRow = options.first(where: \.isCurrent)?.id }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { offset, option in
                if offset > 0 { Rule() }
                row(option)
            }
        }
    }

    private func row(_ option: FeedMenuOption) -> some View {
        Button {
            close()
            guard !option.isCurrent else { return }
            option.choose()
        } label: {
            HStack(spacing: DS.Spacing.s) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(option.title)
                        .foregroundStyle(DS.Palette.ink)
                    if let subtitle = option.subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
                    .opacity(option.isCurrent ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.xs)
            .frame(minHeight: DS.Tap.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(option.isCurrent ? .isSelected : [])
        .accessibilityFocused($focusedRow, equals: option.id)
        .accessibilityIdentifier("\(identifier).option.\(option.id)")
    }

    private func close() {
        withAnimation(DS.Motion.calm) { isOpen = false }
    }
}
