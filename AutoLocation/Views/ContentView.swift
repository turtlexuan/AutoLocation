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
            SidebarView(appState: appState, deviceManager: deviceManager, movementEngine: movementEngine)
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
                let allowWASD = !appState.isSearchFieldFocused
                if let dir = MovementDirection.from(press, allowWASD: allowWASD) {
                    activeDirections.insert(dir)
                    updateKeyboardMovement()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(phases: .up) { press in
                let allowWASD = !appState.isSearchFieldFocused
                if let dir = MovementDirection.from(press, allowWASD: allowWASD) {
                    activeDirections.remove(dir)
                    updateKeyboardMovement()
                    return .handled
                }
                return .ignored
            }
            .onChange(of: appState.isSearchFieldFocused) { _, focused in
                if focused && !activeDirections.isEmpty {
                    activeDirections.removeAll()
                    updateKeyboardMovement()
                }
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

    static func from(_ press: KeyPress, allowWASD: Bool = true) -> MovementDirection? {
        switch press.key {
        case .upArrow:                            return .north
        case .downArrow:                          return .south
        case .rightArrow:                         return .east
        case .leftArrow:                          return .west
        case KeyEquivalent("w") where allowWASD:  return .north
        case KeyEquivalent("s") where allowWASD:  return .south
        case KeyEquivalent("d") where allowWASD:  return .east
        case KeyEquivalent("a") where allowWASD:  return .west
        default: return nil
        }
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    var appState: AppState

    private var indicatorColor: Color {
        if appState.isSimulating || appState.isPlayingGPX {
            return DS.Colors.success
        } else if appState.isLoading {
            return DS.Colors.warning
        } else {
            return DS.Colors.textTertiary
        }
    }

    private var statusIcon: String {
        if appState.isSimulating || appState.isPlayingGPX {
            return "location.fill"
        } else if appState.isLoading {
            return "arrow.triangle.2.circlepath"
        } else {
            return "circle"
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xxs + 1) {
                Image(systemName: statusIcon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(indicatorColor)

                Circle()
                    .fill(indicatorColor)
                    .frame(width: 6, height: 6)
            }

            Text(appState.statusMessage)
                .font(DS.Typography.labelSmall)
                .foregroundStyle(DS.Colors.textSecondary)
                .lineLimit(1)

            Spacer()

            if appState.targetCoordinate != nil {
                Text(appState.coordinateText)
                    .font(DS.Typography.mono)
                    .foregroundStyle(DS.Colors.textTertiary)
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xxs + 2)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
