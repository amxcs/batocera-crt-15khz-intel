#!/bin/bash
# Batocera gameStart/gameStop hook: keep the CRT on its 15kHz interlaced mode.
#
# Called as: crt-mode.sh <event> <system> <emulator> <core> <rom>
#
# On gameStop the emulator (RetroArch with crt_switch_resolution, or the
# emulator's own mode switching) has usually left the output on some other
# mode, and nothing puts it back - emulatorlauncher only restores when it
# changed the mode itself. Without this the TV is left on a 31kHz mode it
# cannot display.

EVENT="$1"
[ "$EVENT" = "gameStop" ] || exit 0

export DISPLAY="${DISPLAY:-:0.0}"
LOG="/userdata/system/logs/crt-mode.log"
MODE="676x464"
OUTPUT="DP-3"

echo "$(date): gameStop, restoring $MODE" >> "$LOG"

# The mode is created by custom-es-config at session start, but recreate it if
# an emulator wiped the mode list.
xrandr --query | grep -q "$MODE" || \
    xrandr --newmode "$MODE" 13.850 676 700 759 867 464 480 486 533 -hsync -vsync interlace >>"$LOG" 2>&1
xrandr --query | grep -A20 "^$OUTPUT connected" | grep -q "$MODE" || \
    xrandr --addmode "$OUTPUT" "$MODE" >>"$LOG" 2>&1

# Re-assert briefly: the emulator may still be tearing down its own mode.
for i in $(seq 1 8); do
    xrandr --query | grep -q "$MODE.*\*" && break
    xrandr --output "$OUTPUT" --mode "$MODE" >>"$LOG" 2>&1
    sleep 1
done
