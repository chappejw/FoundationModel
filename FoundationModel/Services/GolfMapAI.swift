import CoreLocation
import Foundation
import FoundationModels
import MapKit

@Generable
struct ODRSFMapSpec {
    @Guide(description: "ODRSF golf course ids that should appear in the carousel", .minimumCount(1), .maximumCount(5))
    var selectedCourseIDs: [String]

    @Guide(description: "Nearby ODRSF amenity ids to emphasize on the selected course map", .maximumCount(16))
    var selectedAmenityIDs: [String]

    @Guide(description: "The synthetic golf hole to preview", .range(1...18))
    var highlightedHole: Int

    @Guide(description: "Initial map center latitude")
    var latitude: Double

    @Guide(description: "Initial map center longitude")
    var longitude: Double

    @Guide(description: "Initial map latitude span", .range(0.006...0.18))
    var latitudeDelta: Double

    @Guide(description: "Initial map longitude span", .range(0.006...0.18))
    var longitudeDelta: Double

    @Guide(description: "Map style: map, satellite, or hybrid")
    var mapStyle: String

    @Guide(description: "Facility type ids that should be active as filters", .maximumCount(8))
    var activeFacilityTypes: [String]

    @Guide(description: "Short labels explaining ranked amenities", .maximumCount(8))
    var rankingLabels: [String]

    @Guide(description: "One concise professional sentence explaining the generated map")
    var summary: String
}

struct RankedAmenity: Identifiable, Hashable {
    let facility: ODRSFFacility
    let rank: Int
    let distanceFromCourseMiles: Double
    let distanceFromUserMiles: Double?
    let reason: String

    var id: String { facility.id }
}

enum ODRSFMapRanker {
    static let defaultRadiusMiles = 2.0
    static let maximumVisibleAmenities = 72

    static func courses(
        matching searchText: String,
        courses: [GolfCourse],
        userLocation: CLLocation?,
        limit: Int = 5
    ) -> [GolfCourse] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = courses.filter { course in
            query.isEmpty
                || course.name.lowercased().contains(query)
                || course.city.lowercased().contains(query)
                || course.region.lowercased().contains(query)
                || course.address.lowercased().contains(query)
                || course.displayType.lowercased().contains(query)
                || (course.provider ?? "").lowercased().contains(query)
        }

        return Array(filtered.sorted { lhs, rhs in
            switch (lhs.distanceMiles(from: userLocation), rhs.distanceMiles(from: userLocation)) {
            case let (lhs?, rhs?):
                lhs < rhs
            case (_?, nil):
                true
            case (nil, _?):
                false
            case (nil, nil):
                lhs.name < rhs.name
            }
        }.prefix(limit))
    }

    static func rankedAmenities(
        around course: GolfCourse,
        facilities: [ODRSFFacility],
        userLocation: CLLocation?,
        activeTypes: Set<String>,
        selectedAmenityIDs: [String] = [],
        radiusMiles: Double = defaultRadiusMiles,
        limit: Int = maximumVisibleAmenities
    ) -> [RankedAmenity] {
        let courseLocation = course.location
        let selectedIDSet = Set(selectedAmenityIDs)
        let candidates = facilities.compactMap { facility -> (ODRSFFacility, Double, Double)? in
            guard facility.id != course.id else { return nil }
            guard activeTypes.isEmpty || activeTypes.contains(facility.facilityType) else { return nil }
            let distanceFromCourse = facility.location.distance(from: courseLocation) / 1_609.344
            guard distanceFromCourse <= radiusMiles || selectedIDSet.contains(facility.id) else { return nil }

            let score = score(
                facility: facility,
                distanceFromCourseMiles: distanceFromCourse,
                isSelected: selectedIDSet.contains(facility.id)
            )
            return (facility, distanceFromCourse, score)
        }
        .sorted { lhs, rhs in
            if lhs.2 == rhs.2 {
                return lhs.1 < rhs.1
            }
            return lhs.2 > rhs.2
        }
        .prefix(limit)

        return candidates.enumerated().map { index, candidate in
            RankedAmenity(
                facility: candidate.0,
                rank: index + 1,
                distanceFromCourseMiles: candidate.1,
                distanceFromUserMiles: candidate.0.distanceMiles(from: userLocation),
                reason: reason(for: candidate.0, rank: index + 1, distance: candidate.1)
            )
        }
    }

    static func region(for course: GolfCourse, amenities: [RankedAmenity]) -> MKCoordinateRegion {
        let coordinates = [course.coordinate] + amenities.prefix(20).map(\.facility.coordinate)
        return MKCoordinateRegion.bounding(coordinates: coordinates, padding: 1.45)
    }

    static func fallbackSpec(
        for allCourses: [GolfCourse],
        facilities: [ODRSFFacility],
        selectedCourseID: String?,
        searchText: String,
        hole: Int,
        userLocation: CLLocation?,
        activeTypes: Set<String>
    ) -> ODRSFMapSpec {
        let courseMatches = courses(
            matching: searchText,
            courses: allCourses,
            userLocation: userLocation,
            limit: 5
        )
        let preferred = selectedCourseID.flatMap { id in allCourses.first(where: { $0.id == id }) }
        let selected = Array(([preferred].compactMap { $0 } + courseMatches + allCourses).uniquedByID().prefix(3))
        let firstCourse = selected.first ?? allCourses.first
        let ranked: [RankedAmenity]
        let region: MKCoordinateRegion?
        if let firstCourse {
            ranked = rankedAmenities(around: firstCourse, facilities: facilities, userLocation: userLocation, activeTypes: activeTypes, limit: 12)
            region = Self.region(for: firstCourse, amenities: ranked)
        } else {
            ranked = []
            region = nil
        }

        return ODRSFMapSpec(
            selectedCourseIDs: selected.map(\.id),
            selectedAmenityIDs: ranked.prefix(12).map(\.facility.id),
            highlightedHole: min(max(hole, 1), 18),
            latitude: region?.center.latitude ?? firstCourse?.latitude ?? 0,
            longitude: region?.center.longitude ?? firstCourse?.longitude ?? 0,
            latitudeDelta: region?.span.latitudeDelta ?? 0.04,
            longitudeDelta: region?.span.longitudeDelta ?? 0.04,
            mapStyle: "hybrid",
            activeFacilityTypes: Array(activeTypes.prefix(8)),
            rankingLabels: ranked.prefix(6).map { "#\($0.rank) \($0.facility.displayType)" },
            summary: "Showing ODRSF golf facilities with nearby amenities ranked from local distance and facility data."
        )
    }

    private static func score(facility: ODRSFFacility, distanceFromCourseMiles: Double, isSelected: Bool) -> Double {
        let typeBoost: Double = switch ODRSFFacilityType(rawValue: facility.facilityType) {
        case .park, .trail: 8
        case .communityCentre, .pool, .gym, .sportsField: 6
        case .beach, .marina, .athleticPark: 5
        case .rink, .arena, .stadium, .playground: 4
        case .splashPad, .skatePark, .raceTrack, .casino, .miscellaneous, nil: 2
        }
        let completeness = (facility.address.isEmpty ? 0 : 1.5) + (facility.name.hasPrefix("Facility in") ? 0 : 1.0)
        let distanceScore = max(0, 20 - distanceFromCourseMiles * 7)
        return distanceScore + typeBoost + completeness + (isSelected ? 10 : 0)
    }

    private static func reason(for facility: ODRSFFacility, rank: Int, distance: Double) -> String {
        if rank == 1 {
            return "Closest high-quality nearby \(facility.displayType.lowercased()) for the selected course."
        }
        if distance < 0.5 {
            return "Very close to the course and useful for local context."
        }
        return "Ranked for type variety, distance, and ODRSF data completeness."
    }
}

struct SearchODRSFCoursesTool: Tool {
    let name = "search_odrsf_courses"
    let description = "Search ODRSF-only Canadian golf facilities by name, municipality, province, provider, address, or optional GPS coordinates."
    let courses: [GolfCourse]

    @Generable
    struct Arguments {
        @Guide(description: "Search text such as a course, municipality, province, provider, or address")
        var query: String

        @Guide(description: "Optional current latitude. Use 999 when unknown.")
        var latitude: Double

        @Guide(description: "Optional current longitude. Use 999 when unknown.")
        var longitude: Double
    }

    func call(arguments: Arguments) async throws -> String {
        let location = location(latitude: arguments.latitude, longitude: arguments.longitude)
        let matched = ODRSFMapRanker.courses(matching: arguments.query, courses: courses, userLocation: location)
        let lines = matched.map { course in
            let distance = course.distanceMiles(from: location).map { String(format: "%.1f mi from user", $0) } ?? "user distance unknown"
            return "\(course.id): \(course.name), \(course.displayLocation), \(course.displayType), \(distance)"
        }
        return lines.isEmpty ? "No ODRSF golf courses matched." : lines.joined(separator: "\n")
    }

    private func location(latitude: Double, longitude: Double) -> CLLocation? {
        if abs(latitude) <= 90, abs(longitude) <= 180 {
            CLLocation(latitude: latitude, longitude: longitude)
        } else {
            nil
        }
    }
}

struct FindNearbyODRSFAmenitiesTool: Tool {
    let name = "find_nearby_amenities"
    let description = "Find deterministic nearby ODRSF amenities around an ODRSF golf course."
    let courses: [GolfCourse]
    let facilities: [ODRSFFacility]

    @Generable
    struct Arguments {
        @Guide(description: "The course id returned by search_odrsf_courses")
        var courseID: String

        @Guide(description: "Radius in miles from the selected golf course", .range(0.5...5.0))
        var radiusMiles: Double

        @Guide(description: "Facility type ids to include, or an empty array for all types", .maximumCount(10))
        var facilityTypes: [String]

        @Guide(description: "Optional current latitude. Use 999 when unknown.")
        var latitude: Double

        @Guide(description: "Optional current longitude. Use 999 when unknown.")
        var longitude: Double
    }

    func call(arguments: Arguments) async throws -> String {
        guard let course = courses.first(where: { $0.id == arguments.courseID }) else {
            return "Course not found: \(arguments.courseID)"
        }

        let userLocation = location(latitude: arguments.latitude, longitude: arguments.longitude)
        let ranked = ODRSFMapRanker.rankedAmenities(
            around: course,
            facilities: facilities,
            userLocation: userLocation,
            activeTypes: Set(arguments.facilityTypes),
            radiusMiles: arguments.radiusMiles,
            limit: 16
        )

        let lines = ranked.prefix(12).map { amenity in
            let userDistance = amenity.distanceFromUserMiles.map { String(format: "%.1f mi from user", $0) } ?? "user distance unknown"
            return "#\(amenity.rank) \(amenity.facility.id): \(amenity.facility.name), \(amenity.facility.displayType), \(String(format: "%.1f", amenity.distanceFromCourseMiles)) mi from course, \(userDistance), \(amenity.reason)"
        }
        return lines.isEmpty ? "No nearby ODRSF amenities matched." : lines.joined(separator: "\n")
    }

    private func location(latitude: Double, longitude: Double) -> CLLocation? {
        if abs(latitude) <= 90, abs(longitude) <= 180 {
            CLLocation(latitude: latitude, longitude: longitude)
        } else {
            nil
        }
    }
}

struct RankODRSFMapCandidatesTool: Tool {
    let name = "rank_map_candidates"
    let description = "Summarize deterministic ODRSF amenity rankings for a course so the model can choose a concise presentation."
    let courses: [GolfCourse]
    let facilities: [ODRSFFacility]

    @Generable
    struct Arguments {
        @Guide(description: "The selected ODRSF course id")
        var courseID: String

        @Guide(description: "Amenity ids to summarize", .maximumCount(16))
        var amenityIDs: [String]
    }

    func call(arguments: Arguments) async throws -> String {
        guard let course = courses.first(where: { $0.id == arguments.courseID }) else {
            return "Course not found: \(arguments.courseID)"
        }

        let selected = facilities.filter { arguments.amenityIDs.contains($0.id) }
        let ranked = ODRSFMapRanker.rankedAmenities(
            around: course,
            facilities: selected,
            userLocation: nil,
            activeTypes: [],
            selectedAmenityIDs: arguments.amenityIDs,
            radiusMiles: 5,
            limit: 16
        )

        let lines = ranked.prefix(12).map { amenity in
            "#\(amenity.rank) \(amenity.facility.name) [\(amenity.facility.id)] - \(amenity.facility.displayType), \(String(format: "%.1f", amenity.distanceFromCourseMiles)) mi, \(amenity.reason)"
        }
        return lines.isEmpty ? "No ranked ODRSF amenities to summarize." : lines.joined(separator: "\n")
    }
}

private extension Array where Element == GolfCourse {
    func uniquedByID() -> [GolfCourse] {
        var seen: Set<String> = []
        return filter { course in
            seen.insert(course.id).inserted
        }
    }
}
