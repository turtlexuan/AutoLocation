import SwiftUI
import MapKit

struct CoordinateInputView: View {
    var appState: AppState

    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""
    @State private var isLatInvalid: Bool = false
    @State private var isLonInvalid: Bool = false
    @FocusState private var latFocused: Bool
    @FocusState private var lonFocused: Bool

    /// Tracks whether the user is actively editing, to avoid reformatting mid-type.
    private var isEditing: Bool { latFocused || lonFocused }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            coordinateRow(label: "Lat:", text: $latitudeText, focus: $latFocused, isInvalid: isLatInvalid)
            coordinateRow(label: "Lon:", text: $longitudeText, focus: $lonFocused, isInvalid: isLonInvalid)
        }
        .onChange(of: latFocused) { _, focused in
            if !focused { validateAndUpdate() }
        }
        .onChange(of: lonFocused) { _, focused in
            if !focused { validateAndUpdate() }
        }
        .onChange(of: appState.targetCoordinate) { _, newValue in
            guard !isEditing, let coord = newValue else { return }
            latitudeText = String(format: "%.6f", coord.latitude)
            longitudeText = String(format: "%.6f", coord.longitude)
            isLatInvalid = false
            isLonInvalid = false
        }
    }

    private func coordinateRow(label: String, text: Binding<String>, focus: FocusState<Bool>.Binding, isInvalid: Bool) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(label)
                .frame(width: 32, alignment: .trailing)
                .font(DS.Typography.label)
                .foregroundStyle(DS.Colors.textSecondary)

            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(DS.Typography.mono)
                .focused(focus)
                .onSubmit { validateAndUpdate() }
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.xs)
                        .strokeBorder(DS.Colors.error.opacity(isInvalid ? 0.6 : 0), lineWidth: 1.5)
                        .animation(DS.Animation.fast, value: isInvalid)
                )
        }
    }

    private func validateAndUpdate() {
        let lat = Double(latitudeText)
        let lon = Double(longitudeText)

        let latValid = lat.map { (-90...90).contains($0) } ?? latitudeText.isEmpty
        let lonValid = lon.map { (-180...180).contains($0) } ?? longitudeText.isEmpty

        withAnimation(DS.Animation.fast) {
            isLatInvalid = !latValid
            isLonInvalid = !lonValid
        }

        guard let lat, let lon,
              (-90...90).contains(lat),
              (-180...180).contains(lon) else { return }
        appState.targetCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
