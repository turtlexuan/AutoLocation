# Movement Control Panel Implementation Plan

## New Files
1. **MovementEngine.swift** (Services/) - Core movement logic: timer at 1Hz, coordinate math, speed modes
2. **JoystickView.swift** (Views/) - Custom DragGesture joystick, outputs bearing + magnitude
3. **MovementControlPanel.swift** (Views/) - Floating panel: joystick + speed picker + stats + walk-to-pin

## Modified Files
4. **AppState.swift** - Add `isMovementActive`, `currentBearing`, `currentSpeed` state
5. **DeviceManager.swift** - Add `setLocationSilent()` for non-blocking movement updates
6. **MapContainerView.swift** - Add heading indicator annotation, pass movementEngine
7. **ContentView.swift** - Overlay MovementControlPanel on map, add keyboard handling
8. **AutoLocationApp.swift** - Create MovementEngine instance

## Architecture
- MovementEngine runs a 1Hz Timer
- Each tick: newPos = currentPos + speed*bearing, then sends set_location via bridge
- JoystickView feeds (bearing, magnitude) into MovementEngine
- WASD/arrow keys also feed into MovementEngine
- Walk-to-pin: calculates bearing to target, auto-walks until arrival
- appState.targetCoordinate is updated each tick so the map marker moves
