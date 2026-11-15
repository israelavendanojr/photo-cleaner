import SwiftUI

/// Floating capsule tab bar. The selected tab sits on an ink capsule that slides between tabs.
struct PillTabBar<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let title: String
    }

    let items: [Item]
    @Binding var selection: Tab

    @Namespace private var namespace
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(items, id: \.tab) { item in
                tabButton(item)
            }
        }
        .padding(DS.TabBar.padding)
        .background {
            Capsule()
                .fill(DS.Palette.card)
                .softShadow()
        }
        .overlay { Capsule().strokeBorder(DS.Palette.line, lineWidth: 1) }
    }

    private func tabButton(_ item: Item) -> some View {
        let isSelected = item.tab == selection
        return Button {
            guard !isSelected else { return }
            Haptics.tabChange()
            withAnimation(DS.Motion.tab) { selection = item.tab }
        } label: {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? DS.Palette.onInk : DS.Palette.secondary)
                // Three tabs at the largest sizes: the labels need the room more than the air.
                .padding(.horizontal, typeSize.isAccessibilitySize ? DS.Spacing.s : DS.TabBar.itemInset)
                .frame(minHeight: DS.TabBar.itemHeight)
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
                .init(tab: 0, title: "Feed"),
                .init(tab: 1, title: "Library"),
            ],
            selection: $selection
        )
    }
    .frame(maxWidth: .infinity)
    .paperBackground()
}
