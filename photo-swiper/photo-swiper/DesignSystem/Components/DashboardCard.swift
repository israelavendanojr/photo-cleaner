import SwiftUI

/// A panel of the dashboard: a header, then content, on a `card` panel at `Radius.inner`, with the
/// shadow on the shape. The library card uses it, and `BinCard` matches its look, so the screen keeps one rhythm.
struct DashboardCard<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            header
            content
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // The shadow goes on the shape, so text inside doesn't get a halo.
            RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous)
                .fill(DS.Palette.card)
                .softShadow()
        }
    }
}

#Preview {
    DashboardCard {
        Text("21% reviewed")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    } content: {
        Text("Content goes here")
    }
    .padding(DS.Spacing.l)
    .background(DS.Palette.paper)
}
