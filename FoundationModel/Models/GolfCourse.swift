import Foundation
import SwiftData
import CoreLocation

@Model
final class GolfCourse {
    @Attribute(.unique) var sourceID: String
    var name: String
    var address: String
    var phoneNumber: String
    var stateOrProvince: String
    var country: String
    var countryCode: String
    var latitude: Double
    var longitude: Double
    var lastUpdatedAt: Date

    init(
        sourceID: String,
        name: String,
        address: String,
        phoneNumber: String,
        stateOrProvince: String,
        country: String,
        countryCode: String,
        latitude: Double,
        longitude: Double,
        lastUpdatedAt: Date = .now
    ) {
        self.sourceID = sourceID
        self.name = name
        self.address = address
        self.phoneNumber = phoneNumber
        self.stateOrProvince = stateOrProvince
        self.country = country
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.lastUpdatedAt = lastUpdatedAt
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@Model
final class GolfCourseSyncState {
    @Attribute(.unique) var countryCode: String
    var lastSyncedAt: Date

    init(countryCode: String, lastSyncedAt: Date = .distantPast) {
        self.countryCode = countryCode
        self.lastSyncedAt = lastSyncedAt
    }
}
