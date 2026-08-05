#!/bin/bash
# Switch the EmulationStation mode between the candidates, permanently.
#
#   es-mode.sh 720x454   19% vertical stretch in the theme, most H samples
#   es-mode.sh 640x454   5.5% stretch
#   es-mode.sh 606x454   0.1% stretch, but width is not 8-aligned
#   es-mode.sh 608x456   exactly 4:3, and both dimensions 8-aligned
#
# All of them cover the SAME area of the tube - 76.9% H active at 15.734kHz,
# ~454 of 525 lines - so nothing moves or changes size when switching. What
# changes is how many pixels ES samples into that area, and therefore the
# theme's proportions: ES lays out assuming square pixels, and on a 15kHz CRT
# they are not square.
#
# Alignment matters because the i915 patch this setup depends on forces X-tiled
# scanout buffers, and an odd stride can drop Mesa off its fast path.
set -e

case "$1" in
    720x454) ML="14.727 720 748 817 936 454 470 476 525" ;;
    640x454) ML="13.091 640 665 726 832 454 470 476 525" ;;
    606x454) ML="12.399 606 630 688 788 454 470 476 525" ;;
    608x456) ML="12.430 608 632 690 790 456 471 477 525" ;;
    *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
MODE="$1"
export DISPLAY=:0.0

xrandr --newmode "$MODE" $ML -hsync -vsync interlace 2>/dev/null || true
xrandr --addmode DP-3 "$MODE" 2>/dev/null || true
xrandr --output DP-3 --mode "$MODE"

# Never assume the rate suffix - checkModeExists() compares against this exact
# string and a mismatch means the mode is silently never set.
KEY=$(batocera-resolution listModes | grep "^${MODE}\." | head -1 | cut -d: -f1)
[ -n "$KEY" ] || { echo "mode $MODE not listed by batocera-resolution"; exit 1; }
batocera-settings-set global.videomode "$KEY"

# The mode also lives in the two scripts that re-assert it at ES start and
# after a game, so all three have to agree or the next game exit undoes this.
for f in /userdata/system/custom-es-config /userdata/system/scripts/crt-mode.sh; do
    sed -i -E "s/^MODE=\"[0-9]+x[0-9]+\"/MODE=\"$MODE\"/" "$f"
    sed -i -E "s/(--newmode \"\\\$MODE\") [0-9.]+([[:space:]]+[0-9]+){8}/\1 $ML/" "$f"
done

# And in boot-custom.sh, so X comes up on it directly instead of being switched
# after EmulationStation has already started (ES does not survive that).
mount -o remount,rw /boot
grep -q "Modeline \"$MODE\"" /boot/boot-custom.sh || \
    sed -i "/Identifier \"CRT\"/a\\    Modeline \"$MODE\" $ML -hsync -vsync interlace" /boot/boot-custom.sh
sed -i -E "s/PreferredMode\" \"[0-9]+x[0-9]+\"/PreferredMode\" \"$MODE\"/" /boot/boot-custom.sh
sync
mount -o remount,ro /boot

echo "ES mode -> $KEY"
batocera-es-swissknife --restart
