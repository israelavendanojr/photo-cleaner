import SwiftUI

/// The compression levels for one video (JUN-50): None, Light, Balanced and Max, each with what it would
/// make of the video after its trim ("380 MB → ~120 MB"). A level that saves too little to be worth it is
/// greyed out as "Already small". Choosing a level previews it in the viewer behind; Apply keeps it.
///
/// A frosted card in the middle of the full-screen video, in the style of the viewer's other controls,
/// rather than a system sheet: the video stays visible and live around it, so the preview and
/// press-and-hold work while choosing.
struct CompressionPopup: View {
    /// The video's size after its trim, which None keeps.
    let trimmedBytes: Int64
    /// Each level's estimate. Nil while the video's tracks are still being read.
    let estimates: [CompressionLevel: CompressionEstimate]?
    /// The highlighted choice, nil for None.
    let choice: CompressionLevel?
    let onChoose: (CompressionLevel?) -> Void
    let onApply: () -> Void
    let onClose: () -> Void

    var body: some View {
        // Hugs its rows; scrolls inside the card at large text sizes rather than running off the screen.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: DS.Popup.maxWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .environment(\.colorScheme, .dark)
        .padding(DS.Spacing.l)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .accessibilityIdentifier("compress.popup")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(alignment: .top, spacing: DS.Spacing.s) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Compress")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("A smaller copy, the same length. Nothing changes until you clear the bin.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                FrostedIconButton(systemImage: "xmark", accessibilityLabel: "Close", action: onClose)
                    .accessibilityIdentifier("compress.close")
            }
            VStack(spacing: 0) {
                row(nil)
                ForEach(CompressionLevel.allCases, id: \.self) { level in
                    Divider().overlay(.white.opacity(0.15))
                    row(level)
                }
            }
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
            Button("Apply", action: onApply)
                .buttonStyle(TrimButtonStyle(isPrimary: true))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("compress.apply")
        }
        .foregroundStyle(.white)
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
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level?.title ?? "None")
                        .font(.body.weight(.semibold))
                    if let caption = Self.caption(level) {
                        Text(caption)
                            .font(.footnote)
                            .opacity(0.8)
                    }
                }
                Spacer(minLength: DS.Spacing.xs)
                Text(result(level, estimate: estimate))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(.white)
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
    Color.gray.ignoresSafeArea().overlay {
        CompressionPopup(trimmedBytes: 380_000_000,
                         estimates: [.light: estimate(228_000_000, false), .balanced: estimate(120_000_000, false), .max: estimate(360_000_000, true)],
                         choice: .balanced, onChoose: { _ in }, onApply: {}, onClose: {})
    }
}

#Preview("XXL") {
    Color.gray.ignoresSafeArea().overlay {
        CompressionPopup(trimmedBytes: 380_000_000, estimates: nil, choice: nil, onChoose: { _ in }, onApply: {}, onClose: {})
            .dynamicTypeSize(.xxLarge)
    }
}
#endif
