import CoreLocation
import Foundation
import Testing
@testable import photo_swiper

/// Records what would have been sent to Apple's geocoder.
private actor RecordingGeocoder: Geocoding {
    private(set) var asked: [CLLocationCoordinate2D] = []

    func placeName(for location: CLLocation, timeout: Duration) async -> String? {
        asked.append(location.coordinate)
        return "Somewhere"
    }
}

/// Place names are looked up with approximate locations only: the centre of a ~1 km cell, never a
/// photo's own coordinate (JUN-22, S-2). The privacy copy depends on this.
struct PlaceNamerTests {
    @Test func onlyTheCellCentreIsSent() async throws {
        let geocoder = RecordingGeocoder()
        let namer = PlaceNamer(geocoder: geocoder)
        let photo = CLLocation(latitude: 34.01937, longitude: -118.49123)

        let names = await namer.names(for: ["a": photo], within: .seconds(5))

        let asked = await geocoder.asked
        let sent = try #require(asked.first)
        #expect(asked.count == 1)
        #expect(abs(sent.latitude - 34.02) < 1e-9)
        #expect(abs(sent.longitude - -118.49) < 1e-9)
        #expect(names["a"] == "Somewhere")
    }

    @Test func photosInOneCellShareALookup() async {
        let geocoder = RecordingGeocoder()
        let namer = PlaceNamer(geocoder: geocoder)
        let locations = [
            "a": CLLocation(latitude: 34.01937, longitude: -118.49123),
            "b": CLLocation(latitude: 34.02210, longitude: -118.48802),
        ]

        let names = await namer.names(for: locations, within: .seconds(5))

        #expect(await geocoder.asked.count == 1)
        #expect(names == ["a": "Somewhere", "b": "Somewhere"])
    }

    @Test func noTimeLeftMeansNoLookups() async {
        let geocoder = RecordingGeocoder()
        let names = await PlaceNamer(geocoder: geocoder).names(for: ["a": CLLocation(latitude: 1, longitude: 1)], within: .zero)

        #expect(await geocoder.asked.isEmpty)
        #expect(names.isEmpty)
    }
}
