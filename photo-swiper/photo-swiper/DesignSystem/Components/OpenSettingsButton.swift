import SwiftUI

/// Opens this app's page in iOS Settings, where photo and notification access are changed.
struct OpenSettingsButton<Label: View>: View {
    @Environment(\.openURL) private var openURL
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } label: {
            label()
        }
    }
}

extension OpenSettingsButton where Label == Text {
    init(_ title: LocalizedStringKey) {
        self.init { Text(title) }
    }
}
