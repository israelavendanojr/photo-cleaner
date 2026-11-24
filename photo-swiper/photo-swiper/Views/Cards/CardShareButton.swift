import SwiftUI

/// The Share button at the bottom-trailing corner of a photo or video card (JUN-8). Locked, it looks the
/// same and its tap opens the paywall; preparing, it spins and a tap cancels. It's a plain button, like
/// `CardCenterButton`, so a drag that starts on it still swipes the card. VoiceOver reaches it through the
/// card's own "Share" action (`cardShareAction`), since the card combines its children into one element.
struct CardShareButton: View {
    let state: ShareButtonState
    let action: () -> Void

    var body: some View {
        FrostedIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: state.actionName, isBusy: state == .preparing, action: action)
            .accessibilityHidden(true)
    }

    /// Room the card's caption leaves on its trailing side so it never runs under the button.
    static let captionClearance = DS.Tap.minimum + DS.Spacing.m + DS.Spacing.xs
}

extension ShareButtonState {
    /// The card's accessibility action, and the button's label.
    var actionName: String { self == .preparing ? "Cancel sharing" : "Share" }
}

extension View {
    /// The Share button over a card's media, when there's one to show. Goes inside the card's clip.
    func cardShareButton(_ state: ShareButtonState?, action: @escaping () -> Void) -> some View {
        overlay(alignment: .bottomTrailing) {
            if let state {
                CardShareButton(state: state, action: action)
                    .padding(DS.Spacing.m)
            }
        }
    }

    /// The card's named "Share" accessibility action. Goes after the card's `accessibilityElement`.
    func cardShareAction(_ state: ShareButtonState?, action: @escaping () -> Void) -> some View {
        accessibilityActions {
            if let state { Button(state.actionName, action: action) }
        }
    }
}
