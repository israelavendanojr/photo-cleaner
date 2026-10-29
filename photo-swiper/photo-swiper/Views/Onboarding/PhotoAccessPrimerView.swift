import SwiftUI

/// Second onboarding screen: explains the one permission right before iOS asks for it. Once access
/// is granted the library comes into focus photo by photo, a check draws over it, and onboarding moves on.
struct PhotoAccessPrimerView: View {
    /// `preparing` is the moment after access is granted; `granted` is the primer seen again later,
    /// which shows the library already open and just continues.
    enum Progress { case idle, requesting, preparing, granted }

    let progress: Progress
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many of the library's photos have come into focus.
    @State private var revealed: Int
    /// Whether the check over the library is showing.
    @State private var isChecked: Bool
    /// How much of the check has been drawn, 0...1.
    @State private var checkDrawn: CGFloat

    /// Between one photo coming into focus and the next.
    private static let revealStagger = Duration.seconds(0.07)
    /// How long the check takes to draw itself.
    private static let checkDraw = 0.35

    init(progress: Progress, onContinue: @escaping () -> Void) {
        self.progress = progress
        self.onContinue = onContinue
        // Seen again after granting, it's finished from the start rather than replaying.
        let isDone = progress == .granted
        _revealed = State(initialValue: isDone ? LockedLibraryGrid.photos.count : 0)
        _isChecked = State(initialValue: isDone)
        _checkDrawn = State(initialValue: isDone ? 1 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LockedLibraryGrid(revealed: revealed, isChecked: isChecked, checkDrawn: checkDrawn)
                .onboardingEntrance(order: 0)
            Text(Copy.headline)
                .dsSerif(40, relativeTo: .largeTitle, weight: .medium)
                .foregroundStyle(DS.Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, DS.Spacing.xl)
                .onboardingEntrance(order: 1)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(Copy.caption)
                    .font(.body)
                    .foregroundStyle(DS.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Always holds its space, so nothing moves when it appears.
                Text(Copy.keepsScanning)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isChecked ? 1 : 0)
                    .accessibilityHidden(!isChecked)
            }
            .padding(.top, DS.Spacing.m)
            .onboardingEntrance(order: 2)
        }
        .onboardingLayout(footerOrder: 3) {
            VStack(spacing: DS.Spacing.m) {
                Button(action: onContinue) { buttonLabel }
                    .buttonStyle(.pill(.ink))
                    // Not `.disabled`, which would dim the button while it shows progress.
                    .allowsHitTesting(progress == .idle || progress == .granted)
                    .accessibilityLabel(Copy.continueTitle)
                    .accessibilityValue(buttonValue)
                    .accessibilityIdentifier("onboarding.access.continue")
                Text(Copy.limited)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .task(id: progress) {
            guard progress == .preparing, !isChecked else { return }
            await unlock()
        }
    }

    /// Both labels are always laid out, so the button keeps its size when it switches.
    private var buttonLabel: some View {
        let isPreparing = progress == .preparing
        return ZStack {
            Text(Copy.continueTitle)
                .opacity(isPreparing ? 0 : 1)
            HStack(spacing: DS.Spacing.xs) {
                ProgressView()
                    .tint(.white)
                Text(Copy.preparing)
            }
            .opacity(isPreparing ? 1 : 0)
        }
        .multilineTextAlignment(.center)
        .animation(DS.Motion.calm, value: isPreparing)
    }

    private var buttonValue: String {
        switch progress {
        case .preparing: Copy.preparingValue
        case .granted: Copy.granted
        case .idle, .requesting: ""
        }
    }

    /// Brings the photos into focus one after another, then draws the check. With Reduce Motion,
    /// one cross-fade to the finished library.
    private func unlock() async {
        if reduceMotion {
            checkDrawn = 1
            withAnimation(.easeInOut(duration: 0.3)) {
                revealed = LockedLibraryGrid.photos.count
                isChecked = true
            }
        } else {
            for count in 1...LockedLibraryGrid.photos.count {
                withAnimation(DS.Motion.calm) { revealed = count }
                try? await Task.sleep(for: Self.revealStagger)
            }
            withAnimation(DS.Motion.calm) { isChecked = true }
            withAnimation(.easeOut(duration: Self.checkDraw)) { checkDrawn = 1 }
            try? await Task.sleep(for: .seconds(Self.checkDraw))
        }
        guard !Task.isCancelled else { return }
        Haptics.accessGranted()
        AccessibilityNotification.Announcement(Copy.granted).post()
    }
}

/// This screen's words, together so they're easy to change.
private enum Copy {
    static let headline = "One permission, then you're in."
    static let caption = "To find similar shots and blurry ones, \(AppInfo.name) needs to see your whole library."
    static let keepsScanning = "Large libraries keep scanning in the background."
    static let continueTitle = "Continue"
    static let preparing = "Finding your first photos…"
    static let preparingValue = "Finding your first photos"
    static let granted = "Photo access granted"
    static let limited = "Limited access works too, you'll just see fewer suggestions."
}

/// A few photos from a library, out of focus until access is granted, with a check drawn over
/// them once it is. Decorative only.
private struct LockedLibraryGrid: View {
    static let photos = StackedPhotosIllustration.photos
    private static let columns = 3

    /// How many photos, in order, are in focus.
    let revealed: Int
    let isChecked: Bool
    let checkDrawn: CGFloat

    @ScaledMetric(relativeTo: .title) private var badgeSize: CGFloat = 64

    var body: some View {
        Grid(horizontalSpacing: DS.Spacing.xs, verticalSpacing: DS.Spacing.xs) {
            ForEach(0..<Self.photos.count / Self.columns, id: \.self) { row in
                GridRow {
                    ForEach(0..<Self.columns, id: \.self) { column in
                        let i = row * Self.columns + column
                        tile(Self.photos[i], isRevealed: i < revealed)
                    }
                }
            }
        }
        .compositingGroup()
        .cardShadow()
        .overlay { badge }
        .accessibilityHidden(true)
    }

    private func tile(_ name: String, isRevealed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(name)
                    .resizable()
                    .scaledToFill()
                    // Opaque, so the blur doesn't soften the tile's edges.
                    .blur(radius: isRevealed ? 0 : 8, opaque: true)
                    .saturation(isRevealed ? 1 : 0.3)
                    .overlay { DS.Palette.paper.opacity(isRevealed ? 0 : 0.35) }
            }
            .clipShape(shape)
    }

    private var badge: some View {
        Circle()
            .fill(DS.Palette.card)
            .frame(width: badgeSize, height: badgeSize)
            .overlay {
                CheckmarkShape()
                    .trim(from: 0, to: checkDrawn)
                    .stroke(DS.Palette.brick, style: StrokeStyle(lineWidth: badgeSize * 0.08, lineCap: .round, lineJoin: .round))
                    .padding(badgeSize * 0.22)
            }
            .softShadow()
            .scaleEffect(isChecked ? 1 : 0.6)
            .opacity(isChecked ? 1 : 0)
    }
}

/// A check stroke, drawn short side first so trimming it draws it in.
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.54))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.82))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.2))
        }
    }
}

#if DEBUG
#Preview("Idle") {
    PhotoAccessPrimerView(progress: .idle, onContinue: {})
        .background(DS.Palette.paper)
}

#Preview("Preparing") {
    PhotoAccessPrimerView(progress: .preparing, onContinue: {})
        .background(DS.Palette.paper)
}

#Preview("Granted, revisited") {
    PhotoAccessPrimerView(progress: .granted, onContinue: {})
        .background(DS.Palette.paper)
}

#Preview("Idle, dark") {
    PhotoAccessPrimerView(progress: .idle, onContinue: {})
        .background(DS.Palette.paper)
        .preferredColorScheme(.dark)
}

#Preview("Preparing, dark") {
    PhotoAccessPrimerView(progress: .preparing, onContinue: {})
        .background(DS.Palette.paper)
        .preferredColorScheme(.dark)
}

#Preview("Grid") {
    LockedLibraryGrid(revealed: 3, isChecked: false, checkDrawn: 0)
        .padding(28)
        .background(DS.Palette.paper)
}
#endif
