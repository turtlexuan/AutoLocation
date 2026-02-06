import SwiftUI

@main
struct AutoLocationApp: App {
    @State private var appState = AppState()
    @State private var deviceManager: DeviceManager?
    @State private var movementEngine: MovementEngine?

    var body: some Scene {
        WindowGroup {
            ContentView(
                appState: appState,
                deviceManager: deviceManager,
                movementEngine: movementEngine
            )
            .onAppear {
                let manager = DeviceManager(appState: appState)
                deviceManager = manager
                movementEngine = MovementEngine(appState: appState, deviceManager: manager)
                Task {
                    await manager.startBridge()
                    await manager.refreshDevices()
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
    }
}
