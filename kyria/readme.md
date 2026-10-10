# Kyria

## Personal rev3 / floris configuration

The active keyboard is Kyria rev3 with Liatris controllers and the `floris`
keymap. `rev3/keymaps/floris/rgbrules.c` provides standalone layer lighting.
The host extension in `host_lighting.c` exposes real layer state and accepts
atomic RGB frames, forwarding them to the other half. It leaves VIA/Vial
keymap editing available. Flash the same firmware to **both** halves; back up
and restore the Vial layout when firmware upgrades reset EEPROM settings.

### Host lighting on NixOS

Import `kyria/nix/module.nix` from this Git repository's root, then configure:

```nix
services.kyria-layer = {
  enable = true;
  user = "flow";
  layers."2" = {
    name = "COSMIC";
    keys = {
      N = { color = "#4fea55"; brightness = 255; };
      M = { color = "#4fea55"; brightness = 255; };
      Comma = { color = "#4fea55"; brightness = 255; };
      Period = { color = "#4fea55"; brightness = 255; };
    };
    underglow = { color = "#b400ff"; brightness = 180; };
  };
};
```

Keys identify **physical base-QWERTY positions**, not the current layer's
output. `host/led-map.json` lists names and equivalent matrix coordinates
(for example, `"5,1"` is H). `keys."*"` sets the background for all switch
LEDs; individual keys override it. Colors use `#RRGGBB`; brightness is 0–255
and is multiplied by Vial's global brightness. Overrides merge with the eight
default layer schemes. Override a default highlight with brightness 0 to
turn it off. Settings changes require a NixOS rebuild, not another flash.

The user service polls actual firmware layer state every 50 ms, sends lighting
on changes, and refreshes its lease every 400 ms. Status is written atomically
to `$XDG_RUNTIME_DIR/kyria-layer.json`, including `layer`, `name`, both layer
bitmasks, connection state, and whether split-frame synchronization is pending.
Status changes and a once-per-second liveness heartbeat update the file. Read it with:

```sh
cat "$XDG_RUNTIME_DIR/kyria-layer.json"
systemctl --user status kyria-layer
journalctl --user -u kyria-layer
```

Stop the service to return to firmware lighting. Unexpected service failure
returns both halves to firmware lighting within 1.5 seconds. Colors stay in
RAM; normal updates do not write EEPROM. A disconnect triggers automatic
reconnection. During Vial's physical unlock sequence, the service temporarily
backs off and reconnects afterward. The extension needs no separate unlock
because it changes only volatile lighting and reads layer state.

Pause the service before using Vial's GUI or CLI for configuration, since both
clients share the raw-HID request/reply channel. Resume it afterward:

```sh
systemctl --user stop kyria-layer
# Edit or load the layout with Vial.
systemctl --user start kyria-layer
```

### COSMIC panel applet

Enable the native panel indicator alongside the host service:

```nix
services.kyria-layer.applet = {
  enable = true;
  installToPanel = true;
  panel = "Panel";
};
```

The applet displays `L3 · Navigation`, for example, and polls the status file
every 100 ms. Missing, invalid, disconnected, or stale status displays
`Kyria offline`. The daemon refreshes `updatedAt` once per second, allowing
the indicator to detect a crashed service within five seconds. It reads the
same `statusFile` configured for the service and never accesses the keyboard.

The login unit registers the packaged desktop entry in the user's applications
directory and adds `io.github.SMFloris.KyriaLayer` before the status area in
the panel's right wing. Existing plugins and their order are preserved;
repeated installation does not create duplicates. Install into the current
session with `cosmic-applet-kyria-layer --install-panel Panel`. Set
`installToPanel = false` to manage placement manually in COSMIC panel settings.
Disabling the module does not remove the saved panel entry; remove it in panel
settings if desired.

`applet/` contains the Rust source and desktop entry. `nix/applet.nix` builds
it as an added member of Nixpkgs' pinned `cosmic-applets` workspace, reusing
its offline vendored dependencies and libcosmic version. It builds and tests
only the Kyria applet; the installed COSMIC applets remain separate packages.

### Development checks

```sh
python3 -m unittest discover -s tests -v
cc -std=c11 -Wall -Wextra -Werror '-DQMK_KEYBOARD_H="qmk.h"' \
  -Itests/firmware tests/firmware/test_host_lighting.c -o /tmp/kyria-fw-test
/tmp/kyria-fw-test
nix-build tests/module.nix -A package -A configFile -A unit --no-out-link
nix-build tests/module.nix -A applet -A panelUnit --no-out-link
```

Build inside a compatible Vial-QMK checkout:

```sh
make splitkb/kyria/rev3:floris CONVERT_TO=liatris
```

The tests cover physical LED mapping, brightness, HID framing, complete-frame
commit, split transport retries, and lease expiry. The 32-byte raw-HID
extension uses command `0xF0`, operations 0–5 (status, data, commit, release,
heartbeat, begin), and a request token at byte 30. Byte 29 reports errors.
Status includes version 1 and the `KYR1` signature. RGB chunks contain at most
eight LEDs. Complete frames are required before activation, including on the
slave; existing firmware indicators resume when the lease expires.

![Kyria](https://cdn.shopify.com/s/files/1/0227/9171/6941/products/PlateCase_f1870016-98b8-43a9-8aed-3eaf073b367b_900x.jpg?v=1568934600)

An ergonomical 40% split keyboard

* Keyboard Maintainer: [splitkb.com](https://github.com/splitkb)
* Hardware Supported: Pro Micro 5V/16MHz and compatible.
* Hardware Availability: [splitkb.com](https://splitkb.com/products/kyria-pcb-kit)

Make example for this keyboard (after setting up your build environment):

    make splitkb/kyria/rev3:default

Example of flashing this keyboard:

    make splitkb/kyria/rev3:default:flash

Replace "rev3" with "rev2" if you have a Kyria of revision 2.x, or "rev1" if you have a Kyria of revision 1.4 or below.
Not sure what revision yours is? It is printed on the outer lower edge of the PCB!
As a rule of thumb, all Kyrias sold after January 1st 2022 are revision 2.x.

See the [build environment setup](https://docs.qmk.fm/#/getting_started_build_tools) and the [make instructions](https://docs.qmk.fm/#/getting_started_make_guide) for more information. Brand new to QMK? Start with our [Complete Newbs Guide](https://docs.qmk.fm/#/newbs).

A build guide for the Kyria can be found at [docs.splitkb.com](https://docs.splitkb.com/hc/en-us/categories/360002241559-Build-Guides). For revision 3.x you want to use the [Aurora build guide](https://docs.splitkb.com/hc/en-us/articles/6269789921564-Aurora-Build-Guide-1-Introduction), for revision 2.x and below you want to use the [Kyria-specific guide](https://docs.splitkb.com/hc/en-us/articles/360010552059-Kyria-Build-Guide-Introduction).

## Proton C Conversion Guide

If you're one of the lucky people to have Proton Cs to use with their Kyria, there are a couple of caveats to getting this working.

1. You need to have 2x Proton Cs, as you cannot mix and match with Pro Micros or Elite C's.  They both need to be Proton Cs.
2. You'll need to do some modding to enable proper support with the Proton C.

By design, the Kyria uses every available pin on the Pro Micro footprint.  This includes using D3 (RX) for RGB.  This poses a challenge with using the Proton C, since it needs both the TX and RX pins. The Proton C needs both pins, especially if you plan on using Full Duplex Serial. 

To fix this, you need to break off the last header position on the right-hand side on the footprint. This is the `TX0/D3` pad. Leave this pad without a header connected to.

From the A9 pin on the Proton C, you want to run a wire from it to the `SDA + Extra Data` pad near the TRRS jack on the PCB. This will allow for proper, full duplex communication over the TRRS cable. 

To get RGB working properly, as well, you want to run a wire from the `A3` pin on the Proton C, next to the GND and DFU pin, right under the USB port.  Run this to the `TX0/D3` pad (the one you left without a header pin on the PCB).

Once you've done that, you can solder in the Proton C. and flash it.

![Proton C](https://i.imgur.com/nICqWLo.jpg)
