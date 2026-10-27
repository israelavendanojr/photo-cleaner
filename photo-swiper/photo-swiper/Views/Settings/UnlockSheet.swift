import SwiftUI

/// Settings' "Unlock": the same offer as the swipe wall, without the countdown. Closes itself once unlocked.
/// Also offered after a free user's delete and from a full pile, with its own headline.
struct UnlockSheet: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    /// The headline. Nil reads "Unlock" and the app's name.
    var title: String?
    /// A line under the headline, e.g. why the offer is showing now.
    var subtitle: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(title ?? "Unlock \(AppInfo.name)")
                        .dsSerif(34, relativeTo: .largeTitle, weight: .medium)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("unlock.title")
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(DS.Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                UnlockOffer { dismiss() }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DS.Palette.paper)
        .interactiveDismissDisabled(vm.isPurchaseBusy)
        .onAppear { vm.resetPurchaseStatus() }
        .onChange(of: vm.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }
}

#if DEBUG
#Preview {
    UnlockSheet()
        .environment(FeedViewModel.mock())
}

#Preview("After a delete") {
    UnlockSheet(title: "Freed 57 MB", subtitle: "Unlock to keep going without limits.")
        .environment(FeedViewModel.mock())
}
#endif
