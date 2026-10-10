import CoreLocation
import Foundation

/// Turns coordinates into short place names ("Santa Monica") for card captions.
///
/// Reverse geocoding is rate-limited and needs the network, so lookups are cached per ~1 km cell,
/// run one at a time, and stop at a time budget. Anything unresolved simply has no name.
actor PlaceNamer {
    /// About 1.1 km of latitude per cell.
    private struct Cell: Hashable {
        let lat: Int
        let lon: Int

        init(_ location: CLLocation) {
            lat = Int((location.coordinate.latitude * 100).rounded())
            lon = Int((location.coordinate.longitude * 100).rounded())
        }
    }

    private let geocoder = CLGeocoder()
    private var cache: [Cell: String] = [:]

    /// Names for as many of `locations` (keyed by item ID) as resolve within `budget`.
    func names(for locations: [LibraryItem.ID: CLLocation], within budget: Duration) async -> [LibraryItem.ID: String] {
        let clock = ContinuousClock()
        let deadline = clock.now + budget
        var tried = Set<Cell>()
        for location in locations.values {
            let cell = Cell(location)
            guard cache[cell] == nil, tried.insert(cell).inserted else { continue }
            let remaining = deadline - clock.now
            guard remaining > .zero else { break }
            if let name = await geocode(location, timeout: remaining) {
                cache[cell] = name
            }
        }
        return locations.compactMapValues { cache[Cell($0)] }
    }

    private func geocode(_ location: CLLocation, timeout: Duration) async -> String? {
        let geocoder = geocoder
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let placemark = try? await geocoder.reverseGeocodeLocation(location).first
                return placemark?.locality ?? placemark?.name
            }
            group.addTask {
                guard (try? await Task.sleep(for: timeout)) != nil else { return nil }
                geocoder.cancelGeocode()
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
