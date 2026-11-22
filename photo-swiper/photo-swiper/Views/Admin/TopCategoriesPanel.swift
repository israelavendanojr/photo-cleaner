import SwiftUI

/// Developer mode's "Top Categories" (JUN-88): how many rows the Library shows, and how many still open the
/// feed while the section is locked (`TierFeature.topCategories`), each with its default. Applied live and saved.
struct TopCategoriesPanel: View {
    @Environment(FeedViewModel.self) private var vm

    var body: some View {
        SettingsSection("Top Categories") {
            ForEach(TopCategoriesTunable.allCases) { tunable in
                TunableRow(
                    tunable: tunable,
                    value: vm.topCategories.value(tunable),
                    defaultValue: vm.topCategories.defaultValue(tunable),
                    identifierPrefix: "settings.topCategories"
                ) { vm.admin.setTopCategoriesValue(tunable, $0) }
            }
            Button {
                vm.admin.resetTopCategoriesToDefaults()
            } label: {
                SettingsLabel(icon: "arrow.counterclockwise", title: "Reset to defaults",
                              detail: vm.topCategories.isCustomized ? nil : "Using the defaults.")
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .disabled(!vm.topCategories.isCustomized)
            .accessibilityIdentifier("settings.topCategories.reset")
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        TopCategoriesPanel()
            .padding()
    }
    .paperBackground()
    .environment(FeedViewModel.mock())
}
#endif
