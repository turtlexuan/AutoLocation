import Foundation
import MapKit

@Observable
@MainActor
class DeviceManager {
    private let bridge = PythonBridge()
    private(set) var appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Bridge Lifecycle

    func startBridge() async {
        appState.isLoading = true
        appState.statusMessage = "Starting Python bridge..."
        defer { appState.isLoading = false }

        do {
            try await bridge.start()
            appState.isBridgeReady = true
            appState.statusMessage = "Bridge connected"
        } catch {
            appState.isBridgeReady = false
            appState.statusMessage = "Bridge failed: \(error.localizedDescription)"
        }
    }

    func stopBridge() async {
        await bridge.stop()
        appState.isBridgeReady = false
        appState.isSimulating = false
        appState.isPlayingGPX = false
        appState.statusMessage = "Bridge disconnected"
    }

    // MARK: - Device Discovery

    func refreshDevices() async {
        appState.isLoading = true
        appState.statusMessage = "Scanning for devices..."
        defer { appState.isLoading = false }

        do {
            let response = try await bridge.send(command: ["command": "list_devices"])

            guard let devicesArray = response["devices"] as? [[String: Any]] else {
                appState.statusMessage = "Invalid device list response"
                return
            }

            let devices = devicesArray.compactMap { dict -> Device? in
                guard let udid = dict["udid"] as? String,
                      let name = dict["name"] as? String else {
                    return nil
                }
                return Device(
                    udid: udid,
                    name: name,
                    productType: dict["productType"] as? String ?? "Unknown",
                    osVersion: dict["osVersion"] as? String ?? "Unknown",
                    connectionType: dict["connectionType"] as? String ?? "Unknown",
                    tunnelStatus: dict["tunnelStatus"] as? String ?? "unknown",
                    needsTunnel: dict["needsTunnel"] as? Bool ?? false
                )
            }

            appState.devices = devices

            // Auto-select first device if none selected or selected device is no longer available
            if appState.selectedDeviceUDID == nil ||
                !devices.contains(where: { $0.udid == appState.selectedDeviceUDID }) {
                appState.selectedDeviceUDID = devices.first?.udid
            }

            if devices.isEmpty {
                appState.statusMessage = "No devices found"
            } else {
                appState.statusMessage = "Found \(devices.count) device\(devices.count == 1 ? "" : "s")"
            }
        } catch {
            appState.statusMessage = "Device scan failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Tunnel Management

    func startTunnel() async {
        appState.isLoading = true
        appState.statusMessage = "Checking tunnel..."
        defer { appState.isLoading = false }

        do {
            let response = try await bridge.send(command: ["command": "start_tunnel"])
            let tunnelRunning = response["tunnelRunning"] as? Bool ?? false
            let message = response["message"] as? String ?? ""

            if tunnelRunning {
                appState.statusMessage = message
                appState.tunnelCommand = nil
                // Refresh devices to update tunnel status
                await refreshDevices()
            } else {
                // Need user to run command manually
                let command = response["command"] as? String
                appState.tunnelCommand = command
                appState.statusMessage = "Tunnel required — see instructions below"
            }
        } catch {
            appState.statusMessage = "Tunnel check failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Location Simulation

    func setLocation(latitude: Double, longitude: Double) async {
        guard let udid = appState.selectedDeviceUDID else {
            appState.statusMessage = "No device selected"
            return
        }

        appState.isLoading = true
        appState.statusMessage = "Setting location..."
        defer { appState.isLoading = false }

        do {
            let command: [String: Any] = [
                "command": "set_location",
                "udid": udid,
                "latitude": latitude,
                "longitude": longitude
            ]
            _ = try await bridge.send(command: command)

            appState.targetCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            appState.isSimulating = true
            appState.statusMessage = String(format: "Location set to %.6f, %.6f", latitude, longitude)
        } catch {
            appState.statusMessage = "Set location failed: \(error.localizedDescription)"
        }
    }

    func clearLocation() async {
        guard let udid = appState.selectedDeviceUDID else {
            appState.statusMessage = "No device selected"
            return
        }

        appState.isLoading = true
        appState.statusMessage = "Clearing simulated location..."
        defer { appState.isLoading = false }

        do {
            let command: [String: Any] = [
                "command": "clear_location",
                "udid": udid
            ]
            _ = try await bridge.send(command: command)

            appState.isSimulating = false
            appState.statusMessage = "Location cleared — GPS may take a moment to re-acquire real position"
        } catch {
            appState.statusMessage = "Clear location failed: \(error.localizedDescription)"
        }
    }

    // MARK: - GPX Playback

    func playGPX(path: String, speed: Double = 1.0) async {
        guard let udid = appState.selectedDeviceUDID else {
            appState.statusMessage = "No device selected"
            return
        }

        appState.isLoading = true
        appState.statusMessage = "Starting GPX playback..."
        defer { appState.isLoading = false }

        do {
            let command: [String: Any] = [
                "command": "play_gpx",
                "udid": udid,
                "path": path,
                "speed": speed
            ]
            _ = try await bridge.send(command: command)

            appState.isPlayingGPX = true
            appState.statusMessage = "Playing GPX route (speed: \(speed)x)"
        } catch {
            appState.statusMessage = "GPX playback failed: \(error.localizedDescription)"
        }
    }

    func stopPlayback() async {
        guard let udid = appState.selectedDeviceUDID else {
            appState.statusMessage = "No device selected"
            return
        }

        appState.isLoading = true
        appState.statusMessage = "Stopping playback..."
        defer { appState.isLoading = false }

        do {
            let command: [String: Any] = [
                "command": "stop_playback",
                "udid": udid
            ]
            _ = try await bridge.send(command: command)

            appState.isPlayingGPX = false
            appState.statusMessage = "Playback stopped"
        } catch {
            appState.statusMessage = "Stop playback failed: \(error.localizedDescription)"
        }
    }
}
