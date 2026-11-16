import SwiftUI

/// Delete / Later / Keep buttons under the card stack.
struct ActionBar: View {
    let onAction: (SwipeDirection) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.xl) {
            CircleActionButton(title: "Delete", systemImage: "trash", variant: .destructive) {
                onAction(.left)
            }
            CircleActionButton(title: "Later", systemImage: "arrow.up", diameter: DS.Control.minorAction) {
                onAction(.up)
            }
            .padding(.top, DS.Spacing.xs)
            CircleActionButton(title: "Keep", systemImage: "checkmark", variant: .primary) {
                onAction(.right)
            }
        }
        .padding(.top, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.xs)
    }
}

#Preview {
    ActionBar { print($0) }
        .padding()
        .paperBackground()
}
