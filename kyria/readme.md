# Kyria rev3 / floris

Personal firmware for a **Kyria rev3 with two Liatris controllers**, with Vial
editing, per-layer lighting, a NixOS host service, and a COSMIC panel indicator.
The firmware build target is `splitkb/kyria/rev3:floris CONVERT_TO=liatris`.

## Files to edit

| Path | Purpose |
| --- | --- |
| `rev3/keymaps/floris/layout.vil` | Saved personal Vial layout: keys, encoders, macros, tap dances, and settings. |
| `rev3/keymaps/floris/keymap.json` | Factory key/encoder defaults and enabled RGB effects. These differ from the personal Vial layout; restore `layout.vil` after flashing. |
| `rev3/keymaps/floris/config.h`, `rules.mk` | Vial identity, unlock keys, layer count, and firmware features. |
| `rev3/keymaps/floris/rgbrules.c` | Standalone lighting when the host service is absent. |
| `rev3/keymaps/floris/host_lighting.c`, `.h` | Layer reporting and synchronized RGB frames for both halves. |
| `rev3/`, `kyria.c`, `info.json`, `rules.mk` | Required QMK hardware definitions and callbacks. |
| `host/` | Python service, physical LED map, and default colors. |
| `nix/`, `applet/` | NixOS module and COSMIC applet. |
| `flash.sh`, `shell.nix`, `tests/` | Guided flashing, Nix tools, and validation. |

Older revisions and alternative keymaps have been removed; Git history retains them.

## Build firmware

Run these commands from the **Git repository root** (the directory containing
`kyria/`). This repository is a keyboard definition, so it needs a Vial-QMK
checkout with its submodules. The following firmware revision was used for the
successful rev3/floris builds:

```sh
export KYRIA_REPO="$PWD"
export QMK_HOME="$HOME/Projects/personal/kyria-vial-qmk"
git clone https://github.com/splitkb/vial-qmk.git "$QMK_HOME"
git -C "$QMK_HOME" checkout ae5e437c6401cd0686ed7efb096624e665732ca4
git -C "$QMK_HOME" submodule update --init --recursive

# One-time setup in the fresh checkout; keep the upstream definition as a backup.
mv "$QMK_HOME/keyboards/splitkb/kyria" "$QMK_HOME/kyria-upstream-backup"
ln -s "$KYRIA_REPO/kyria" "$QMK_HOME/keyboards/splitkb/kyria"
nix-shell "$KYRIA_REPO/kyria/shell.nix"
```

Inside that shell:

```sh
cd "$QMK_HOME"
make splitkb/kyria/rev3:floris CONVERT_TO=liatris
```

The output is `$QMK_HOME/splitkb_kyria_rev3_floris_liatris.uf2`.
`shell.nix` supplies ARM GCC, Make, and a QMK CLI with the Python dependencies
needed by this older firmware tree. It uses your `<nixpkgs>`; on this machine,
use the system pin by appending
`-I nixpkgs="$(nix eval --raw -f /etc/nixos/npins/default.nix nixpkgs)"`
to the `nix-shell` command. On another OS, install the checkout's QMK toolchain
and `requirements.txt`, then run the same Make command.

## Guided build, flash, and restore

From `kyria/`, enter the shell and run the walkthrough:

```sh
nix-shell shell.nix
./flash.sh --qmk-home "$QMK_HOME"
```

The shell includes the pinned Vitaly 0.1.32 CLI and firmware build tools.
`QMK_HOME` can also be set in the environment; otherwise the script asks for
its path. The checkout must contain this repository's keyboard definition as
shown above. From the QMK checkout, the same walkthrough is `kyria-flash`.

The script walks through these steps:

1. Pause the lighting service if it is running, validate the saved layout,
   and build rev3/floris for Liatris.
2. Ask which half is your main USB half (left or right), then ask you to
   close Vial and connect that half by USB. Double-tap that
   half's reset button. The script finds and mounts its `RPI-RP2` drive,
   checks the bootloader identity, and copies the UF2.
3. Ask you to move USB to the other half and repeat the reset/flash.
   Leave the interconnect attached throughout; connect only one USB half.
4. Restore the other half, then ask you to move USB back and restore your
   main half. The walkthrough finishes with USB on your main half. For each unlock, hold **T + Y** until the CLI reports unlocked
   (about five seconds). Each restore is followed by a full JSON readback
   comparison.
5. Restart the lighting service if it was running and both restores passed.
   Check typing, encoders, layer switching, and lighting on both halves.

Both halves are flashed before Vial unlock so they share the same split
protocol. Vial commands run sequentially with a 90-second timeout; reported
errors stop the walkthrough even if the CLI exits successfully. An interrupted
or failed restoration leaves the lighting service paused; finish restoring,
then run `systemctl --user start kyria-layer.service`.

**No backups are made.** The script replaces both halves' layouts with
`rev3/keymaps/floris/layout.vil`. Temporary exports used for verification are
deleted on exit. To use an existing UF2 or a different Vitaly-exported layout:

```sh
./flash.sh --firmware "$QMK_HOME/splitkb_kyria_rev3_floris_liatris.uf2"
./flash.sh --qmk-home "$QMK_HOME" --layout /path/to/layout.vil
./flash.sh --help
```

## Edit the layout without flashing

Stop the host service before using Vial GUI or CLI: both share the raw-HID
request/reply channel. Edit the connected keyboard, export the result, and
restart the service. To make your changes reproducible:

```sh
vitaly -i 53060 save -f "$KYRIA_REPO/kyria/rev3/keymaps/floris/layout.vil"
git -C "$KYRIA_REPO" diff -- kyria/rev3/keymaps/floris/layout.vil
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
your settings; brightness 0 disables a default highlight. Vial's global RGB
brightness multiplies the configured brightness, and its RGB toggle still works.

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
file at `$XDG_RUNTIME_DIR/kyria-layer.json`. The applet shows `L3 · Navigation`,
or `Kyria offline` for disconnected, missing, or stale status. Stop the service
to return to built-in lighting; a crash or disconnect restores firmware
lighting within 1.5 seconds. Host colors stay in RAM and synchronize to both
halves. Keep the Vial UID and physical unlock combination unchanged.

## Update checklist

- **Keys/macros:** edit through Vial, export `layout.vil`, review, commit, push.
  Restore that export on the other half if either half can be the USB master.
- **Firmware or built-in lighting:** pull this repo, rebuild in the linked
  Vial-QMK checkout, and run `./flash.sh` to flash and restore both halves.
- **Host service/applet:** commit and push this repo, put the new full SHA in
  `/etc/nixos/common/kyria.nix`, rebuild NixOS, and restart the two user units.
  Keep the host protocol compatible with the installed firmware.
- **Layer colors/names only:** edit the NixOS layer mapping and rebuild/restart
  the service. No firmware flash is needed.

For a source update: `git -C "$KYRIA_REPO" pull --ff-only`. Review the diff
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
