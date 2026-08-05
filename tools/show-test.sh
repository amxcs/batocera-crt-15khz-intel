#!/bin/bash
# Show a still image 1:1 on the CRT via mpv. Nearest-neighbour everywhere and
# no dithering, so 1px marker lines stay exactly one pixel wide.
export DISPLAY=:0.0
pkill -f "mpv --no-config --really-quiet --fullscreen" 2>/dev/null
[ "$1" = "off" ] && exit 0
exec mpv --no-config --really-quiet --fullscreen --no-keepaspect \
     --image-display-duration=inf --loop=inf --osd-level=0 \
     --no-input-default-bindings --input-conf=/dev/null \
     --scale=nearest --dscale=nearest --cscale=nearest \
     --sigmoid-upscaling=no --dither=no "$1"
