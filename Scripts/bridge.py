#!/usr/bin/env python3
"""
AutoLocation Python Bridge
===========================
A long-running process that accepts JSON commands on stdin and returns
JSON responses on stdout. Communicates with pymobiledevice3 to control
iPhone GPS location simulation.

Protocol:
  - One JSON object per line (JSON-line protocol)
  - On startup, prints {"type": "ready"}
  - Reads commands from stdin, writes responses to stdout
  - All stdout prints use flush=True
  - Debug/error logging goes to stderr

iOS 17+ Tunnel:
  For iOS >= 17, a developer tunnel must be running. The bridge will:
  1. Try to connect via the tunneld daemon (pymobiledevice3 remote tunneld)
  2. If tunneld is not running, try to start a tunnel subprocess
  3. Use the tunnel's RSD service for location simulation
"""

import json
import os
import signal
import sys
import threading
import time
import xml.etree.ElementTree as ET
from datetime import datetime

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------

_shutdown_event = threading.Event()


def _handle_signal(signum, frame):
    """Handle SIGINT / SIGTERM – set the shutdown flag and exit cleanly."""
    log(f"Received signal {signum}, shutting down...")
    _shutdown_event.set()
    sys.exit(0)


signal.signal(signal.SIGINT, _handle_signal)
signal.signal(signal.SIGTERM, _handle_signal)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def log(msg: str):
    """Write a debug message to stderr (never to stdout)."""
    print(f"[bridge] {msg}", file=sys.stderr, flush=True)


def respond(obj: dict):
    """Write a JSON response to stdout (one line, flushed)."""
    print(json.dumps(obj), flush=True)


def error_response(message: str) -> dict:
    return {"status": "error", "message": message}


def ok_response(**kwargs) -> dict:
    return {"status": "ok", **kwargs}


def _is_bundled() -> bool:
    """Return True if running as a PyInstaller bundle."""
    return getattr(sys, "_MEIPASS", None) is not None


def _get_tunneld_command() -> str:
    """Return the shell command to start the tunneld daemon."""
    if _is_bundled():
        return "sudo pymobiledevice3 remote tunneld"
    return f"sudo {sys.executable} -m pymobiledevice3 remote tunneld"


# ---------------------------------------------------------------------------
# pymobiledevice3 imports (deferred so we can report a friendly error)
# ---------------------------------------------------------------------------

_pmd3_available = False
_pmd3_import_error = None

try:
    from pymobiledevice3.usbmux import list_devices as usbmux_list_devices
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.services.simulate_location import DtSimulateLocation

    _pmd3_available = True
except ImportError as exc:
    _pmd3_import_error = str(exc)

# Tunneld API for iOS 17+
_tunneld_available = False
try:
    from pymobiledevice3.tunneld.api import (
        get_tunneld_devices,
        get_tunneld_device_by_udid,
    )
    from pymobiledevice3.remote.remote_service_discovery import (
        RemoteServiceDiscoveryService,
    )

    _tunneld_available = True
except ImportError:
    pass


def require_pmd3():
    """Raise if pymobiledevice3 is not installed."""
    if not _pmd3_available:
        raise RuntimeError(
            f"pymobiledevice3 is not installed or could not be imported: "
            f"{_pmd3_import_error}. "
            f"Please run: pip install pymobiledevice3>=2.0.0"
        )


# ---------------------------------------------------------------------------
# Lockdown client cache & tunnel RSD cache
# ---------------------------------------------------------------------------

_lockdown_cache: dict = {}  # udid -> lockdown client
_rsd_cache: dict = {}  # udid -> RemoteServiceDiscoveryService (from tunnel)
_tunnel_process = None  # Background tunnel subprocess

# Persistent DVT session for iOS 17+ location simulation.
# Keyed by udid -> {"dvt": DvtSecureSocketProxyService, "loc_sim": LocationSimulation}
# We keep the DVT connection alive between set and clear so that
# stopLocationSimulation() is called on the same channel that started it.
_dvt_sessions: dict = {}


def get_lockdown(udid: str = None):
    """
    Return a cached lockdown client for the given udid.
    If udid is None, connect to the first available device.
    """
    require_pmd3()

    if udid and udid in _lockdown_cache:
        return _lockdown_cache[udid]

    if udid:
        lockdown = create_using_usbmux(serial=udid)
    else:
        lockdown = create_using_usbmux()

    resolved_udid = lockdown.udid if hasattr(lockdown, "udid") else udid or "unknown"
    _lockdown_cache[resolved_udid] = lockdown
    return lockdown


def invalidate_lockdown(udid: str = None):
    """Remove a cached lockdown client (e.g. after an error)."""
    if udid and udid in _lockdown_cache:
        del _lockdown_cache[udid]
    if udid and udid in _rsd_cache:
        del _rsd_cache[udid]
    if udid:
        _close_dvt_session(udid)


def _ios_major_version(lockdown) -> int:
    """Return the major iOS version number from a lockdown client."""
    version_str = lockdown.product_version  # e.g. "17.1.2"
    return int(version_str.split(".")[0])


def _get_rsd_for_device(udid: str = None) -> "RemoteServiceDiscoveryService":
    """
    Get an RSD service provider for an iOS 17+ device via tunneld.
    The tunneld daemon must be running (sudo pymobiledevice3 remote tunneld).
    """
    if not _tunneld_available:
        raise RuntimeError(
            "tunneld API not available. Please upgrade pymobiledevice3."
        )

    # Check cache first
    if udid and udid in _rsd_cache:
        return _rsd_cache[udid]

    try:
        if udid:
            rsd = get_tunneld_device_by_udid(udid)
            if rsd is None:
                raise RuntimeError(
                    f"No tunnel found for device {udid}. "
                    f"Please start the tunnel daemon first:\n"
                    f"  {_get_tunneld_command()}"
                )
        else:
            devices = get_tunneld_devices()
            if not devices:
                raise RuntimeError(
                    "No tunneled devices found. "
                    "Please start the tunnel daemon first:\n"
                    f"  {_get_tunneld_command()}"
                )
            rsd = devices[0]

        if udid:
            _rsd_cache[udid] = rsd
        return rsd
    except Exception as e:
        if "Connection refused" in str(e) or "TunneldConnection" in type(e).__name__:
            raise RuntimeError(
                "Tunnel daemon is not running. For iOS 17+, you need to start it:\n"
                f"  {_get_tunneld_command()}\n"
                "Then click 'Start Tunnel' in the app, or run the command above in Terminal."
            ) from e
        raise


# ---------------------------------------------------------------------------
# Tunnel management
# ---------------------------------------------------------------------------


def cmd_start_tunnel() -> dict:
    """Start the tunneld daemon as a background subprocess with sudo."""
    global _tunnel_process

    # Check if tunneld is already running
    try:
        if _tunneld_available:
            devices = get_tunneld_devices()
            return ok_response(
                message=f"Tunnel daemon already running ({len(devices)} device(s) tunneled)",
                tunnelRunning=True,
            )
    except Exception:
        pass

    tunneld_cmd = _get_tunneld_command()

    # We can't start sudo from the bridge directly in a useful way.
    # Return instructions for the user.
    return ok_response(
        message=(
            "Tunnel daemon needs to be started with admin privileges.\n"
            "Please run this command in Terminal:\n\n"
            f"  {tunneld_cmd}\n\n"
            "Keep that terminal open, then click Refresh in the app."
        ),
        tunnelRunning=False,
        command=tunneld_cmd,
    )


def cmd_check_tunnel() -> dict:
    """Check if the tunneld daemon is running and has connected devices."""
    if not _tunneld_available:
        return ok_response(tunnelRunning=False, message="tunneld API not available")

    try:
        devices = get_tunneld_devices()
        return ok_response(
            tunnelRunning=True,
            deviceCount=len(devices),
            message=f"Tunnel running with {len(devices)} device(s)",
        )
    except Exception as e:
        return ok_response(
            tunnelRunning=False,
            message=f"Tunnel not running: {e}",
        )


# ---------------------------------------------------------------------------
# Command implementations
# ---------------------------------------------------------------------------


def cmd_ping() -> dict:
    return ok_response(message="pong")


def cmd_list_devices() -> dict:
    require_pmd3()
    connected = usbmux_list_devices()
    devices = []
    for mux_device in connected:
        try:
            lockdown = create_using_usbmux(serial=mux_device.serial)
            major = _ios_major_version(lockdown)

            # Check tunnel status for iOS 17+
            tunnel_status = "not_needed"
            if major >= 17:
                tunnel_status = "not_connected"
                try:
                    if _tunneld_available:
                        rsd = get_tunneld_device_by_udid(mux_device.serial)
                        if rsd is not None:
                            tunnel_status = "connected"
                except Exception:
                    pass

            devices.append(
                {
                    "udid": mux_device.serial,
                    "name": lockdown.display_name,
                    "productType": lockdown.product_type,
                    "osVersion": lockdown.product_version,
                    "connectionType": str(mux_device.connection_type),
                    "tunnelStatus": tunnel_status,
                    "needsTunnel": major >= 17,
                }
            )
        except Exception as e:
            devices.append(
                {
                    "udid": mux_device.serial,
                    "name": "Unknown",
                    "productType": "Unknown",
                    "osVersion": "Unknown",
                    "connectionType": str(mux_device.connection_type),
                    "tunnelStatus": "unknown",
                    "needsTunnel": False,
                    "error": str(e),
                }
            )
    return ok_response(devices=devices)


def _set_location_legacy(lockdown, latitude: float, longitude: float):
    """iOS < 17: use DtSimulateLocation via lockdown."""
    DtSimulateLocation(lockdown).set(latitude, longitude)


def _clear_location_legacy(lockdown):
    """iOS < 17: use DtSimulateLocation via lockdown."""
    DtSimulateLocation(lockdown).clear()


def _get_dvt_session(rsd, udid: str):
    """
    Get or create a persistent DVT session for the given device.
    Returns the LocationSimulation object bound to a long-lived DVT channel.
    """
    from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import DvtSecureSocketProxyService
    from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

    if udid in _dvt_sessions:
        return _dvt_sessions[udid]["loc_sim"]

    # Open a new DVT connection (enter the context manager manually to keep it alive)
    dvt = DvtSecureSocketProxyService(lockdown=rsd)
    dvt.__enter__()
    loc_sim = LocationSimulation(dvt)
    _dvt_sessions[udid] = {"dvt": dvt, "loc_sim": loc_sim}
    log(f"Opened persistent DVT session for device {udid}")
    return loc_sim


def _close_dvt_session(udid: str):
    """Close and remove the persistent DVT session for the given device."""
    session = _dvt_sessions.pop(udid, None)
    if session:
        try:
            session["dvt"].__exit__(None, None, None)
            log(f"Closed DVT session for device {udid}")
        except Exception as e:
            log(f"Error closing DVT session for {udid}: {e}")


def _set_location_dvt(rsd, udid: str, latitude: float, longitude: float):
    """iOS 17+: use persistent DVT LocationSimulation channel via tunnel RSD."""
    loc_sim = _get_dvt_session(rsd, udid)
    loc_sim.set(latitude, longitude)


def _clear_location_dvt(rsd, udid: str):
    """
    iOS 17+: stop location simulation by clearing and closing the DVT session.

    The key insight is that iOS ties the simulation to the instruments channel.
    Closing the DVT connection is the most reliable way to stop simulation
    (same as what happens when you disconnect Xcode). We also send the
    stopLocationSimulation message first as a courtesy, with a brief delay
    to let the device process it before tearing down the channel.
    """
    if udid in _dvt_sessions:
        try:
            loc_sim = _dvt_sessions[udid]["loc_sim"]
            loc_sim.clear()
            log(f"Sent stopLocationSimulation for {udid}")
        except Exception as e:
            log(f"stopLocationSimulation failed for {udid} (will close session anyway): {e}")
        # Give the device a moment to process the stop before we tear down the channel
        time.sleep(0.5)
        _close_dvt_session(udid)
    else:
        log(f"No active DVT session for {udid}, nothing to clear")


def cmd_set_location(latitude: float, longitude: float, udid: str = None) -> dict:
    require_pmd3()
    lockdown = get_lockdown(udid)
    major = _ios_major_version(lockdown)

    try:
        if major >= 17:
            rsd = _get_rsd_for_device(udid)
            _set_location_dvt(rsd, udid or lockdown.udid, latitude, longitude)
        else:
            _set_location_legacy(lockdown, latitude, longitude)
    except Exception:
        # On error, clean up the DVT session too
        if udid:
            _close_dvt_session(udid)
        invalidate_lockdown(udid)
        raise

    return ok_response()


def cmd_clear_location(udid: str = None) -> dict:
    require_pmd3()
    lockdown = get_lockdown(udid)
    major = _ios_major_version(lockdown)

    try:
        if major >= 17:
            rsd = _get_rsd_for_device(udid)
            _clear_location_dvt(rsd, udid or lockdown.udid)
        else:
            _clear_location_legacy(lockdown)
    except Exception:
        # On error, clean up the DVT session too
        if udid:
            _close_dvt_session(udid)
        invalidate_lockdown(udid)
        raise

    return ok_response()


# ---------------------------------------------------------------------------
# GPX playback
# ---------------------------------------------------------------------------

_playback_thread: threading.Thread = None
_playback_stop = threading.Event()


def _parse_gpx(path: str) -> list:
    """
    Parse a GPX file and return a list of dicts:
        [{"lat": float, "lon": float, "time": datetime | None}, ...]

    Handles both <wpt> (waypoints) and <trkpt> (track points).
    """
    tree = ET.parse(path)
    root = tree.getroot()

    # Detect namespace (GPX files typically use a default namespace)
    ns = ""
    if root.tag.startswith("{"):
        ns = root.tag.split("}")[0] + "}"

    points = []

    # Collect <wpt> elements
    for wpt in root.findall(f"{ns}wpt"):
        point = _parse_point(wpt, ns)
        if point:
            points.append(point)

    # Collect <trkpt> elements from all tracks/segments
    for trk in root.findall(f"{ns}trk"):
        for seg in trk.findall(f"{ns}trkseg"):
            for trkpt in seg.findall(f"{ns}trkpt"):
                point = _parse_point(trkpt, ns)
                if point:
                    points.append(point)

    # Collect <rtept> elements from routes
    for rte in root.findall(f"{ns}rte"):
        for rtept in rte.findall(f"{ns}rtept"):
            point = _parse_point(rtept, ns)
            if point:
                points.append(point)

    return points


def _parse_point(element, ns: str) -> dict:
    """Extract lat, lon, and optional time from a GPX point element."""
    lat = element.get("lat")
    lon = element.get("lon")
    if lat is None or lon is None:
        return None

    time_el = element.find(f"{ns}time")
    parsed_time = None
    if time_el is not None and time_el.text:
        try:
            text = time_el.text.strip()
            # Handle common GPX time formats
            if text.endswith("Z"):
                text = text[:-1] + "+00:00"
            parsed_time = datetime.fromisoformat(text)
        except ValueError:
            pass

    return {"lat": float(lat), "lon": float(lon), "time": parsed_time}


def _playback_worker(path: str, udid: str, speed: float):
    """Background thread that replays GPX waypoints sequentially."""
    try:
        points = _parse_gpx(path)
        if not points:
            log(f"GPX file '{path}' contains no points")
            return

        log(f"Starting GPX playback: {len(points)} points, speed={speed}x")

        for i, point in enumerate(points):
            if _playback_stop.is_set():
                log("Playback stopped by user")
                return

            try:
                cmd_set_location(point["lat"], point["lon"], udid)
            except Exception as e:
                log(f"Error setting location at point {i}: {e}")
                return

            # Calculate delay until next point
            if i < len(points) - 1:
                delay = _compute_delay(point, points[i + 1], speed)
                # Wait in small increments so we can respond to stop quickly
                waited = 0.0
                while waited < delay:
                    if _playback_stop.is_set():
                        log("Playback stopped by user")
                        return
                    step = min(0.1, delay - waited)
                    _playback_stop.wait(step)
                    waited += step

        log("GPX playback finished")
    except Exception as e:
        log(f"Playback error: {e}")


def _compute_delay(current: dict, next_pt: dict, speed: float) -> float:
    """
    Compute seconds to wait between two GPX points.
    Uses timestamps if available, otherwise defaults to 1 second.
    """
    if current.get("time") and next_pt.get("time"):
        delta = (next_pt["time"] - current["time"]).total_seconds()
        if delta > 0:
            return max(0.0, delta / speed)
    # Default interval when no timestamps
    return 1.0 / speed


def cmd_play_gpx(path: str, udid: str = None, speed: float = 1.0) -> dict:
    global _playback_thread

    # Stop any existing playback first
    _stop_playback_internal()

    if speed <= 0:
        return error_response("Speed must be greater than 0")

    _playback_stop.clear()
    _playback_thread = threading.Thread(
        target=_playback_worker,
        args=(path, udid, speed),
        daemon=True,
    )
    _playback_thread.start()
    return ok_response()


def _stop_playback_internal():
    """Stop any running playback thread and wait for it to finish."""
    global _playback_thread
    if _playback_thread and _playback_thread.is_alive():
        _playback_stop.set()
        _playback_thread.join(timeout=5.0)
    _playback_thread = None


def cmd_stop_playback() -> dict:
    _stop_playback_internal()
    return ok_response()


# ---------------------------------------------------------------------------
# Command dispatcher
# ---------------------------------------------------------------------------

_COMMANDS = {
    "ping": lambda data: cmd_ping(),
    "list_devices": lambda data: cmd_list_devices(),
    "set_location": lambda data: cmd_set_location(
        latitude=data["latitude"],
        longitude=data["longitude"],
        udid=data.get("udid"),
    ),
    "clear_location": lambda data: cmd_clear_location(
        udid=data.get("udid"),
    ),
    "play_gpx": lambda data: cmd_play_gpx(
        path=data["path"],
        udid=data.get("udid"),
        speed=data.get("speed", 1.0),
    ),
    "stop_playback": lambda data: cmd_stop_playback(),
    "start_tunnel": lambda data: cmd_start_tunnel(),
    "check_tunnel": lambda data: cmd_check_tunnel(),
}


def dispatch(line: str):
    """Parse a JSON command line and execute the matching handler."""
    try:
        data = json.loads(line)
    except json.JSONDecodeError as e:
        respond(error_response(f"Invalid JSON: {e}"))
        return

    command = data.get("command")
    if not command:
        respond(error_response("Missing 'command' field"))
        return

    handler = _COMMANDS.get(command)
    if not handler:
        respond(error_response(f"Unknown command: {command}"))
        return

    try:
        result = handler(data)
        respond(result)
    except KeyError as e:
        respond(error_response(f"Missing required field: {e}"))
    except Exception as e:
        log(f"Error executing '{command}': {e}")
        respond(error_response(str(e)))


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------


def main():
    # Signal readiness
    respond({"type": "ready"})

    log("Bridge started, waiting for commands...")

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            if _shutdown_event.is_set():
                break
            dispatch(line)
    except EOFError:
        log("stdin closed, exiting")
    except KeyboardInterrupt:
        log("Interrupted, exiting")
    finally:
        _stop_playback_internal()
        # Close any persistent DVT sessions
        for udid in list(_dvt_sessions.keys()):
            _close_dvt_session(udid)
        log("Bridge shut down")


def start_tunneld():
    """Run the pymobiledevice3 tunneld daemon (requires root privileges).

    This is invoked when the bridge binary is called with --tunneld.
    It starts the same daemon as `pymobiledevice3 remote tunneld`.
    """
    log("Starting tunneld daemon...")
    try:
        from pymobiledevice3.cli import cli

        cli(["remote", "tunneld"], standalone_mode=False)
    except SystemExit:
        pass
    except Exception as e:
        log(f"Failed to start tunneld: {e}")
        sys.exit(1)


if __name__ == "__main__":
    if "--tunneld" in sys.argv:
        start_tunneld()
    else:
        main()
