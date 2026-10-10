# Repository Guidelines

## Project Structure & Module Organization

This repository contains Kyria keyboard definitions and keymaps for QMK/Vial, rather than a complete firmware build environment. The owner's active hardware is **Kyria rev3**, using the **`floris` keymap**.

- `rev3/keymaps/floris/`: personal firmware configuration. `keymap.json` defines initial layers and encoder mappings; `config.h` defines Vial settings; `rules.mk` enables features; `rgbrules.c` implements layer-dependent lighting; `vial.json` describes the editor layout.
- `rev3/keyboard.json` and `rev3/config.h`: rev3 hardware and display configuration.
- `kyria.c`, `info.json`, and `rules.mk`: shared keyboard code and metadata.
- `rev1/` and `rev2/`: older hardware definitions.
- `keymaps/default/`, `keymaps/debug/`, and other rev3 keymaps: reference and alternative configurations.
- `host/` and `nix/module.nix`: Linux layer-status/lighting service and its NixOS module; `tests/` covers host and firmware protocol behavior.

## Build, Test, and Development Commands

Place this directory at `keyboards/splitkb/kyria` in a compatible Vial-QMK checkout. Run firmware commands from that checkout's root:

```sh
make splitkb/kyria/rev3:floris
make splitkb/kyria/rev3:floris:flash
```

The first command compiles the active firmware; the second builds and flashes a connected keyboard in bootloader mode. Flash only when explicitly requested. Run `git diff --check` locally to catch whitespace errors.

## Coding Style & Naming Conventions

Use four-space indentation in C and JSON, following nearby code. Preserve license headers, QMK callback names, uppercase configuration macros, and `KC_*` keycodes. Keep build feature declarations in `rules.mk`. Preserve readable keymap arrays and existing `clang-format` guards; no repository-wide formatter or lint configuration is included.

## Testing Guidelines

Run `python3 -m unittest discover -s tests -v` for host changes and the firmware protocol harness documented in `readme.md` for protocol changes. Build the NixOS module with `nix-build tests/module.nix -A package -A configFile -A unit --no-out-link`. Compile firmware changes for rev3/floris with `CONVERT_TO=liatris`. After authorized flashing, check both halves, layer switching, encoders, Vial, and RGB. Vial edits live on the keyboard; compare an export before assuming saved defaults match. Stop the host service before configuring the keyboard through Vial.

## Commit & Pull Request Guidelines

History contains only `initial commit`, so no established message convention exists. Use concise, imperative subjects, such as `Fix RGB indicators on navigation layer`. Describe affected files, intended behavior, and build or hardware validation in pull requests. Link relevant issues and include photos for visible lighting changes when available.

## Configuration Precautions

Default changes to `rev3/keymaps/floris/`. Preserve the Vial keyboard UID and unlock combination unless changing them is intentional. Verify layer indices and LED mappings against the actual layout before modifying RGB rules.
