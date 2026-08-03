# Batocera + 15kHz CRT on Intel gen9 graphics (real 480i)

Getting Batocera to drive a consumer CRT TV at **true 15kHz, including interlaced
480i**, on **Intel** integrated graphics.

Every 15kHz/CRT guide out there assumes an AMD card. The community kernel patch
set that Batocera already ships
([`D0023R/linux_kernel_15khz`](https://github.com/D0023R/linux_kernel_15khz))
contains generic DRM fixes plus **AMD-only** display-engine fixes; Intel is not
covered, and the one Intel bug report there has been open and unresolved since
2020. This repo is the missing Intel piece.

Tested on:

| | |
|---|---|
| GPU | Intel HD Graphics 530 (Skylake, `DISPLAY_VER` 9) |
| Batocera | 43.1, kernel 6.18.16, X11 + openbox |
| Output | DisplayPort → VGA → SCART sync combiner → consumer CRT TV |
| Connector | `DP-3` (no EDID) |

---

## The actual problem

Interlace support was never the blocker. `intel_dp.c` already enables it:

```c
if (!HAS_GMCH(display) && DISPLAY_VER(display) < 12)
	connector->base.interlace_allowed = true;
```

The blocker is the **framebuffer modifier**. Mesa/glamor allocates **Y-tiled**
scanout buffers on gen9, and the display engine refuses Y-tiled scanout while a
pipe runs in IF-ID interlace mode:

```
[drm:skl_plane_check [i915]] [PLANE:33:plane 1A] Y/Yf tiling not supported in IF-ID mode
[drm:intel_plane_atomic_check [i915]] [PLANE:33:plane 1A] atomic driver check failed
[drm:drm_atomic_check_only] atomic driver check for ... failed: -22
```

Userspace picks the modifier when it *allocates* the buffer, long before any
mode is set, so by the time you ask for an interlaced mode it is already too
late. Every attempt dies as:

```
xrandr: Configure crtc 0 failed
(EE) modeset(0): failed to set mode: No such file or directory
```

The tell-tale sign in the CRTC state dump is the modifier value
`0x100000000000002` = `I915_FORMAT_MOD_Y_TILED`.

### The fix

[`patches/0001-drm-i915-no-Y-tiled-scanout-on-gen9.patch`](patches/) makes
`plane_has_modifier()` advertise only `LINEAR`/`X_TILED` on gen9. Userspace then
picks X-tiled, which scans out interlaced perfectly, **and glamor keeps
working**.

### Why not just `Option "AccelMethod" "none"`?

It does produce linear buffers and interlace does work — but Batocera's Mesa
build has no `swrast_dri.so`, so EmulationStation loses GL and enters a crash
loop. Don't go down this road.

### Why not HDMI instead of DisplayPort?

Worse. An HDMI→VGA adapter presents its own EDID pinned to 31–75 kHz, and even
*progressive* 15kHz modes get rejected on that port. DP with no EDID is far more
permissive.

---

## Build

```bash
# Match Batocera's exact kernel version, from the release tag you run:
#   configs/batocera-x86_64.board -> BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE
curl -O https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.16.tar.xz
tar xf linux-6.18.16.tar.xz && cd linux-6.18.16

# Batocera's own kernel patches (15kHz, controllers, ...) from the same tag:
#   board/batocera/x86/linux_patches/
for p in ../batocera_patches/*.patch; do patch -p1 < "$p"; done

patch -p1 < ../patches/0001-drm-i915-no-Y-tiled-scanout-on-gen9.patch

# Batocera's kernel config, from board/batocera/x86/linux_x86_64-defconfig.config
cp ../linux_x86_64-defconfig.config .config
make olddefconfig
make -j"$(nproc)" modules      # only i915.ko is needed
```

`vermagic` must match the running kernel exactly or the module refuses to load.
Build deps on Ubuntu: `flex bison libssl-dev libelf-dev dwarves`.

---

## Install

`/lib/modules` sits on a **tmpfs-backed overlay** and reverts on every boot, so
the module cannot simply be copied in place. `/boot` is a real, persistent
partition and Batocera runs `/boot/boot-custom.sh` from `S00bootcustom`,
**before udev loads modules** — so the swap happens there, and no module unload
is ever needed (unloading `i915` live is impractical: fbcon, the snd_hda audio
component and every open DRM fd hold references).

```bash
mount -o remount,rw /boot
cp i915.ko          /boot/i915-patched.ko
cp boot/boot-custom.sh /boot/boot-custom.sh
sync && mount -o remount,ro /boot

cp userdata/system/custom-es-config      /userdata/system/custom-es-config
mkdir -p /userdata/system/scripts
cp userdata/system/scripts/crt-mode.sh   /userdata/system/scripts/crt-mode.sh
chmod +x /userdata/system/custom-es-config /userdata/system/scripts/crt-mode.sh
```

Keep a copy of the stock module first — if it ever fails to load you get no
display (SSH still works):

```bash
cp /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/i915/i915.ko \
   /userdata/system/kernel-backup/i915.ko.original
```

To revert everything: delete `/boot/boot-custom.sh`.

---

## Settings

### `/userdata/system/batocera.conf`

```ini
global.videomode=676x464.59.94
global.retroarch.crt_switch_resolution=1
global.retroarch.crt_switch_resolution_super=1280
global.retroarch.crt_switch_hires_menu=false
global.gfxbackend=vulkan
mame.switchres=1
fbneo.switchres=1
```

`global.videomode` is the important one. Any value other than `default` makes
`emulatorlauncher` **skip `minTomaxResolution()` entirely** — that call runs
`xrandr --auto` and lands the TV on 640x480 @31kHz for ~4 seconds at every game
launch (RetroArch then inherits it as `video_fullscreen_x/y`).

### Kernel command line

Added to `APPEND` in `/boot/EFI/batocera/syslinux.cfg`, `/boot/boot/syslinux.cfg`
and the `linux` lines of `/boot/EFI/BOOT/grub.cfg`:

```
video=DP-3:640x240eS
```

`S` selects a 15kHz mode from the low-dotclock table added by Batocera's
`01_linux_15khz.patch`, `e` forces the connector on. This fixes the early-boot
splash, which otherwise runs at a 31kHz VESA fallback the TV cannot display. It
also removes every 31kHz mode from the connector's list, so a stray
`xrandr --auto` can no longer land on an undisplayable frequency.

### Desktop / ES modeline

Created by `custom-es-config`, tuned for one specific TV — **you will need your
own timings**:

```
xrandr --newmode 676x464 13.850 676 700 759 867 464 480 486 533 -hsync -vsync interlace
```

---

## Gotchas that cost real time

- **`intel_dp_mode_valid()` rejects any mode below 10 MHz pixel clock** on DP
  (`if (mode->clock < 10000) return MODE_CLOCK_LOW;`). A `320x240` 15kHz mode is
  6.5 MHz, so it is silently pruned from the kernel command line and the
  connector falls back to a 31kHz VESA mode. `640x240` (13.0 MHz) is fine.
  Modelines added by hand with `xrandr --newmode` bypass this validation
  entirely, which is why they can use lower dotclocks.

- **Name the modeline after its real resolution.** `batocera-resolution` splits
  the mode name on `x` and runs numeric tests on the halves; a name like
  `700x480_v2` throws `[: Illegal number` and the function bails out mid-way.

- **`global.videomode` needs the refresh suffix.** `checkModeExists()` compares
  against `batocera-resolution listModes` output, whose key is `676x464.59.94`.
  A bare `676x464` fails validation and the mode is never set.

- **Don't use `es.resolution` in `/boot/batocera-boot.conf`.** That file is
  resynced from `batocera.conf` (it says so in its own header) and the value is
  silently blanked to `es.resolution=`.

- **`custom-es-config` must re-assert the mode in a loop.**
  `emulationstation-standalone` backgrounds it and then runs `xrandr --auto`
  while starting ES, snapping the output back. The loop here is bounded — it
  stops once the mode holds — so it does not fight RetroArch's per-game
  switching later.

- **Restore the mode on `gameStop`.** `emulatorlauncher` only restores a
  resolution *it* changed itself; after an emulator does its own mode switching
  nothing puts the CRT back. Hence `crt-mode.sh`.

- **fbcon cannot do interlace.** The early-boot console/splash must use a
  *progressive* 15kHz mode (240p). Interlace is for X only.

- **The splash pillarboxes at 240p.** mpv derives display aspect from the mode's
  pixel dimensions — 640x240 reads as 2.67:1 — and adds black bars, even though
  640x240 physically fills a 4:3 CRT (the pixels are twice as tall).
  `boot-custom.sh` patches `--no-keepaspect` into `/etc/init.d/S28splash`.

---

## Verifying

```bash
# what the CRTC is actually driving, incl. horizontal frequency
DISPLAY=:0.0 xrandr --verbose --query | grep -A3 'SR-1_\|676x464'

# every mode change, in order - the quickest way to spot a stray 31kHz mode
grep 'Allocate new frame buffer' /var/log/Xorg.0.log

# confirm the patched module is in place
cat /tmp/i915-boot-swap.log
```

A healthy PS1 game launch looks like this — no 640x480 anywhere:

```
1649.987  Allocate new frame buffer 1280x240 stride
1651.149  Allocate new frame buffer 1280x480 stride     <- SR-1_1280x480@60.00i
1676.929  Allocate new frame buffer 676x464 stride      <- back to ES
```

```
SR-1_1280x480@60.00i  26.108MHz -HSync -VSync Interlace *current
      h: width 1280 ... clock 15.69KHz
      v: height 480 ... clock 60.00Hz
```

---

## Caveats

- **A Batocera upgrade breaks this.** `vermagic` is tied to the exact kernel
  version, so after an update `i915` will not load and you get no display.
  Recovery over SSH: `mount -o remount,rw /boot && rm /boot/boot-custom.sh`,
  then rebuild against the new kernel.
- The modeline is calibrated for one specific TV. Different set, different
  timings.
- The `DISPLAY_VER(display) == 9` guard means the patch only changes behaviour
  on gen9. Other generations are untouched, but also untested.
- An earlier experiment forcing `interlace_allowed` in `intel_dp.c` turned out
  to be a no-op on gen9 (it is already enabled there) and is deliberately not
  included here.
