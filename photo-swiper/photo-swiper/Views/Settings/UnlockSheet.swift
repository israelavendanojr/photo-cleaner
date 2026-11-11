import SwiftUI

/// Settings' "Unlock": the same layout and offer as the swipe wall, without the countdown. Closes
/// itself once unlocked. Also offered after a free user's delete (at most once a day), with its own headline.
struct UnlockSheet: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    /// The headline. Nil reads "Unlock" and the app's name.
    var title: String?
    /// A line under the headline, e.g. why the offer is showing now. Nil uses a plain line about the unlock.
    var subtitle: String?

    var body: some View {
        UpsellLayout(supporting: subtitle ?? UnlockCopy.sheetSupporting) {
            Text(title ?? "Unlock \(AppInfo.name)")
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("unlock.title")
        } offer: {
            UnlockOffer { dismiss() }
        }
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
