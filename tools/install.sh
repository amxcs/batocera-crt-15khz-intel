#!/bin/bash
# One-shot installer for the 15kHz CRT setup on a Batocera box.
#
#   ssh root@batocera 'curl -fsSL https://raw.githubusercontent.com/amxcs/batocera-crt-15khz-intel/master/tools/install.sh | bash -s -- --yes'
#
# Installs everything that can be installed: the boot hook, the Xorg modelines,
# the ES mode script, the gameStop hook, the batocera.conf keys and the kernel
# command line. The patched i915 module is the one thing it cannot produce --
# that has to be built against the exact running kernel (see the README) and
# handed to this script with --module. Without it everything else still goes in
# and progressive 15kHz works; interlaced 480i does not.
#
# Safe to re-run: every step checks before it writes, and originals are backed
# up to /userdata/crt-install-backup/ the first time they are touched.

set -u

REPO_RAW="https://raw.githubusercontent.com/amxcs/batocera-crt-15khz-intel/master"
RELEASES="https://github.com/amxcs/batocera-crt-15khz-intel/releases/download"

# The build this repo targets. A different Batocera means a different kernel,
# and a module built for another kernel is worse than no module at all.
TARGET_BATOCERA="43.1"
BACKUP=/userdata/crt-install-backup
CONF=/userdata/system/batocera.conf
DRY=0
ASSUME_YES=0
MODULE=""
OUTPUT=""
FORCE_MODULE=0
MODULE_AUTO=0
BOOT_RW=0

# /boot must never be left writable, however this script exits.
cleanup() {
    if [ "$BOOT_RW" = 1 ]; then
        sync
        mount -o remount,ro /boot 2>/dev/null && BOOT_RW=0
    fi
}
trap cleanup EXIT INT TERM

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then say "   [dry-run] $*"; else eval "$@"; fi; }

usage() {
    cat <<EOF
Usage: install.sh [options]

  --module PATH|URL   patched i915.ko to install; defaults to the prebuilt one
                      published for this kernel, when Batocera matches
  --force-module      install it even if its vermagic cannot be read
  --output NAME       force the connector name instead of auto-detecting
  --dry-run           print what would happen, change nothing
  --yes               do not ask for confirmation
  --help              this text
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --module) MODULE="${2:-}"; shift 2 ;;
        --force-module) FORCE_MODULE=1; shift ;;
        --output) OUTPUT="${2:-}"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --help|-h) usage ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

[ "$(id -u)" = 0 ] || die "run as root"
[ -f "$CONF" ] || die "$CONF not found -- is this a Batocera system?"

KVER="$(uname -r)"

# --- 1. which connector is the CRT on? ---------------------------------------
step "Detecting the display connector"

if [ -z "$OUTPUT" ]; then
    # Prefer DRM sysfs: it works with no X server running. Connector dirs are
    # named card0-DP-3, card0-HDMI-A-1, ... and the xrandr name drops the card
    # prefix, with HDMI-A-n becoming HDMI-n.
    for d in /sys/class/drm/card*-*/status; do
        [ -f "$d" ] || continue
        [ "$(cat "$d")" = connected ] || continue
        n="$(basename "$(dirname "$d")")"
        n="${n#card*-}"
        OUTPUT="$(printf '%s' "$n" | sed 's/^HDMI-A-/HDMI-/')"
        break
    done
fi
if [ -z "$OUTPUT" ] && command -v xrandr >/dev/null 2>&1; then
    OUTPUT="$(DISPLAY=:0 xrandr --query 2>/dev/null | awk '/ connected/{print $1; exit}')"
fi
[ -n "$OUTPUT" ] || die "no connected output found -- pass --output DP-3 (or whatever yours is)"

say "   connector: $OUTPUT"
say "   kernel:    $KVER"

edid="/sys/class/drm/card0-${OUTPUT}/edid"
[ -e "$edid" ] || edid="/sys/class/drm/card0-$(printf '%s' "$OUTPUT" | sed 's/^HDMI-/HDMI-A-/')/edid"
if [ -e "$edid" ] && [ -s "$edid" ]; then
    warn "$OUTPUT reports an EDID. A display that declares its limits may refuse"
    warn "15kHz modelines. The tested setup has no EDID at all on this port."
fi

# --- 2. the patched module ---------------------------------------------------
step "Patched i915 module"

BATO="$(cut -d' ' -f1 /usr/share/batocera/batocera.version 2>/dev/null)"
say "   Batocera: ${BATO:-unknown}"

# With no --module, take the prebuilt one published for this exact kernel. It
# is only offered when the Batocera version matches, because that is what makes
# the kernel version predictable.
if [ -z "$MODULE" ]; then
    if [ "$BATO" = "$TARGET_BATOCERA" ]; then
        MODULE="$RELEASES/batocera-${TARGET_BATOCERA}/i915-patched-${KVER}.ko"
        MODULE_AUTO=1
        say "   using the prebuilt module for Batocera $TARGET_BATOCERA"
    elif [ -n "$BATO" ]; then
        warn "this is Batocera $BATO, and the prebuilt module is for $TARGET_BATOCERA."
        warn "Kernel $KVER almost certainly differs, so no module will be installed."
        warn "Build one (see the README) and re-run with --module."
    fi
fi

MODULE_LOCAL=""
if [ -n "$MODULE" ]; then
    case "$MODULE" in
        http://*|https://*)
            MODULE_LOCAL=/tmp/i915-patched.ko
            say "   downloading $MODULE"
            # Downloaded even in dry-run: it only writes to /tmp, and without
            # the file there is nothing to check the vermagic of -- which is
            # the one question a rehearsal is for.
            if ! curl -fsSL "$MODULE" -o "$MODULE_LOCAL"; then
                # A module the user named is a hard requirement; one this script
                # chose is a convenience, so its absence must not stop the rest.
                [ "$MODULE_AUTO" = 1 ] || die "download failed: $MODULE"
                warn "no prebuilt module published for kernel $KVER -- continuing without it"
                MODULE=""; MODULE_LOCAL=""
            fi
            ;;
        *)
            [ -f "$MODULE" ] || die "no such file: $MODULE"
            MODULE_LOCAL="$MODULE"
            ;;
    esac

    # Checked in dry-run too -- it only reads the file, and "would this module
    # be accepted?" is the main thing a rehearsal should answer.
    if [ -f "$MODULE_LOCAL" ]; then
        vm="$(modinfo -F vermagic "$MODULE_LOCAL" 2>/dev/null)"
        case "$vm" in
            "$KVER"*) say "   vermagic OK: $vm" ;;
            "")
                # An unreadable vermagic means this is not a module built for
                # this kernel -- most likely not a module at all. Installing it
                # leaves the machine with no display on the next boot, so this
                # is a stop, not a warning.
                [ "$FORCE_MODULE" = 1 ] || die "cannot read a vermagic from '$MODULE_LOCAL'.
       That is not a kernel module built for $KVER. Installing it would leave
       you with no display. Use --force-module only if you are certain."
                warn "vermagic unreadable, installing anyway (--force-module)"
                ;;
            *)        die "vermagic mismatch: module is '$vm', kernel is '$KVER'.
       Installing it would leave you with no display. Rebuild it against $KVER." ;;
        esac
    fi
else
    warn "no --module given: interlaced 480i will NOT work."
    warn "Everything else is still installed; add the module later and reboot."
fi

# --- 3. confirm --------------------------------------------------------------
if [ "$ASSUME_YES" = 0 ] && [ "$DRY" = 0 ]; then
    say ""
    say "About to write to /boot, $CONF and /userdata/system/."
    say "Originals are backed up to $BACKUP/."
    # /dev/tty, not stdin: under `curl ... | bash` stdin is the script itself.
    printf 'Continue? [y/N] ' > /dev/tty
    read -r ans < /dev/tty || die "no terminal to confirm on -- add --yes, or use ssh -t"
    case "$ans" in y|Y|yes|YES) ;; *) die "aborted" ;; esac
fi

mkdir -p "$BACKUP"

backup() {          # backup <file> -- first time only, never overwrite
    [ -f "$1" ] || return 0
    b="$BACKUP/$(printf '%s' "${1#/}" | tr / _)"
    [ -f "$b" ] && return 0
    run "cp -p '$1' '$b'"
}

fetch() {           # fetch <repo-relative path> <destination>
    # Only treat the parent directory as a clone if it really is one. Without
    # the marker check, running this from /tmp makes $here "/" and every
    # payload path resolves to the live system file -- which then gets copied
    # over itself.
    here="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
    if [ -n "$here" ] && [ -f "$here/tools/install.sh" ] && [ -f "$here/$1" ]; then
        run "cp '$here/$1' '$2'"
    else
        run "curl -fsSL '$REPO_RAW/$1' -o '$2'" || die "could not fetch $1"
    fi
}

# every payload file hardcodes the tested connector and kernel version
personalise() {
    [ "$DRY" = 1 ] && return 0
    sed -i -e "s/DP-3/$OUTPUT/g" -e "s|/lib/modules/[0-9][^/]*/|/lib/modules/$KVER/|g" "$1"
}

# --- 4. /boot ----------------------------------------------------------------
step "Installing to /boot"

run "mount -o remount,rw /boot" || die "cannot make /boot writable"
BOOT_RW=1

backup /boot/boot-custom.sh
fetch boot/boot-custom.sh /boot/boot-custom.sh
personalise /boot/boot-custom.sh
run "chmod +x /boot/boot-custom.sh"
say "   /boot/boot-custom.sh"

if [ -n "$MODULE_LOCAL" ]; then
    run "cp '$MODULE_LOCAL' /boot/i915-patched.ko"
    say "   /boot/i915-patched.ko"
fi

# kernel command line: force the connector on and start it on a 15kHz mode
step "Kernel command line"
CMDLINE="video=${OUTPUT}:640x240eS"
for f in /boot/EFI/batocera/syslinux.cfg /boot/boot/syslinux.cfg /boot/EFI/BOOT/grub.cfg; do
    [ -f "$f" ] || continue
    if grep -q "video=${OUTPUT}:" "$f"; then
        say "   already present in $f"
        continue
    fi
    backup "$f"
    # [[:space:]] rather than \s: the latter is a GNU sed extension and this
    # has to work wherever Batocera's sed came from.
    run "sed -i -e 's|^\\([[:space:]]*APPEND .*\\)$|\\1 ${CMDLINE}|' -e 's|^\\([[:space:]]*linux .*\\)$|\\1 ${CMDLINE}|' '$f'"
    say "   added to $f"
done

run "sync"
run "mount -o remount,ro /boot"
BOOT_RW=0

# --- 5. /userdata ------------------------------------------------------------
step "Installing to /userdata"

backup /userdata/system/custom-es-config
fetch userdata/system/custom-es-config /userdata/system/custom-es-config
personalise /userdata/system/custom-es-config
run "chmod +x /userdata/system/custom-es-config"
say "   /userdata/system/custom-es-config"

run "mkdir -p /userdata/system/scripts /userdata/system/logs /userdata/system/crt-tools"
for t in calibrate.sh es-mode.sh show-test.sh try-mode.sh gen-overscan-ruler.py gen-1px-frames.py; do
    fetch "tools/$t" "/userdata/system/crt-tools/$t"
    run "chmod +x '/userdata/system/crt-tools/$t'"
done
say "   /userdata/system/crt-tools/ (calibration helpers)"

backup /userdata/system/scripts/crt-mode.sh
fetch userdata/system/scripts/crt-mode.sh /userdata/system/scripts/crt-mode.sh
personalise /userdata/system/scripts/crt-mode.sh
run "chmod +x /userdata/system/scripts/crt-mode.sh"
say "   /userdata/system/scripts/crt-mode.sh"

# --- 6. batocera.conf --------------------------------------------------------
step "Settings"

backup "$CONF"

set_key() {         # set_key <key> <value> -- replace in place, or append
    k="$1"; v="$2"
    if [ "$DRY" = 1 ]; then say "   [dry-run] $k=$v"; return 0; fi
    if grep -q "^${k}=" "$CONF"; then
        cur="$(grep -m1 "^${k}=" "$CONF" | cut -d= -f2-)"
        [ "$cur" = "$v" ] && return 0
        sed -i "s|^${k}=.*|${k}=${v}|" "$CONF"
        say "   $k: $cur -> $v"
    else
        printf '%s=%s\n' "$k" "$v" >> "$CONF"
        say "   $k=$v (added)"
    fi
}

set_key global.videomode                              640x454.59.94
set_key global.gfxbackend                             vulkan
set_key global.retroarch.crt_switch_resolution        1
set_key global.retroarch.crt_switch_resolution_super  1280
set_key global.retroarch.crt_switch_hires_menu        false
set_key global.retroarch.menu_driver                  rgui
set_key mame.switchres                                1
set_key fbneo.switchres                               1

# standalone emulators inherit the current mode, so each needs its own
set_key n64.videomode        640x480.59.94
set_key gamecube.videomode   640x480.59.94
set_key gamecube.dolphin_aspect_ratio 3
set_key wii.videomode        640x480.59.94
set_key ps2.videomode        640x480.59.94
set_key ps2.pcsx2_deinterlacing 1

# the two LCD handhelds -- see the README
set_key gba.videomode                          640x240.60.00
set_key gba.retroarch.crt_switch_resolution    0
set_key gba.ratio                              full
set_key gamegear.videomode                     640x240.60.00
set_key gamegear.retroarch.crt_switch_resolution 0
set_key gamegear.ratio                         full

# es.resolution in batocera-boot.conf is resynced from here and silently
# blanked; it must not be set at all
if grep -q '^es\.resolution=' "$CONF"; then
    run "sed -i '/^es\\.resolution=/d' '$CONF'"
    say "   removed es.resolution (it fights global.videomode)"
fi

# --- done --------------------------------------------------------------------
step "Done"
say "   backups:   $BACKUP/"
say "   connector: $OUTPUT"
if [ -z "$MODULE_LOCAL" ]; then
    say ""
    say "   No patched module installed -- 480i will not work until you build one"
    say "   for $KVER and re-run with --module."
fi
say ""
say "   Reboot to apply. If the screen stays black, SSH still works:"
say "     rm /boot/boot-custom.sh   # reverts the module swap and the modelines"

# --- 7. calibration ----------------------------------------------------------
# Only offered, never assumed: it needs a terminal and, more importantly, it
# needs the TV's own geometry to be set first. Under `curl | bash` there is no
# terminal at all unless ssh was given -t.
CAL=/userdata/system/crt-tools/calibrate.sh
step "Overscan calibration"

if [ "$DRY" = 1 ]; then
    say "   [dry-run] would offer to run $CAL"
elif [ ! -e /dev/tty ] || ! (: < /dev/tty) 2>/dev/null; then
    say "   No terminal here, so this part cannot be interactive."
    say "   After the reboot, run:"
    say ""
    say "     ssh -t root@$(hostname) $CAL"
else
    say "   The remaining step is trimming the picture to fit your tube, which"
    say "   needs you in front of the television. It reads one number per edge"
    say "   off a ruler pattern and writes the modeline for you."
    say ""
    say "   It should be done AFTER a reboot, and after the TV's own geometry"
    say "   has been set with 240p Test Suite."
    printf '   Run it now anyway? [y/N] ' > /dev/tty
    read -r ans < /dev/tty || ans=n
    case "$ans" in
        y|Y|yes|YES) exec "$CAL" ;;
        *) say ""; say "   Later:  ssh -t root@$(hostname) $CAL" ;;
    esac
fi
