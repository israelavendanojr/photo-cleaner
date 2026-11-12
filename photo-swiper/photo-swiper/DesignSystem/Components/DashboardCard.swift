import SwiftUI

/// A section of the dashboard: a headline title with an optional trailing accessory (a status, a picker),
/// then its content, on a `card` panel. Every section uses it, so the screen keeps one rhythm.
struct DashboardCard<Content: View, Accessory: View>: View {
    let title: String
    private let content: Content
    private let accessory: Accessory

    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                    titleText
                    Spacer(minLength: DS.Spacing.xs)
                    accessory
                }
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    titleText
                    accessory
                }
            }
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

    private var titleText: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(DS.Palette.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(spacing: DS.Spacing.l) {
        DashboardCard("Worth a look") {
            Text("Large videos · 6.12 GB")
        } accessory: {
            Text("Updated just now")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
        }
        DashboardCard("Cleared over time") {
            Text("A chart goes here")
        }
    }
    .padding(DS.Spacing.l)
    .background(DS.Palette.paper)
}
