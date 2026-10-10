import importlib.util
import json
from pathlib import Path
import re
import struct
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("kyria_layer", ROOT / "host/kyria_layer.py")
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)
LED_MAP = json.loads((ROOT / "host/led-map.json").read_text())
DEFAULTS = json.loads((ROOT / "host/defaults.json").read_text())


class FrameTests(unittest.TestCase):
    def test_distinct_layer_underglow_and_physical_directions(self):
        config = {"layers": DEFAULTS}
        focus = host.render_frame(config, LED_MAP, 2)
        arrows = host.render_frame(config, LED_MAP, 3)
        for key in ("N", "M", "Comma", "Period"):
            self.assertEqual(focus[LED_MAP["keyLeds"][key]], bytes.fromhex("4fea55"))
        for key in ("H", "J", "K", "L"):
            self.assertEqual(arrows[LED_MAP["keyLeds"][key]], bytes.fromhex("4fea55"))
        self.assertEqual(len({host.render_frame(config, LED_MAP, i)[0] for i in range(8)}), 8)
        self.assertEqual(LED_MAP["underglowLeds"], list(range(25, 31)))

    def test_numbers_highlight_home_rows_with_left_underglow_bypassed(self):
        frame = host.render_frame({"layers": DEFAULTS}, LED_MAP, 1)
        for key, index in zip("GFDSA", range(13, 18)):
            self.assertEqual(LED_MAP["keyLeds"][key], index)
            self.assertEqual(frame[index], host.rgb(DEFAULTS["1"]["keys"][key]))
        background = host.rgb(DEFAULTS["1"]["keys"]["*"])
        for index in range(19, 24):
            self.assertEqual(frame[index], background)
        for key, index in zip(("H", "J", "K", "L", "Semicolon"), range(44, 49)):
            self.assertEqual(LED_MAP["keyLeds"][key], index)
            self.assertEqual(frame[index], host.rgb(DEFAULTS["1"]["keys"][key]))

    def test_host_led_map_matches_firmware_hardware_definition(self):
        source = (ROOT / "rev3/keyboard.json").read_text()
        hardware = json.loads(re.sub(r"//[^\n]*", "", source))
        leds = hardware["rgb_matrix"]["layout"]
        self.assertEqual(LED_MAP["ledCount"], len(leds))
        self.assertEqual(hardware["rgb_matrix"]["split_count"], [25, 31])
        self.assertEqual(LED_MAP["underglowLeds"], [i for i, led in enumerate(leds) if led["flags"] == 2])
        self.assertEqual(LED_MAP["switchLeds"], [i for i, led in enumerate(leds) if led["flags"] == 4])
        for index, led in enumerate(leds):
            if "matrix" in led:
                row, column = led["matrix"]
                self.assertEqual(LED_MAP["keyLeds"][f"{row},{column}"], index)

    def test_brightness_and_key_override_are_order_independent(self):
        config = {"layers": {"0": {
            "keys": {"H": {"color": "#ff0000", "brightness": 128}, "*": {"color": "#0000ff"}},
            "underglow": {"color": "#00ff00", "brightness": 64},
        }}}
        frame = host.render_frame(config, LED_MAP, 0)
        self.assertEqual(frame[44], b"\x80\0\0")
        self.assertEqual(frame[45], b"\0\0\xff")
        self.assertEqual(frame[25], b"\0\x40\0")

    def test_invalid_keys_layers_and_brightness_are_rejected(self):
        for scheme in [
            {"keys": {"typo": {"color": "#ffffff"}}, "underglow": {"color": "#000000"}},
            {"keys": {}, "underglow": {"color": "#ffffff", "brightness": 256}},
        ]:
            with self.assertRaises(ValueError):
                host.validate_config({"layers": {"0": scheme}}, LED_MAP)
        with self.assertRaises(ValueError):
            host.validate_config({"layers": {"8": DEFAULTS["0"]}}, LED_MAP)

    def test_status_is_atomic_and_unchanged_status_is_not_rewritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "status.json"
            writer = host.StatusFile(path)
            writer.write({"layer": 2})
            modified = path.stat().st_mtime_ns
            writer.write({"layer": 2})
            self.assertEqual(path.stat().st_mtime_ns, modified)
            writer.write({"layer": 3})
            self.assertEqual(json.loads(path.read_text()), {"layer": 3})
            self.assertFalse(path.with_suffix(".json.tmp").exists())


class ProtocolTests(unittest.TestCase):
    def keyboard(self):
        keyboard = host.Keyboard.__new__(host.Keyboard)
        keyboard.fd = 99
        keyboard.sequence = 0
        return keyboard

    def test_unrelated_hid_replies_are_ignored(self):
        keyboard = self.keyboard()
        reply = bytearray(32)
        reply[:5] = bytes((host.COMMAND, host.STATUS, host.PROTOCOL_VERSION, LED_MAP["ledCount"], 3))
        reply[8:12] = struct.pack("<I", 8)
        reply[12:16] = struct.pack("<I", 1)
        reply[16:20] = b"KYR1"
        reply[30] = 1
        with patch.object(host.os, "write", return_value=33) as write, \
             patch.object(host.select, "select", return_value=([99], [], [])), \
             patch.object(host.os, "read", side_effect=[b"\xff" * 32, bytes(reply)]):
            status = keyboard.status()
        self.assertEqual(status["layer"], 3)
        self.assertEqual(status["activeLayers"], 8)
        self.assertEqual(write.call_args.args[1][0], 0)

    def test_frame_is_chunked_and_committed_after_all_leds(self):
        keyboard = self.keyboard()
        frame = host.render_frame({"layers": DEFAULTS}, LED_MAP, 2)
        with patch.object(keyboard, "request") as request:
            keyboard.frame(frame)
        calls = request.call_args_list
        self.assertEqual(calls[0].args, (host.BEGIN,))
        self.assertEqual(calls[-1].args, (host.COMMIT,))
        self.assertEqual(len(calls), 9)
        reconstructed = b"".join(call.args[1][2:] for call in calls[1:-1])
        self.assertEqual(reconstructed, b"".join(frame))

    def test_old_firmware_with_global_brightness_scaling_is_rejected(self):
        keyboard = self.keyboard()
        reply = bytearray(32)
        reply[2] = 1
        reply[16:20] = b"KYR1"
        with patch.object(keyboard, "request", return_value=reply):
            with self.assertRaisesRegex(host.ProtocolError, "Unsupported host-lighting protocol"):
                keyboard.status()


if __name__ == "__main__":
    unittest.main()
