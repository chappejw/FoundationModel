import Foundation

enum GolfDatasetCountry: String, CaseIterable, Identifiable {
    case unitedStates = "United States"
    case canada = "Canada"

    var id: String { rawValue }

    var isoCode: String {
        switch self {
        case .unitedStates: "US"
        case .canada: "CA"
        }
    }
}

struct DownloadedGolfCourse {
    let sourceID: String
    let name: String
    let address: String
    let phoneNumber: String
    let stateOrProvince: String
    let country: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
}

enum OverpassGolfCourseServiceError: LocalizedError {
    case badResponse

    var errorDescription: String? {
        switch self {
        case .badResponse:
            "Unable to parse golf course data from Overpass API."
        }
    }
}

struct OverpassGolfCourseService {
    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    func downloadCourses(for country: GolfDatasetCountry) async throws -> [DownloadedGolfCourse] {
        let query = """
        [out:json][timeout:1800];
        area["ISO3166-1"="\(country.isoCode)"]["admin_level"="2"]->.searchArea;
        (
          node["golf"="course"](area.searchArea);
          way["golf"="course"](area.searchArea);
          relation["golf"="course"](area.searchArea);
        );
        out center tags;
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw OverpassGolfCourseServiceError.badResponse
        }

        let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)

        return decoded.elements.compactMap { element in
            guard
                let tags = element.tags,
                let name = tags["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty
            else {
                return nil
            }

            let latitude = element.lat ?? element.center?.lat
            let longitude = element.lon ?? element.center?.lon

            guard let latitude, let longitude else {
                return nil
            }

            let street = [tags["addr:housenumber"], tags["addr:street"]]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            let locality = [tags["addr:city"], tags["addr:state"], tags["addr:postcode"]]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")

            let address = [street, locality]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")

            let phone = tags["phone"] ?? tags["contact:phone"] ?? ""
            let stateOrProvince = tags["addr:state"] ?? tags["addr:province"] ?? tags["is_in:state"] ?? ""

            return DownloadedGolfCourse(
                sourceID: "\(element.type)-\(element.id)",
                name: name,
                address: address,
                phoneNumber: phone,
                stateOrProvince: stateOrProvince,
                country: country.rawValue,
                countryCode: country.isoCode,
                latitude: latitude,
                longitude: longitude
            )
        }
    }
}

private struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

private struct OverpassElement: Decodable {
    let type: String
    let id: Int64
    let lat: Double?
    let lon: Double?
    let center: OverpassCenter?
    let tags: [String: String]?
}

private struct OverpassCenter: Decodable {
    let lat: Double
    let lon: Double
}
