import Foundation
import MapKit

struct FavoriteLocation: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    let createdAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: UUID = UUID(), name: String, coordinate: CLLocationCoordinate2D, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.createdAt = createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FavoriteLocation, rhs: FavoriteLocation) -> Bool {
        lhs.id == rhs.id
    }
}
