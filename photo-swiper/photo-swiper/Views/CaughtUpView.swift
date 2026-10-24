import SwiftUI

/// Shown when the feed has nothing left: a calm stop, not a dead end.
struct CaughtUpView: View {
    @Environment(FeedViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Circle()
                .strokeBorder(DS.Palette.brick, lineWidth: 2)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("All caught up.")
                .dsSerif(34, relativeTo: .largeTitle)
                .foregroundStyle(DS.Palette.ink)
                .padding(.top, DS.Spacing.l)
            Text("Nothing left to look at. Enjoy the space.")
                .font(.callout)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, DS.Spacing.xs)
            if vm.freedBytes > 0 {
                Text("\(Text(Format.size(vm.freedBytes)).font(.system(.title3, design: .serif)).foregroundStyle(DS.Palette.brick)) freed so far")
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.secondary)
                    .padding(.top, DS.Spacing.l)
            }
            Spacer()
            Button("Start another session") {
                Task { await vm.requestNextSession() }
            }
            .buttonStyle(.pill(.ink))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, DS.Spacing.xxl)
        .padding(.bottom, DS.Spacing.m)
        .background(DS.Palette.paper)
    }
}

#Preview {
    CaughtUpView()
        .environment(FeedViewModel.mock(startingAt: .caughtUp))
}
