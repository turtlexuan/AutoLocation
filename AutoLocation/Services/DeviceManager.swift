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
            autoSelectDeviceIfNeeded(from: devices)

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

        if await isTunnelAlreadyRunning() {
            await refreshDevices()
            return
        }

        appState.statusMessage = "Starting tunnel (password may be required)..."

        let tunnelCommand = findTunnelCommand()
        let logPath = NSTemporaryDirectory() + "autolocation_tunnel.log"
        print("[DeviceManager] Tunnel command: \(tunnelCommand)")

        let scriptSource = buildAppleScript(command: tunnelCommand, logPath: logPath)
        print("[DeviceManager] AppleScript: \(scriptSource)")

        guard await runOsascript(scriptSource) else {
            appState.statusMessage = "Tunnel start cancelled or failed"
            return
        }

        if await pollForTunnel() {
            return
        }

        reportTunnelFailure(logPath: logPath)
    }

    private func isTunnelAlreadyRunning() async -> Bool {
        guard let response = try? await bridge.send(command: ["command": "check_tunnel"]),
              response["tunnelRunning"] as? Bool == true else {
            return false
        }
        appState.statusMessage = response["message"] as? String ?? "Tunnel running"
        appState.tunnelCommand = nil
        return true
    }

    private func buildAppleScript(command: String, logPath: String) -> String {
        let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\")
                                    .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedLogPath = logPath.replacingOccurrences(of: "\\", with: "\\\\")
                                    .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escapedCommand) > '\(escapedLogPath)' 2>&1 &\" with administrator privileges"
    }

    /// Polls up to ~20 seconds for the tunnel to become ready. Returns true if tunnel started.
    private func pollForTunnel() async -> Bool {
        let maxAttempts = 10
        let pollInterval: Duration = .seconds(2)

        appState.statusMessage = "Waiting for tunnel to initialize..."

        for attempt in 1...maxAttempts {
            try? await Task.sleep(for: pollInterval)

            if let response = try? await bridge.send(command: ["command": "check_tunnel"]),
               response["tunnelRunning"] as? Bool == true {
                appState.tunnelCommand = nil
                appState.statusMessage = "Tunnel started successfully"
                await refreshDevices()
                return true
            }

            if attempt < maxAttempts {
                appState.statusMessage = "Waiting for tunnel to initialize... (\(attempt * 2)s)"
            }
        }
        return false
    }

    private func reportTunnelFailure(logPath: String) {
        let logContent = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        if logContent.isEmpty {
            appState.statusMessage = "Tunnel process started — click Refresh to check status"
        } else {
            let lastLines = logContent.components(separatedBy: "\n").suffix(3).joined(separator: " ")
            print("[DeviceManager] Tunnel log: \(logContent)")
            appState.statusMessage = "Tunnel may have failed: \(lastLines)"
        }
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
        await sendDeviceCommand(
            fields: ["command": "set_location", "latitude": latitude, "longitude": longitude],
            loadingMessage: "Setting location...",
            failurePrefix: "Set location failed"
        ) {
            appState.targetCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            appState.isSimulating = true
            appState.statusMessage = String(format: "Location set to %.6f, %.6f", latitude, longitude)
        }
    }

    func clearLocation() async {
        await sendDeviceCommand(
            fields: ["command": "clear_location"],
            loadingMessage: "Clearing simulated location...",
            failurePrefix: "Clear location failed"
        ) {
            appState.isSimulating = false
            appState.statusMessage = "Location cleared — GPS may take a moment to re-acquire real position"
        }
    }

    /// Lightweight location update for movement engine -- no loading indicator or status changes.
    func setLocationSilent(latitude: Double, longitude: Double) async {
        guard let udid = appState.selectedDeviceUDID else { return }

        do {
            _ = try await bridge.send(command: [
                "command": "set_location",
                "udid": udid,
                "latitude": latitude,
                "longitude": longitude
            ])
            appState.isSimulating = true
        } catch {
            appState.statusMessage = "Movement update failed: \(error.localizedDescription)"
        }
    }

    // MARK: - GPX Playback

    func playGPX(path: String, speed: Double = 1.0) async {
        await sendDeviceCommand(
            fields: ["command": "play_gpx", "path": path, "speed": speed],
            loadingMessage: "Starting GPX playback...",
            failurePrefix: "GPX playback failed"
        ) {
            appState.isPlayingGPX = true
            appState.statusMessage = "Playing GPX route (speed: \(speed)x)"
        }
    }

    func stopPlayback() async {
        await sendDeviceCommand(
            fields: ["command": "stop_playback"],
            loadingMessage: "Stopping playback...",
            failurePrefix: "Stop playback failed"
        ) {
            appState.isPlayingGPX = false
            appState.statusMessage = "Playback stopped"
        }
    }

    // MARK: - Helpers

    /// Auto-selects the first device if none is selected or the current selection is no longer available.
    private func autoSelectDeviceIfNeeded(from devices: [Device]) {
        let currentSelectionValid = devices.contains { $0.udid == appState.selectedDeviceUDID }
        if !currentSelectionValid {
            appState.selectedDeviceUDID = devices.first?.udid
        }
    }

    /// Sends a bridge command for the selected device with standard loading/error handling.
    /// The `fields` dictionary is merged with the selected device's UDID before sending.
    /// On success, the `onSuccess` closure is called to update app state.
    private func sendDeviceCommand(
        fields: [String: Any],
        loadingMessage: String,
        failurePrefix: String,
        onSuccess: () -> Void
    ) async {
        guard let udid = appState.selectedDeviceUDID else {
            appState.statusMessage = "No device selected"
            return
        }

        appState.isLoading = true
        appState.statusMessage = loadingMessage
        defer { appState.isLoading = false }

        do {
            var command = fields
            command["udid"] = udid
            _ = try await bridge.send(command: command)
            onSuccess()
        } catch {
            appState.statusMessage = "\(failurePrefix): \(error.localizedDescription)"
        }
    }
}
