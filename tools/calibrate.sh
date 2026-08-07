#!/bin/bash
# Interactive overscan calibration: put the ruler on the tube, read one number
# per edge, get a modeline back and have it written everywhere it has to agree.
#
#   ssh -t root@batocera /userdata/system/crt-tools/calibrate.sh
#
# The -t matters. Everything here reads from /dev/tty rather than stdin, so it
# also survives being piped, but ssh gives the remote no terminal at all without
# it and there is then nothing to read from.
#
# Order is not negotiable: the TV's own geometry has to be set first, against a
# game. This only trims the menu to fit inside the frame the TV is already
# showing -- it cannot make the tube show more.

set -u

OUTPUT="${CRT_OUTPUT:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
RULER=/tmp/crt-ruler.png

# Full-raster reference. Every trimmed mode is derived from this one by moving
# lines out of the active area and into the porches; htotal and vtotal never
# change, so the horizontal frequency and the field rate stay put.
BASE_CLOCK=13.091
BASE_H="640 665 726 832"
BASE_VACT=480
BASE_VSS=483            # sync start at full raster
BASE_VSE=489            # sync end
BASE_VTOT=525

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

ask() {                 # ask <prompt> <variable name>
    printf '%s' "$1" > /dev/tty
    read -r REPLY < /dev/tty
    eval "$2=\"\$REPLY\""
}

# The device node exists even when there is no controlling terminal -- ssh
# without -t is exactly that case -- so test that it can actually be opened.
if ! (: < /dev/tty) 2>/dev/null; then
    die "no controlling terminal. This step is interactive; run it as:
       ssh -t root@\$BOX $0"
fi
[ "$(id -u)" = 0 ] || die "run as root"

export DISPLAY=:0.0

if [ -z "$OUTPUT" ]; then
    OUTPUT="$(xrandr --query 2>/dev/null | awk '/ connected/{print $1; exit}')"
fi
[ -n "$OUTPUT" ] || die "no connected output -- set CRT_OUTPUT=DP-3 (or yours)"

cat <<EOF

  Overscan calibration
  --------------------
  Connector: $OUTPUT

  Step 1 of 2 happens on the television, not here.

  Launch 240p Test Suite for PS1 and use its grid and overscan patterns to set
  H/V size, H/V position and pincushion in the TV's own menu. Games run on the
  full raster, so what you set there is the real frame -- the widest, most
  centred picture the tube can give you.

  Do that first. This script only trims the menu to fit inside that frame; it
  cannot make the TV show more than it is showing.

EOF

ask "  Has the TV's geometry already been set that way? [y/N] " ans
case "$ans" in
    y|Y|yes|YES|д|да|Д|ДА) ;;
    *)
        say ""
        say "  Fine -- do that first, then run this again."
        say "  Nothing has been changed."
        exit 0
        ;;
esac

# --- put the ruler on the tube ----------------------------------------------
say ""
say "  Step 2: reading the overscan."
say ""

command -v python3 >/dev/null 2>&1 || die "python3 not found"
python3 -c 'import PIL' 2>/dev/null || die "python3 PIL not available -- cannot draw the ruler"

[ -f "$HERE/gen-overscan-ruler.py" ] || die "gen-overscan-ruler.py not next to this script"
python3 "$HERE/gen-overscan-ruler.py" "$RULER" >/dev/null || die "could not generate the ruler"

# The ruler is a 720x480 image and has to be shown 1:1, so switch to the
# full-raster mode for the duration. Remember what was on before.
PREV="$(xrandr --query | awk '/\*/{print $1; exit}')"
xrandr --newmode "720x480" 14.727 720 748 817 936 480 483 489 525 -hsync -vsync interlace 2>/dev/null || true
xrandr --addmode "$OUTPUT" "720x480" 2>/dev/null || true
xrandr --output "$OUTPUT" --mode "720x480" 2>/dev/null || warn "could not switch to 720x480 -- the reading may be off"

restore_mode() {
    [ -n "${PREV:-}" ] && xrandr --output "$OUTPUT" --mode "$PREV" 2>/dev/null
    "$HERE/show-test.sh" off 2>/dev/null
}
trap restore_mode EXIT INT TERM

"$HERE/show-test.sh" "$RULER" >/dev/null 2>&1 &
sleep 2

cat <<'EOF'
  The ruler is on the screen now. Each edge carries markers at 5, 10, 15 ...
  pixels in from that edge, each labelled with its distance.

  Read the SMALLEST number still fully visible on each edge. That is how many
  pixels the TV is hiding there.

EOF

read_edge() {           # read_edge <label> <variable>
    while :; do
        ask "  $1 edge, smallest visible number: " v
        case "$v" in
            ''|*[!0-9]*) say "  Digits only." ; continue ;;
        esac
        [ "$v" -le 60 ] || { say "  The ruler only goes to 60."; continue; }
        eval "$2=$v"
        return
    done
}

read_edge "Top   " TOP
read_edge "Bottom" BOTTOM
read_edge "Left  " LEFT
read_edge "Right " RIGHT

"$HERE/show-test.sh" off 2>/dev/null

# --- compute -----------------------------------------------------------------
VACT=$(( BASE_VACT - TOP - BOTTOM ))
[ "$VACT" -ge 380 ] || die "that leaves only $VACT active lines, which is not plausible -- re-measure"

# Interlaced modes want an even active count: each field carries half of it.
if [ $(( VACT % 2 )) -ne 0 ]; then
    VACT=$(( VACT - 1 ))
    BOTTOM=$(( BOTTOM + 1 ))
    say ""
    say "  Rounded to an even $VACT lines (each interlaced field carries half)."
fi

# Hiding N lines at the top means N more lines of back porch; hiding them at the
# bottom means N more of front porch. vtotal is untouched, so the field rate and
# the horizontal frequency do not move and the picture does not shift.
VSS=$(( BASE_VSS - TOP ))
VSE=$(( BASE_VSE - TOP ))
MODE="640x${VACT}"
ML="$BASE_CLOCK $BASE_H $VACT $VSS $VSE $BASE_VTOT"

cat <<EOF

  Measured: top $TOP, bottom $BOTTOM, left $LEFT, right $RIGHT

  Vertical  -> trimmed in the modeline:

      Modeline "$MODE" $ML -hsync -vsync interlace

      $BASE_VACT active lines minus $TOP at the top and $BOTTOM at the bottom.
      vtotal stays $BASE_VTOT, so 15.734kHz and 59.94Hz are unchanged and the
      picture does not move -- it only gets shorter.

EOF

if [ "$LEFT" -gt 0 ] || [ "$RIGHT" -gt 0 ]; then
cat <<EOF
  Horizontal -> NOT trimmed here, on purpose.

      The horizontal active proportion (76.9%) is what makes the menu and the
      games land in the same place; changing it for the menu alone would undo
      that. Use the TV's own H-Size and H-Position for the $LEFT/$RIGHT px
      instead -- and if you do, re-run this, because moving the TV's geometry
      changes the vertical reading too.

EOF
fi

ask "  Write this mode and make it permanent? [y/N] " ans
case "$ans" in
    y|Y|yes|YES|д|да|Д|ДА) ;;
    *) say ""; say "  Nothing written."; exit 0 ;;
esac

restore_mode() { "$HERE/show-test.sh" off 2>/dev/null; }   # es-mode.sh sets the mode itself

[ -x "$HERE/es-mode.sh" ] || die "es-mode.sh not next to this script"
CRT_OUTPUT="$OUTPUT" "$HERE/es-mode.sh" "$MODE" "$ML" || die "es-mode.sh failed"

say ""
say "  Done. $MODE is now the ES mode, in all five places it has to agree."
say "  Re-run this any time you touch the TV's geometry again."
