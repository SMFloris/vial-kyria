"""Exercise the flash walkthrough with fake USB/HID tools; never access hardware."""
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

FAKE = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
name = pathlib.Path(sys.argv[0]).name
root = pathlib.Path(os.environ['FLASH_TEST_ROOT'])
args = sys.argv[1:]
with (root / 'events').open('a') as log:
    log.write(name + ' ' + ' '.join(args) + '\n')
if name == 'systemctl':
    if 'is-active' in args: sys.exit(0)
elif name == 'lsblk':
    drives = [{'name': '/dev/fake', 'label': 'RPI-RP2'}]
    if os.environ.get('FLASH_TEST_FAILURE') == 'ambiguous': drives *= 2
    print(json.dumps({'blockdevices': drives}))
elif name == 'findmnt':
    print(json.dumps({'filesystems': [{'target': str(root / 'mount')}]}))
elif name == 'cp':
    shutil.copyfile(args[-2], args[-1])
elif name == 'git':
    revision = 'ae5e437c6401cd0686ed7efb096624e665732ca4'
    if args[0] == 'init':
        (pathlib.Path(args[-1]) / '.git').mkdir()
    else:
        checkout = pathlib.Path(args[1])
        action = args[2]
        if action == 'fetch' and os.environ.get('FLASH_TEST_FAILURE') == 'download':
            sys.exit(1)
        if action == 'checkout':
            (checkout / 'quantum').mkdir()
            (checkout / 'quantum/vial.c').touch()
            (checkout / 'keyboards/splitkb/kyria').mkdir(parents=True)
        elif action == 'rev-parse': print(revision)
        elif action == 'remote' and args[3] == 'get-url':
            print('https://github.com/splitkb/vial-qmk.git')
        elif action == 'submodule' and os.environ.get('FLASH_TEST_FAILURE') == 'submodule':
            sys.exit(1)
elif name == 'make':
    checkout = pathlib.Path(args[1])
    shutil.copyfile(root / 'firmware.uf2', checkout / 'splitkb_kyria_rev3_floris_liatris.uf2')
elif name == 'vitaly':
    action = args[2]
    if action == 'devices': print('Path: /dev/hidrawFAKE')
    elif action == 'lock':
        print('Device is locked: ' + ('true' if os.environ.get('FLASH_TEST_FAILURE') == 'unlock' else 'false'))
    elif action == 'bootload' and os.environ.get('FLASH_TEST_FAILURE') == 'bootload':
        print('Error: failed to enter bootloader')
    elif action == 'load' and os.environ.get('FLASH_TEST_FAILURE') == 'load':
        print('Error: failed to load layout')  # Real CLI can exit 0 on error.
    elif action == 'save':
        layout = json.loads((root / 'layout.vil').read_text())
        if os.environ.get('FLASH_TEST_FAILURE') == 'readback': layout['layout'][0] = []
        pathlib.Path(args[-1]).write_text(json.dumps(layout))
'''


class FlashTests(unittest.TestCase):
    def run_walkthrough(self, failure='', main_half='left', automatic_build=False, manual_reset=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'bin').mkdir()
            (root / 'mount').mkdir()
            (root / 'mount/INFO_UF2.TXT').write_text(
                'Model: Raspberry Pi RP2\nBoard-ID: RPI-RP2\n')
            (root / 'layout.vil').write_bytes(
                (ROOT / 'rev3/keymaps/floris/layout.vil').read_bytes())
            block = bytearray(512)
            struct.pack_into('<III', block, 0, 0x0a324655, 0x9e5d5157, 0x2000)
            struct.pack_into('<I', block, 28, 0xe48bff56)
            struct.pack_into('<I', block, 508, 0x0ab16f30)
            (root / 'firmware.uf2').write_bytes(block)
            for command in ('vitaly', 'lsblk', 'findmnt', 'udisksctl', 'cp', 'sync', 'systemctl', 'git', 'make'):
                executable = root / 'bin' / command
                executable.write_text(FAKE)
                executable.chmod(0o755)
            env = dict(os.environ, PATH=f'{root / "bin"}:{os.environ["PATH"]}',
                       FLASH_TEST_ROOT=str(root), FLASH_TEST_FAILURE=failure,
                       XDG_RUNTIME_DIR=str(root), TMPDIR=str(root),
                       XDG_CACHE_HOME=str(root / 'cache'), QMK_BIN='fake-qmk')
            env.pop('QMK_HOME', None)
            arguments = ['bash', str(ROOT / 'flash.sh'), '--layout', str(root / 'layout.vil')]
            if manual_reset:
                arguments += ['--manual-reset']
            if automatic_build:
                arguments += ['--build-only']
            else:
                arguments += ['--firmware', str(root / 'firmware.uf2')]
            result = subprocess.run(arguments, input=main_half + '\n' + '\n' * 6,
                                    text=True, capture_output=True, env=env, timeout=15)
            if automatic_build and result.returncode == 0:
                # A second run must reuse the same completed download.
                result = subprocess.run(arguments, text=True, capture_output=True,
                                        env=env, timeout=15)
            self.assertFalse(list((root / 'cache/kyria/vial-qmk').glob('.download.*')),
                             'Partial downloads must be removed')
            events = (root / 'events').read_text().splitlines()
            self.assertFalse(list(root.glob('kyria-flash.*')), 'Temporary readback must be removed')
            return result, events

    def test_automatic_download_and_cached_build_do_not_access_hardware(self):
        result, events = self.run_walkthrough(automatic_build=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Reusing downloaded Vial-QMK', result.stdout)
        self.assertEqual(sum(' fetch --depth 1 origin ae5e437' in e for e in events), 1)
        self.assertEqual(sum(' submodule update --init --recursive --depth 1' in e for e in events), 1)
        self.assertEqual(sum(e.startswith('make ') for e in events), 2)
        self.assertFalse(any(e.startswith(('vitaly ', 'cp ', 'systemctl ', 'lsblk ')) for e in events))

    def test_failed_download_stops_before_build_and_hardware(self):
        for failure in ('download', 'submodule'):
            with self.subTest(failure=failure):
                result, events = self.run_walkthrough(failure=failure, automatic_build=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(e.startswith(('make ', 'vitaly ', 'cp ', 'systemctl ')) for e in events))

    def test_flash_both_before_restore_and_restart_service(self):
        result, events = self.run_walkthrough()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        flash = [i for i, event in enumerate(events) if event.startswith('cp ')]
        vial = [event for event in events if event.startswith('vitaly ')]
        self.assertEqual(len(flash), 2)
        self.assertLess(flash[-1], next(i for i, e in enumerate(events) if e.startswith('vitaly -i 53060 load ')))
        self.assertEqual([e.split()[3] for e in vial], ['devices', 'lock', 'bootload'] * 2 + ['devices', 'lock', 'load', 'save'] * 2)
        self.assertTrue(events[-1].startswith('systemctl --user start'))
        self.assertNotIn('reset button', result.stdout)

    def test_manual_reset_skips_vial_until_both_halves_are_flashed(self):
        result, events = self.run_walkthrough(manual_reset=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        flash = [i for i, event in enumerate(events) if event.startswith('cp ')]
        self.assertEqual(len(flash), 2)
        self.assertLess(flash[-1], next(i for i, e in enumerate(events) if e.startswith('vitaly ')))
        self.assertFalse(any(' bootload' in e for e in events))
        self.assertIn('Double-tap THAT half', result.stdout)

    def test_failed_unlock_or_bootload_never_copies_firmware(self):
        for failure in ('unlock', 'bootload'):
            with self.subTest(failure=failure):
                result, events = self.run_walkthrough(failure=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(e.startswith('cp ') or ' save ' in e or '--user start' in e for e in events))
                if failure == 'unlock':
                    self.assertFalse(any(' bootload' in e for e in events))

    def test_right_main_half_finishes_on_right(self):
        result, events = self.run_walkthrough(main_half='right')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertLess(result.stdout.index('Flashing right (main)'), result.stdout.index('Flashing left'))
        self.assertIn('Move USB back to the right MAIN half', result.stdout)
        self.assertIn('USB should be connected to the right (main) half', result.stdout)

    def test_exit_zero_vial_error_stops_without_restart(self):
        result, events = self.run_walkthrough('load')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Vitaly reported a failure', result.stderr)
        self.assertFalse(any(' save ' in e or '--user start' in e for e in events))

    def test_mismatched_readback_stops_without_restart(self):
        result, events = self.run_walkthrough('readback')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Layout verification failed', result.stderr)
        self.assertFalse(any('--user start' in e for e in events))

    def test_multiple_bootloaders_never_copy_firmware(self):
        result, events = self.run_walkthrough('ambiguous', manual_reset=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(e.startswith(('cp ', 'vitaly ')) for e in events))


if __name__ == '__main__':
    unittest.main()
