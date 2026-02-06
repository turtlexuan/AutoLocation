# Bundle Python Bridge via PyInstaller — Implementation Record

## Files Changed

### New
- **`Scripts/build_bridge.sh`** — Shell script that builds `bridge.py` into a standalone binary using PyInstaller `--onedir` mode. Outputs to `Scripts/dist/bridge/bridge`.

### Modified
- **`AutoLocation/Services/PythonBridge.swift`** — Added `findBundledBridge()` method that checks app bundle (`Contents/Resources/bridge/bridge`) and dev path (`Scripts/dist/bridge/bridge`). Modified `start()` to prefer bundled binary, falling back to Python for development.
- **`Scripts/bridge.py`** — Added `_is_bundled()` (checks `sys._MEIPASS`) and `_get_tunneld_command()` helper. Replaced all `sys.executable` references in tunnel command strings to use the helper.
- **`project.yml`** — Added `preBuildScripts` to run `build_bridge.sh` and folder reference for `Scripts/dist/bridge` as a resource (optional).
- **`.gitignore`** — Added `Scripts/dist/`, `Scripts/build/`, `Scripts/*.spec`.

## How to Build
```bash
# From project root:
Scripts/build_bridge.sh

# Verify:
echo '{"command": "ping"}' | Scripts/dist/bridge/bridge
```

## How it Works
1. `build_bridge.sh` creates venv, installs PyInstaller + pymobiledevice3, runs PyInstaller
2. Xcode pre-build script runs `build_bridge.sh` (incremental — skips if binary is newer than bridge.py)
3. `Scripts/dist/bridge/` folder is copied into app bundle as `Contents/Resources/bridge/`
4. At runtime, `PythonBridge.start()` checks for bundled binary first, falls back to Python
