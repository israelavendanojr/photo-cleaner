import SwiftUI

/// The full-screen video's timeline, after Photos' trimmer: stills across the clip, a handle at each end
/// and a playhead.
///
/// Dragging the stills seeks, inside the selection once there is one, and resumes if it was playing.
/// Dragging a handle shows the frame under it, and on release plays the selection from its start;
/// the viewer loops it. The handles sit outside the stills, so a drag near either end of the stills
/// still seeks. Before a handle moves the frame is neutral; once trimmed it turns brick and what's cut
/// is dimmed. With `draft` nil there are no handles: a plain seek bar.
struct TrimStrip: View {
    let playback: VideoPlayback
    @Binding var draft: TrimDraft?

    @State private var isScrubbing = false
    @ScaledMetric(relativeTo: .body) private var height = DS.Trim.stripHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A handle's visible width; its touch area reaches out to `DS.Tap.minimum`.
    private let handleWidth = DS.Trim.handleWidth
    private var handles: CGFloat { draft == nil ? 0 : handleWidth }
    private var isTrimmed: Bool { draft?.isTrimmed ?? false }
    /// The frame and handles: neutral like Photos' until trimmed, then brick, the color of space to clear.
    private var accent: Color { isTrimmed ? DS.Palette.brick : .white.opacity(0.85) }
    private static let space = "trimStrip"

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - 2 * handles, 1)
            ZStack(alignment: .leading) {
                // The same frosted ground as the play button, so the bar reads as one piece, and the
                // handle slots a moved handle leaves aren't see-through.
                UnevenRoundedRectangle(bottomTrailingRadius: DS.Trim.cornerRadius, topTrailingRadius: DS.Trim.cornerRadius,
                                       style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: height)
                stills(width: width)
                    .offset(x: handles)
                if let draft {
                    cut(draft, width: width)
                    selection(draft, width: width)
                }
                playhead
                    .offset(x: handles + x(playback.currentTime, in: width) - DS.Trim.playheadWidth / 2)
                    .allowsHitTesting(false)
            }
            // Pinned to the strip's height, so the taller playhead overhangs evenly instead of pushing
            // the stills down out of line with the play button.
            .frame(width: proxy.size.width, height: height, alignment: .leading)
            .coordinateSpace(.named(Self.space))
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : DS.Motion.calm, value: isTrimmed)
        .disabled(!playback.isReady)
    }

    // MARK: Stills

    private func stills(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if playback.frames.isEmpty {
                Color.white.opacity(0.12)
            } else {
                ForEach(playback.frames.indices, id: \.self) { i in
                    Image(uiImage: playback.frames[i])
                        .resizable()
                        .scaledToFill()
                        .frame(width: width / CGFloat(playback.frames.count), height: height)
                        .clipped()
                }
            }
        }
        .frame(width: width, height: height)
        // With no handles, the stills end the bar, so they take its rounded trailing corners.
        .clipShape(UnevenRoundedRectangle(
            bottomTrailingRadius: draft == nil ? DS.Trim.cornerRadius : 0,
            topTrailingRadius: draft == nil ? DS.Trim.cornerRadius : 0,
            style: .continuous
        ))
        .contentShape(Rectangle())
        .gesture(seekGesture(width: width))
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(Format.duration(playback.currentTime)) of \(Format.duration(playback.duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: playback.skip(by: 5)
            case .decrement: playback.skip(by: -5)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("videoScrubber")
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isScrubbing {
                    isScrubbing = true
                    playback.beginScrubbing()
                }
                var seconds = time(at: value.location.x, in: width)
                if let range = draft.flatMap({ $0.isTrimmed ? $0.range : nil }) {
                    seconds = min(max(seconds, range.start), range.end)
                }
                playback.scrub(toTime: seconds)
            }
            .onEnded { _ in
                isScrubbing = false
                playback.endScrubbing()
            }
    }

    // MARK: Trim

    /// What's cut, dimmed.
    private func cut(_ draft: TrimDraft, width: CGFloat) -> some View {
        let start = x(draft.range.start, in: width)
        let end = x(draft.range.end, in: width)
        return ZStack(alignment: .leading) {
            Color.black.opacity(0.55)
                .frame(width: start, height: height)
                .offset(x: handles)
            Color.black.opacity(0.55)
                .frame(width: max(width - end, 0), height: height)
                .offset(x: handles + end)
        }
        .allowsHitTesting(false)
    }

    /// The frame around what's kept, with its two handles. At the very start it meets the play button
    /// square, as in Photos; anywhere else its corners are rounded.
    private func selection(_ draft: TrimDraft, width: CGFloat) -> some View {
        let start = x(draft.range.start, in: width)
        let end = x(draft.range.end, in: width)
        let leading = leadingRadius(draft)
        return ZStack(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: leading, bottomLeadingRadius: leading,
                                   bottomTrailingRadius: DS.Trim.cornerRadius, topTrailingRadius: DS.Trim.cornerRadius,
                                   style: .continuous)
                .strokeBorder(accent, lineWidth: DS.Trim.frameWidth)
                .frame(width: end - start + 2 * handleWidth, height: height)
                .offset(x: start)
                .allowsHitTesting(false)
            handle(.start, width: width)
                .offset(x: start)
            handle(.end, width: width)
                .offset(x: end + handleWidth)
        }
    }

    private enum Edge { case start, end }

    /// Square while the start handle is against the play button, rounded once it moves in.
    private func leadingRadius(_ draft: TrimDraft) -> CGFloat {
        draft.range.start <= TrimDraft.tolerance ? 0 : DS.Trim.cornerRadius
    }

    private func handle(_ edge: Edge, width: CGFloat) -> some View {
        Image(systemName: edge == .start ? "chevron.compact.left" : "chevron.compact.right")
            .font(.title3.weight(.bold))
            .foregroundStyle(isTrimmed ? .white : .black.opacity(0.7))
            .frame(width: handleWidth, height: height)
            .background(accent, in: UnevenRoundedRectangle(
                topLeadingRadius: edge == .start ? draft.map(leadingRadius) ?? 0 : 0,
                bottomLeadingRadius: edge == .start ? draft.map(leadingRadius) ?? 0 : 0,
                bottomTrailingRadius: edge == .end ? DS.Trim.cornerRadius : 0,
                topTrailingRadius: edge == .end ? DS.Trim.cornerRadius : 0,
                style: .continuous
            ))
            // Reaches outward to a full tap target, never over the stills it bounds.
            .contentShape(Rectangle()
                .size(width: DS.Tap.minimum, height: height)
                .offset(x: edge == .start ? handleWidth - DS.Tap.minimum : 0))
            .gesture(handleGesture(edge, width: width))
            .accessibilityElement()
            .accessibilityLabel(edge == .start ? "Trim start" : "Trim end")
            .accessibilityValue(Format.duration(edge == .start ? draft?.range.start ?? 0 : draft?.range.end ?? 0))
            .accessibilityAdjustableAction { direction in
                let step: TimeInterval = direction == .increment ? 1 : -1
                move(edge, to: (edge == .start ? draft?.range.start : draft?.range.end).map { $0 + step } ?? 0, preview: false)
            }
            .accessibilityIdentifier(edge == .start ? "video.trimStart" : "video.trimEnd")
    }

    private func handleGesture(_ edge: Edge, width: CGFloat) -> some Gesture {
        // In the strip's space, which stays put while the handle follows the finger.
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if !isScrubbing {
                    isScrubbing = true
                    playback.beginScrubbing()
                }
                // The finger holds the handle by its middle; the selection's edge is half a handle inward.
                let inward = edge == .start ? handleWidth / 2 : -handleWidth / 2
                move(edge, to: time(at: value.location.x - handles + inward, in: width), preview: true)
            }
            .onEnded { _ in
                isScrubbing = false
                // The selection plays from its start, as the viewer loops it.
                if let start = draft?.range.start { playback.scrub(toTime: start) }
                playback.endScrubbing()
            }
    }

    /// Moves a handle and, while dragging, shows the frame under it.
    private func move(_ edge: Edge, to seconds: TimeInterval, preview: Bool) {
        guard var current = draft else { return }
        switch edge {
        case .start: current.setStart(seconds)
        case .end: current.setEnd(seconds)
        }
        draft = current
        if preview { playback.scrub(toTime: edge == .start ? current.range.start : current.range.end) }
    }

    // MARK: Geometry

    private var playhead: some View {
        Capsule()
            .fill(.white)
            .frame(width: DS.Trim.playheadWidth, height: height + DS.Spacing.xs)
            // A hairline edge keeps it readable over bright frames.
            .overlay { Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 0.5) }
            .opacity(playback.isReady ? 1 : 0)
    }

    /// Where `seconds` falls along the stills.
    private func x(_ seconds: TimeInterval, in width: CGFloat) -> CGFloat {
        guard playback.duration > 0 else { return 0 }
        return CGFloat(min(max(seconds / playback.duration, 0), 1)) * width
    }

    /// The time at `x` along the stills.
    private func time(at x: CGFloat, in width: CGFloat) -> TimeInterval {
        playback.duration * Double(min(max(x / width, 0), 1))
    }
}
