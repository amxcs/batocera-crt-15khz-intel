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

# Give Xorg the interlaced 480i modeline up front, so the X server comes up on
# it directly instead of starting on the kernel's 640x240 console mode and
# being switched afterwards. EmulationStation does not survive a resolution
# change once it is running - it goes black and never repaints - so the mode
# has to be right before ES starts, not after.
#
# The console/splash stays on 640x240: fbcon cannot do interlace, and this only
# affects the X server.
#
# Three modelines, all covering the SAME physical area of the tube - identical
# horizontal timing (76.9% active, the switchres generic_15 proportion) at the
# exact NTSC 15.734kHz, so switching between them moves nothing. They differ
# only in how many pixels are sampled into that area:
#
#   640x454  ES menu. 454 of 480 active lines is the overscan trim - this TV
#            hides 13 lines top and 13 bottom (the porches below carry that
#            split), and line pitch depends on Hfreq and vtotal only, so
#            dropping active lines shortens the picture without touching the
#            59.94Hz field rate. Measure your own set with tools/calibrate.sh.
#   720x480  full raster, for standalone emulators that stretch to the window.
#   640x480  full raster and 4:3 in pixels, for standalone emulators that fit
#            4:3 with square pixels (they pillarbox in a 1.5:1 window).
#
# Per-system assignment is `<system>.videomode` in batocera.conf; see README.
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/20-crt-480i.conf << 'XORG_EOF'
Section "Device"
    Identifier "card0"
    Driver "modesetting"
    Option "monitor-DP-3" "CRT"
EndSection

Section "Monitor"
    Identifier "CRT"
    Modeline "640x454" 13.091 640 665 726 832 454 470 476 525 -hsync -vsync interlace
    Modeline "720x480" 14.727 720 748 817 936 480 483 489 525 -hsync -vsync interlace
    Modeline "640x480" 13.091 640 665 726 832 480 483 489 525 -hsync -vsync interlace
    Option "PreferredMode" "640x454"
EndSection
XORG_EOF
echo "$(date): wrote Xorg 480i modeline config" >> "$LOG"
