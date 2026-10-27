import SwiftUI

/// Settings' "Unlock": the same offer as the swipe wall, without the countdown. Closes itself once unlocked.
struct UnlockSheet: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                Text("Unlock \(AppInfo.name)")
                    .dsSerif(34, relativeTo: .largeTitle, weight: .medium)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
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
#endif
