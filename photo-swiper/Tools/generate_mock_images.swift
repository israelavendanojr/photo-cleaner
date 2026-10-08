// Generates the soft, illustrated mock images used by the mock feed.
// Usage: swift Tools/generate_mock_images.swift photo-swiper/Assets.xcassets/Mock
// Output is deterministic; re-running overwrites the image sets.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Helpers

struct RGB {
    let r, g, b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    func cg(_ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func canvas(_ w: Int, _ h: Int, draw: (CGContext, CGFloat, CGFloat) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip so y grows downward, like a screen.
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx, CGFloat(w), CGFloat(h))
    return ctx.makeImage()!
}

func linear(_ ctx: CGContext, _ stops: [(UInt32, CGFloat)], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: space, colors: stops.map { RGB($0.0).cg() } as CFArray,
                       locations: stops.map(\.1))!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// A soft-edged disc: solid core fading to transparent.
func glow(_ ctx: CGContext, _ hex: UInt32, center: CGPoint, radius: CGFloat, softness: CGFloat = 0.82, alpha: CGFloat = 1) {
    let c = RGB(hex)
    let g = CGGradient(colorsSpace: space, colors: [c.cg(alpha), c.cg(alpha), c.cg(0)] as CFArray,
                       locations: [0, softness, 1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func fill(_ ctx: CGContext, _ hex: UInt32, alpha: CGFloat = 1, _ path: CGPath) {
    ctx.addPath(path)
    ctx.setFillColor(RGB(hex).cg(alpha))
    ctx.fillPath()
}

func hill(_ w: CGFloat, _ h: CGFloat, top: CGFloat, rise: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: -20, y: h))
    p.addLine(to: CGPoint(x: -20, y: top + rise))
    p.addQuadCurve(to: CGPoint(x: w + 20, y: top + rise), control: CGPoint(x: w / 2, y: top - rise))
    p.addLine(to: CGPoint(x: w + 20, y: h))
    p.closeSubpath()
    return p
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - Scenes

func sunset(sky: [(UInt32, CGFloat)], sun: UInt32, sunAt: CGPoint, ground: UInt32, groundTop: CGFloat) -> CGImage {
    canvas(750, 1125) { ctx, w, h in
        linear(ctx, sky, from: .zero, to: CGPoint(x: 0, y: h))
        glow(ctx, sun, center: CGPoint(x: w * sunAt.x, y: h * sunAt.y), radius: w * 0.2)
        fill(ctx, ground, hill(w, h, top: h * groundTop, rise: h * 0.05))
    }
}

func landscape(sky: [(UInt32, CGFloat)], layers: [(UInt32, CGFloat, CGFloat)]) -> CGImage {
    canvas(750, 1125) { ctx, w, h in
        linear(ctx, sky, from: .zero, to: CGPoint(x: 0, y: h))
        for (hex, top, rise) in layers { fill(ctx, hex, hill(w, h, top: h * top, rise: h * rise)) }
    }
}

func night(stars seed: Int) -> CGImage {
    canvas(750, 1125) { ctx, w, h in
        linear(ctx, [(0x2F2A26, 0), (0x16120F, 1)], from: .zero, to: CGPoint(x: w * 0.4, y: h))
        var s = UInt64(seed)
        for _ in 0..<40 {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let x = CGFloat(s >> 33 % 1000) .truncatingRemainder(dividingBy: w)
            let y = CGFloat((s >> 13) % 600)
            glow(ctx, 0xF3E6D0, center: CGPoint(x: x, y: y), radius: 4, softness: 0.3, alpha: 0.7)
        }
        glow(ctx, 0xF6E3B8, center: CGPoint(x: w * 0.7, y: h * 0.22), radius: 70, softness: 0.7)
        fill(ctx, 0x0E0B09, hill(w, h, top: h * 0.78, rise: h * 0.03))
    }
}

func interior(_ base: UInt32, _ accent: UInt32, lamp: CGPoint) -> CGImage {
    canvas(750, 1125) { ctx, w, h in
        linear(ctx, [(base, 0), (accent, 1)], from: .zero, to: CGPoint(x: w, y: h))
        glow(ctx, 0xFFF1D6, center: CGPoint(x: w * lamp.x, y: h * lamp.y), radius: w * 0.45, softness: 0.1, alpha: 0.55)
        fill(ctx, 0x6E5644, alpha: 0.55, rounded(CGRect(x: w * 0.1, y: h * 0.68, width: w * 0.8, height: h * 0.4), 40))
        fill(ctx, 0xE9DCCB, alpha: 0.6, rounded(CGRect(x: w * 0.58, y: h * 0.14, width: w * 0.28, height: h * 0.22), 18))
    }
}

/// Two rounded figures on a warm diagonal, as in the similar-shots design.
func figures(variant v: Int, palette: (sky: UInt32, sky2: UInt32, ground: UInt32, ground2: UInt32)) -> CGImage {
    canvas(900, 900) { ctx, w, h in
        linear(ctx, [(palette.sky, 0), (palette.sky2, 1)], from: .zero, to: CGPoint(x: 0, y: h * 0.6))
        let ground = CGMutablePath()
        ground.move(to: CGPoint(x: 0, y: h * 0.7))
        ground.addLine(to: CGPoint(x: w, y: h * 0.5))
        ground.addLine(to: CGPoint(x: w, y: h))
        ground.addLine(to: CGPoint(x: 0, y: h))
        ground.closeSubpath()
        ctx.saveGState()
        ctx.addPath(ground)
        ctx.clip()
        linear(ctx, [(palette.ground, 0), (palette.ground2, 1)], from: CGPoint(x: 0, y: h * 0.5), to: CGPoint(x: 0, y: h))
        ctx.restoreGState()

        let dx = CGFloat([0, -14, 10, -6, 18, -20][v % 6])
        let dy = CGFloat([0, 8, -6, 12, 4, -4][v % 6])
        let tilt = CGFloat([0, 10, -8, 16, -14, 6][v % 6])
        // Left figure
        fill(ctx, 0x3F4A56, rounded(CGRect(x: w * 0.2 + dx, y: h * 0.68 + dy, width: w * 0.3, height: h * 0.45), w * 0.15))
        fill(ctx, 0x7C4E3A, CGPath(ellipseIn: CGRect(x: w * 0.27 + dx, y: h * 0.48 + dy, width: w * 0.16, height: w * 0.16), transform: nil))
        // Right figure
        fill(ctx, 0xA35140, rounded(CGRect(x: w * 0.54 - dx, y: h * 0.72 + dy, width: w * 0.27, height: h * 0.42), w * 0.135))
        fill(ctx, 0xC48A68, CGPath(ellipseIn: CGRect(x: w * 0.6 - dx + tilt, y: h * 0.53 + dy, width: w * 0.15, height: w * 0.15), transform: nil))
    }
}

/// A phone-screenshot mockup: header band, text lines, and a colored block.
func screenshot(header: UInt32, body: UInt32, line: UInt32, block: UInt32) -> CGImage {
    canvas(600, 1300) { ctx, w, h in
        fill(ctx, body, CGPath(rect: CGRect(x: 0, y: 0, width: w, height: h), transform: nil))
        fill(ctx, header, CGPath(rect: CGRect(x: 0, y: 0, width: w, height: h * 0.12), transform: nil))
        for (i, width) in [0.62, 0.42].enumerated() {
            fill(ctx, line, rounded(CGRect(x: w * 0.12, y: h * (0.17 + 0.04 * CGFloat(i)), width: w * width, height: 22), 11))
        }
        fill(ctx, block, rounded(CGRect(x: w * 0.12, y: h * 0.27, width: w * 0.76, height: h * 0.2), 36))
        for (i, width) in [0.7, 0.5, 0.6].enumerated() {
            fill(ctx, line, rounded(CGRect(x: w * 0.12, y: h * (0.52 + 0.04 * CGFloat(i)), width: w * width, height: 22), 11))
        }
    }
}

/// A forwarded image: a framed picture with a caption band.
func forwarded(_ bg: UInt32, _ art: UInt32, _ band: UInt32) -> CGImage {
    canvas(750, 1125) { ctx, w, h in
        fill(ctx, band, CGPath(rect: CGRect(x: 0, y: 0, width: w, height: h), transform: nil))
        fill(ctx, bg, rounded(CGRect(x: w * 0.08, y: h * 0.2, width: w * 0.84, height: h * 0.5), 30))
        glow(ctx, art, center: CGPoint(x: w * 0.5, y: h * 0.45), radius: w * 0.26, softness: 0.9)
        fill(ctx, 0xFFFFFF, alpha: 0.75, rounded(CGRect(x: w * 0.18, y: h * 0.76, width: w * 0.64, height: 26), 13))
        fill(ctx, 0xFFFFFF, alpha: 0.5, rounded(CGRect(x: w * 0.28, y: h * 0.8, width: w * 0.44, height: 26), 13))
    }
}

// MARK: - Catalog

let images: [(String, CGImage)] = [
    ("photo-sunset", sunset(sky: [(0xF2C39A, 0), (0xE49A7A, 0.6), (0x9A6A72, 1)], sun: 0xF7DCAE, sunAt: CGPoint(x: 0.68, y: 0.42), ground: 0x3A2F33, groundTop: 0.86)),
    ("photo-beach", sunset(sky: [(0xBCD6E0, 0), (0xECE3D4, 0.55)], sun: 0xFFF6E2, sunAt: CGPoint(x: 0.3, y: 0.3), ground: 0xD8C094, groundTop: 0.62)),
    ("photo-desert", landscape(sky: [(0xF3D9B8, 0), (0xEBB48D, 1)], layers: [(0xC98D68, 0.55, 0.04), (0xA8684E, 0.7, 0.03), (0x6E4636, 0.84, 0.02)])),
    ("photo-hills", landscape(sky: [(0xD6E2D4, 0), (0xEEF0E4, 0.6)], layers: [(0xA9BC9C, 0.5, 0.06), (0x7F9A76, 0.66, 0.05), (0x5A7454, 0.82, 0.03)])),
    ("photo-dusk", sunset(sky: [(0xE9DCCB, 0), (0xC8A684, 1)], sun: 0xFBEBD0, sunAt: CGPoint(x: 0.5, y: 0.5), ground: 0x5C4436, groundTop: 0.8)),
    ("photo-coast", landscape(sky: [(0xC9DCE6, 0), (0xF1E9DD, 0.7)], layers: [(0x8FB0BE, 0.6, 0.0), (0x6D93A4, 0.72, 0.0), (0xE3D2B4, 0.86, 0.04)])),
    ("photo-pink", sunset(sky: [(0xF5D3CF, 0), (0xD99A9A, 0.7), (0x7F5A72, 1)], sun: 0xFCE7DA, sunAt: CGPoint(x: 0.35, y: 0.55), ground: 0x4C3A48, groundTop: 0.84)),
    ("photo-night", night(stars: 7)),
    ("photo-room", interior(0xE6D6C2, 0xB99778, lamp: CGPoint(x: 0.3, y: 0.25))),
    ("photo-cafe", interior(0xD9C3A5, 0x8A6A52, lamp: CGPoint(x: 0.7, y: 0.3))),
    ("photo-pocket", canvas(750, 1125) { ctx, w, h in // accidental: dark, smeared
        linear(ctx, [(0x2A2420, 0), (0x4A3C33, 0.6), (0x1C1714, 1)], from: .zero, to: CGPoint(x: w, y: h))
        glow(ctx, 0x9C7B62, center: CGPoint(x: w * 0.8, y: h * 0.15), radius: w * 0.5, softness: 0.1, alpha: 0.6)
    }),
    ("photo-receipt", canvas(750, 1125) { ctx, w, h in
        fill(ctx, 0xCDBFAE, CGPath(rect: CGRect(x: 0, y: 0, width: w, height: h), transform: nil))
        fill(ctx, 0xFBF8F2, rounded(CGRect(x: w * 0.2, y: h * 0.08, width: w * 0.6, height: h * 0.86), 8))
        for i in 0..<14 {
            let width = [0.4, 0.3, 0.45, 0.35][i % 4]
            fill(ctx, 0xBDB3A7, rounded(CGRect(x: w * 0.27, y: h * (0.16 + CGFloat(i) * 0.05), width: w * width, height: 14), 7))
        }
    }),
    ("video-waves", landscape(sky: [(0xBCD6E0, 0), (0xF3ECE4, 0.5)], layers: [(0x7FA3B4, 0.55, 0.0), (0x5E8698, 0.68, 0.02), (0xE9DCC6, 0.82, 0.05)])),
    ("video-party", interior(0x6E4A52, 0x2A1E24, lamp: CGPoint(x: 0.5, y: 0.35))),
    ("fwd-1", forwarded(0xF2C39A, 0xFFF1D6, 0x3A3A3C)),
    ("fwd-2", forwarded(0xBCD6E0, 0xFFFFFF, 0x2B2A2D)),
    ("fwd-3", forwarded(0xD6E2D4, 0xF4F1E8, 0x46413C)),
    ("fwd-4", forwarded(0xECE6F2, 0xA08BC4, 0x2F2A26)),
    ("shot-light", screenshot(header: 0xE4EBF3, body: 0xFFFFFF, line: 0xD3D9E0, block: 0x7FA3D6)),
    ("shot-dark", screenshot(header: 0x2B2A2D, body: 0x1C1B1E, line: 0x45444A, block: 0xC6A46C)),
    ("shot-cream", screenshot(header: 0xF3ECE4, body: 0xFFFFFF, line: 0xE3DAD0, block: 0xD98A68)),
    ("shot-sand", screenshot(header: 0xE6DFD2, body: 0xF2EEE6, line: 0xD2C8B8, block: 0x8DA67E)),
    ("shot-lavender", screenshot(header: 0xECE6F2, body: 0xFFFFFF, line: 0xDCD5E6, block: 0xA08BC4)),
] + (0..<6).map { v in
    ("similar-a-\(v + 1)", figures(variant: v, palette: (0xF2CFA8, 0xE8A887, 0xCDB494, 0xB59A7A)))
} + (0..<6).map { v in
    ("similar-b-\(v + 1)", figures(variant: v, palette: (0xCFDDE6, 0xEADFD2, 0xBFCDB6, 0x8FA684)))
}

// MARK: - Write

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Mock", isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: out, withIntermediateDirectories: true)
try #"{"info":{"author":"xcode","version":1},"properties":{"provides-namespace":false}}"#
    .write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

for (name, image) in images {
    let set = out.appendingPathComponent("\(name).imageset", isDirectory: true)
    try fm.createDirectory(at: set, withIntermediateDirectories: true)
    let file = set.appendingPathComponent("\(name).png")
    let dest = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("Failed to write \(name)") }
    let contents = #"{"images":[{"filename":"\#(name).png","idiom":"universal"}],"info":{"author":"xcode","version":1}}"#
    try contents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
print("Wrote \(images.count) images to \(out.path)")
