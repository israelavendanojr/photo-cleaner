import SwiftUI

/// The one shape every unlock screen shares, so the wall and the sheets read as the same offer:
/// an optional eyebrow, a serif headline, one supporting sentence, an optional card of the user's
/// own numbers, then the offer. Holds no state; the screens supply the content.
struct UpsellLayout<Headline: View, Context: View, Offer: View>: View {
    /// Small line above the headline that says why this is showing, e.g. "Out of swipes".
    var eyebrow: String?
    var supporting: String?
    private let headline: Headline
    private let context: Context
    private let offer: Offer

    init(
        eyebrow: String? = nil,
        supporting: String? = nil,
        @ViewBuilder headline: () -> Headline,
        @ViewBuilder context: () -> Context = { EmptyView() },
        @ViewBuilder offer: () -> Offer
    ) {
        self.eyebrow = eyebrow
        self.supporting = supporting
        self.headline = headline()
        self.context = context()
        self.offer = offer()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                context
                    .padding(.top, DS.Spacing.l)
                offer
                    .padding(.top, DS.Spacing.xl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DS.Palette.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.secondary)
                    .accessibilityAddTraits(.isHeader)
            }
            headline
                .dsSerif(34, relativeTo: .largeTitle, weight: .medium)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let supporting {
                Text(supporting)
                    .font(.callout)
                    .foregroundStyle(DS.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Spacing.xxs)
            }
        }
    }
}

/// The raised card an unlock screen puts the user's own numbers in, matching onboarding's free-tier card.
struct UpsellCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            content
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Shadow on the shape only, so the text inside doesn't get a halo.
            RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous)
                .fill(DS.Palette.card)
                .softShadow()
        }
    }
}

/// One line of "what you get": an ink symbol and a sentence.
struct IncludedRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview {
    UpsellLayout(eyebrow: "Out of swipes", supporting: "Unlock to keep swiping without waiting.") {
        Text("+10 in 2h 14m")
    } context: {
        UpsellCard {
            Text("Still to go, about").font(.footnote).foregroundStyle(DS.Palette.secondary)
            Text("8.40 GB of likely clutter").font(.callout)
        }
    } offer: {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            IncludedRow(systemImage: "infinity", text: "Unlimited swipes")
            Button("Unlock for $9.99") {}.buttonStyle(.pill(.brick))
        }
    }
}
#endif
