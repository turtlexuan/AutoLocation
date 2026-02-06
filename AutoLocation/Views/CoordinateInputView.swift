import SwiftUI
import MapKit

struct CoordinateInputView: View {
    var appState: AppState

    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lat:")
                    .frame(width: 35, alignment: .trailing)
                    .font(.caption)
                TextField("Latitude", text: $latitudeText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: latitudeText) {
                        updateCoordinate()
                    }
            }
            HStack {
                Text("Lon:")
                    .frame(width: 35, alignment: .trailing)
                    .font(.caption)
                TextField("Longitude", text: $longitudeText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: longitudeText) {
                        updateCoordinate()
                    }
            }
        }
        .onChange(of: appState.targetCoordinate) { _, newValue in
            if let coord = newValue {
                let newLat = String(format: "%.6f", coord.latitude)
                let newLon = String(format: "%.6f", coord.longitude)
                if newLat != latitudeText { latitudeText = newLat }
                if newLon != longitudeText { longitudeText = newLon }
            }
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
