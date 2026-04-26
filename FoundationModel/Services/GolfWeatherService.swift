import CoreLocation
import Foundation
import WeatherKit

struct GolfWeatherSnapshot: Codable, Hashable, Sendable {
    let temperatureFahrenheit: Double
    let windSpeedMilesPerHour: Double
    let windDirectionDegrees: Double
    let windCompassDirection: String
    let source: String

    var temperatureText: String {
        "\(Int(temperatureFahrenheit.rounded()))F"
    }

    var windText: String {
        "\(Int(windSpeedMilesPerHour.rounded())) mph \(windCompassDirection)"
    }
}

enum GolfWeatherService {
    static func currentWeather(for course: GolfCourse) async -> GolfWeatherSnapshot {
        do {
            let service = WeatherService.shared
            let weather = try await service.weather(for: course.location)
            let current = weather.currentWeather
            let temperature = current.temperature.converted(to: .fahrenheit).value
            let windSpeed = current.wind.speed.converted(to: .milesPerHour).value
            let windDirection = current.wind.direction.converted(to: .degrees).value
            let compass = String(describing: current.wind.compassDirection).uppercased()

            return GolfWeatherSnapshot(
                temperatureFahrenheit: temperature,
                windSpeedMilesPerHour: windSpeed,
                windDirectionDegrees: windDirection,
                windCompassDirection: compass,
                source: "WeatherKit"
            )
        } catch {
            return fallbackWeather(for: course)
        }
    }

    static func fallbackWeather(for course: GolfCourse) -> GolfWeatherSnapshot {
        let seed = abs(course.id.unicodeScalars.reduce(0) { $0 + Int($1.value) })
        let temperature = 54.0 + Double(seed % 28)
        let windSpeed = 5.0 + Double(seed % 13)
        let windDirection = Double((seed * 37) % 360)
        let compass = compassDirection(for: windDirection)

        return GolfWeatherSnapshot(
            temperatureFahrenheit: temperature,
            windSpeedMilesPerHour: windSpeed,
            windDirectionDegrees: windDirection,
            windCompassDirection: compass,
            source: "Demo fallback"
        )
    }

    private static func compassDirection(for degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((degrees + 22.5).truncatingRemainder(dividingBy: 360)) / 45.0)
        return directions[max(0, min(index, directions.count - 1))]
    }
}
