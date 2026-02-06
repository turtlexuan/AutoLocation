import Foundation
import MapKit

struct Waypoint: Identifiable, Hashable, Codable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var name: String?

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, name: String? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encodeIfPresent(name, forKey: .name)
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Waypoint, rhs: Waypoint) -> Bool {
        lhs.id == rhs.id
    }
}
