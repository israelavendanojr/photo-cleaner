import CoreLocation
import Foundation

/// Looks up a short place name ("Santa Monica") for a location. `CLGeocoding` asks Apple; tests use a fake.
protocol Geocoding: Sendable {
    /// A short name for `location`, or nil if none arrives within `timeout`.
    func placeName(for location: CLLocation, timeout: Duration) async -> String?
}

/// Turns coordinates into short place names ("Santa Monica") for card captions.
///
/// Reverse geocoding is a network call to Apple, so only the centre of a ~1 km cell is ever sent,
/// never a photo's own coordinate. The privacy copy ("approximate locations") depends on this.
/// It's also rate-limited, so lookups are cached per cell, run one at a time, and stop at a time
/// budget. Anything unresolved simply has no name.
actor PlaceNamer {
    /// About 1.1 km of latitude per cell.
    struct Cell: Hashable {
        let lat: Int
        let lon: Int

        init(_ location: CLLocation) {
            lat = Int((location.coordinate.latitude * 100).rounded())
            lon = Int((location.coordinate.longitude * 100).rounded())
        }

        /// What's sent to the geocoder: the cell's centre, never more than about 0.8 km from a photo in it.
        var center: CLLocation {
            CLLocation(latitude: Double(lat) / 100, longitude: Double(lon) / 100)
        }
    }

    private let geocoder: any Geocoding
    private var cache: [Cell: String] = [:]

    init(geocoder: any Geocoding = CLGeocoding()) {
        self.geocoder = geocoder
    }

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
            if let name = await geocoder.placeName(for: cell.center, timeout: remaining) {
                cache[cell] = name
            }
        }
        return locations.compactMapValues { cache[Cell($0)] }
    }
}

/// Apple's reverse geocoder, which needs the network. One `CLGeocoder`, used one lookup at a time
/// by `PlaceNamer`.
final class CLGeocoding: Geocoding, @unchecked Sendable {
    private let geocoder = CLGeocoder()

    func placeName(for location: CLLocation, timeout: Duration) async -> String? {
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
