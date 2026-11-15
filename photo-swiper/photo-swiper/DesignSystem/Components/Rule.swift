import SwiftUI

/// A hairline across the page: the line a ruled row sits under. Lists on the paper are ruled, not boxed.
struct Rule: View {
    var body: some View {
        Rectangle()
            .fill(DS.Palette.line)
            .frame(height: DS.Rule.thickness)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: DS.Spacing.m) {
        Rule()
        Text("A ruled row")
        Rule()
    }
    .padding(DS.Spacing.l)
    .paperBackground()
}
