import SwiftUI

struct MovementControlPanel: View {
    var movementEngine: MovementEngine
    var appState: AppState

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            // Joystick
            JoystickView(radius: 50) { bearing, magnitude in
                movementEngine.updateInput(bearing: bearing, magnitude: magnitude)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                // Speed mode picker
                HStack(spacing: DS.Spacing.xxs) {
                    ForEach(MovementEngine.SpeedMode.allCases) { mode in
                        Button {
                            movementEngine.speedMode = mode
                        } label: {
                            VStack(spacing: DS.Spacing.xxxs) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 11, weight: .medium))
                                Text(mode.rawValue)
                                    .font(DS.Typography.labelSmall)
                            }
                            .frame(width: 48, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.sm)
                                    .fill(movementEngine.speedMode == mode
                                          ? DS.Colors.active.opacity(0.15)
                                          : DS.Colors.textPrimary.opacity(0.04))
                            )
                            .foregroundStyle(movementEngine.speedMode == mode
                                             ? DS.Colors.active
                                             : DS.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Stats
                HStack(spacing: DS.Spacing.xs) {
                    StatCard(
                        icon: "safari",
                        value: movementEngine.bearingText,
                        label: "Bearing"
                    )
                    StatCard(
                        icon: "speedometer",
                        value: movementEngine.speedText,
                        label: "Speed"
                    )
                    StatCard(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        value: movementEngine.distanceText,
                        label: "Distance"
                    )
                }

                // Walk to pin button + stop
                HStack(spacing: DS.Spacing.xs) {
                    Button {
                        if let target = appState.targetCoordinate,
                           let current = movementEngine.currentLocation,
                           target != current {
                            movementEngine.walkToPoint(target)
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.xxs) {
                            Image(systemName: "figure.walk.motion")
                                .font(.system(size: 11, weight: .medium))
                            Text("Walk to Pin")
                                .font(DS.Typography.labelSmall)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, DS.Spacing.xxs + 2)
                        .background(DS.Colors.movement.opacity(0.12), in: Capsule())
                        .foregroundStyle(DS.Colors.movement)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        appState.targetCoordinate == nil
                        || movementEngine.isWalkingToPoint
                    )

                    if movementEngine.isMoving {
                        Button {
                            movementEngine.stopMoving()
                        } label: {
                            HStack(spacing: DS.Spacing.xxs) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 9))
                                Text("Stop")
                                    .font(DS.Typography.labelSmall)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, DS.Spacing.xxs + 2)
                            .background(DS.Colors.error.opacity(0.12), in: Capsule())
                            .foregroundStyle(DS.Colors.error)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text("WASD / Arrow keys")
                        .font(DS.Typography.labelSmall)
                        .foregroundStyle(DS.Colors.textTertiary)
                }
            }
        }
        .padding(DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .strokeBorder(
                            movementEngine.isMoving
                                ? DS.Colors.movement.opacity(0.3)
                                : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .shadowMedium()
    }
}
