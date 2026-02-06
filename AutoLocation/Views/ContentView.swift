import SwiftUI

struct ContentView: View {
    var appState: AppState
    var deviceManager: DeviceManager?
    var movementEngine: MovementEngine?
    var locationSearchService: LocationSearchService

    @FocusState private var isMapFocused: Bool
    @State private var activeDirections: Set<MovementDirection> = []

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState, deviceManager: deviceManager)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            VStack(spacing: 0) {
                ZStack {
                    MapContainerView(
                        appState: appState,
                        deviceManager: deviceManager,
                        movementEngine: movementEngine
                    )

                    // Search bar overlay at top
                    VStack {
                        LocationSearchView(
                            searchService: locationSearchService,
                            appState: appState
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        Spacer()

                        // Movement control panel overlay
                        if let engine = movementEngine {
                            MovementControlPanel(
                                movementEngine: engine,
                                appState: appState
                            )
                            .padding(12)
                        }
                    }
                }
                StatusBarView(appState: appState)
            }
            .focusable()
            .focused($isMapFocused)
            .onKeyPress(phases: .down) { press in
                if let dir = MovementDirection.from(press) {
                    activeDirections.insert(dir)
                    updateKeyboardMovement()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(phases: .up) { press in
                if let dir = MovementDirection.from(press) {
                    activeDirections.remove(dir)
                    updateKeyboardMovement()
                    return .handled
                }
                return .ignored
            }
            .onAppear { isMapFocused = true }
        }
    }

    private func updateKeyboardMovement() {
        guard let engine = movementEngine else { return }

        if activeDirections.isEmpty {
            engine.updateInput(bearing: engine.currentBearing, magnitude: 0)
            return
        }

        var dx: Double = 0
        var dy: Double = 0
        if activeDirections.contains(.north) { dy += 1 }
        if activeDirections.contains(.south) { dy -= 1 }
        if activeDirections.contains(.east)  { dx += 1 }
        if activeDirections.contains(.west)  { dx -= 1 }

        guard dx != 0 || dy != 0 else {
            engine.updateInput(bearing: engine.currentBearing, magnitude: 0)
            return
        }

        let angle = atan2(dx, dy) * 180.0 / .pi
        let bearing = angle < 0 ? angle + 360 : angle
        engine.updateInput(bearing: bearing, magnitude: 1.0)
    }
}

// MARK: - Movement Directions

enum MovementDirection: Hashable {
    case north, south, east, west

    static func from(_ press: KeyPress) -> MovementDirection? {
        switch press.key {
        case .upArrow, KeyEquivalent("w"):    return .north
        case .downArrow, KeyEquivalent("s"):  return .south
        case .rightArrow, KeyEquivalent("d"): return .east
        case .leftArrow, KeyEquivalent("a"):  return .west
        default: return nil
        }
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    var appState: AppState

    private var indicatorColor: Color {
        if appState.isSimulating || appState.isPlayingGPX {
            return .green
        } else if appState.isLoading {
            return .yellow
        } else {
            return .gray
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)

            Text(appState.statusMessage)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if appState.targetCoordinate != nil {
                Text(appState.coordinateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
