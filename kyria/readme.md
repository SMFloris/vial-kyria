# Kyria rev3 / floris

Personal firmware for a **Kyria rev3 with two Liatris controllers**, with Vial
editing, per-layer lighting, a NixOS host service, and a COSMIC panel indicator.
The firmware build target is `splitkb/kyria/rev3:floris CONVERT_TO=liatris`.
This board has 25 left switch LEDs with underglow bypassed, and 31 right LEDs
(six underglow plus 25 switch LEDs). Firmware and host maps use 56 LEDs total.

## Files to edit

| Path | Purpose |
| --- | --- |
| `rev3/keymaps/floris/layout.vil` | Saved personal Vial layout: keys, encoders, macros, tap dances, and settings. |
| `rev3/keymaps/floris/keymap.json` | Factory key/encoder defaults and the sole solid-color RGB effect. These differ from the personal Vial layout; restore `layout.vil` after flashing. |
| `rev3/keymaps/floris/config.h`, `rules.mk` | Vial identity, unlock keys, layer count, and firmware features. |
| `rev3/keymaps/floris/rgbrules.c` | Displays host frames; uses dim white keys and underglow when the host is absent. |
| `rev3/keymaps/floris/host_lighting.c`, `.h` | Layer reporting and synchronized RGB frames for both halves. |
| `rev3/`, `kyria.c`, `info.json`, `rules.mk` | Required QMK hardware definitions and callbacks. |
| `host/` | Python service, physical LED map, and default colors. |
| `nix/`, `applet/` | NixOS module and COSMIC applet. |
| `flash.sh`, `shell.nix`, `tests/` | Guided flashing, Nix tools, and validation. |

Older revisions and alternative keymaps have been removed; Git history retains them.

## Build firmware

From `kyria/`, build without accessing the keyboard:

```sh
nix-shell shell.nix
./flash.sh --build-only
```

On the first run, the script automatically downloads
`https://github.com/splitkb/vial-qmk.git` at the tested revision
`ae5e437c6401cd0686ed7efb096624e665732ca4`, initializes its submodules,
and links this repository at `keyboards/splitkb/kyria`. The managed checkout
is cached at `${XDG_CACHE_HOME:-$HOME/.cache}/kyria/vial-qmk/<revision>/` and
reused on later runs. Failed downloads are removed and can be retried.
The resulting `splitkb_kyria_rev3_floris_liatris.uf2` path is printed.

`shell.nix` supplies ARM GCC, Make, Git, Vitaly, and QMK's Python dependencies.
It uses your `<nixpkgs>`; on this machine, use the system pin by appending
`-I nixpkgs="$(nix eval --raw -f /etc/nixos/npins/default.nix nixpkgs)"`
to the `nix-shell` command.

To use your own compatible checkout, set `QMK_HOME` or pass
`--qmk-home /path/to/vial-qmk`; its `keyboards/splitkb/kyria` must already
point to this repository. This override skips automatic download and setup.
`kyria-flash` also runs the walkthrough from another working directory.

## Guided build, flash, and restore

From `kyria/`, enter the shell and run the walkthrough:

```sh
nix-shell shell.nix
./flash.sh
```

The shell includes the pinned Vitaly 0.1.32 CLI and firmware build tools.
No checkout path is needed: Vial-QMK is downloaded and set up automatically.
An existing `QMK_HOME` environment variable overrides that download; unset it
to use the managed checkout.

The script walks through these steps:

1. Validate the saved layout, download/reuse Vial-QMK, and build rev3/floris
   for Liatris. Pause the lighting service if it is running before flashing.
2. Ask which half is your main USB half (left or right), then ask you to
   close Vial and connect that half by USB. Hold **T + Y** during the unlock;
   the script enters the bootloader through Vial, mounts its `RPI-RP2` drive,
   checks the bootloader identity, and copies the UF2.
3. Ask you to move USB to the other half and repeat the unlock/flash.
   Leave the interconnect attached throughout; connect only one USB half.
4. Restore the other half, then ask you to move USB back and restore your
   main half. The walkthrough finishes with USB on your main half. For each
   unlock, hold **T + Y** until the CLI reports unlocked
   (about five seconds). Each restore is followed by a full JSON readback
   comparison.
5. Restart the lighting service if it was running and both restores passed.
   Check typing, encoders, layer switching, and lighting on both halves.

Both halves are flashed before restoring their layouts. For recovery or
incompatible firmware on the two halves, run `./flash.sh --manual-reset`:
it asks you to double-tap each half's reset button and skips Vial until both
halves have been flashed. Restoration still requires T + Y unlock.
The script waits up to 15 seconds for the Vial interface after reconnecting.
If none appears, check the USB connection and hidraw permissions; a half
already showing `RPI-RP2` needs `--manual-reset` rather than Vial unlock.
Multiple distinct interfaces produce a separate error.
Vial commands run sequentially with a 90-second timeout; reported
errors stop the walkthrough even if the CLI exits successfully. An interrupted
or failed restoration leaves the lighting service paused; finish restoring,
then run `systemctl --user start kyria-layer.service`.

**No backups are made.** The script replaces both halves' layouts with
`rev3/keymaps/floris/layout.vil`. Temporary exports used for verification are
deleted on exit. To use an existing UF2 or a different Vitaly-exported layout:

```sh
./flash.sh --firmware /path/to/firmware.uf2
./flash.sh --layout /path/to/layout.vil
./flash.sh --manual-reset
./flash.sh --help
```

## Edit the layout without flashing

Stop the host service before using Vial GUI or CLI: both share the raw-HID
request/reply channel. Edit the connected keyboard, export the result, and
restart the service. To make your changes reproducible:

```sh
vitaly -i 53060 save -f "$(git rev-parse --show-toplevel)/kyria/rev3/keymaps/floris/layout.vil"
git -C "$(git rev-parse --show-toplevel)" diff -- kyria/rev3/keymaps/floris/layout.vil
```

Review and commit that export. It includes settings, macros, and tap dances;
changing `keymap.json` alone does not update the layout already stored in Vial.

## Install the host service and COSMIC applet

Import the module from a Git revision you have already pushed:

```nix
{ ... }:
let
  kyria = builtins.fetchGit {
    url = "https://github.com/SMFloris/vial-kyria.git";
    ref = "master";
    rev = "<full Git commit SHA>";
  };
in {
  imports = [ "${kyria}/kyria/nix/module.nix" ];
  services.kyria-layer = {
    enable = true;
    user = "flow";
    applet.enable = true;
    applet.installToPanel = true;
    applet.panel = "Panel";
    layers."2" = {
      name = "COSMIC";
      keys.N = { color = "#4fea55"; brightness = 255; };
      underglow = { color = "#b400ff"; brightness = 180; };
    };
  };
}
```

On this machine the import and settings live in `/etc/nixos/common/kyria.nix`.
Activate with `cd /etc/nixos && ./rebuild.sh switch`; elsewhere use
`sudo nixos-rebuild switch`. Then start the current session's user units:

```sh
systemctl --user daemon-reload
systemctl --user start kyria-layer.service kyria-layer-panel.service
cat "$XDG_RUNTIME_DIR/kyria-layer.json"
journalctl --user -u kyria-layer.service -f
```

The panel installer preserves existing applets and inserts the layer indicator
before the status area in the right wing. It registers a desktop-entry symlink
in your user applications directory, updating it at login. Manual placement:
`cosmic-applet-kyria-layer --install-panel Panel`. Set `installToPanel = false`
when managing placement through COSMIC settings. When disabling the applet,
remove its panel entry and user desktop-entry symlink if no longer wanted.

### Lighting and layer reference

Configure `services.kyria-layer.layers."<number>".keys."<key>"` and
`.underglow` using `{ color = "#RRGGBB"; brightness = 0..255; }`.
Key names refer to **physical QWERTY positions**, regardless of current outputs.
`host/led-map.json` lists names and matrix coordinates such as `"5,1"` (H).
`keys."*"` sets all switch LEDs; specific keys override it. Defaults merge with
your settings; brightness 0 disables a default highlight. Brightness is absolute:
255 sends the configured color unchanged, independently of Vial's RGB settings.
The host uses protocol version 2; update both halves with the matching firmware.
Default highlights use 255, the subdued key background uses 8, and underglow
uses 128 to preserve its previous intensity. All layer names and lighting live
in the host configuration; firmware contains only a neutral white fallback, with no layer palette.

| Layer | Name | Default underglow | Useful keys in saved layout |
| --- | --- | --- | --- |
| 0 | Typing | Blue | Home-row modifiers; left thumb MO(2), MO(3), MO(4). |
| 1 | Numbers | Amber | Hold A or semicolon; right-thumb TG(1) toggles. |
| 2 | COSMIC | Purple | Hold MO(2): N/M/Comma/Period focus left/down/up/right. |
| 3 | Navigation | Green | Hold MO(3): H/J/K/L are left/down/up/right arrows. |
| 4 | Editor | Cyan | Editor macros. |
| 5 | Function | Red | Function keys. |
| 6 | Settings | White | Keyboard settings. |
| 7 | Spare | Pink | Reserved. |

Layer 2 also has Z fullscreen, X maximize, C horizontal, V vertical, B stacking,
Tab sticky, and right-top outer key floating (`Super+Space`).

The service polls actual layer state every 50 ms and writes an atomic status
file at `$XDG_RUNTIME_DIR/kyria-layer.json`. The applet uses one-based display
numbers: firmware layer 0 is shown as 1,
and layer 7 as 8. A neutral keyboard icon sits beside a compact, colored
`1: Typing` label with a subtle white-ish outline. The label uses the normal
COSMIC font and only takes the width it needs. Names longer than 20 characters
end in an ellipsis. Set `layers."3".name = "Navigation"` to show `4: Navigation`;
omit `name` or set it to `null` for the number without a name. Lighting
configuration indices remain 0–7. A muted dash means disconnected, missing, or stale
status. Stopping the service restores dim white keys and underglow; a crash or
disconnect restores the same fallback within 1.5 seconds. Host colors stay in RAM and synchronize to both
halves. Keep the Vial UID and physical unlock combination unchanged.

## Update checklist

- **Keys/macros:** edit through Vial, export `layout.vil`, review, commit, push.
  Restore that export on the other half if either half can be the USB master.
- **Firmware or LED hardware mapping:** pull this repo and run `./flash.sh`
  to download/reuse Vial-QMK, rebuild, flash, and restore both halves.
- **Host service/applet:** commit and push this repo, put the new full SHA in
  `/etc/nixos/common/kyria.nix`, rebuild NixOS, and restart the two user units.
  Keep the host protocol compatible with the installed firmware.
- **Layer colors/names only:** edit the NixOS layer mapping and rebuild/restart
  the service. No firmware flash is needed.

For a source update: `git -C "$(git rev-parse --show-toplevel)" pull --ff-only`. Review the diff
before committing; push the keyboard repo before pushing a NixOS config that
pins its new revision. Git SSH authentication and local sudo authentication
are required for pushing and system activation respectively.

## Validate changes

From `kyria/`:

```sh
python3 -m unittest discover -s tests -v
cc -std=c11 -Wall -Wextra -Werror '-DQMK_KEYBOARD_H="qmk.h"' \
  -Itests/firmware tests/firmware/test_host_lighting.c -o /tmp/kyria-fw-test
/tmp/kyria-fw-test
nix-build tests/module.nix -A package -A configFile -A unit --no-out-link
nix-build tests/module.nix -A applet -A panelUnit --no-out-link
git diff --check
```

On this machine append `--arg nixpkgs '(import /etc/nixos/npins).nixpkgs'` to
`nix-build` to use the system's pinned packages. The Nix applet build runs its
Rust tests using the same vendored libcosmic dependencies as COSMIC. Firmware
changes also require the rev3/floris build above; hardware checks follow an
explicitly requested flash.
