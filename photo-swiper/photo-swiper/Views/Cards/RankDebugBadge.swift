import SwiftUI

extension View {
    /// Debug builds only: the ranker's score breakdown in the card's top trailing corner.
    /// Turn it off with the launch argument `-debug.showRankScores NO`.
    func rankDebugBadge(for item: LibraryItem) -> some View {
        #if DEBUG
        overlay(alignment: .topTrailing) { RankDebugBadge(item: item) }
        #else
        self
        #endif
    }
}

#if DEBUG
/// Why the ranker placed this card where it did, plus any raw image signals. Items without features
/// (mock data) show nothing.
private struct RankDebugBadge: View {
    let item: LibraryItem
    @AppStorage("debug.showRankScores") private var isOn = true

    var body: some View {
        if isOn, let features = item.features {
            let breakdown = FeedRanker().score(features, now: .now)
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.2f", breakdown.total)).bold()
                ForEach(breakdown.parts, id: \.name) { part in
                    Text("\(part.name) \(String(format: "%+.2f", part.value))")
                }
                ForEach(signalLines(features), id: \.self) { line in
                    Text(line).opacity(0.7)
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .padding(12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Raw image signals, for tuning `ImageFlags` thresholds on a real library.
    private func signalLines(_ f: AssetFeatures) -> [String] {
        var lines: [String] = []
        if let sharpness = f.sharpness { lines.append("sharp \(Int(sharpness.rounded()))") }
        if let e = f.exposure { lines.append(String(format: "dark %.2f lit %.2f", e.darkFraction, e.brightFraction)) }
        if let aesthetic = f.aesthetic { lines.append(String(format: "aes %+.2f", aesthetic)) }
        if f.isUtility == true { lines.append("utility") }
        return lines
    }
}
#endif
