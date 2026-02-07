import SwiftUI
import MapKit

struct CoordinateInputView: View {
    var appState: AppState

    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""
    @FocusState private var latFocused: Bool
    @FocusState private var lonFocused: Bool

    /// Tracks whether the user is actively editing, to avoid reformatting mid-type.
    private var isEditing: Bool { latFocused || lonFocused }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lat:")
                    .frame(width: 35, alignment: .trailing)
                    .font(.caption)
                TextField("Latitude", text: $latitudeText)
                    .textFieldStyle(.roundedBorder)
                    .focused($latFocused)
                    .onSubmit { updateCoordinate() }
            }
            HStack {
                Text("Lon:")
                    .frame(width: 35, alignment: .trailing)
                    .font(.caption)
                TextField("Longitude", text: $longitudeText)
                    .textFieldStyle(.roundedBorder)
                    .focused($lonFocused)
                    .onSubmit { updateCoordinate() }
            }
        }
        .onChange(of: latFocused) { _, focused in
            if !focused { updateCoordinate() }
        }
        .onChange(of: lonFocused) { _, focused in
            if !focused { updateCoordinate() }
        }
        .onChange(of: appState.targetCoordinate) { _, newValue in
            guard !isEditing, let coord = newValue else { return }
            let newLat = String(format: "%.6f", coord.latitude)
            let newLon = String(format: "%.6f", coord.longitude)
            if newLat != latitudeText { latitudeText = newLat }
            if newLon != longitudeText { longitudeText = newLon }
        }
    }

    private func updateCoordinate() {
        guard let lat = Double(latitudeText),
              let lon = Double(longitudeText),
              (-90...90).contains(lat),
              (-180...180).contains(lon) else { return }
        appState.targetCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
