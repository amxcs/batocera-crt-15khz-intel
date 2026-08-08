# Batocera + 15kHz CRT on Intel gen9 graphics (real 480i)

[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](LICENSE)
[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-ffdd00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/retro_gaming)

Getting Batocera to drive a consumer CRT TV at **true 15kHz, including interlaced
480i**, on **Intel** integrated graphics.

📺 **[Watch it working](https://www.youtube.com/watch?v=1lH606wSWck)** — install
to calibrated picture, on the hardware described below.

Every 15kHz/CRT guide out there assumes an AMD card. The community kernel patch
set that Batocera already ships
([`D0023R/linux_kernel_15khz`](https://github.com/D0023R/linux_kernel_15khz))
contains generic DRM fixes plus **AMD-only** display-engine fixes; Intel is not
covered, and the one Intel bug report there has been open and unresolved for
years. This repo is the missing Intel piece.

Tested on **two** machines, both 1-litre HP office mini-PCs — the kind that turns
up second-hand for very little and fits behind the television:

| | machine A | machine B |
|---|---|---|
| Model | HP ProDesk 400 **G2** Mini | HP ProDesk 400 **G5** Desktop Mini (SKU `6GE67AV`) |
| CPU | Core i3-6100T (Skylake) | Core i3-8100T (Coffee Lake) |
| GPU | Intel HD Graphics 530 | Intel UHD Graphics 630 (`8086:3e91`) |
| `DISPLAY_VER` | 9 | 9 |
| RAM | 16GB DDR4 | 16GB DDR4 |
| Storage | 1TB NVMe + 1TB HDD | 1TB NVMe (Crucial P2) + 1TB HDD (HGST) |
| Network | USB Wi-Fi | onboard Ethernet |
| Bluetooth | USB dongle | USB dongle (CSR) |

Both GPUs are `DISPLAY_VER` 9, which is the only thing the patch actually cares
about — Skylake's HD 530 and Coffee Lake's UHD 630 are the same display
generation, and the fix applies unchanged to both. That is a wide net: it covers
most Intel desktop iGPUs from roughly 6th to 9th generation.

| | |
|---|---|
| Batocera | **43.1**, kernel 6.18.16, X11 + openbox — the version this targets |
| Display | Sony Trinitron — KV-29LS30E on A, KV-21LS30E on B |
| Output | VGA → SCART sync combiner → consumer CRT TV |
| Cable | simple homemade VGA-to-SCART cable |
| Port | 15-pin VGA (flex port) |
| Connector | `DP-3` — the name the driver uses, no EDID; see below |

The cable goes into the machine's **15-pin VGA port** — nothing is plugged into a
DisplayPort socket. The driver still calls the output `DP-3`, because on these
Minis the VGA port is a flex-port option fed by an on-board DisplayPort-to-VGA
bridge. The kernel lists no analog connector at all:

```
card0-DP-1      disconnected      card0-HDMI-A-1  disconnected
card0-DP-2      disconnected      card0-HDMI-A-2  disconnected
card0-DP-3      connected         card0-HDMI-A-3  disconnected
```

Worth knowing before you go hunting for a `VGA-1` that does not exist — and it
is also why there is no EDID (`/sys/class/drm/card0-DP-3/edid` is 0 bytes), which
is what lets arbitrary modelines through in the first place.

**`DP-3` is this board's number, not a constant.** The same flex port comes out
as `DP-1` or `DP-2` on other machines, and every script here takes the connector
as an argument. Find yours before you start:

```bash
DISPLAY=:0 xrandr --query | awk '/ connected/{print $1; exit}'
```

Or, with no X server running:

```bash
for d in /sys/class/drm/card*-*/status; do
    [ "$(cat "$d")" = connected ] && basename "$(dirname "$d")"
done
```

`tools/install.sh` does this detection itself, so if you use it you never have to
know the number.

The point worth making: a used 1-litre office box with an integrated GPU and no
extra hardware drives a 29" Trinitron at true 15kHz, interlaced modes included.
No ancient graphics card, no CRT Emudriver, no AMD.

<!-- Drop a photo of the machine next to the TV at docs/images/prodesk-mini.jpg
     and uncomment the line below - it shows the size better than any spec table.
![HP ProDesk 400 Mini next to the Trinitron](docs/images/prodesk-mini.jpg)
-->

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
*progressive* 15kHz modes get rejected on that port. The VGA flex port, which the
driver exposes as DisplayPort and which reports no EDID at all, is far more
permissive — an external adapter brings its own opinion about what the display
can do, the built-in bridge does not.

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

### The patch is opt-in, so it needs a kernel parameter

The patch does **not** change anything by default. It adds a module parameter,
and the restriction only applies when that is set:

```
i915.no_ytiled_scanout=1
```

Put it on the kernel command line next to `video=<connector>:640x240eS`.

It works this way because the modifier is chosen when userspace *allocates* the
buffer, long before a mode is set — so the driver cannot know whether that
buffer will ever be scanned out interlaced, and cannot decide per-mode. All it
can do is stop offering the modifiers interlace cannot use. Doing that
unconditionally would cost every gen9 machine Y tiling and render compression
for a feature almost none of them want, which is not a reasonable default. With
the parameter, a machine that drives a 15kHz CRT opts in and everyone else is
unaffected.

> **Note:** the module published under [releases](../../releases) was built from
> an earlier revision of this patch, which applied the restriction
> unconditionally and therefore needs no parameter. It works, and the installer
> still uses it. The parameter above applies to anything built from the patch as
> it stands now.

---

## Install

### One command

> **This is written for Batocera 43.1, kernel 6.18.16.** Flash that version and
> everything below works as written, module included. On any other version the
> installer detects the mismatch, skips the prebuilt module and tells you so —
> the rest still installs, but 480i needs a module built against *your* kernel.
> See *Build*.

Fresh Batocera 43.1, on the network, SSH enabled. One command:

```bash
ssh root@batocera 'curl -fsSL https://raw.githubusercontent.com/amxcs/batocera-crt-15khz-intel/master/tools/install.sh | bash -s -- --yes'
```

That is the whole installation. With no `--module` it fetches the prebuilt
`i915-patched-6.18.16.ko` from this repo's releases, checks its `vermagic`
against the running kernel, and refuses it if they differ. Then reboot.

Then calibrate, once, in front of the television:

```bash
ssh -t root@batocera /userdata/system/crt-tools/calibrate.sh
```

Those two commands are the entire process, and they have been run exactly as
written on a freshly flashed 43.1 stick.

Rehearse first if you prefer — `--dry-run` prints every write without making
one, and still performs the module check:

```bash
ssh root@batocera 'curl -fsSL https://raw.githubusercontent.com/amxcs/batocera-crt-15khz-intel/master/tools/install.sh | bash -s -- --dry-run --yes'
```

To use your own module instead, `--module` takes a local path or a URL.

What it does: detects the connector, verifies the module's `vermagic` against the
running kernel and **refuses to install a mismatched one** (that is the failure
that leaves you with no display), installs the boot hook, the Xorg modelines, the
ES mode script and the gameStop hook, sets the `batocera.conf` keys, and adds
`video=<connector>:640x240eS` to all three bootloader configs. It is safe to
re-run: every step checks before writing, `/boot` is returned to read-only even
if the script dies, and originals are backed up to `/userdata/crt-install-backup/`
the first time each file is touched.

If it goes wrong, one line reverts the part that can stop the display coming up:

```bash
ssh root@batocera 'rm /boot/boot-custom.sh'
```

### By hand

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

`tools/` holds the calibration helpers, none of which belong in
`/userdata/system/scripts/` (see the gotcha about that directory below):

| | |
|---|---|
| `es-mode.sh` | switch the ES mode permanently — updates all five places it has to agree |
| `try-mode.sh` | apply a modeline live, print its Hfreq/field rate, warn if it strays from NTSC |
| `gen-overscan-ruler.py` | generate the labelled ruler used to measure overscan |
| `gen-1px-frames.py` | finer 1px nested frames, once the ruler has got you close |
| `show-test.sh` | display a still 1:1 on the CRT (mpv, nearest-neighbour, no dither) |
| `install.sh` | do all of the above in one command; see *One command* |
| `calibrate.sh` | interactive overscan calibration — ruler on the tube, modeline out |
| `es-frame.sh` | ES `--screensize`/`--screenoffset`; **read its header first**, it does not do what it sounds like |

Keep a copy of the stock module first — if it ever fails to load you get no
display (SSH still works):

```bash
cp /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/i915/i915.ko \
   /userdata/system/kernel-backup/i915.ko.original
```

To revert everything: delete `/boot/boot-custom.sh`.

---

## Calibration, in order

Do these two steps in this order. They are not independent: the TV's own
geometry moves *everything*, so calibrating the menu first only means redoing it
after the first time you touch the service menu.

**1. Set the TV's geometry against a game, not against the menu.**

Launch **240p Test Suite** for PS1 and use its grid and overscan patterns to set
H/V size, H/V position and pincushion on the TV itself. Games run on the full
raster, so what you set here is the real frame — the widest, most centred
picture the tube can give you. Sony Trinitron service-menu values recorded for
this setup are in [`docs/sony-trinitron-service-values.md`](docs/).

Get this right before touching anything in software. Reducing **V-Size** is the
only way to make *games* show more; no Batocera setting can do it for them.

**2. Trim the menu until it fits inside that frame.**

Only now handle EmulationStation. [`tools/calibrate.sh`](tools/) walks the whole
step: it asks whether you have done part 1, puts the ruler on the tube, takes one
number per edge, works out the modeline and writes it everywhere it has to agree.

```bash
ssh -t root@batocera /userdata/system/crt-tools/calibrate.sh
```

The `-t` is required — it is interactive, and `ssh` gives the remote session no
terminal without it. `install.sh` offers to run this at the end, and puts the
helpers in `/userdata/system/crt-tools/`.

By hand it is the same three moves: generate the ruler with
[`tools/gen-overscan-ruler.py`](tools/) — labelled markers 5px, 10px, 15px… in
from each edge — display it 1:1 with [`tools/show-test.sh`](tools/), then pass the
result to [`tools/es-mode.sh`](tools/), which updates all five places.

The arithmetic, if you would rather do it yourself: hiding **T** lines at the top
and **B** at the bottom means moving them out of the active area and into the
porches, leaving `vtotal` alone so nothing about the frequency changes.

```
vactive     = 480 - T - B
vsync start = 483 - T
vsync end   = 489 - T
vtotal      = 525          (unchanged)
```

The tested `640x454` mode is what this gives for T=13, B=13.

Horizontal overscan is **not** trimmed this way. The 76.9% horizontal active
proportion is what makes the menu and the games land in the same place; use the
TV's H-Size for that instead — and then measure again, because moving the TV's
geometry changes the vertical reading too.

Trim **active lines, not the timing**: line pitch depends on the horizontal
frequency and vtotal alone, so −2 active lines with +1 vback keeps the vertical
centre where it is. See *Overscan: trim active lines, not the timing* below for
why, and *Do not use EmulationStation's `--screensize` for this* for the obvious
approach that does not work.

### Confirmed working

Tested on this setup and landing in the frame correctly. These are the machines
that were designed to drive a television in the first place, which is what this
whole setup is for:

| | |
|---|---|
| Nintendo | NES, SNES, N64, GameCube |
| Sega | Master System, Mega Drive, 32X, Saturn, Dreamcast |
| Sony | PS1, PS2 |

**Handhelds are a separate case.** GBA and Game Gear run, and run well, but
their games were drawn for a small LCD and never had a scanline in mind, so
getting them onto a tube costs a compromise rather than a setting. Both are
covered in *The two handhelds are a compromise, not a fit* below — treat that
section as optional reading unless you actually want them.

**On Dreamcast, pick 60Hz when a PAL game asks.** European releases often open
with a 50/60Hz selector, and the choice reaches all the way to the modeline —
the same disc gives either `SR-1_1280x480@59.94i` (vtotal 523) or
`SR-1_1280x480@50.00i` (vtotal 627). Horizontal frequency is ~15.68kHz either
way, so line pitch is unchanged and the 50Hz mode's 480 active lines fill only
76.6% of the raster instead of 91.8% — a picture about 17% shorter, on a set
that may well hold separate geometry for 50Hz signals. 60Hz keeps every system
in one modeline family and one TV calibration, and avoids the PAL speed penalty
as a bonus. Nothing in `batocera.conf` overrides this: the emulated console is
already on `reicast_broadcast=NTSC`, and the game asks anyway.

---

## Settings

### `/userdata/system/batocera.conf`

```ini
global.videomode=640x454.59.94
global.retroarch.crt_switch_resolution=1
global.retroarch.crt_switch_resolution_super=1280
global.retroarch.crt_switch_hires_menu=false
global.retroarch.menu_driver=rgui
global.gfxbackend=vulkan
mame.switchres=1
fbneo.switchres=1
```

`global.videomode` is the important one. Any value other than `default` makes
`emulatorlauncher` **skip `minTomaxResolution()` entirely** — that call runs
`xrandr --auto` and lands the TV on 640x480 @31kHz for ~4 seconds at every game
launch (RetroArch then inherits it as `video_fullscreen_x/y`).

`crt_switch_hires_menu=false` matters too: with it on, RetroArch switches to a
high-resolution (31kHz) mode for its own menu, which the TV cannot display.
`menu_driver=rgui` keeps that menu readable at 240p.

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

### The desktop modeline: NTSC frequency, switchres proportions

Two constraints pull in opposite directions, and satisfying only one of them
was the single biggest time sink here.

**Frequency must be NTSC.** switchres' own `720x480` (14.657925 MHz / htotal 935
→ 15.676kHz) sits between PAL and NTSC. The TV accepted it and then took **~2
minutes to lock at boot**. (ES's background music plays during that black
screen, which is misleading — its HTTP port 1234 answering is the real
readiness signal, and it answered at 29s.) At 15.734kHz the picture is instant.

**Geometry must match the game modes.** Games come out of switchres'
`generic_15` preset, which uses an 8.0µs horizontal back porch and so only
**76.9% H active**. Textbook NTSC (`13.5 720 739 801 858`, 4.7µs back porch) is
**83.9%**. Run the menu on the textbook one and it is ~9% wider than every game
and sits ~6% further left — one TV calibration cannot cover both.

The fix is to keep 15.734kHz but stretch htotal until H active matches
generic_15. The game mode is
`26.108160 1280 1332 1455 1664 480 483 489 523 interlace`; scaled to 720 wide
that gives htotal 936, and 15.734kHz then fixes the clock at 14.727.

| mode | Hfreq | field | H active | V active |
|---|---|---|---|---|
| textbook NTSC `13.5/858` | 15.734k | 59.94 | 83.9% | 91.4% |
| switchres `720x480` | 15.676k | 59.95 | 77.0% | 91.8% |
| **this repo's `640x454`** | **15.734k** | **59.94** | **76.9%** | **86.5%** |
| `SR-1_1280x480i` in game | 15.690k | 60.00 | 76.9% | 91.8% |
| `SR-1_1280x240` in game | 15.660k | 60.00 | 77.0% | 92.0% |

240p and 480i share their geometry, because a 480i *field* and a 240p *frame*
both sweep 240 active lines at 60Hz — interlace just offsets alternate fields by
half a line. So resolution changes mid-session do not move the picture, as long
as every mode comes from one preset.

### Overscan: trim active lines, not the timing

The last row of the ES mode above is 86.5%, not 91.4%, because 454 of the 480
lines are active. That is the overscan trim, and it is free:

> **Line pitch depends on Hfreq and vtotal only.** At 15.734kHz / 59.94Hz,
> vtotal is pinned at 525 lines. Reducing the *active* count does not stretch
> the remaining lines — the blanking absorbs the difference — so the picture
> gets genuinely shorter while the field rate never moves.

Rule when retrimming: **−2 active lines = +1 vback**, which keeps the vertical
centre fixed. Trying to shrink the picture by growing vtotal instead is a dead
end: 30 fewer visible lines would need vtotal 560, i.e. a 56.2Hz field rate.

### How wide should the menu mode be?

Independent of the trim, and easy to miss: **EmulationStation lays its theme out
assuming square pixels**, and on a 15kHz CRT they are nowhere near square. A
720x454 mode shown on a 4:3 tube has a pixel aspect of 0.84 — the whole
interface is stretched 19% vertically, so nothing in the theme is the shape its
designer intended. The width that makes it exact is `454 × 4/3 ≈ 605`.

| ES mode | layout ratio | error vs 4:3 |
|---|---|---|
| `720x454` | 1.586 | 19% |
| `640x454` | 1.410 | 5.5% |
| `608x456` | 1.333 | 0% |

All of these cover the identical area of the tube, so switching between them
moves nothing — only the sampling density changes. Going narrower costs
horizontal detail, but less than it looks: a 15kHz set fed over SCART RGB
resolves roughly 520–600 pixels across the active line, so the extra samples in
a 720-wide mode are largely not displayed anyway.

`640x454` is the setting here — a deliberate middle: most of the proportional
correction, no unusual dimensions. The geometrically exact `608x456` was tried
and did appear to make menu transitions slightly choppier, which is plausible on
two counts (an odd stride can drop Mesa off its fast path, and fewer horizontal
pixels means fewer distinct positions for a sliding animation). Switch between
them with [`tools/es-mode.sh`](tools/), which updates all five places the mode
has to be consistent.

### Measuring the trim

Measure how much to trim with [`tools/gen-overscan-ruler.py`](tools/) — it draws
labelled markers every 5px in from each edge, so you read one number per edge
instead of iterating on "a bit more". Everything on it is ≥3px thick, because a
1px horizontal line lives in only one field of an interlaced mode and flickers
at 30Hz. Display it 1:1 with [`tools/show-test.sh`](tools/) (mpv,
nearest-neighbour, dithering off).

The TV's own geometry controls are the other half of this; see [`docs/`](docs/)
for the Sony Trinitron service values recorded here. Reducing **V-Size** is the
only way to make *games* show more, since their modes use the full raster.

### Do not use EmulationStation's `--screensize` for this

It looks like the right tool and is not. `ScreenWidth`/`ScreenHeight` are only
the logical resolution the theme lays out against, which ES then stretches back
to the full window — so it creates no borders. `--screenoffset` does work but
only translates, clipping the opposite edge. Captured proof: at
`--screensize 720 415 --screenoffset 0 15` in a 720x480 mode, content started at
row 15 and still ran to row 479, with the ES help bar pushed off screen.

The stretching is useful in the *opposite* direction though — it is how ES can
be driven on a 1280-wide super-resolution mode without the theme coming out
squashed.

---

## Getting every emulator into the same frame

libretro systems agree with each other for free, because RetroArch's switchres
picks their mode. Standalone emulators do not: they simply inherit whatever mode
is current, which is ES's deliberately-trimmed one, so they come out smaller
than the games.

`emulatorlauncher.py` calls `generator.getResolutionMode(config)`, whose base
implementation is just `return config['videomode']` — so **`<system>.videomode`
in `batocera.conf`** is the per-system lever. Three modes are defined in
`boot-custom.sh`, all with **identical raster geometry** (76.9% H active,
15.734kHz, same porches) and differing only in pixel count:

| mode | modeline | for |
|---|---|---|
| `640x454` | `13.091 640 665 726 832 454 470 476 525` | ES menu (`global.videomode`) |
| `720x480` | `14.727 720 748 817 936 480 483 489 525` | standalone emulators that stretch |
| `640x480` | `13.091 640 665 726 832 480 483 489 525` | standalone emulators that force 4:3 |

Because all three cover the same physical area of the tube, switching between
them does not move or resize anything — only the sampling density changes.

### The rule

> **The mode decides the window's pixel shape. The emulator's own aspect setting
> decides what it draws inside that window.**

An emulator that fits 4:3 with square pixels will pillarbox in a 720x480 window
(1.5:1) but fill a 640x480 one exactly. Worked examples:

| system | emulator | settings | why |
|---|---|---|---|
| n64 | `mupen64plus` + glide64mk2 | `n64.videomode=640x480.59.94` | scales the N64 framebuffer by an integer factor, so SM64's 320x224 became 640x448 and left 40px black each side of a 720-wide window |
| gamecube | `dolphin` | `gamecube.videomode=640x480.59.94`, `gamecube.dolphin_aspect_ratio=3` | mode fixed the ~57px side bars; 15px remained because Dolphin rendered 625x480 regardless of aspect mode (the game's VI active width, not aspect fitting — `dolphin_aspect_ratio=2` "Force 4:3" changed nothing). `3` = "Stretch to window" ignores aspect entirely |
| ps2 | `pcsx2` | `ps2.videomode=640x480.59.94` | was still on the ES mode entirely, rendering 640 wide left-anchored in a 720-wide window. `pcsx2_ratio=Stretch` was needed while the window was 720 wide; once it is 640x480 — exactly 4:3 — `Auto 4:3/3:2` fills it just as completely and keeps genuine 16:9 titles undistorted |
| wii | `dolphin` | `wii.videomode=640x480.59.94` only | aspect deliberately left on Auto — forcing 4:3 would squash genuine 16:9 titles |

Aspect values are emulator-specific and Batocera writes them straight through:
`dolphin_aspect_ratio` 0 Auto / 1 Force 16:9 / 2 Force 4:3 / 3 Stretch;
`pcsx2_ratio` `Stretch` / `Auto 4:3/3:2` / `4:3` / `16:9`.

### Turn the deinterlacer off

Worth doing once the display chain is genuinely interlaced, and easy to overlook
because it is not a geometry setting. PCSX2 defaults to `deinterlace_mode = 0`
(Automatic), so a 480i game goes: two fields → merged into one progressive frame
→ handed to an interlaced mode that splits it back into fields. That costs the
original field timing and adds blend ghosting on motion, to fix a problem that
does not exist here.

```ini
ps2.pcsx2_deinterlacing=1     # "None"
```

The fields then pass through untouched, 60 per second, exactly as the console
would drive the tube. Combing on fast edges is the correct appearance, not an
artefact. `upscale_multiplier=1` (native internal resolution) is worth checking
at the same time, for the same reason.

### The two handhelds are a compromise, not a fit

Plenty of systems here need per-system settings — N64, GameCube, Wii and PS2 all
have their own entries above. But those are all **standalone** emulators, which
need a `videomode` simply because they inherit the current mode instead of
choosing one. GBA and Game Gear are different: they are the only **libretro**
systems that need help, and switchres normally does that job perfectly well.

The reason is that **they were never meant to reach a CRT.** Every television
console on the list was designed to drive an NTSC set, so its frame already fits
a 15kHz raster — 224 or 240 active lines inside a 262-line frame. These two were
built around a small LCD panel and have no TV output at all. GBA is 240x**160**,
Game Gear 160x**144**. Nobody ever had to make those numbers land on a scanline.

The result is that neither has a usable integer vertical scale. 1× leaves the
picture floating in the middle of the tube; 2× does not fit in a progressive
15kHz frame at all; 3× fits only by going interlaced, which reintroduces flicker
on content that is natively progressive — and these are handheld games, so
essentially all of it is.

So something has to give, and the choice below is **non-integer scaling in
exchange for a stable progressive picture**: run a real 240p mode and let the
emulator scale unevenly into it, rather than take a mathematically clean 3× that
flickers. Uneven line doubling on a CRT is far less objectionable than 30Hz
interlace shimmer on a static HUD. The two sections that follow are the same
decision applied twice.

### GBA: why switchres picks 480i, and how to get 240p

GBA is 240x**160**. At 15.68kHz / 59.73Hz vtotal is pinned at 262 progressive or
525 interlaced, so the integer vertical scales available are:

| scale | lines | raster | active |
|---|---|---|---|
| 1× | 160 | 262 progressive | 61% — two-thirds of the screen height |
| 2× | 320 | does not fit in 262 | — |
| 3× | 480 | 525 interlaced | 91.4% ✓ |

So `SR-1_1280x480@59.73i` is the correct choice — 3× is the only integer scale
that fills the screen, and 480 lines at 60Hz on a 15kHz monitor *must* be
interlaced. The cost is interlace flicker on content that is natively
progressive. For flicker-free 240p at the price of a non-integer 1.5× scale:

```ini
gba.videomode=640x240.60.00
gba.retroarch.crt_switch_resolution=0
gba.ratio=full
```

All three are needed. Without the second, switchres recomputes 3× and returns to
480i whatever mode you set. Without the third you get ~140px black on each side:
with CRT switching on, RetroArch's own CRT code supplies the non-square-pixel
aspect (`[CRT] Setting aspect ratio: 5.333333`); turn switching off and that
correction disappears, leaving RetroArch to treat 640x240 as 2.67:1.

### Game Gear: 144 lines fit nowhere, and switchres leaves the spec

Game Gear is 160x**144** — even further from a scanline count than GBA. At
15.66kHz / 60Hz the integer scales are:

| scale | lines | raster | active |
|---|---|---|---|
| 1× | 144 | 261 progressive | 55% — a small box in the middle |
| 2× | 288 | needs ~17.3kHz at 60Hz | out of range |
| 3× | 432 | 525 interlaced | 82% ✓ but interlaced |

Left alone, switchres does not pick either usable option. It doubles to 288 lines
and then, unable to reach 60Hz at that line count inside a 15kHz budget, drops
the field rate instead of the scale:

```
SR-1_1280x288@52.43   27.216MHz  1280 1334 1462 1680  288 289 292 309  -hsync -vsync
                      → 16.20kHz / 52.43Hz
```

That is progressive, but at a horizontal frequency a 15kHz set cannot lock and a
field rate 13% below what the games run at. The fix is the same three keys as
GBA, for the same 240p-with-non-integer-scaling reason:

```ini
gamegear.videomode=640x240.60.00
gamegear.retroarch.crt_switch_resolution=0
gamegear.ratio=full
```

Master System, on the same core and the same `.zip` files, needs none of this —
it was a TV console, so switchres produces a clean `SR-1_1280x192@59.92` at
15.64kHz without help. That contrast is the whole point of this section.

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

- **`global.videomode` needs the refresh suffix**, and you may not be able to
  look it up. `checkModeExists()` compares the value against
  `batocera-resolution listModes` keys, which look like `640x454.59.94`; a bare
  `640x454` fails. But on this build `listModes` returns only the two `max-*`
  entries and never enumerates custom modelines at all, so no hand-made mode can
  ever match and `changeMode()` logs `invalid video mode` instead of setting it.
  That is survivable — `custom-es-config` has already put the output on the
  right mode by then, and `minTomaxResolution()` is skipped for any
  `global.videomode` other than `default` — but it means the key cannot be read
  back from `listModes`. `tools/es-mode.sh` falls back to building it from the
  rate `xrandr` reports.

- **Batocera executes *everything* in `/userdata/system/scripts/`** as a
  gameStart/gameStop hook. A backup copy left there (`crt-mode.sh.bak-858`) ran
  alongside the real script and forced the previous mode back at every game
  exit. Keep backups outside that directory.

- **Per-game overrides beat per-system settings, silently.** ES writes
  `n64["Super Mario 64 (USA).z64"].videomode=...` into `batocera.conf` when
  Advanced Game Options is saved for a title, and that line wins over
  `n64.videomode`. When one game in a system behaves differently from the rest,
  check `grep -nE '^[a-z0-9]+\[' /userdata/system/batocera.conf` first.

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
DISPLAY=:0.0 xrandr --verbose --query | grep -A2 '\*current'

# every mode change, in order - the quickest way to spot a stray 31kHz mode
grep 'Allocate new frame buffer' /var/log/Xorg.0.log

# which mode emulatorlauncher asked for, and what switchres computed
grep -E 'wanted video mode|resolution:' /userdata/system/logs/es_launch_stdout.log
grep -E 'Switchres:|\[CRT\]'            /userdata/system/logs/es_launch_stderr.log

# confirm the patched module is in place
cat /tmp/i915-boot-swap.log
```

**Measure, don't eyeball.** What the TV shows is confounded by its own overscan,
so descriptions of where the black bars are cost several wrong turns here. Two
reliable tools:

```bash
# what an emulator actually renders, and where
DISPLAY=:0.0 ffmpeg -f x11grab -video_size 640x454 -i :0.0 -frames:v 1 -y shot.png
# ...then find the bounding box of the non-black pixels

# the window geometry itself - works even when the game is too dark to threshold
DISPLAY=:0.0 xdotool search --name '.*' getwindowgeometry %@
```

The brightness method needs a bright scene: a first attempt on a dark game
reported a 435x267 image with wildly asymmetric borders, which was pure
measurement error.

A healthy PS1 game launch looks like this — no 640x480 anywhere:

```
1649.987  Allocate new frame buffer 1280x240 stride
1651.149  Allocate new frame buffer 1280x480 stride     <- SR-1_1280x480@60.00i
1676.929  Allocate new frame buffer 640x454 stride      <- back to ES
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
- **Running ES on a super-resolution mode was tried and rejected.** The theory
  was that menu and games sharing one horizontal frequency (games are 15.690kHz,
  the menu 15.734kHz) would remove the TV's re-lock at every game launch. Both
  `1280x452` and Tekken 3's exact `1280x480` worked technically, with
  `es.customsargs="--screensize 720 480"` keeping the theme's proportions. The
  menu looked worse and the timing gain was barely perceptible — a CRT locks on
  sync, not pixel count, so the pixel clock alone buys nothing, and matching the
  game frequency exactly costs the overscan trim, since a signal cannot be
  identical to the game's *and* be shorter.

---

## How this was built

The hardware, the measurements and the testing are mine: two machines, two
Trinitrons, a lot of hours in front of the tube. So is the observation that
started it — 15kHz already worked on the same box under Lubuntu with RetroArch,
and not under Batocera, so the difference had to be findable by comparing the
two. The code archaeology, the patch, the scripts and this document were written
with Claude Opus 5.

## License

Copyright (C) 2026 amxcs

Licensed under the **GNU General Public License, version 2** — see [LICENSE](LICENSE).

`patches/0001-drm-i915-no-Y-tiled-scanout-on-gen9.patch` modifies Linux kernel
source and is a derivative work of it, so GPL-2.0 is not a preference here but a
condition of the kernel's own licence. The scripts and documentation are released
under the same terms for consistency.

If this saved you a weekend, you can
[buy me a coffee](https://buymeacoffee.com/retro_gaming).
