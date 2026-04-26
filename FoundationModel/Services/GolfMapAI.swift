import CoreLocation
import Foundation
import FoundationModels

@Generable
struct GolfMapSpec {
    @Guide(description: "Course ids that should appear in the carousel", .minimumCount(1), .maximumCount(5))
    var selectedCourseIDs: [String]

    @Guide(description: "The golf hole to highlight", .range(1...18))
    var highlightedHole: Int

    @Guide(description: "Initial map center latitude")
    var latitude: Double

    @Guide(description: "Initial map center longitude")
    var longitude: Double

    @Guide(description: "Initial map latitude span", .range(0.002...1.0))
    var latitudeDelta: Double

    @Guide(description: "Initial map longitude span", .range(0.002...1.0))
    var longitudeDelta: Double

    @Guide(description: "Short labels for the most important course annotations", .maximumCount(6))
    var annotationLabels: [String]

    @Guide(description: "One concise sentence explaining why these maps are useful for the player")
    var summary: String
}

struct SearchGolfCoursesTool: Tool {
    let name = "search_golf_courses"
    let description = "Search the bundled golf course catalog by course name, city, region, country, address, or optional GPS coordinates."
    let courses: [GolfCourse]

    @Generable
    struct Arguments {
        @Guide(description: "Search text such as a course, city, province, state, country, or address")
        var query: String

        @Guide(description: "Optional current latitude. Use 999 when unknown.")
        var latitude: Double

        @Guide(description: "Optional current longitude. Use 999 when unknown.")
        var longitude: Double
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let location: CLLocation?
        if abs(arguments.latitude) <= 90, abs(arguments.longitude) <= 180 {
            location = CLLocation(latitude: arguments.latitude, longitude: arguments.longitude)
        } else {
            location = nil
        }

        let matched = courses
            .filter { course in
                query.isEmpty
                    || course.name.lowercased().contains(query)
                    || course.city.lowercased().contains(query)
                    || course.region.lowercased().contains(query)
                    || course.country.lowercased().contains(query)
                    || course.address.lowercased().contains(query)
            }
            .sorted { lhs, rhs in
                switch (lhs.distanceMiles(from: location), rhs.distanceMiles(from: location)) {
                case let (lhs?, rhs?):
                    lhs < rhs
                case (_?, nil):
                    true
                case (nil, _?):
                    false
                case (nil, nil):
                    lhs.name < rhs.name
                }
            }
            .prefix(5)

        return matched.map { course in
            let distance = course.distanceMiles(from: location).map { String(format: "%.1f mi", $0) } ?? "distance unknown"
            return "\(course.id): \(course.name), \(course.displayLocation), \(distance)"
        }.joined(separator: "\n")
    }
}

struct GetGolfCourseDetailTool: Tool {
    let name = "get_course_detail"
    let description = "Get location, address, available hole numbers, and attribution for a bundled golf course."
    let courses: [GolfCourse]

    @Generable
    struct Arguments {
        @Guide(description: "The course id from search_golf_courses")
        var courseID: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let course = courses.first(where: { $0.id == arguments.courseID }) else {
            return "Course not found: \(arguments.courseID)"
        }

        let holes = course.holes.map { hole in
            "hole \(hole.number) par \(hole.par.map(String.init) ?? "?")"
        }.joined(separator: ", ")

        return """
        id: \(course.id)
        name: \(course.name)
        address: \(course.address)
        location: \(course.latitude), \(course.longitude)
        known holes: \(holes.isEmpty ? "none; synthetic hole preview is available" : holes)
        attribution: \(course.attribution)
        """
    }
}

struct GetGolfCourseWeatherTool: Tool {
    let name = "get_course_weather"
    let description = "Get current or fallback demo weather for a bundled golf course."
    let courses: [GolfCourse]

    @Generable
    struct Arguments {
        @Guide(description: "The course id from search_golf_courses")
        var courseID: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let course = courses.first(where: { $0.id == arguments.courseID }) else {
            return "Course not found: \(arguments.courseID)"
        }

        let weather = await GolfWeatherService.currentWeather(for: course)
        return "\(weather.temperatureText), wind \(weather.windText), source \(weather.source)"
    }
}

enum GolfMapSpecFactory {
    static func fallbackSpec(for courses: [GolfCourse], selectedCourseID: String?, hole: Int, location: CLLocation?) -> GolfMapSpec {
        let sorted = courses.sorted { lhs, rhs in
            switch (lhs.distanceMiles(from: location), rhs.distanceMiles(from: location)) {
            case let (lhs?, rhs?):
                lhs < rhs
            case (_?, nil):
                true
            case (nil, _?):
                false
            case (nil, nil):
                lhs.name < rhs.name
            }
        }

        let preferred = selectedCourseID.flatMap { id in courses.first(where: { $0.id == id }) }
        let selected = ([preferred].compactMap { $0 } + sorted).uniquedByID().prefix(3)
        let firstCourse = selected.first ?? courses.first
        let region = firstCourse?.mapRegion(for: hole)

        return GolfMapSpec(
            selectedCourseIDs: selected.map(\.id),
            highlightedHole: min(max(hole, 1), 18),
            latitude: region?.center.latitude ?? firstCourse?.latitude ?? 0,
            longitude: region?.center.longitude ?? firstCourse?.longitude ?? 0,
            latitudeDelta: region?.span.latitudeDelta ?? 0.02,
            longitudeDelta: region?.span.longitudeDelta ?? 0.02,
            annotationLabels: ["Tee", "Green", "Current hole"],
            summary: "Showing nearby course maps with a deterministic local fallback while the on-device model is unavailable."
        )
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
