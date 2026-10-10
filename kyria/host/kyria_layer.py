#!/usr/bin/env python3
"""Kyria layer status and lighting service (Linux hidraw, no Python dependencies)."""

import argparse
import fcntl
import json
import logging
import os
from pathlib import Path
import select
import signal
import struct
import time

COMMAND = 0xF0
STATUS, DATA, COMMIT, RELEASE, HEARTBEAT, BEGIN = range(6)
PROTOCOL_VERSION = 1
CHUNK_LEDS = 8
LOGGER = logging.getLogger("kyria-layer")


class ProtocolError(Exception):
    pass


def rgb(style):
    color = style["color"]
    if len(color) != 7 or color[0] != "#":
        raise ValueError(f"Invalid color: {color!r}")
    channels = bytes.fromhex(color[1:])
    brightness = style.get("brightness", 255)
    if not isinstance(brightness, int) or not 0 <= brightness <= 255:
        raise ValueError("Brightness must be an integer from 0 to 255")
    return bytes(channel * brightness // 255 for channel in channels)


def validate_config(config, led_map):
    interval = config.get("pollIntervalMs", 50)
    if not 10 <= interval <= 250:
        raise ValueError("pollIntervalMs must be between 10 and 250")
    for layer, scheme in config["layers"].items():
        if str(int(layer)) != layer or not 0 <= int(layer) <= 7:
            raise ValueError(f"Invalid layer: {layer!r}")
        rgb(scheme["underglow"])
        for key, style in scheme.get("keys", {}).items():
            if key != "*" and key not in led_map["keyLeds"]:
                raise ValueError(f"Unknown physical key: {key!r}")
            rgb(style)


def render_frame(config, led_map, layer):
    """Unspecified keys are dark; '*' supplies the per-key background."""
    scheme = config["layers"].get(str(layer), config["layers"].get("0"))
    frame = [b"\0\0\0"] * led_map["ledCount"]
    if scheme is None:
        return frame
    keys = scheme.get("keys", {})
    if "*" in keys:
        for index in led_map["switchLeds"]:
            frame[index] = rgb(keys["*"])
    for index in led_map["underglowLeds"]:
        frame[index] = rgb(scheme["underglow"])
    # Apply individual keys after the background, regardless of JSON key order.
    for key, style in keys.items():
        if key != "*":
            frame[led_map["keyLeds"][key]] = rgb(style)
    return frame


def device_paths(vendor_id, product_id, sys_root=Path("/sys/class/hidraw")):
    for entry in sorted(sys_root.glob("hidraw*")):
        try:
            fields = dict(line.split("=", 1) for line in (entry / "device/uevent").read_text().splitlines())
            _, vendor, product = fields["HID_ID"].split(":")
            descriptor = (entry / "device/report_descriptor").read_bytes()
            if (int(vendor, 16), int(product, 16)) == (vendor_id, product_id):
                # QMK raw-HID usage page 0xFF60, usage 0x61, not the typing interface.
                if b"\x06\x60\xff" in descriptor and b"\x09\x61" in descriptor:
                    yield Path("/dev") / entry.name
        except (OSError, ValueError, KeyError):
            continue


class Keyboard:
    def __init__(self, path):
        self.path = str(path)
        self.fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
        self.sequence = 0

    def close(self):
        os.close(self.fd)

    def request(self, operation, payload=b"", timeout=0.3):
        if len(payload) > 26:
            raise ValueError("Payload too large")
        self.sequence = (self.sequence + 1) % 256
        packet = bytearray(32)
        packet[:2] = bytes((COMMAND, operation))
        packet[2:2 + len(payload)] = payload
        packet[30] = self.sequence
        if os.write(self.fd, b"\0" + packet) != 33:
            raise ProtocolError("Short HID write")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.fd], [], [], max(0, deadline - time.monotonic()))
            if not ready:
                break
            try:
                reply = os.read(self.fd, 64)
            except BlockingIOError:
                continue
            if not reply:
                raise OSError("Keyboard disconnected")
            if len(reply) == 33 and reply[0] == 0:
                reply = reply[1:]
            if len(reply) != 32 or reply[:2] != bytes((COMMAND, operation)) or reply[30] != self.sequence:
                continue
            if reply[29]:
                raise ProtocolError(f"Firmware rejected operation {operation}: {reply[29]}")
            return reply
        raise ProtocolError("No host-lighting response (firmware extension missing or Vial unlock in progress)")

    def status(self):
        reply = self.request(STATUS)
        if reply[2] != PROTOCOL_VERSION or reply[16:20] != b"KYR1":
            raise ProtocolError("Unsupported host-lighting protocol")
        return {
            "layer": reply[4],
            "hostLighting": bool(reply[5]),
            "splitSyncPending": bool(reply[6]),
            "activeLayers": struct.unpack_from("<I", reply, 8)[0],
            "defaultLayers": struct.unpack_from("<I", reply, 12)[0],
            "ledCount": reply[3],
        }

    def frame(self, colors):
        self.request(BEGIN)
        for start in range(0, len(colors), CHUNK_LEDS):
            chunk = colors[start:start + CHUNK_LEDS]
            self.request(DATA, bytes((start, len(chunk))) + b"".join(chunk))
        self.request(COMMIT)


def connect(config, led_map):
    errors = []
    for path in device_paths(config["vendorId"], config["productId"]):
        keyboard = None
        try:
            keyboard = Keyboard(path)
            status = keyboard.status()
            if status["ledCount"] != led_map["ledCount"]:
                raise ProtocolError("Keyboard LED count does not match the Kyria rev3 map")
            return keyboard
        except (OSError, ProtocolError) as error:
            errors.append(f"{path}: {error}")
            if keyboard is not None:
                keyboard.close()
    raise OSError("; ".join(errors) or "Kyria raw-HID interface not found or inaccessible")


class StatusFile:
    def __init__(self, path):
        self.path = Path(path)
        self.previous = None

    def write(self, status):
        if status == self.previous:
            return
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        with temporary.open("w") as output:
            os.chmod(temporary, 0o600)
            json.dump(status, output, sort_keys=True)
            output.write("\n")
        temporary.replace(self.path)
        self.previous = status.copy()


def run(config, led_map, status_path):
    status_file = StatusFile(status_path)
    lock_file = Path(status_path).with_suffix(".lock").open("w")
    fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    running = True

    def stop(_signal, _frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    keyboard = None
    previous_frame = None
    last_heartbeat = 0
    last_warning = -10
    try:
        while running:
            try:
                if keyboard is None:
                    keyboard = connect(config, led_map)
                    previous_frame = None
                    LOGGER.info("Connected to %s", keyboard.path)
                status = keyboard.status()
                layer = status["layer"]
                frame = render_frame(config, led_map, layer)
                now = time.monotonic()
                if frame != previous_frame or not status["hostLighting"]:
                    keyboard.frame(frame)
                    previous_frame = frame
                    last_heartbeat = now
                elif now - last_heartbeat >= 0.4:
                    keyboard.request(HEARTBEAT)
                    last_heartbeat = now
                status.update({
                    "connected": True,
                    "name": config["layers"].get(str(layer), {}).get("name", f"Layer {layer}"),
                    "device": keyboard.path,
                })
                status_file.write(status)
                time.sleep(config.get("pollIntervalMs", 50) / 1000)
            except (OSError, ProtocolError) as error:
                status_file.write({"connected": False, "layer": None, "name": "Disconnected", "error": str(error)})
                if time.monotonic() - last_warning >= 10:
                    LOGGER.warning("%s", error)
                    last_warning = time.monotonic()
                if keyboard is not None:
                    keyboard.close()
                    keyboard = None
                time.sleep(1)
    finally:
        if keyboard is not None:
            try:
                keyboard.request(RELEASE)
            except (OSError, ProtocolError):
                pass
            keyboard.close()
        status_file.write({"connected": False, "layer": None, "name": "Stopped"})
        lock_file.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--led-map", type=Path, default=Path(__file__).with_name("led-map.json"))
    parser.add_argument("--status-file", default=None)
    parser.add_argument("--probe", action="store_true", help="Read status without changing lighting")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    config = json.loads(args.config.read_text())
    led_map = json.loads(args.led_map.read_text())
    validate_config(config, led_map)
    if args.probe:
        keyboard = connect(config, led_map)
        try:
            print(json.dumps(keyboard.status(), sort_keys=True))
        finally:
            keyboard.close()
        return
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if args.status_file is None and runtime is None:
        parser.error("Set XDG_RUNTIME_DIR or supply --status-file")
    run(config, led_map, args.status_file or str(Path(runtime) / "kyria-layer.json"))


if __name__ == "__main__":
    main()
