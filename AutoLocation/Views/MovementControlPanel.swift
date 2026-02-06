import SwiftUI

struct MovementControlPanel: View {
    var movementEngine: MovementEngine
    var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            // Joystick
            JoystickView(radius: 50) { bearing, magnitude in
                movementEngine.updateInput(bearing: bearing, magnitude: magnitude)
            }

            VStack(alignment: .leading, spacing: 10) {
                // Speed mode picker
                HStack(spacing: 4) {
                    ForEach(MovementEngine.SpeedMode.allCases) { mode in
                        Button {
                            movementEngine.speedMode = mode
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: mode.icon)
                                    .font(.caption)
                                Text(mode.rawValue)
                                    .font(.caption2)
                            }
                            .frame(width: 48, height: 36)
                        }
                        .buttonStyle(.bordered)
                        .tint(movementEngine.speedMode == mode ? .accentColor : .secondary)
                    }
                }

                // Stats
                HStack(spacing: 16) {
                    statItem(
                        icon: "safari",
                        value: movementEngine.bearingText
                    )
                    statItem(
                        icon: "speedometer",
                        value: movementEngine.speedText
                    )
                    statItem(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        value: movementEngine.distanceText
                    )
                }

                // Walk to pin button + stop
                HStack(spacing: 8) {
                    Button {
                        if let target = appState.targetCoordinate,
                           let current = movementEngine.currentLocation,
                           target != current {
                            movementEngine.walkToPoint(target)
                        }
                    } label: {
                        Label("Walk to Pin", systemImage: "figure.walk.motion")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        appState.targetCoordinate == nil
                        || movementEngine.isWalkingToPoint
                    )

                    if movementEngine.isMoving {
                        Button {
                            movementEngine.stopMoving()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }

                    Spacer()

                    Text("WASD / Arrow keys")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
        }
    }
}
