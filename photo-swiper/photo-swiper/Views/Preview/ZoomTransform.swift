import CoreGraphics

/// How far a full-screen preview is zoomed and panned.
///
/// The content is fitted and centered in its container, scaled about its center, then offset.
/// Points here are relative to the container's center, so a content point `p` (unscaled, from
/// the content's center) lands on screen at `p * scale + offset`.
struct ZoomTransform: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    var isZoomed: Bool { scale > 1.01 }

    /// Scaled by `factor`, keeping whatever is under `focal` exactly where it is.
    func zoomed(by factor: CGFloat, about focal: CGPoint) -> ZoomTransform {
        ZoomTransform(
            scale: scale * factor,
            offset: CGSize(
                width: focal.x - (focal.x - offset.width) * factor,
                height: focal.y - (focal.y - offset.height) * factor
            )
        )
    }

    func panned(by translation: CGSize) -> ZoomTransform {
        ZoomTransform(
            scale: scale,
            offset: CGSize(width: offset.width + translation.width, height: offset.height + translation.height)
        )
    }

    /// One step of a pinch: the content under the fingers' old midpoint scales by `factor` and
    /// follows the midpoint to `end`, so moving both fingers together pans. Past `limits` the
    /// pinch gets stiff instead of stopping dead; `settled` brings it back.
    func pinched(by factor: CGFloat, from start: CGPoint, to end: CGPoint, limits: ClosedRange<CGFloat>) -> ZoomTransform {
        guard factor > 0, factor.isFinite, scale > 0 else { return self }
        var factor = factor
        let pastLimit = (scale <= limits.lowerBound && factor < 1) || (scale >= limits.upperBound && factor > 1)
        if pastLimit { factor = pow(factor, Self.resistance) }
        let target = min(max(scale * factor, limits.lowerBound * Self.overshoot.lowerBound),
                         limits.upperBound * Self.overshoot.upperBound)
        return zoomed(by: target / scale, about: start)
            .panned(by: CGSize(width: end.x - start.x, height: end.y - start.y))
    }

    /// Where a gesture comes to rest: back to fit when not really zoomed, back down to the
    /// largest allowed scale about `focal` when over it, and panned back inside the edges.
    func settled(content: CGSize, container: CGSize, limits: ClosedRange<CGFloat>, focal: CGPoint = .zero) -> ZoomTransform {
        var settled = self
        if settled.scale > limits.upperBound {
            settled = settled.zoomed(by: limits.upperBound / settled.scale, about: focal)
        }
        guard settled.isZoomed, settled.scale > limits.lowerBound else { return ZoomTransform() }
        settled.offset = Self.clamped(settled.offset, scale: settled.scale, content: content, container: container)
        return settled
    }

    /// Lets zoomed content pan until its edge meets the container's edge, and keeps it centered
    /// on an axis where it's still smaller than the container.
    static func clamped(_ offset: CGSize, scale: CGFloat, content: CGSize, container: CGSize) -> CGSize {
        let maxX = max((content.width * scale - container.width) / 2, 0)
        let maxY = max((content.height * scale - container.height) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    /// How much of a pinch past the limits still counts, as an exponent on the step.
    private static let resistance: CGFloat = 0.3
    /// How far past the limits a pinch can go, as fractions of them.
    private static let overshoot: ClosedRange<CGFloat> = 0.6...1.4
}
