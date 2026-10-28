import CoreGraphics
import Testing
@testable import photo_swiper

/// The pinch, pan, and edge math behind the full-screen previews.
struct ZoomTransformTests {
    /// A 390-wide portrait screen showing a 4:3 landscape photo fitted to its width.
    private let container = CGSize(width: 390, height: 844)
    private let content = CGSize(width: 390, height: 292.5)
    private let limits: ClosedRange<CGFloat> = 1...4

    /// Where the content point `p` (from the content's center, unscaled) shows on screen.
    private func screen(_ p: CGPoint, _ t: ZoomTransform) -> CGPoint {
        CGPoint(x: p.x * t.scale + t.offset.width, y: p.y * t.scale + t.offset.height)
    }

    /// Which content point sits under the screen point `q`.
    private func contentPoint(under q: CGPoint, _ t: ZoomTransform) -> CGPoint {
        CGPoint(x: (q.x - t.offset.width) / t.scale, y: (q.y - t.offset.height) / t.scale)
    }

    private func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001
    }

    // MARK: Anchoring

    @Test func zoomKeepsTheFocalPointUnderTheFingers() {
        let focal = CGPoint(x: 120, y: -60)
        var t = ZoomTransform()
        let anchored = contentPoint(under: focal, t)
        for factor: CGFloat in [1.3, 1.5, 0.8, 1.7] {
            t = t.zoomed(by: factor, about: focal)
            #expect(close(screen(anchored, t), focal))
        }
        #expect(abs(t.scale - 1.3 * 1.5 * 0.8 * 1.7) < 0.0001)
    }

    @Test func zoomingAboutTheCenterDoesNotPan() {
        let t = ZoomTransform().zoomed(by: 2, about: .zero)
        #expect(t.scale == 2)
        #expect(t.offset == .zero)
    }

    @Test func pinchStepsKeepTheSamePointUnderTheFingersInsideTheLimits() {
        var t = ZoomTransform(scale: 1.5, offset: CGSize(width: 20, height: -10))
        var midpoint = CGPoint(x: -80, y: 40)
        let anchored = contentPoint(under: midpoint, t)
        for step in [(1.1, CGPoint(x: -70, y: 45)), (1.2, CGPoint(x: -50, y: 60)), (0.9, CGPoint(x: -55, y: 50))] {
            t = t.pinched(by: step.0, from: midpoint, to: step.1, limits: limits)
            midpoint = step.1
            #expect(close(screen(anchored, t), midpoint))
        }
    }

    @Test func movingBothFingersTogetherPans() {
        let t = ZoomTransform(scale: 2, offset: .zero)
            .pinched(by: 1, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: -15), limits: limits)
        #expect(t.scale == 2)
        #expect(t.offset == CGSize(width: 30, height: -25))
    }

    // MARK: Edges

    @Test func panStopsWhereTheEdgeMeetsTheScreen() {
        // At 2x the photo is 780 wide, so it pans 195 each way.
        let far = ZoomTransform.clamped(CGSize(width: 500, height: 0), scale: 2, content: content, container: container)
        #expect(far.width == 195)
        let near = ZoomTransform.clamped(CGSize(width: -120, height: 0), scale: 2, content: content, container: container)
        #expect(near.width == -120)
        let other = ZoomTransform.clamped(CGSize(width: -500, height: 0), scale: 2, content: content, container: container)
        #expect(other.width == -195)
    }

    @Test func anAxisSmallerThanTheScreenStaysCentered() {
        // At 2x the photo is 585 tall, still shorter than the 844 screen.
        let offset = ZoomTransform.clamped(CGSize(width: 0, height: 200), scale: 2, content: content, container: container)
        #expect(offset.height == 0)
        // At 4x it's 1170 tall and pans 163 each way.
        let tall = ZoomTransform.clamped(CGSize(width: 0, height: 400), scale: 4, content: content, container: container)
        #expect(tall.height == 163)
    }

    @Test func settlingPansBackInside() {
        let t = ZoomTransform(scale: 2, offset: CGSize(width: 300, height: 90))
            .settled(content: content, container: container, limits: limits)
        #expect(t.scale == 2)
        #expect(t.offset == CGSize(width: 195, height: 0))
    }

    // MARK: Limits

    @Test func pinchingPastTheMaxResistsThenSettlesAtTheMax() {
        let atMax = ZoomTransform(scale: 4)
        let over = atMax.pinched(by: 2, from: .zero, to: .zero, limits: limits)
        #expect(over.scale > 4)
        #expect(over.scale < 8, "Past the max a pinch only gives a little")
        #expect(over.scale <= 4 * 1.4)

        let focal = CGPoint(x: 100, y: 0)
        let anchored = contentPoint(under: focal, over)
        let settled = over.settled(content: content, container: container, limits: limits, focal: focal)
        #expect(settled.scale == 4)
        // Shrinks back toward the fingers, as long as the edges allow.
        #expect(close(screen(anchored, settled), focal))
    }

    @Test func pinchingBelowFitResistsThenSettlesToFit() {
        let under = ZoomTransform().pinched(by: 0.5, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 80, y: 60), limits: limits)
        #expect(under.scale < 1)
        #expect(under.scale > 0.5, "Below fit a pinch only gives a little")
        #expect(under.settled(content: content, container: container, limits: limits) == ZoomTransform())
    }

    @Test func barelyZoomedSettlesToFit() {
        let t = ZoomTransform(scale: 1.005, offset: CGSize(width: 3, height: 1))
        #expect(!t.isZoomed)
        #expect(t.settled(content: content, container: container, limits: limits) == ZoomTransform())
    }

    @Test func overshootIsCapped() {
        var t = ZoomTransform(scale: 4)
        for _ in 0..<50 { t = t.pinched(by: 1.5, from: .zero, to: .zero, limits: limits) }
        #expect(abs(t.scale - 4 * 1.4) < 0.0001)
        var u = ZoomTransform()
        for _ in 0..<50 { u = u.pinched(by: 0.5, from: .zero, to: .zero, limits: limits) }
        #expect(abs(u.scale - 0.6) < 0.0001)
    }

    @Test func badFactorsAreIgnored() {
        let t = ZoomTransform(scale: 2, offset: CGSize(width: 10, height: 0))
        #expect(t.pinched(by: 0, from: .zero, to: .zero, limits: limits) == t)
        #expect(t.pinched(by: .nan, from: .zero, to: .zero, limits: limits) == t)
        #expect(t.pinched(by: .infinity, from: .zero, to: .zero, limits: limits) == t)
    }
}
