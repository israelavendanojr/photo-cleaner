import SwiftUI

/// How a card lies while it waits behind the top one in the feed's loose stack.
enum StackPose {
    /// A card's tilt in degrees, a few either way. It comes from the card's ID alone, so a card lies
    /// the same way every time it's drawn, on every launch, wherever it is in the stack.
    static func tilt(for id: FeedCard.ID) -> Double {
        let hash = stableHash(id)
        // Bit 0 picks the side, the rest how far.
        let side: Double = hash & 1 == 0 ? 1 : -1
        let share = Double((hash >> 1) % 1000) / 999
        let range = DS.Stack.tilt
        return side * (range.lowerBound + share * (range.upperBound - range.lowerBound))
    }

    /// FNV-1a. `Hasher` is seeded per launch, so it would turn the stack over on every start.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

/// Lays a card in the stack: tilted, nudged and dimmed by how far back it is. As the top card is
/// dragged away (`progress`), each card behind moves a step forward in proportion, so the next one
/// straightens and brightens under the finger. With Reduce Motion the cards hold still during the
/// drag and take their new place when the top card has gone.
struct StackedBehind: ViewModifier {
    /// 0 for the top card, 1 for the one behind it, and so on.
    let depth: Int
    let tilt: Double
    /// How far the top card is toward leaving, 0...1.
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Steps back from the top, counting the drag: 1 is right behind, 0 is on top.
        let back = depth == 0 ? 0 : Double(depth) - (reduceMotion ? 0 : min(max(progress, 0), 1))
        // Only the card right behind is nudged out from under the top one.
        let nudge = DS.Stack.nudge * max(0, 1 - abs(back - 1))
        content
            .brightness(-DS.Stack.dimStep * back)
            .rotationEffect(.degrees(tilt * min(back, 1)))
            .offset(x: nudge, y: nudge)
    }
}
