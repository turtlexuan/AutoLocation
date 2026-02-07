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
            coordinateRow(label: "Lat:", text: $latitudeText, focus: $latFocused)
            coordinateRow(label: "Lon:", text: $longitudeText, focus: $lonFocused)
        }
        .onChange(of: latFocused) { _, focused in
            if !focused { updateCoordinate() }
        }
        .onChange(of: lonFocused) { _, focused in
            if !focused { updateCoordinate() }
        }
        .onChange(of: appState.targetCoordinate) { _, newValue in
            guard !isEditing, let coord = newValue else { return }
            latitudeText = String(format: "%.6f", coord.latitude)
            longitudeText = String(format: "%.6f", coord.longitude)
        }
    }

    private func coordinateRow(label: String, text: Binding<String>, focus: FocusState<Bool>.Binding) -> some View {
        HStack {
            Text(label)
                .frame(width: 35, alignment: .trailing)
                .font(.caption)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .focused(focus)
                .onSubmit { updateCoordinate() }
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
