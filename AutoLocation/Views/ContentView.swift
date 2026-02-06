import SwiftUI

struct ContentView: View {
    var appState: AppState
    var deviceManager: DeviceManager?

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState, deviceManager: deviceManager)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            VStack(spacing: 0) {
                MapContainerView(appState: appState, deviceManager: deviceManager)
                StatusBarView(appState: appState)
            }
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
