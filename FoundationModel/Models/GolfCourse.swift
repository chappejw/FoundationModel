import CoreLocation
import Foundation
import MapKit

struct GolfCatalogEnvelope: Decodable {
    let schemaVersion: Int
    let attribution: [String]
    let courses: [GolfCourse]
}

struct GolfCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct GolfHole: Codable, Hashable, Identifiable, Sendable {
    let number: Int
    let par: Int?
    let tee: GolfCoordinate?
    let green: GolfCoordinate?
    let path: [GolfCoordinate]?

    var id: Int { number }
}

struct GolfCourse: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let country: String
    let region: String
    let city: String
    let address: String
    let latitude: Double
    let longitude: Double
    let boundary: [GolfCoordinate]?
    let holes: [GolfHole]
    let attribution: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var displayLocation: String {
        [city, region, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func hole(number: Int) -> GolfHole {
        if let hole = holes.first(where: { $0.number == number }) {
            return hole
        }
        return syntheticHole(number: number)
    }

    func distanceMiles(from location: CLLocation?) -> Double? {
        guard let location else { return nil }
        return self.location.distance(from: location) / 1_609.344
    }

    func mapRegion(for holeNumber: Int) -> MKCoordinateRegion {
        let hole = hole(number: holeNumber)
        let coordinates = (hole.path ?? []).map(\.coordinate)

        if coordinates.count >= 2 {
            return MKCoordinateRegion.bounding(coordinates: coordinates, padding: 1.8)
        }

        if let boundary, boundary.count >= 3 {
            return MKCoordinateRegion.bounding(coordinates: boundary.map(\.coordinate), padding: 1.15)
        }

        return MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        )
    }

    private func syntheticHole(number: Int) -> GolfHole {
        let angle = Double(number - 1) * (.pi * 2.0 / 18.0)
        let radius = 0.0024 + Double(number % 3) * 0.00035
        let tee = GolfCoordinate(
            latitude: latitude + cos(angle) * radius,
            longitude: longitude + sin(angle) * radius
        )
        let green = GolfCoordinate(
            latitude: latitude + cos(angle + 0.42) * (radius + 0.0012),
            longitude: longitude + sin(angle + 0.42) * (radius + 0.0012)
        )
        let mid = GolfCoordinate(
            latitude: (tee.latitude + green.latitude) / 2.0,
            longitude: (tee.longitude + green.longitude) / 2.0
        )
        return GolfHole(number: number, par: nil, tee: tee, green: green, path: [tee, mid, green])
    }
}

enum GolfCourseCatalog {
    static func load() -> GolfCatalogEnvelope {
        guard let url = Bundle.main.url(forResource: "golf_courses", withExtension: "json") else {
            return fallback
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(GolfCatalogEnvelope.self, from: data)
        } catch {
            return fallback
        }
    }

    private static let fallback = GolfCatalogEnvelope(
        schemaVersion: 1,
        attribution: ["Fallback demo data generated locally."],
        courses: [
            GolfCourse(
                id: "fallback-course",
                name: "Demo Links",
                country: "US",
                region: "CA",
                city: "Pebble Beach",
                address: "Demo coordinate",
                latitude: 36.5686,
                longitude: -121.9505,
                boundary: nil,
                holes: [],
                attribution: "Fallback demo data."
            )
        ]
    )
}

extension MKCoordinateRegion {
    static func bounding(coordinates: [CLLocationCoordinate2D], padding: Double) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let latitudeDelta = max((maxLatitude - minLatitude) * padding, 0.006)
        let longitudeDelta = max((maxLongitude - minLongitude) * padding, 0.006)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2.0,
                longitude: (minLongitude + maxLongitude) / 2.0
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}
