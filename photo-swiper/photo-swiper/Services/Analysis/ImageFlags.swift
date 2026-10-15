import Foundation

/// Turns image signals into the review flags the cards show. Pure; nil signals never flag anything.
///
/// Deliberately conservative: `PhotoCardView` blurs any photo whose review flag is `.blurry`, so a
/// false positive visibly damages a good photo. Flags are informational and only nudge ranking;
/// nothing is ever pre-marked for deletion.
enum ImageFlags {
    /// Sharpest-tile Laplacian variance below this reads as blurry.
    static let blurryBelow = 20.0
    /// Vision rating a soft photo above this suggests the softness is intentional, so it isn't called blurry.
    static let intentionalSoftAbove = 0.3
    /// Mostly-black or mostly-blown frames with less detail than this are accidental. Night shots
    /// have bright lights and edges, which push their sharpest tile well above it.
    static let detailBelow = 60.0
    /// Share of near-black pixels that makes a frame mostly black.
    static let mostlyDarkFraction = 0.90
    /// Share of near-white pixels that makes a frame mostly blown out.
    static let mostlyBrightFraction = 0.90
    /// Vision scores below this, together with low detail, read as an accidental shot.
    static let junkAestheticBelow = -0.5
    static let junkSharpnessBelow = 40.0

    /// Review flags in display order: accidental, then receipt, then blurry. Accidental and blurry
    /// never both appear. `LibraryItem.reviewFlag` shows the first, so receipts are never blurred.
    static func classify(_ features: AssetFeatures) -> [LibraryItem.Flag] {
        var flags: [LibraryItem.Flag] = []
        let accidental = isAccidental(features)
        if accidental { flags.append(.accidental) }
        if features.isUtility == true { flags.append(.receipt) }
        if !accidental, isBlurry(features) { flags.append(.blurry) }
        return flags
    }

    static func isBlurry(_ features: AssetFeatures) -> Bool {
        guard let sharpness = features.sharpness, sharpness < blurryBelow else { return false }
        if let aesthetic = features.aesthetic, aesthetic > intentionalSoftAbove { return false }
        return true
    }

    /// A pocket or lens-cap shot, a blown-out frame, or something Vision rates as junk that's also soft.
    static func isAccidental(_ features: AssetFeatures) -> Bool {
        guard let sharpness = features.sharpness else { return false }
        if let exposure = features.exposure, sharpness < detailBelow,
           exposure.darkFraction >= mostlyDarkFraction || exposure.brightFraction >= mostlyBrightFraction {
            return true
        }
        if let aesthetic = features.aesthetic, aesthetic < junkAestheticBelow, sharpness < junkSharpnessBelow {
            return true
        }
        return false
    }
}
