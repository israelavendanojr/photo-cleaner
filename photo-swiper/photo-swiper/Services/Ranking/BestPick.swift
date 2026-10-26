import Foundation

/// Chooses the keeper of a similar group and says, truthfully, what decided it.
///
/// What the user did in Photos comes first: their favorite, then the burst frame they picked, then
/// the one they edited. Otherwise the frame with the best mix of sharpness, exposure, and Vision's
/// aesthetics score wins. The reason names the first of those that set the winner apart, and a
/// quality reason is only given when the winner really is the best of the whole set on it. Nothing
/// is claimed that isn't measured. Pure, so tests pin every reason.
enum BestPick {
    struct Weights: Sendable, Equatable {
        var sharpness = 1.0
        var aesthetic = 0.8
        var exposure = 0.6
    }

    enum Reason: String, Sendable, CaseIterable {
        case favorite = "Your favorite"
        case burstPick = "Your burst pick"
        case edited = "The one you edited"
        case sharpest = "Sharpest of the set"
        case exposure = "Best exposure"
        case aesthetic = "Highest-rated shot"
        /// Won on the mix of signals without topping the set on any single one.
        case overall = "Best of the set overall"
    }

    struct Choice: Hashable, Sendable {
        let bestID: LibraryItem.ID
        let reason: Reason
    }

    /// Nil for fewer than two members, or when two or more are favorites: the user already chose
    /// more than one keeper, so those photos stay single cards.
    static func choose(_ members: [RankCandidate], weights: Weights = Weights()) -> Choice? {
        guard members.count > 1, members.filter(\.features.isFavorite).count < 2 else { return nil }
        let quality = Quality(members, weights: weights)

        // The user's own signals, in order. Each narrows the contenders; the one that leaves a single
        // contender is the reason.
        let userSignals: [(Reason, (AssetFeatures) -> Bool)] = [
            (.favorite, \.isFavorite),
            (.burstPick, { $0.isUserBurstPick == true }),
            (.edited, \.hasAdjustments),
        ]
        var contenders = members
        for (reason, signal) in userSignals {
            let marked = contenders.filter { signal($0.features) }
            guard !marked.isEmpty else { continue }
            if marked.count == 1 { return Choice(bestID: marked[0].id, reason: reason) }
            contenders = marked
        }

        let ranked = contenders.sorted { a, b in
            let qa = quality.total(a.id), qb = quality.total(b.id)
            if qa != qb { return qa > qb }
            if a.features.createdAt != b.features.createdAt { return a.features.createdAt > b.features.createdAt }
            return a.id < b.id
        }
        let winner = ranked[0], runnerUp = ranked[1]
        return Choice(bestID: winner.id, reason: quality.reason(winner: winner.id, over: runnerUp.id))
    }
}

/// Each member's quality, from signals scaled 0...1 across the group so they weigh comparably.
private struct Quality {
    private enum Component: CaseIterable {
        case sharpness, exposure, aesthetic

        var reason: BestPick.Reason {
            switch self {
            case .sharpness: .sharpest
            case .exposure: .exposure
            case .aesthetic: .aesthetic
            }
        }
    }

    /// Scaled value per component and member. A component is left out when any member lacks it, so a
    /// missing signal never counts for or against anyone.
    private var scaled: [Component: [LibraryItem.ID: Double]] = [:]
    private var raw: [Component: [LibraryItem.ID: Double]] = [:]
    private let weights: BestPick.Weights

    init(_ members: [RankCandidate], weights: BestPick.Weights) {
        self.weights = weights
        for component in Component.allCases {
            let values = members.compactMap { member in Self.value(component, member.features).map { (member.id, $0) } }
            guard values.count == members.count else { continue }
            let low = values.map(\.1).min() ?? 0, high = values.map(\.1).max() ?? 0
            raw[component] = Dictionary(uniqueKeysWithValues: values)
            scaled[component] = Dictionary(uniqueKeysWithValues: values.map { ($0.0, high > low ? ($0.1 - low) / (high - low) : 0) })
        }
    }

    func total(_ id: LibraryItem.ID) -> Double {
        Component.allCases.reduce(0) { $0 + weight($1) * (scaled[$1]?[id] ?? 0) }
    }

    /// The component that did the most to put `winner` ahead of `runnerUp`, provided the winner tops
    /// the whole set on it. Falls back to the next biggest, then to `.overall`.
    func reason(winner: LibraryItem.ID, over runnerUp: LibraryItem.ID) -> BestPick.Reason {
        let leads: [(component: Component, lead: Double)] = Component.allCases.map { component in
            let values = scaled[component] ?? [:]
            let lead: Double = weight(component) * ((values[winner] ?? 0) - (values[runnerUp] ?? 0))
            return (component, lead)
        }
        for (component, _) in leads.filter({ $0.lead > 0 }).sorted(by: { $0.lead > $1.lead }) {
            guard let values = raw[component], let best = values[winner] else { continue }
            if values.allSatisfy({ $0.key == winner || $0.value < best }) { return component.reason }
        }
        return .overall
    }

    private func weight(_ component: Component) -> Double {
        switch component {
        case .sharpness: weights.sharpness
        case .exposure: weights.exposure
        case .aesthetic: weights.aesthetic
        }
    }

    /// Higher is better for every component.
    private static func value(_ component: Component, _ features: AssetFeatures) -> Double? {
        switch component {
        case .sharpness:
            // Laplacian variance spans orders of magnitude; its log tracks how sharp a frame looks.
            features.sharpness.map { log1p(max($0, 0)) }
        case .exposure:
            // Crushed or blown pixels, and a mean far from mid-gray, all count against a frame.
            features.exposure.map { 1 - $0.darkFraction - $0.brightFraction - abs($0.mean - 0.45) }
        case .aesthetic:
            features.aesthetic
        }
    }
}
