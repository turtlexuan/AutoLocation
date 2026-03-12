import Foundation
import MapKit

@Observable
@MainActor
final class FavoritesManager {
    private(set) var favorites: [FavoriteLocation] = []

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AutoLocation", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("favorites.json")
    }

    init() {
        load()
    }

    func add(name: String, coordinate: CLLocationCoordinate2D) {
        let favorite = FavoriteLocation(name: name, coordinate: coordinate)
        favorites.insert(favorite, at: 0)
        save()
    }

    func remove(_ favorite: FavoriteLocation) {
        favorites.removeAll { $0.id == favorite.id }
        save()
    }

    func rename(_ favorite: FavoriteLocation, to newName: String) {
        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }) else { return }
        favorites[index].name = newName
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            favorites = try JSONDecoder().decode([FavoriteLocation].self, from: data)
        } catch {
            print("Failed to load favorites: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(favorites)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save favorites: \(error)")
        }
    }
}
