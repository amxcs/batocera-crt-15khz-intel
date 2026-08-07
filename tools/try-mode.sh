#!/bin/bash
# Try a modeline on the CRT without touching any of the permanent config.
#
#   try-mode.sh <clock> <hdisp> <hss> <hse> <htot> <vdisp> <vss> <vse> <vtot>
#   try-mode.sh restore      - go back to the installed ES mode
#   try-mode.sh show         - print the current mode's timings
#
# The connector and the mode to restore to are taken from the running system.
# Override with CRT_OUTPUT=DP-1 and CRT_MODE=640x454 if the guess is wrong.
#
# Keep Hfreq at 15.734kHz and the field rate at 59.94Hz. Those are the exact
# NTSC values, and they are the reason the TV locks instantly; drifting off
# them is what previously made it take ~2 minutes to show a picture. The script
# warns when a modeline strays.
#
# Safe to change:
#   hss/hse together   move the picture LEFT  (larger) / RIGHT (smaller)
#   vss/vse together   move the picture UP    (larger) / DOWN  (smaller)
#   clock+htot scaled together   change picture WIDTH while Hfreq stays put
#     e.g. 13.5/858 = full width (textbook NTSC, 83.9% H active),
#          14.727/936 = the switchres generic_15 proportions (76.9%)
#   vdisp with vtot fixed at 525   change picture HEIGHT. Line pitch depends on
#     Hfreq and vtotal only, so fewer active lines = a genuinely shorter
#     picture at an unchanged 59.94Hz. Rule: -2 active lines = +1 vback, which
#     keeps the vertical centre put.
#
# Note this only *tests*. A change of resolution (not just timing) needs
# EmulationStation restarted before it renders into the new size.
export DISPLAY="${DISPLAY:-:0.0}"
NAME=test

OUT="${CRT_OUTPUT:-$(xrandr --query 2>/dev/null | awk '/ connected/{print $1; exit}')}"
[ -n "$OUT" ] || { echo "no connected output; set CRT_OUTPUT"; exit 1; }

# What to go back to. Read it from the installed ES mode rather than assuming:
# this used to say 720x454, which stopped being the shipped mode and left
# 'restore' switching to something that does not exist.
BASE="${CRT_MODE:-$(sed -n 's/^MODE="\([0-9]*x[0-9]*\)".*/\1/p' \
      /userdata/system/custom-es-config 2>/dev/null | head -1)}"
[ -n "$BASE" ] || BASE=640x454

show() {
    xrandr --verbose --query | grep -A3 '\*current' | head -4
}

case "$1" in
show)
    show; exit 0 ;;
restore)
    xrandr --output "$OUT" --mode "$BASE" && echo "restored $BASE"
    xrandr --delmode "$OUT" "$NAME" 2>/dev/null
    xrandr --rmmode "$NAME" 2>/dev/null
    show; exit 0 ;;
esac

if [ $# -lt 9 ]; then
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

CLK=$1 HD=$2 HSS=$3 HSE=$4 HT=$5 VD=$6 VSS=$7 VSE=$8 VT=$9

HFREQ=$(awk "BEGIN{printf \"%.3f\", $CLK*1000/$HT}")
VFREQ=$(awk "BEGIN{printf \"%.3f\", $CLK*1000000/$HT/($VT/2)}")
echo "Hfreq ${HFREQ}kHz   field ${VFREQ}Hz   H active $(awk "BEGIN{printf \"%.1f\", $HD/$HT*100}")%"
awk "BEGIN{if ($HFREQ<15.4||$HFREQ>16.05) print \"  WARNING: Hfreq far from NTSC 15.734 - the TV may be slow to lock\"}"
awk "BEGIN{if ($VFREQ<59.0||$VFREQ>60.5) print \"  WARNING: field rate far from 59.94\"}"

# Switch away first: a mode cannot be deleted while it is in use.
xrandr --output "$OUT" --mode "$BASE" 2>/dev/null
xrandr --delmode "$OUT" "$NAME" 2>/dev/null
xrandr --rmmode "$NAME" 2>/dev/null

xrandr --newmode "$NAME" "$CLK" "$HD" "$HSS" "$HSE" "$HT" "$VD" "$VSS" "$VSE" "$VT" \
       -hsync -vsync interlace || exit 1
xrandr --addmode "$OUT" "$NAME" || exit 1
xrandr --output "$OUT" --mode "$NAME" || exit 1
echo "applied - 'try-mode.sh restore' puts $BASE back"
show
