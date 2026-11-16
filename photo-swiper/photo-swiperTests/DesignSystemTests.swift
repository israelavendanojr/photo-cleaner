import Testing
import UIKit
@testable import photo_swiper

/// The design system's bundled pieces: a font or color set that goes missing fails quietly on
/// screen (a system serif, a clear color), so these fail loudly instead.
@MainActor
struct DesignSystemTests {
    @Test(arguments: ["Newsreader16pt-Regular", "Newsreader16pt-Italic"])
    func newsreaderIsRegistered(name: String) {
        #expect(UIFont(name: name, size: 20) != nil)
    }

    @Test(arguments: [
        "paper", "card", "ink", "onInk", "secondary", "brick", "brickFill", "brickTint", "line", "outline", "muted", "shadow",
    ])
    func everyPaletteColorHasALightAndADarkValue(name: String) throws {
        let color = try #require(UIColor(named: "Palette/\(name)"))
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        // The brick pill's fill is the one pair allowed to be close; none are the same.
        #expect(light != dark)
    }

    @Test func thePaperTextureHasBothAppearances() {
        #expect(UIImage(named: "Paper", in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: .light)) != nil)
        #expect(UIImage(named: "Paper", in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: .dark)) != nil)
    }
}
