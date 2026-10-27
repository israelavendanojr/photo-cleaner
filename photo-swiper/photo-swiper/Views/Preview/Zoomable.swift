import SwiftUI
import UIKit

extension View {
    /// The touch handling a full-screen preview shares between photos and videos: pinch zooms
    /// toward the fingers, double-tap zooms in at the tap or back out, one finger pans while
    /// zoomed, and at rest one finger swipes to decide or close through `swipe`.
    ///
    /// Attach to the full-screen container the content is centered in. `content` is the
    /// content's fitted size and `container` the container's size.
    func zoomable(
        _ zoom: Binding<ZoomTransform>,
        content: CGSize,
        container: CGSize,
        swipe: PreviewDrag,
        onSwipe: @escaping (PreviewDrag.Outcome) -> Void,
        onTap: @escaping () -> Void
    ) -> some View {
        modifier(Zoomable(zoom: zoom, content: content, container: container, swipe: swipe, onSwipe: onSwipe, onTap: onTap))
    }
}

private struct Zoomable: ViewModifier {
    @Binding var zoom: ZoomTransform
    let content: CGSize
    let container: CGSize
    let swipe: PreviewDrag
    let onSwipe: (PreviewDrag.Outcome) -> Void
    let onTap: () -> Void

    /// What the current one-finger drag is doing, decided when it starts.
    private enum Drag {
        case swipe
        /// Panning from `offset`, measured from where the drag had got to when it started.
        case pan(offset: CGSize, translation: CGSize)
        /// Taken over by a pinch; ignored until the finger lifts.
        case ignored
    }

    @State private var drag: Drag?
    @State private var isPinching = false
    /// The fingers' last midpoint, so a pinch past the max settles back toward it.
    @State private var focal = CGPoint.zero

    static let limits: ClosedRange<CGFloat> = 1...4
    private static let doubleTapScale: CGFloat = 2.5

    func body(content view: Content) -> some View {
        view
            .gesture(PinchGesture(action: pinch))
            // Alongside the pinch, so a one-finger drag follows the finger straight away.
            .simultaneousGesture(dragGesture)
            .onTapGesture(count: 2, coordinateSpace: .local) { toggleZoom(at: $0) }
            .onTapGesture(perform: onTap)
            // A new fitted size, like a video's real size replacing its poster's, moves the edges.
            .onChange(of: content) { if !isPinching { settle(animated: false) } }
            .onChange(of: container) { if !isPinching { settle(animated: false) } }
    }

    // MARK: Pinch

    private func pinch(_ phase: PinchGesture.Phase) {
        switch phase {
        case .began:
            isPinching = true
            // Two fingers mean zoom, never a decision: drop any swipe the first finger began.
            if case .swipe = drag { swipe.cancel() }
            if drag != nil { drag = .ignored }
        case .changed(let factor, let start, let end):
            focal = centered(end)
            zoom = zoom.pinched(by: factor, from: centered(start), to: focal, limits: Self.limits)
        case .ended:
            isPinching = false
            settle(animated: true)
        }
    }

    /// From the container's top-left to its center.
    private func centered(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - container.width / 2, y: point.y - container.height / 2)
    }

    private func settle(animated: Bool) {
        let settled = zoom.settled(content: content, container: container, limits: Self.limits, focal: focal)
        guard settled != zoom else { return }
        if animated {
            withAnimation(DS.Motion.snapBack) { zoom = settled }
        } else {
            zoom = settled
        }
    }

    // MARK: Drag

    /// Global coordinates so the content's own offset and scale don't skew the finger's movement.
    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let current = drag ?? (isPinching ? .ignored
                    : zoom.isZoomed ? .pan(offset: zoom.offset, translation: value.translation)
                    : .swipe)
                drag = current
                switch current {
                case .swipe:
                    swipe.track(value)
                case .pan(let offset, let start):
                    let moved = CGSize(
                        width: offset.width + value.translation.width - start.width,
                        height: offset.height + value.translation.height - start.height
                    )
                    zoom.offset = ZoomTransform.clamped(moved, scale: zoom.scale, content: content, container: container)
                case .ignored:
                    break
                }
            }
            .onEnded { value in
                defer { drag = nil }
                guard case .swipe = drag, let outcome = swipe.end(value) else { return }
                onSwipe(outcome)
            }
    }

    // MARK: Double tap

    /// Zooms in keeping the tapped point under the finger, or back out to fit.
    private func toggleZoom(at point: CGPoint) {
        withAnimation(DS.Motion.calm) {
            if zoom.isZoomed {
                zoom = ZoomTransform()
            } else {
                let zoomed = ZoomTransform().zoomed(by: Self.doubleTapScale, about: centered(point))
                zoom = zoomed.settled(content: content, container: container, limits: Self.limits)
            }
        }
    }
}

/// A two-finger pinch reporting its midpoint as well as its scale, which `MagnifyGesture`
/// doesn't do after it starts. Each change is a step from the last one.
struct PinchGesture: UIGestureRecognizerRepresentable {
    enum Phase {
        case began
        /// Scaled by `factor` while the midpoint moved from `from` to `to`, in the local space.
        case changed(factor: CGFloat, from: CGPoint, to: CGPoint)
        case ended
    }

    let action: (Phase) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        let point = context.converter.location(in: .local)
        switch recognizer.state {
        case .began:
            action(.began)
            action(.changed(factor: recognizer.scale, from: point, to: point))
        case .changed:
            // A finger lifting or landing jumps the midpoint; start again from the new one.
            if recognizer.numberOfTouches == coordinator.touches {
                action(.changed(factor: recognizer.scale, from: coordinator.point, to: point))
            }
        case .ended, .cancelled, .failed:
            action(.ended)
            return
        default:
            return
        }
        recognizer.scale = 1
        coordinator.point = point
        coordinator.touches = recognizer.numberOfTouches
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var point = CGPoint.zero
        var touches = 0

        /// Keeps the preview's own drag and taps working beside the pinch.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
