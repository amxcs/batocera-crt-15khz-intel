#!/bin/bash
# Set EmulationStation's --screensize / --screenoffset via es.customsargs.
#
#   es-frame.sh <height> <offsetY> [width] [offsetX]
#
# READ THIS BEFORE REACHING FOR IT. These two options do not do what their
# names suggest, and this was established with a framebuffer capture, not by
# guessing:
#
#   --screensize   is only the *logical* resolution the theme lays out against.
#                  ES stretches that back out to the full window afterwards, so
#                  changing it does NOT shrink the picture or create borders.
#                  At `--screensize 720 415` in a 720x480 mode, content still
#                  ran from row 15 to row 479.
#   --screenoffset does work, but it only translates. Whatever it adds at the
#                  top it clips off the bottom.
#
# So this cannot fix overscan. To make ES genuinely smaller, give it a mode with
# fewer active lines (see the README): line pitch depends on Hfreq and vtotal
# alone, so 454 active lines out of 525 is a real 5% shorter raster at an
# unchanged 59.94Hz, with no resampling.
#
# What --screensize *is* good for is the opposite problem: driving ES on a
# super-resolution mode (e.g. 1280 wide) without the theme coming out squashed,
# by laying it out at 720 and letting ES stretch it.
H=${1:?height}
OY=${2:?offsetY}
W=${3:-720}
OX=${4:-0}
echo "ES logical size ${W}x${H}, offset +${OX}+${OY}"
batocera-settings-set es.customsargs "--screensize $W $H --screenoffset $OX $OY"
batocera-es-swissknife --restart
