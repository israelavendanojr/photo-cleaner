import SwiftUI
import UIKit

/// Shown when photo access is denied, with a way back through Settings.
struct LibraryAccessView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DS.Palette.brick)
                .accessibilityHidden(true)
            Text("Photos are off.")
                .dsSerif(34, relativeTo: .largeTitle)
                .foregroundStyle(DS.Palette.ink)
                .padding(.top, DS.Spacing.l)
            Text("Photo Swiper needs access to your library to find photos you may want to clear. Nothing is uploaded.")
                .font(.callout)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, DS.Spacing.xs)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.pill(.ink))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, DS.Spacing.xxl)
        .padding(.bottom, DS.Spacing.m)
        .background(DS.Palette.paper)
        .onChange(of: scenePhase) { _, phase in
            // Pick up a change made in Settings.
            if phase == .active { Task { await vm.start() } }
        }
    }
}

#Preview {
    LibraryAccessView()
        .environment(FeedViewModel.mock())
}
