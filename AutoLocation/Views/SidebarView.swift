import SwiftUI

struct SidebarView: View {
    var appState: AppState
    var deviceManager: DeviceManager?
    var movementEngine: MovementEngine?

    @State private var gpxFilePath: String?
    @State private var playbackSpeed: Double = 1.0
    @State private var useCustomSpeed: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sm) {
                devicesSection
                tunnelSection
                locationSection
                routePlannerSection
                gpxSection
            }
            .padding(DS.Spacing.sm)
        }
        .scrollContentBackground(.hidden)
        .background(DS.Colors.backgroundPrimary.opacity(0.5))
    }

    // MARK: - Devices Section

    private var devicesSection: some View {
        CollapsibleSection(
            title: "Devices",
            icon: "iphone",
            storageKey: "sidebar.devices.expanded",
            badge: appState.devices.isEmpty ? nil : "\(appState.devices.count)"
        ) {
            HStack {
                Spacer()
                Button {
                    Task {
                        await deviceManager?.refreshDevices()
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xxs) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                        Text("Refresh")
                            .font(DS.Typography.labelSmall)
                    }
                    .foregroundStyle(DS.Colors.active)
                    .padding(.horizontal, DS.Spacing.xs)
                    .padding(.vertical, DS.Spacing.xxs)
                    .background(DS.Colors.active.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(appState.isLoading)
            }

            if appState.devices.isEmpty {
                VStack(spacing: DS.Spacing.xxs) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(DS.Colors.textTertiary)
                    Text("No devices found")
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Colors.textSecondary)
                    Text("Connect an iPhone via USB or Wi-Fi")
                        .font(DS.Typography.labelSmall)
                        .foregroundStyle(DS.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
            } else {
                ForEach(appState.devices) { device in
                    DeviceRow(
                        device: device,
                        isSelected: appState.selectedDeviceUDID == device.udid
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.selectedDeviceUDID = device.udid
                    }
                }
            }
        }
    }

    // MARK: - Tunnel Section

    @ViewBuilder
    private var tunnelSection: some View {
        if let device = appState.selectedDevice, device.needsTunnel {
            CollapsibleSection(
                title: "Developer Tunnel",
                icon: "network",
                storageKey: "sidebar.tunnel.expanded",
                badge: device.tunnelStatus == "connected" ? "Connected" : "Required",
                badgeColor: device.tunnelStatus == "connected" ? DS.Colors.success : DS.Colors.warning
            ) {
                StatusBadge(
                    label: device.tunnelStatus == "connected"
                        ? "Tunnel connected"
                        : "Tunnel required for iOS 17+",
                    color: device.tunnelStatus == "connected" ? DS.Colors.success : DS.Colors.warning,
                    size: .small
                )

                if device.tunnelStatus != "connected" {
                    ActionButton(
                        title: "Start Tunnel",
                        icon: "network.badge.shield.half.filled",
                        style: .warning,
                        isLoading: appState.isLoading
                    ) {
                        Task {
                            await deviceManager?.startTunnel()
                        }
                    }
                    .disabled(appState.isLoading)

                    Text("Admin password will be required to start the tunnel daemon.")
                        .font(DS.Typography.labelSmall)
                        .foregroundStyle(DS.Colors.textTertiary)
                }
            }
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        CollapsibleSection(
            title: "Location",
            icon: "location",
            storageKey: "sidebar.location.expanded"
        ) {
            CoordinateInputView(appState: appState)

            let deviceReady = appState.selectedDevice?.isTunnelReady ?? false

            ActionButton(
                title: "Set Location",
                icon: "location.fill",
                style: .primary,
                isLoading: appState.isLoading
            ) {
                guard let coord = appState.targetCoordinate else { return }
                Task {
                    await deviceManager?.setLocation(
                        latitude: coord.latitude,
                        longitude: coord.longitude
                    )
                }
            }
            .disabled(
                appState.targetCoordinate == nil
                || appState.selectedDevice == nil
                || !deviceReady
                || appState.isLoading
            )

            ActionButton(
                title: "Clear Location",
                icon: "location.slash",
                style: .secondary
            ) {
                Task {
                    await deviceManager?.clearLocation()
                }
            }
            .disabled(!appState.isSimulating || appState.isLoading)

            if let _ = appState.selectedDevice, !deviceReady {
                HStack(spacing: DS.Spacing.xxs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Colors.warning)
                    Text("Start the developer tunnel first to enable location simulation.")
                        .font(DS.Typography.labelSmall)
                        .foregroundStyle(DS.Colors.warning)
                }
            }
        }
    }

    // MARK: - Route Planner Section

    private var routePlannerSection: some View {
        CollapsibleSection(
            title: "Route Planner",
            icon: "point.topLeft.down.to.point.bottomRight.curvePath.fill",
            storageKey: "sidebar.route.expanded",
            badge: appState.routeWaypoints.isEmpty ? nil : "\(appState.routeWaypoints.count) pts"
        ) {
            // Edit Route toggle
            ActionButton(
                title: appState.isEditingRoute ? "Done Editing" : "Add Waypoints",
                icon: appState.isEditingRoute ? "checkmark.circle" : "plus.circle",
                style: appState.isEditingRoute ? .warning : .primary
            ) {
                appState.isEditingRoute.toggle()
            }
            .disabled(appState.isFollowingRoute)

            if appState.isEditingRoute {
                HStack(spacing: DS.Spacing.xxs) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 10))
                    Text("Tap the map to add waypoints")
                        .font(DS.Typography.labelSmall)
                }
                .foregroundStyle(DS.Colors.textTertiary)
            }

            // Waypoint list
            if !appState.routeWaypoints.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xxxs) {
                    ForEach(Array(appState.routeWaypoints.enumerated()), id: \.element.id) { index, waypoint in
                        HStack(spacing: DS.Spacing.xs) {
                            // Numbered circle
                            ZStack {
                                Circle()
                                    .fill(waypointRowColor(for: index))
                                    .frame(width: 22, height: 22)
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                if let name = waypoint.name {
                                    Text(name)
                                        .font(DS.Typography.label)
                                        .lineLimit(1)
                                }
                                Text(String(format: "%.5f, %.5f", waypoint.coordinate.latitude, waypoint.coordinate.longitude))
                                    .font(DS.Typography.labelSmall)
                                    .foregroundStyle(DS.Colors.textTertiary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                appState.routeWaypoints.remove(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(DS.Colors.textTertiary)
                                    .frame(width: 20, height: 20)
                                    .background(DS.Colors.textPrimary.opacity(0.06), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(appState.isFollowingRoute)
                        }
                        .padding(.vertical, DS.Spacing.xxs)
                        .padding(.horizontal, DS.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .fill(
                                    appState.isFollowingRoute && appState.currentRouteWaypointIndex == index
                                        ? DS.Colors.active.opacity(0.08)
                                        : Color.clear
                                )
                        )
                    }
                }

                Divider()
                    .padding(.vertical, DS.Spacing.xxs)

                // Speed setting
                HStack {
                    Text("Speed:")
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Colors.textSecondary)
                    Spacer()
                    Picker("", selection: $useCustomSpeed) {
                        Text("Preset").tag(false)
                        Text("Custom").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }

                if useCustomSpeed {
                    HStack(spacing: DS.Spacing.xxs) {
                        TextField("Speed", value: Binding(
                            get: { movementEngine?.customSpeedKmh ?? 5.0 },
                            set: { movementEngine?.customSpeedKmh = $0 }
                        ), format: .number.precision(.fractionLength(1)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Text("km/h")
                            .font(DS.Typography.label)
                            .foregroundStyle(DS.Colors.textTertiary)
                    }
                } else {
                    Picker("Speed", selection: Binding(
                        get: { movementEngine?.speedMode ?? .walk },
                        set: { movementEngine?.speedMode = $0 }
                    )) {
                        ForEach(MovementEngine.SpeedMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                // Loop toggle
                Toggle(isOn: Binding(
                    get: { appState.shouldLoopRoute },
                    set: { appState.shouldLoopRoute = $0 }
                )) {
                    HStack(spacing: DS.Spacing.xxs) {
                        Image(systemName: "repeat")
                            .font(.system(size: 10))
                        Text("Loop Route")
                            .font(DS.Typography.label)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(appState.isFollowingRoute)

                // Start / Stop buttons
                if appState.routeWaypoints.count >= 2 {
                    let deviceReady = appState.selectedDevice?.isTunnelReady ?? false

                    HStack(spacing: DS.Spacing.xs) {
                        ActionButton(
                            title: "Start",
                            icon: "play.fill",
                            style: .success
                        ) {
                            movementEngine?.followRoute(waypoints: appState.routeWaypoints)
                        }
                        .disabled(
                            appState.selectedDevice == nil
                            || !deviceReady
                            || appState.isFollowingRoute
                            || appState.routeWaypoints.count < 2
                            || appState.isLoading
                        )

                        ActionButton(
                            title: "Stop",
                            icon: "stop.fill",
                            style: .destructive
                        ) {
                            movementEngine?.stopRoute()
                        }
                        .disabled(!appState.isFollowingRoute || appState.isLoading)
                    }
                }

                // Clear All button
                ActionButton(
                    title: "Clear Route",
                    icon: "trash",
                    style: .secondary
                ) {
                    appState.routeWaypoints.removeAll()
                    appState.isEditingRoute = false
                    appState.currentRouteWaypointIndex = 0
                }
                .disabled(appState.isFollowingRoute)
            }
        }
    }

    // MARK: - GPX Section

    private var gpxSection: some View {
        CollapsibleSection(
            title: "GPX Playback",
            icon: "point.topLeft.down.to.point.bottomRight.curvePath",
            storageKey: "sidebar.gpx.expanded",
            defaultExpanded: false
        ) {
            ActionButton(
                title: "Load GPX File...",
                icon: "doc.badge.plus",
                style: .secondary
            ) {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.init(filenameExtension: "gpx")!]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.message = "Select a GPX file for route playback"
                if panel.runModal() == .OK, let url = panel.url {
                    gpxFilePath = url.path
                }
            }

            if let path = gpxFilePath {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.textTertiary)
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Text("Speed:")
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Colors.textSecondary)
                    Picker("Speed", selection: $playbackSpeed) {
                        Text("1x").tag(1.0)
                        Text("2x").tag(2.0)
                        Text("5x").tag(5.0)
                        Text("10x").tag(10.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                HStack(spacing: DS.Spacing.xs) {
                    ActionButton(
                        title: "Play",
                        icon: "play.fill",
                        style: .success
                    ) {
                        Task {
                            await deviceManager?.playGPX(path: path, speed: playbackSpeed)
                        }
                    }
                    .disabled(
                        appState.selectedDevice == nil
                        || appState.isLoading
                        || appState.isPlayingGPX
                    )

                    ActionButton(
                        title: "Stop",
                        icon: "stop.fill",
                        style: .destructive
                    ) {
                        Task {
                            await deviceManager?.stopPlayback()
                        }
                    }
                    .disabled(!appState.isPlayingGPX || appState.isLoading)
                }
            }
        }
    }

    // MARK: - Helpers

    private func waypointRowColor(for index: Int) -> Color {
        guard appState.isFollowingRoute else { return DS.Colors.route }
        if index < appState.currentRouteWaypointIndex {
            return DS.Colors.success
        } else if index == appState.currentRouteWaypointIndex {
            return DS.Colors.warning
        } else {
            return DS.Colors.route
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let device: Device
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            // Accent left border
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? DS.Colors.active : Color.clear)
                .frame(width: 3)
                .padding(.vertical, DS.Spacing.xxs)

            Image(systemName: "iphone")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isSelected ? DS.Colors.active : DS.Colors.textTertiary)

            VStack(alignment: .leading, spacing: DS.Spacing.xxxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(device.name)
                        .font(DS.Typography.label)
                        .fontWeight(.medium)
                        .foregroundStyle(DS.Colors.textPrimary)

                    if device.needsTunnel {
                        StatusBadge(
                            label: device.tunnelStatus == "connected" ? "Ready" : "Tunnel",
                            color: device.tunnelStatus == "connected" ? DS.Colors.success : DS.Colors.warning,
                            size: .small
                        )
                    }
                }
                Text("\(device.productType) \u{2022} iOS \(device.osVersion)")
                    .font(DS.Typography.labelSmall)
                    .foregroundStyle(DS.Colors.textTertiary)
            }

            Spacer()

            Image(systemName: device.connectionType == "USB" ? "cable.connector" : "wifi")
                .font(.system(size: 10))
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .padding(.vertical, DS.Spacing.xs)
        .padding(.trailing, DS.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(isSelected ? DS.Colors.active.opacity(0.08) : Color.clear)
        )
    }
}
