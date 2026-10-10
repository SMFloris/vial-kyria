#!/usr/bin/env bash
set -Eeuo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
layout="$source_dir/rev3/keymaps/floris/layout.vil"
qmk_home=${QMK_HOME:-}
firmware=
build_only=0
manual_reset=0
qmk_revision=ae5e437c6401cd0686ed7efb096624e665732ca4
qmk_url=https://github.com/splitkb/vial-qmk.git

usage() {
    cat <<'EOF'
Usage: ./flash.sh [--qmk-home DIR] [--firmware FILE] [--layout FILE] [--build-only] [--manual-reset]

Build and flash Kyria rev3/floris for Liatris, then restore and verify both
halves. Unlock with T + Y; bootloader entry is automatic by default.
No backups are created. The checked-in layout.vil is restored.

  --qmk-home DIR  Use an existing checkout instead of downloading Vial-QMK.
  --firmware FILE  Use an existing UF2 instead of building.
  --layout FILE    Restore a different Vitaly-exported layout.
  --build-only    Download/setup and build without accessing the keyboard.
  --manual-reset  Use each half’s reset button instead of Vial bootloader entry.
  --help          Show this help without accessing the keyboard.

With no QMK_HOME/--qmk-home, a pinned checkout is downloaded and reused in
${XDG_CACHE_HOME:-$HOME/.cache}/kyria/vial-qmk/.

Run inside nix-shell shell.nix. Keep the interconnect attached, connect only
one half by USB, and close Vial GUI/other CLI clients before continuing.
EOF
}

die() { printf '\n%s\n' "$*" >&2; exit 1; }
prompt() {
    printf '\n%s\n' "$*"
    read -r -p 'Press Enter when ready (Ctrl+C to stop): ' _ || exit 130
}

while (($#)); do
    case "$1" in
        --qmk-home|--firmware|--layout)
            (($# >= 2)) || die "Missing value for $1"
            case "$1" in
                --qmk-home) qmk_home=$2 ;;
                --firmware) firmware=$2 ;;
                --layout) layout=$2 ;;
            esac
            shift 2 ;;
        --build-only) build_only=1; shift ;;
        --manual-reset) manual_reset=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage; die "Unknown argument: $1" ;;
    esac
done

for command in python3 vitaly timeout tee grep lsblk findmnt udisksctl flock realpath cp sync systemctl; do
    command -v "$command" >/dev/null || die "Missing $command. Enter nix-shell shell.nix first."
done
layout=$(realpath -e -- "$layout")
python3 - "$layout" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    layout = json.load(source)
if layout.get('uid') != 11996955115473074447 or len(layout.get('layout', [])) != 8:
    raise SystemExit('Layout must match the Kyria Vial UID and contain eight layers.')
PY

exec {flash_lock}>"${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/kyria-flash-${UID}.lock"
flock -n "$flash_lock" || die 'Another Kyria flash walkthrough is already running.'
work_dir=$(mktemp -d -t kyria-flash.XXXXXXXX)
service_was_running=0
complete=0
checkout_stage=
cleanup() {
    local status=$?
    trap - EXIT
    rm -rf -- "$work_dir"
    if [[ -n $checkout_stage ]]; then rm -rf -- "$checkout_stage"; fi
    if ((service_was_running)); then
        if ((complete)); then
            systemctl --user start kyria-layer.service || status=1
        else
            printf '\nLighting remains paused. After completing restoration, run:\n  systemctl --user start kyria-layer.service\n' >&2
        fi
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -z $firmware ]]; then
    command -v make >/dev/null || die 'Make is missing; enter the Nix shell.'
    if [[ -z $qmk_home ]]; then
        command -v git >/dev/null || die 'Git is missing; enter the Nix shell.'
        cache_parent="${XDG_CACHE_HOME:-$HOME/.cache}/kyria/vial-qmk"
        qmk_home="$cache_parent/$qmk_revision"
        mkdir -p -- "$cache_parent"
        if [[ ! -e $qmk_home && ! -L $qmk_home ]]; then
            checkout_stage=$(mktemp -d "$cache_parent/.download.XXXXXXXX")
            printf '\nDownloading compatible Vial-QMK (%s)…\n' "$qmk_revision"
            git init --quiet "$checkout_stage"
            git -C "$checkout_stage" remote add origin "$qmk_url"
            git -C "$checkout_stage" fetch --depth 1 origin "$qmk_revision"
            git -C "$checkout_stage" checkout --detach FETCH_HEAD
            git -C "$checkout_stage" submodule update --init --recursive --depth 1
            [[ -f $checkout_stage/quantum/vial.c ]] || die 'Downloaded checkout is missing Vial support.'
            # Only replace the upstream keyboard in our newly created checkout.
            rm -rf -- "$checkout_stage/keyboards/splitkb/kyria"
            ln -s -- "$source_dir" "$checkout_stage/keyboards/splitkb/kyria"
            printf '%s\n' "$qmk_revision" > "$checkout_stage/.git/kyria-managed"
            mv -- "$checkout_stage" "$qmk_home"
            checkout_stage=
        else
            [[ -f $qmk_home/.git/kyria-managed ]] || die "Cache is not managed by this script: $qmk_home"
            [[ $(cat "$qmk_home/.git/kyria-managed") == "$qmk_revision" &&
               $(git -C "$qmk_home" rev-parse HEAD) == "$qmk_revision" &&
               $(git -C "$qmk_home" remote get-url origin) == "$qmk_url" ]] || die 'Cached Vial-QMK revision or origin differs; use --qmk-home for your own checkout.'
            [[ -L $qmk_home/keyboards/splitkb/kyria ]] || die 'Cached keyboard path is no longer a symlink.'
            # Repoint only the managed symlink when this repo has moved.
            ln -sfn -- "$source_dir" "$qmk_home/keyboards/splitkb/kyria"
            printf '\nReusing downloaded Vial-QMK: %s\n' "$qmk_home"
        fi
    fi
    qmk_home=$(realpath -e -- "$qmk_home")
    [[ -f $qmk_home/quantum/vial.c ]] || die 'This must be a Vial-QMK checkout.'
    keyboard_dir="$qmk_home/keyboards/splitkb/kyria"
    [[ -d $keyboard_dir ]] || die 'Install this repo at keyboards/splitkb/kyria first; see readme.md.'
    for file in kyria.c info.json rules.mk rev3/keyboard.json rev3/config.h rev3/rev3.c; do
        cmp -s "$source_dir/$file" "$keyboard_dir/$file" || die "Checkout has a different $file. Link this repo as described in readme.md."
    done
    for file in "$source_dir"/rev3/keymaps/floris/*; do
        [[ $file == *.vil ]] && continue
        cmp -s "$file" "$keyboard_dir/rev3/keymaps/floris/${file##*/}" || die 'Checkout has a different floris keymap. Link this repo before building.'
    done
    printf '\nBuilding rev3/floris for Liatris…\n'
    QMK_HOME="$qmk_home" make -C "$qmk_home" splitkb/kyria/rev3:floris \
        CONVERT_TO=liatris QMK_BIN="${QMK_BIN:-$(command -v qmk)}"
    firmware="$qmk_home/splitkb_kyria_rev3_floris_liatris.uf2"
fi
firmware=$(realpath -e -- "$firmware")
python3 - "$firmware" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as source:
    data = source.read()
if not data or len(data) % 512:
    raise SystemExit('Firmware must be a complete UF2 file.')
for offset in range(0, len(data), 512):
    block = data[offset:offset + 512]
    magic0, magic1, flags = struct.unpack_from('<III', block)
    family = struct.unpack_from('<I', block, 28)[0]
    end = struct.unpack_from('<I', block, 508)[0]
    if (magic0, magic1, end) != (0x0a324655, 0x9e5d5157, 0x0ab16f30) or not flags & 0x2000 or family != 0xe48bff56:
        raise SystemExit('Firmware must be an RP2040/Liatris UF2 image.')
print('Validated RP2040 UF2:', sys.argv[1])
PY
if ((build_only)); then
    printf '\nFirmware ready: %s\n' "$firmware"
    exit 0
fi

if systemctl --user is-active --quiet kyria-layer.service; then
    systemctl --user stop kyria-layer.service
    service_was_running=1
fi

printf 'Restore layout: %s\n' "$layout"
while :; do
    read -r -p 'Which half is your main USB half? [left/right]: ' main_half || exit 130
    case "${main_half,,}" in
        left|l) main_half=left; other_half=right; break ;;
        right|r) main_half=right; other_half=left; break ;;
        *) printf 'Enter left or right.\n' ;;
    esac
done
printf 'Main USB half: %s. The walkthrough finishes with USB on this half.\n' "$main_half"
prompt 'Close Vial GUI and other Vial CLI clients. This flashes both halves and replaces their layouts with the file above.'

# Vitaly can exit successfully after reporting an error. Run exactly one
# command at a time, check both exit status and output, and bound HID waits.
vial() {
    if ! timeout --foreground 90s vitaly -i 53060 "$@" 2>&1 | tee "$work_dir/vitaly.log"; then
        die "Vial command failed or timed out: $*"
    fi
    if grep -Eiq '(^|[[:space:]])error:|failed to' "$work_dir/vitaly.log"; then
        die "Vitaly reported a failure: $*"
    fi
}

boot_partition() {
    lsblk --json --paths --output NAME,LABEL | python3 -c '
import json, sys
def walk(devices):
    for device in devices:
        yield device
        yield from walk(device.get("children", []))
devices = [d["name"] for d in walk(json.load(sys.stdin)["blockdevices"]) if d.get("label") == "RPI-RP2"]
if len(devices) > 1:
    print("Multiple RPI-RP2 drives found; connect only one half by USB.", file=sys.stderr)
    sys.exit(2)
if not devices:
    sys.exit(1)
print(devices[0])
'
}

mount_path() {
    findmnt --json --source "$1" --output TARGET | python3 -c '
import json, sys
data = json.load(sys.stdin)
filesystems = data.get("filesystems", [])
if len(filesystems) != 1: sys.exit(1)
print(filesystems[0]["target"])
' 2>/dev/null
}

wait_for_kyria() {
    local count deadline=$((SECONDS + 15))
    while :; do
        vial devices
        # Count unique raw-HID paths, using Vitaly's quoted output format.
        count=$(python3 - "$work_dir/vitaly.log" <<'PYCOUNT'
import re, sys
with open(sys.argv[1]) as source:
    paths = set(re.findall(r'Path:\s*"?(/dev/hidraw[0-9]+)', source.read()))
print(len(paths))
PYCOUNT
)
        case "$count" in
            1) return ;;
            0)
                ((SECONDS < deadline)) || die 'No Kyria Vial interface appeared within 15 seconds. Connect the keyboard in normal firmware mode and check USB/hidraw access. If it is already an RPI-RP2 drive, rerun with --manual-reset.'
                printf 'Waiting for the Kyria Vial interface to reconnect…\n'
                sleep 1 ;;
            *) die "Found $count distinct Kyria Vial interfaces. Connect only one half by USB." ;;
        esac
    done
}

unlock_half() {
    wait_for_kyria
    printf '\nHold T + Y continuously until the CLI reports unlocked (about five seconds).\n'
    vial lock -u
    grep -q 'Device is locked: false' "$work_dir/vitaly.log" || die 'Unlock did not complete. For firmware recovery, rerun with --manual-reset.'
}

flash_half() {
    local half=$1 partition mount_point deadline status
    if ((manual_reset)); then
        prompt "Connect USB to the $half half, leaving the interconnect attached. Double-tap THAT half’s reset button so RPI-RP2 appears. If the drive is already visible, leave it in bootloader mode."
    else
        prompt "Connect USB to the $half half, leaving the interconnect attached. Wait for the keyboard to reconnect; the CLI will unlock it and enter the bootloader."
        unlock_half
        vial bootload
    fi
    deadline=$((SECONDS + 30))
    while :; do
        if partition=$(boot_partition); then break; else status=$?; fi
        ((status != 2)) || die 'Disconnect the extra bootloader drive and retry.'
        ((SECONDS < deadline)) || die 'RPI-RP2 did not appear. Reconnect and retry with --manual-reset if needed.'
        sleep 1
    done
    if ! mount_point=$(mount_path "$partition"); then
        udisksctl mount --block-device "$partition"
        mount_point=$(mount_path "$partition") || die 'Could not locate the bootloader mount.'
    fi
    python3 - "$mount_point" <<'PY'
from pathlib import Path
import sys
info = (Path(sys.argv[1]) / 'INFO_UF2.TXT').read_text()
if 'Board-ID: RPI-RP2' not in info or 'Model: Raspberry Pi RP2' not in info:
    raise SystemExit('Mounted drive is not the expected RP2040 bootloader.')
PY
    printf '\nFlashing %s half at %s…\n' "$half" "$mount_point"
    cp -- "$firmware" "$mount_point/NEW.UF2"
    sync
    printf 'UF2 copied. Wait for the keyboard to restart.\n'
}

restore_half() {
    local half=$1
    prompt "USB should be connected to the $half half, now running the new firmware. Wait for the keyboard to reconnect."
    unlock_half
    vial load -f "$layout"
    vial save -f "$work_dir/readback.vil"
    python3 - "$layout" "$work_dir/readback.vil" <<'PY'
import json, sys
with open(sys.argv[1]) as source, open(sys.argv[2]) as readback:
    if json.load(source) != json.load(readback):
        raise SystemExit('Layout verification failed: exported settings differ from the restore file.')
print('Layout readback matches: keys, encoders, macros, tap dances, and settings.')
PY
}

# Restore only after BOTH halves share the new split protocol. A mixed pair
# may not recognize the two-half unlock combination during an upgrade.
flash_half "$main_half (main)"
flash_half "$other_half"
restore_half "$other_half"
prompt "Move USB back to the $main_half MAIN half, keeping the interconnect attached."
restore_half "$main_half (main)"
complete=1
printf '\nBoth halves flashed and layouts verified. Test typing, encoders, MO(2) desktop controls, MO(3) arrows, and layer lighting.\n'
