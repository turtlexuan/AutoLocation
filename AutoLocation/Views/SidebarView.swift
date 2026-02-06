import SwiftUI

struct SidebarView: View {
    var appState: AppState
    var deviceManager: DeviceManager?

    @State private var gpxFilePath: String?
    @State private var playbackSpeed: Double = 1.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                devicesSection
                tunnelSection
                locationSection
                gpxSection
            }
            .padding()
        }
    }

    // MARK: - Devices Section

    private var devicesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Devices", systemImage: "iphone")
                        .font(.headline)

                    Spacer()

                    Button {
                        Task {
                            await deviceManager?.refreshDevices()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.isLoading)
                }

                Divider()

                if appState.devices.isEmpty {
                    VStack(spacing: 4) {
                        Text("No devices found")
                            .foregroundStyle(.secondary)
                        Text("Connect an iPhone via USB or Wi-Fi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
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
    }

    // MARK: - Tunnel Section

    @ViewBuilder
    private var tunnelSection: some View {
        if let device = appState.selectedDevice, device.needsTunnel {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Developer Tunnel", systemImage: "network")
                        .font(.headline)

                    Divider()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(device.tunnelStatus == "connected" ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(device.tunnelStatus == "connected"
                             ? "Tunnel connected"
                             : "Tunnel required for iOS 17+")
                            .font(.caption)
                    }

                    if device.tunnelStatus != "connected" {
                        Button {
                            Task {
                                await deviceManager?.startTunnel()
                            }
                        } label: {
                            Label("Start Tunnel", systemImage: "network.badge.shield.half.filled")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(appState.isLoading)

                        Text("Admin password will be required to start the tunnel daemon.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Location", systemImage: "location")
                    .font(.headline)

                Divider()

                CoordinateInputView(appState: appState)

                let deviceReady = appState.selectedDevice?.isTunnelReady ?? false

                Button {
                    guard let coord = appState.targetCoordinate else { return }
                    Task {
                        await deviceManager?.setLocation(
                            latitude: coord.latitude,
                            longitude: coord.longitude
                        )
                    }
                } label: {
                    Label("Set Location", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(
                    appState.targetCoordinate == nil
                    || appState.selectedDevice == nil
                    || !deviceReady
                    || appState.isLoading
                )

                Button {
                    Task {
                        await deviceManager?.clearLocation()
                    }
                } label: {
                    Label("Clear Location", systemImage: "location.slash")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .disabled(!appState.isSimulating || appState.isLoading)

                if let device = appState.selectedDevice, !deviceReady {
                    Text("Start the developer tunnel first to enable location simulation.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - GPX Section

    private var gpxSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("GPX Playback", systemImage: "point.topLeft.down.to.point.bottomRight.curvePath")
                    .font(.headline)

                Divider()

                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.init(filenameExtension: "gpx")!]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.message = "Select a GPX file for route playback"
                    if panel.runModal() == .OK, let url = panel.url {
                        gpxFilePath = url.path
                    }
                } label: {
                    Label("Load GPX File...", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)

                if let path = gpxFilePath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack {
                        Text("Speed:")
                            .font(.caption)
                        Picker("Speed", selection: $playbackSpeed) {
                            Text("1x").tag(1.0)
                            Text("2x").tag(2.0)
                            Text("5x").tag(5.0)
                            Text("10x").tag(10.0)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await deviceManager?.playGPX(path: path, speed: playbackSpeed)
                            }
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(
                            appState.selectedDevice == nil
                            || appState.isLoading
                            || appState.isPlayingGPX
                        )

                        Button {
                            Task {
                                await deviceManager?.stopPlayback()
                            }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(!appState.isPlayingGPX || appState.isLoading)
                    }
                }
            }
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let device: Device
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone")
                .font(.title3)
                .foregroundStyle(isSelected ? .white : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(device.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? .white : .primary)

                    if device.needsTunnel {
                        Circle()
                            .fill(device.tunnelStatus == "connected" ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                    }
                }
                Text("\(device.productType) \u{2022} iOS \(device.osVersion)")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }

            Spacer()

            Image(systemName: device.connectionType == "USB" ? "cable.connector" : "wifi")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.gray.opacity(0.5))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
}
