import SwiftUI

/// The paywall as a sheet that closes itself: from Settings' "Unlock", and after a free user's delete
/// (at most once a day). The same screen as the swipe wall.
struct UnlockSheet: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaywallView { dismiss() }
            .interactiveDismissDisabled(vm.isPurchaseBusy)
            .onAppear { vm.resetPurchaseStatus() }
            .onChange(of: vm.isUnlocked) { _, unlocked in
                if unlocked { dismiss() }
            }
    }
}

#if DEBUG
#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            UnlockSheet()
        }
        .environment(FeedViewModel.mock())
}
#endif
