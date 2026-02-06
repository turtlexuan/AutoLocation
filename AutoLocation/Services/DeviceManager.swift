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

        // First check if tunnel is already running
        do {
            let response = try await bridge.send(command: ["command": "check_tunnel"])
            if response["tunnelRunning"] as? Bool == true {
                appState.statusMessage = response["message"] as? String ?? "Tunnel running"
                appState.tunnelCommand = nil
                await refreshDevices()
                return
            }
        } catch {
            // Continue to start tunnel
        }

        // Start tunnel with admin privileges
        appState.statusMessage = "Starting tunnel (password may be required)..."

        let command = findTunnelCommand()
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = "do shell script \"\(escaped) > /dev/null 2>&1 &\" with administrator privileges"

        let success = await runOsascript(scriptSource)

        guard success else {
            appState.statusMessage = "Tunnel start cancelled or failed"
            return
        }

        // Poll for tunnel readiness (up to ~10 seconds)
        appState.statusMessage = "Waiting for tunnel to initialize..."
        for attempt in 1...5 {
            try? await Task.sleep(for: .seconds(2))
            do {
                let response = try await bridge.send(command: ["command": "check_tunnel"])
                if response["tunnelRunning"] as? Bool == true {
                    appState.tunnelCommand = nil
                    appState.statusMessage = "Tunnel started successfully"
                    await refreshDevices()
                    return
                }
            } catch {
                // Keep polling
            }
            if attempt < 5 {
                appState.statusMessage = "Waiting for tunnel to initialize... (\(attempt * 2)s)"
            }
        }

        appState.statusMessage = "Tunnel process started — click Refresh to check status"
    }

    /// Run an AppleScript string via /usr/bin/osascript in the background.
    private func runOsascript(_ source: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                proc.arguments = ["-e", source]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    continuation.resume(returning: proc.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Find the best command to run the tunneld daemon.
    private func findTunnelCommand() -> String {
        let fileManager = FileManager.default

        // 1. Bundled bridge binary (distributed app)
        if let resourceURL = Bundle.main.resourceURL {
            let path = resourceURL.appendingPathComponent("bridge/bridge").path
            if fileManager.isExecutableFile(atPath: path) {
                return "'\(path)' --tunneld"
            }
        }

        // 2. Dev paths — walk up from executable to find project root
        var searchRoots: [String] = []
        if let execURL = Bundle.main.executableURL {
            var dir = execURL.deletingLastPathComponent()
            for _ in 0..<12 {
                searchRoots.append(dir.path)
                dir = dir.deletingLastPathComponent()
            }
        }
        searchRoots.append(fileManager.currentDirectoryPath)

        for root in searchRoots {
            // PyInstaller dist bridge
            let distBridge = root + "/Scripts/dist/bridge/bridge"
            if fileManager.isExecutableFile(atPath: distBridge) {
                return "'\(distBridge)' --tunneld"
            }
            // pymobiledevice3 CLI in venv
            let pmd3 = root + "/Scripts/.venv/bin/pymobiledevice3"
            if fileManager.isExecutableFile(atPath: pmd3) {
                return "'\(pmd3)' remote tunneld"
            }
        }

        // 3. System pymobiledevice3
        for path in ["/usr/local/bin/pymobiledevice3", "/opt/homebrew/bin/pymobiledevice3"] {
            if fileManager.isExecutableFile(atPath: path) {
                return "'\(path)' remote tunneld"
            }
        }

        return "pymobiledevice3 remote tunneld"
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

    /// Lightweight location update for movement engine — no UI state changes.
    func setLocationSilent(latitude: Double, longitude: Double) async {
        guard let udid = appState.selectedDeviceUDID else { return }

        do {
            let command: [String: Any] = [
                "command": "set_location",
                "udid": udid,
                "latitude": latitude,
                "longitude": longitude
            ]
            _ = try await bridge.send(command: command)
            appState.isSimulating = true
        } catch {
            appState.statusMessage = "Movement update failed: \(error.localizedDescription)"
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
