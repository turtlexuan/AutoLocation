# AutoLocation

A native macOS application for simulating GPS location on connected iOS devices. Built with SwiftUI and powered by [pymobiledevice3](https://github.com/doronz88/pymobiledevice3).

AutoLocation provides real-time location spoofing through a visual map interface with support for manual coordinate entry, joystick-based movement, multi-waypoint route navigation, and GPX file playback.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Architecture](#architecture)
- [Usage Guide](#usage-guide)
- [iOS 17+ Tunnel](#ios-17-tunnel)
- [Build Configuration](#build-configuration)
- [Project Structure](#project-structure)

---

## Features

**Device Management**
- Automatic discovery of iOS devices over USB and Wi-Fi
- Multi-device support with one-click selection
- Real-time tunnel status indicators for iOS 17+ devices

**Location Simulation**
- Click-to-set location on an interactive map
- Manual coordinate input with validation
- Place search powered by MapKit
- Instant set/clear with device feedback

**Movement Controls**
- Virtual joystick for analog directional movement
- Keyboard input via WASD / Arrow keys
- Walk-to-pin: navigate from current position to a target point
- Speed presets: Walk (5 km/h), Run (11 km/h), Cycle (20 km/h), Drive (40 km/h)
- Custom speed entry in km/h
- Live stats: bearing, speed, distance traveled

**Route Planning**
- Visual multi-waypoint route editor (click map to add points)
- Drag-to-reorder waypoints
- Start/stop route following with automatic waypoint progression
- Loop mode for continuous route cycling
- Real-time route polyline with progress indicators

**GPX Playback**
- Import standard `.gpx` files (waypoints, tracks, routes)
- Adjustable playback speed (1x, 2x, 5x, 10x)
- Timestamp-aware pacing for realistic movement

**UI/UX**
- Collapsible sidebar sections with persisted state
- Design system with consistent tokens (color, typography, spacing)
- Glassmorphic map overlays
- Dark mode native

---

## Requirements

| Dependency | Version |
|---|---|
| macOS | 14.0 (Sonoma) or later |
| Xcode | 16.0+ |
| Swift | 5.9+ |
| Python | 3.11+ (3.13 recommended) |
| XcodeGen | Latest (`brew install xcodegen`) |
| pymobiledevice3 | 2.0.0+ |

**iOS Device Requirements**
- iOS 16 and earlier: USB connection, Developer Mode enabled
- iOS 17+: USB or Wi-Fi, Developer tunnel required (admin password prompt)

---

## Getting Started

### 1. Clone and setup

```bash
git clone <repository-url>
cd AutoLocation
```

### 2. Setup Python environment

```bash
cd Scripts
chmod +x setup.sh
./setup.sh
cd ..
```

This creates a virtual environment and installs `pymobiledevice3`.

### 3. Build the bridge binary (optional, recommended)

```bash
cd Scripts
chmod +x build_bridge.sh
./build_bridge.sh
cd ..
```

Packages the Python bridge into a standalone binary via PyInstaller for faster startup. If skipped, the app falls back to running `bridge.py` directly via Python.

### 4. Generate Xcode project and build

```bash
xcodegen generate
open AutoLocation.xcodeproj
```

Build and run from Xcode, or:

```bash
xcodebuild -scheme AutoLocation -configuration Debug build
```

### 5. Connect a device

- Plug in an iOS device via USB (or connect over Wi-Fi)
- Click **Refresh** in the Devices section
- For iOS 17+, click **Start Tunnel** when prompted (requires admin password)

---

## Architecture

### High-Level Overview

```
┌──────────────────────────────────────────────────────┐
│  SwiftUI Views                                       │
│  ┌────────────┐ ┌──────────┐ ┌────────────────────┐ │
│  │ SidebarView│ │  Map +   │ │ MovementControl    │ │
│  │            │ │ Overlays │ │ Panel              │ │
│  └──────┬─────┘ └─────┬────┘ └─────────┬──────────┘ │
│         │             │                │             │
│         ▼             ▼                ▼             │
│  ┌────────────────────────────────────────────────┐  │
│  │  AppState (@Observable)                        │  │
│  │  Single source of truth for all UI state       │  │
│  └─────────┬──────────────────────┬───────────────┘  │
│            │                      │                  │
│  ┌─────────▼──────────┐ ┌────────▼───────────────┐  │
│  │  DeviceManager     │ │  MovementEngine        │  │
│  │  Device discovery, │ │  Physics simulation,   │  │
│  │  location commands │ │  route following       │  │
│  └─────────┬──────────┘ └────────────────────────┘  │
│            │                                         │
│  ┌─────────▼──────────┐                              │
│  │  PythonBridge      │                              │
│  │  (Swift Actor)     │                              │
│  └─────────┬──────────┘                              │
└────────────┼─────────────────────────────────────────┘
             │  JSON-line protocol (stdin/stdout)
┌────────────▼─────────────────────────────────────────┐
│  bridge.py / bridge binary                           │
│  pymobiledevice3 — USB/tunnel communication          │
│  DtSimulateLocation (iOS <17) / DVT session (iOS 17+)│
└──────────────────────────────────────────────────────┘
```

### Layer Responsibilities

| Layer | Component | Role |
|---|---|---|
| **State** | `AppState` | Single observable object shared across all views. Holds devices, coordinates, simulation flags, route data. |
| **View** | `ContentView`, `SidebarView`, `MapContainerView`, etc. | Pure SwiftUI views bound to `AppState`. No business logic. |
| **Service** | `DeviceManager` | Orchestrates device discovery, tunnel management, and location commands via the bridge. |
| **Service** | `MovementEngine` | Timer-driven movement simulation. Haversine math for bearing/distance. Drives continuous location updates at 1 Hz. |
| **Service** | `LocationSearchService` | MapKit `MKLocalSearchCompleter` wrapper for place search. |
| **Bridge** | `PythonBridge` | Swift `actor` managing the Python subprocess lifecycle. JSON-line request/response protocol. |
| **Bridge** | `bridge.py` | Python process wrapping `pymobiledevice3`. Handles device enumeration, location simulation, GPX parsing, and tunnel status. |

### Concurrency Model

- **`AppState`**: `@Observable` (Swift 5.9 Observation framework). All mutations on `@MainActor`.
- **`DeviceManager`**: `@MainActor` — safe to call from UI, dispatches bridge commands.
- **`MovementEngine`**: `@MainActor` — timer-based loop, writes to `AppState` and calls `DeviceManager`.
- **`PythonBridge`**: Swift `actor` — serializes all subprocess I/O. Uses `CheckedContinuation` for async/await bridge.

### Data Flow

```
User taps map
  → ContentView.handleMapTap()
    → AppState.targetCoordinate = coord
      → SidebarView (coordinate fields update)
      → MapContainerView (camera pans, marker appears)

User clicks "Set Location"
  → DeviceManager.setLocation()
    → PythonBridge.send({"command": "set_location", ...})
      → bridge.py → pymobiledevice3 → iOS device
    → AppState.isSimulating = true
      → StatusBarView updates indicator

User drags joystick
  → JoystickView.onUpdate(bearing, magnitude)
    → MovementEngine.updateInput()
      → Timer tick (1s) → calculate new position
        → DeviceManager.setLocationSilent()
          → bridge.py → device
        → AppState.targetCoordinate = newPosition
          → Map marker moves
```

---

## Usage Guide

### Setting a Location

1. **Search**: Type in the search bar and select a result, or
2. **Click**: Click anywhere on the map to place a pin, or
3. **Manual**: Enter latitude/longitude in the sidebar fields
4. Click **Set Location** to push the coordinates to the device
5. Click **Clear Location** to stop simulation

### Movement

- **Joystick**: Drag the on-screen joystick to move in any direction
- **Keyboard**: Use `W/A/S/D` or arrow keys for 8-directional movement
- **Walk to Pin**: Click a destination on the map, then click "Walk to Pin" in the movement panel
- **Speed**: Select a preset or enter a custom speed in the Route Planner section

### Route Planning

1. Click **Add Waypoints** in the Route Planner section
2. Click the map to place waypoints (numbered markers appear)
3. Click **Done Editing** when finished
4. Configure speed and loop preference
5. Click **Start** to begin following the route
6. The blue arrow moves along the path, advancing through each waypoint

### GPX Playback

1. Expand the **GPX Playback** section
2. Click **Load GPX File** and select a `.gpx` file
3. Choose playback speed multiplier
4. Click **Play** to start, **Stop** to end

---

## iOS 17+ Tunnel

iOS 17 introduced a new developer connection model requiring a persistent tunnel daemon.

**How it works:**

1. AutoLocation detects the iOS version and shows the tunnel section
2. Clicking **Start Tunnel** prompts for your admin password (via macOS system dialog)
3. The tunnel daemon (`pymobiledevice3 remote tunneld`) starts in the background
4. AutoLocation polls until the tunnel is established (up to 20 seconds)
5. Once connected, all location commands route through the tunnel's DVT session

**Manual tunnel start** (if automatic prompt fails):

```bash
sudo pymobiledevice3 remote tunneld
```

The tunnel daemon persists across app restarts. It only needs to be started once per boot.

---

## Build Configuration

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation.

**Key settings in `project.yml`:**

| Setting | Value | Reason |
|---|---|---|
| `MACOSX_DEPLOYMENT_TARGET` | `14.0` | Requires MapKit SwiftUI APIs from Sonoma |
| `SWIFT_STRICT_CONCURRENCY` | `complete` | Full actor isolation enforcement |
| `ENABLE_USER_SCRIPT_SANDBOXING` | `false` | Required for Python bridge subprocess |
| `CODE_SIGN_IDENTITY` | `-` | Ad-hoc signing for local development |

**Pre-build script**: `build_bridge.sh` runs before each build to bundle the Python bridge binary. Incremental — skips if the binary is newer than `bridge.py`.

---

## Project Structure

```
AutoLocation/
├── project.yml                      # XcodeGen project definition
├── README.md
│
├── AutoLocation/
│   ├── AutoLocationApp.swift        # App entry point, window config
│   ├── Info.plist                   # App metadata, location permission
│   ├── AutoLocation.entitlements
│   │
│   ├── Models/
│   │   ├── AppState.swift           # Central observable state
│   │   ├── Device.swift             # iOS device model
│   │   └── Route.swift              # Waypoint model with Codable coords
│   │
│   ├── Services/
│   │   ├── PythonBridge.swift       # Actor — subprocess JSON protocol
│   │   ├── DeviceManager.swift      # Device discovery, location, tunnel
│   │   ├── MovementEngine.swift     # Physics simulation, route following
│   │   └── LocationSearchService.swift  # MapKit search completer
│   │
│   ├── Views/
│   │   ├── ContentView.swift        # Main layout, keyboard input, status bar
│   │   ├── SidebarView.swift        # Device list, location, route, GPX sections
│   │   ├── MapContainerView.swift   # Map display, markers, polylines, recenter
│   │   ├── LocationSearchView.swift # Search bar overlay with results dropdown
│   │   ├── MovementControlPanel.swift  # Joystick, speed picker, stats
│   │   ├── CoordinateInputView.swift   # Lat/lon text fields with validation
│   │   └── JoystickView.swift       # Analog joystick with compass labels
│   │
│   └── DesignSystem/
│       ├── DesignSystem.swift       # DS namespace: colors, typography, spacing
│       └── Components/
│           ├── CollapsibleSection.swift  # Expandable card with persisted state
│           ├── ActionButton.swift        # Styled button (primary/success/etc.)
│           ├── StatusBadge.swift         # Colored dot + label capsule
│           └── StatCard.swift            # Icon + value + label metric card
│
└── Scripts/
    ├── bridge.py                    # Python bridge — pymobiledevice3 wrapper
    ├── build_bridge.sh              # PyInstaller bundler (optional)
    ├── setup.sh                     # Python venv + dependency installer
    └── requirements.txt             # pymobiledevice3>=2.0.0
```

---

## License

Copyright 2025. All rights reserved.
