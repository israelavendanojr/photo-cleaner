import SwiftUI

/// The compression levels for one video (JUN-50): None, Light, Balanced and Max, each with what it would
/// make of the video after its trim ("380 MB → ~120 MB"). A level that saves too little to be worth it is
/// greyed out as "Already small". Choosing a level previews it in the viewer above; Apply keeps it.
///
/// Opened as a medium sheet over the full-screen video, which stays live behind it, so the preview and
/// press-and-hold work while choosing.
struct CompressionSheet: View {
    /// The video's size after its trim, which None keeps.
    let trimmedBytes: Int64
    /// Each level's estimate. Nil while the video's tracks are still being read.
    let estimates: [CompressionLevel: CompressionEstimate]?
    /// The highlighted choice, nil for None.
    let choice: CompressionLevel?
    let onChoose: (CompressionLevel?) -> Void
    let onApply: () -> Void

    var body: some View {
        // Scrolls at large text sizes rather than clipping in the medium sheet.
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DS.Palette.paper)
        .environment(\.colorScheme, .light)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Compress")
                    .font(.headline)
                    .foregroundStyle(DS.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("A smaller copy, the same length. Nothing changes until you clear the bin.")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                row(nil)
                ForEach(CompressionLevel.allCases, id: \.self) { level in
                    Divider().overlay(DS.Palette.line)
                    row(level)
                }
            }
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
            Button("Apply", action: onApply)
                .buttonStyle(.pill(.ink))
                .accessibilityIdentifier("compress.apply")
        }
        .padding(DS.Spacing.l)
    }

    private func row(_ level: CompressionLevel?) -> some View {
        let estimate = level.flatMap { estimates?[$0] }
        let isSmall = estimate?.isAlreadySmall ?? false
        let isChosen = choice == level
        return Button { onChoose(level) } label: {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(DS.Palette.ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level?.title ?? "None")
                        .font(.body.weight(.semibold))
                    if let caption = Self.caption(level) {
                        Text(caption)
                            .font(.footnote)
                    }
                }
                Spacer(minLength: DS.Spacing.xs)
                Text(result(level, estimate: estimate))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(DS.Palette.ink)
            .padding(.horizontal, DS.Spacing.m)
            .frame(minHeight: DS.Tap.minimum + DS.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSmall || (level != nil && estimates == nil))
        .opacity(isSmall ? 0.4 : 1)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityIdentifier("compress.\(level?.rawValue ?? "none")")
    }

    /// "380 MB → ~120 MB", "Already small", or the size None keeps.
    private func result(_ level: CompressionLevel?, estimate: CompressionEstimate?) -> String {
        guard level != nil else { return Format.size(trimmedBytes) }
        guard let estimate else { return "…" }
        if estimate.isAlreadySmall { return "Already small" }
        return "\(Format.size(estimate.trimmedBytes)) → ~\(Format.size(estimate.compressedBytes))"
    }

    static func caption(_ level: CompressionLevel?) -> String? {
        switch level {
        case nil: "Original quality"
        case .light: "Looks the same"
        case .balanced: nil
        case .max: "Fine on a phone"
        }
    }
}

#if DEBUG
#Preview {
    let estimate = { (bytes: Int64, small: Bool) in
        CompressionEstimate(trimmedBytes: 380_000_000, compressedBytes: bytes, isAlreadySmall: small)
    }
    Color.black.sheet(isPresented: .constant(true)) {
        CompressionSheet(trimmedBytes: 380_000_000,
                         estimates: [.light: estimate(228_000_000, false), .balanced: estimate(120_000_000, false), .max: estimate(360_000_000, true)],
                         choice: .balanced, onChoose: { _ in }, onApply: {})
            .presentationDetents([.medium])
    }
}

#Preview("XXL") {
    Color.black.sheet(isPresented: .constant(true)) {
        CompressionSheet(trimmedBytes: 380_000_000, estimates: nil, choice: nil, onChoose: { _ in }, onApply: {})
            .presentationDetents([.large])
            .dynamicTypeSize(.xxLarge)
    }
}
#endif
