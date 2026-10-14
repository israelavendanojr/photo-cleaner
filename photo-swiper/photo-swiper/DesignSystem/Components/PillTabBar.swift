import SwiftUI

/// Floating capsule tab bar. The selected tab sits on an ink capsule that slides between tabs.
struct PillTabBar<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let title: String
        let systemImage: String
        let selectedSystemImage: String
    }

    let items: [Item]
    @Binding var selection: Tab

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(items, id: \.tab) { item in
                tabButton(item)
            }
        }
        .padding(DS.Spacing.xxs + 2)
        .background(DS.Palette.card, in: Capsule())
        .overlay { Capsule().strokeBorder(DS.Palette.line, lineWidth: 1) }
        .softShadow()
    }

    private func tabButton(_ item: Item) -> some View {
        let isSelected = item.tab == selection
        return Button {
            guard !isSelected else { return }
            Haptics.tabChange()
            withAnimation(DS.Motion.tab) { selection = item.tab }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: isSelected ? item.selectedSystemImage : item.systemImage)
                    .font(.body.weight(.semibold))
                    .symbolEffect(.bounce, value: isSelected)
                    .frame(width: 24)
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : DS.Palette.secondary)
            .padding(.horizontal, DS.Spacing.l)
            .frame(minHeight: 48)
            .background {
                if isSelected {
                    Capsule()
                        .fill(DS.Palette.ink)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(TabPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(DS.Motion.calm, value: configuration.isPressed)
    }
}

#Preview {
    @Previewable @State var selection = 0
    VStack {
        Spacer()
        PillTabBar(
            items: [
                .init(tab: 0, title: "Feed", systemImage: "square.stack", selectedSystemImage: "square.stack.fill"),
                .init(tab: 1, title: "Library", systemImage: "photo.on.rectangle", selectedSystemImage: "photo.fill.on.rectangle.fill"),
            ],
            selection: $selection
        )
    }
    .frame(maxWidth: .infinity)
    .background(DS.Palette.paper)
}
