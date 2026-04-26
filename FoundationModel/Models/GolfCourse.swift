import CoreLocation
import Foundation
import MapKit
import SwiftUI

struct GolfCatalogEnvelope: Decodable {
    let schemaVersion: Int
    let source: String?
    let attribution: [String]
    let courses: [GolfCourse]
}

struct ODRSFFacilityCatalogEnvelope: Decodable {
    let schemaVersion: Int
    let source: String?
    let attribution: [String]
    let facilities: [ODRSFFacility]
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
    let facilityType: String?
    let sourceFacilityType: String?
    let provider: String?
    let sourceIndex: String?
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

    var displayType: String {
        (sourceFacilityType?.isEmpty == false ? sourceFacilityType : facilityType) ?? "golf facility"
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

struct ODRSFFacility: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let facilityType: String
    let sourceFacilityType: String
    let provider: String
    let municipality: String
    let province: String
    let country: String
    let address: String
    let latitude: Double
    let longitude: Double
    let sourceIndex: String
    let isGolfFacility: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var displayLocation: String {
        [municipality, province, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var displayType: String {
        ODRSFFacilityType(rawValue: facilityType)?.title ?? facilityType.capitalized
    }

    func distanceMiles(from location: CLLocation?) -> Double? {
        guard let location else { return nil }
        return self.location.distance(from: location) / 1_609.344
    }
}

enum ODRSFFacilityType: String, CaseIterable, Identifiable, Codable, Sendable {
    case trail
    case park
    case sportsField = "sports field"
    case playground
    case pool
    case communityCentre = "community centre"
    case rink
    case splashPad = "splash pad"
    case arena
    case miscellaneous
    case gym
    case beach
    case skatePark = "skate park"
    case raceTrack = "race track"
    case marina
    case athleticPark = "athletic park"
    case stadium
    case casino

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trail: "Trails"
        case .park: "Parks"
        case .sportsField: "Sports Fields"
        case .playground: "Playgrounds"
        case .pool: "Pools"
        case .communityCentre: "Community"
        case .rink: "Rinks"
        case .splashPad: "Splash Pads"
        case .arena: "Arenas"
        case .miscellaneous: "Other"
        case .gym: "Gyms"
        case .beach: "Beaches"
        case .skatePark: "Skate Parks"
        case .raceTrack: "Race Tracks"
        case .marina: "Marinas"
        case .athleticPark: "Athletic Parks"
        case .stadium: "Stadiums"
        case .casino: "Casinos"
        }
    }

    var singularTitle: String {
        switch self {
        case .communityCentre: "Community Centre"
        case .sportsField: "Sports Field"
        case .splashPad: "Splash Pad"
        case .skatePark: "Skate Park"
        case .raceTrack: "Race Track"
        case .athleticPark: "Athletic Park"
        default: title.trimmingCharacters(in: CharacterSet(charactersIn: "s"))
        }
    }

    var symbolName: String {
        switch self {
        case .trail: "figure.hiking"
        case .park: "tree"
        case .sportsField: "sportscourt"
        case .playground: "figure.play"
        case .pool: "figure.pool.swim"
        case .communityCentre: "building.2"
        case .rink: "snowflake"
        case .splashPad: "drop"
        case .arena: "building.columns"
        case .miscellaneous: "mappin"
        case .gym: "dumbbell"
        case .beach: "beach.umbrella"
        case .skatePark: "figure.skating"
        case .raceTrack: "flag.2.crossed"
        case .marina: "sailboat"
        case .athleticPark: "figure.run"
        case .stadium: "sportscourt.fill"
        case .casino: "suit.club"
        }
    }

    var tint: Color {
        switch self {
        case .trail: .mint
        case .park: .green
        case .sportsField: .blue
        case .playground: .orange
        case .pool: .cyan
        case .communityCentre: .indigo
        case .rink: .teal
        case .splashPad: .blue
        case .arena: .purple
        case .miscellaneous: .gray
        case .gym: .red
        case .beach: .yellow
        case .skatePark: .pink
        case .raceTrack: .brown
        case .marina: .cyan
        case .athleticPark: .orange
        case .stadium: .purple
        case .casino: .red
        }
    }
}

enum GolfCourseCatalog {
    static func load() -> GolfCatalogEnvelope {
        guard let url = Bundle.main.url(forResource: "odrsf_golf_courses", withExtension: "json") else {
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
        schemaVersion: 2,
        source: "Fallback",
        attribution: ["ODRSF resource unavailable. Fallback point generated locally."],
        courses: [
            GolfCourse(
                id: "fallback-odrsf-course",
                name: "ODRSF Golf Facility",
                country: "CA",
                region: "BC",
                city: "Vancouver",
                address: "Fallback coordinate",
                latitude: 49.2247921,
                longitude: -123.0503412,
                boundary: nil,
                holes: [],
                facilityType: "sports field",
                sourceFacilityType: "golf course",
                provider: "Fallback",
                sourceIndex: "",
                attribution: "Fallback demo data."
            )
        ]
    )
}

enum ODRSFFacilityCatalog {
    static func load() -> ODRSFFacilityCatalogEnvelope {
        guard let url = Bundle.main.url(forResource: "odrsf_facilities", withExtension: "json") else {
            return fallback
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ODRSFFacilityCatalogEnvelope.self, from: data)
        } catch {
            return fallback
        }
    }

    private static let fallback = ODRSFFacilityCatalogEnvelope(
        schemaVersion: 1,
        source: "Fallback",
        attribution: ["ODRSF facility resource unavailable."],
        facilities: []
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
