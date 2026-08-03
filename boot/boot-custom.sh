#!/bin/bash
# Batocera S00bootcustom hook - runs before udev loads kernel modules.
#
# Swaps in a locally patched i915 module. The patch stops the driver from
# advertising Y/Yf tiled framebuffer modifiers on gen9 display, so Mesa/glamor
# allocates X-tiled scanout buffers instead. Y-tiled scanout is rejected by the
# display engine in IF-ID interlace mode, which made every interlaced (480i)
# modeset fail with -EINVAL on the 15kHz CRT hooked up to DP-3.
#
# /lib/modules lives on a tmpfs-backed overlay and reverts on every boot, so the
# copy has to happen here, on the persistent /boot partition, each time.

[ "$1" = "start" ] || exit 0

SRC=/boot/i915-patched.ko
DST=/lib/modules/6.18.16/kernel/drivers/gpu/drm/i915/i915.ko
LOG=/tmp/i915-boot-swap.log

if [ -f "$SRC" ] && [ -f "$DST" ]; then
    if cp "$SRC" "$DST"; then
        echo "$(date): swapped in patched i915" >> "$LOG"
    else
        echo "$(date): FAILED to copy patched i915" >> "$LOG"
    fi
else
    echo "$(date): patched i915 or target missing, keeping stock" >> "$LOG"
fi

# The boot splash runs mpv with its own DRM modeset on the connector's mode,
# which is the 15kHz 640x240 progressive mode forced by video=DP-3:640x240eS.
# mpv derives the display aspect from those pixel dimensions (2.67:1) and
# pillarboxes the 4:3 splash, leaving black bars down both sides. On a 15kHz
# CRT 640x240 already fills a 4:3 screen (the pixels are twice as tall), so
# tell mpv not to letterbox and let it stretch to the full frame.
SPLASH=/etc/init.d/S28splash
if [ -f "$SPLASH" ] && ! grep -q 'no-keepaspect' "$SPLASH"; then
    if sed -i 's|--really-quiet --no-config|--really-quiet --no-config --no-keepaspect|g' "$SPLASH"; then
        echo "$(date): patched splash for 15kHz pixel aspect" >> "$LOG"
    fi
fi
