import Foundation
import MapKit

@Observable
class LocationSearchService: NSObject {
    var queryFragment: String = "" {
        didSet {
            if queryFragment.isEmpty {
                completions = []
                isSearching = false
            }
            completer.queryFragment = queryFragment
        }
    }
    var completions: [MKLocalSearchCompletion] = []
    var isSearching: Bool = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest, .query]
        completer.delegate = self
    }

    @MainActor
    func search(_ completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.first?.placemark.coordinate
        } catch {
            return nil
        }
    }
}

extension LocationSearchService: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        isSearching = false
        completions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        isSearching = false
        completions = []
    }
}
