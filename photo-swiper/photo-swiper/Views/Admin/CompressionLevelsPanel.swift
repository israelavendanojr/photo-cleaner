import SwiftUI

/// Developer mode's "Compression levels" (JUN-50): every `CompressionTunable` with its default beside
/// it, applied live and saved. Each export logs its estimate and real size, to tune these against.
struct CompressionLevelsPanel: View {
    @Environment(FeedViewModel.self) private var vm

    var body: some View {
        SettingsSection("Compression levels") {
            ForEach(CompressionTunable.allCases) { tunable in
                TunableRow(
                    tunable: tunable,
                    value: vm.compression.value(tunable),
                    defaultValue: vm.compression.defaultValue(tunable),
                    identifierPrefix: "settings.compression"
                ) { vm.admin.setCompressionValue(tunable, $0) }
            }
            SettingsLabel(icon: "info.circle", title: "Light keeps the source's size",
                          detail: "No level goes above the source's size or bitrate.")
                .settingsRowPadding()
            Button {
                vm.admin.resetCompressionToDefaults()
            } label: {
                SettingsLabel(icon: "arrow.counterclockwise", title: "Reset to defaults",
                              detail: vm.compression.isCustomized ? nil : "Using the defaults.")
                    .settingsRowPadding()
            }
            .buttonStyle(.plain)
            .disabled(!vm.compression.isCustomized)
            .accessibilityIdentifier("settings.compression.reset")
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        CompressionLevelsPanel()
            .padding()
    }
    .paperBackground()
    .environment(FeedViewModel.mock())
}
#endif
