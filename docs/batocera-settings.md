# `batocera.conf` — the settings this setup depends on

Everything below lives in `/userdata/system/batocera.conf`. Nothing here is
specific to the Intel patch; it is the configuration that makes the menu and
every emulator land in the same frame on the CRT.

## Global

```ini
global.videomode=640x454.59.94
global.gfxbackend=vulkan
global.retroarch.crt_switch_resolution=1
global.retroarch.crt_switch_resolution_super=1280
global.retroarch.crt_switch_hires_menu=false
global.retroarch.menu_driver=rgui
mame.switchres=1
fbneo.switchres=1
```

`global.videomode` doubles as the mode every *standalone* emulator inherits, so
anything without its own `<system>.videomode` runs in the menu's trimmed frame.

## Per system

Only systems whose emulator is **not** libretro need these — RetroArch's
switchres picks its own mode per game.

```ini
n64.videomode=640x480.59.94

gamecube.videomode=640x480.59.94
gamecube.dolphin_aspect_ratio=3
wii.videomode=640x480.59.94

ps2.videomode=640x480.59.94
ps2.pcsx2_ratio=Auto 4:3/3:2
ps2.pcsx2_deinterlacing=1

cannonball.videomode=720x480.59.94
pygame.videomode=720x480.59.94
sdlpop.videomode=720x480.59.94
iortcw.videomode=720x480.59.94
moonlight.videomode=720x480.59.94
odcommander.videomode=720x480.59.94
steam.videomode=720x480.59.94
```

`640x480` for the ones that fit 4:3 with square pixels, `720x480` for the ones
that stretch to the window. Both are full-raster and cover the same area of the
tube; see the README for why the distinction exists.

The ports at the bottom are set to `720x480` as a default and have **not** been
verified individually. If one of them shows side bars, it belongs in the
`640x480` group.

## The handhelds — the libretro exceptions

Every other console here was designed to drive a television, so switchres has a
15kHz raster to aim at and needs no help. GBA and Game Gear were built around an
LCD panel and never had a TV output, so their line counts — 160 and 144 — fit
nothing. Both therefore need a compromise: a real 240p mode with non-integer
vertical scaling, rather than an integer scale that is either far too small or
interlaced.

GBA is 240x160, and 3× (480 lines, interlaced) is the only integer vertical
scale that fills a 15kHz raster. That is the mathematically right answer, but it
flickers on content that is natively progressive. To run 240p instead:

```ini
gba.videomode=640x240.60.00
gba.retroarch.crt_switch_resolution=0
gba.ratio=full
```

Game Gear is 160x144 and is worse: 2× is 288 lines, which needs ~17.3kHz at 60Hz.
Left alone switchres takes it anyway and drops the field rate to stay inside its
frequency budget, producing `SR-1_1280x288@52.43` at 16.20kHz — outside what a
15kHz set can lock. Same three keys, same reasoning:

```ini
gamegear.videomode=640x240.60.00
gamegear.retroarch.crt_switch_resolution=0
gamegear.ratio=full
```

All three are required in both cases. Without the second, switchres recomputes
its own scale and returns to its mode whatever you set. Without the third,
RetroArch loses the non-square-pixel correction that its CRT code was supplying
and leaves a wide black border on each side.

Master System runs on the same core as Game Gear and needs none of this — it was
a TV console, and switchres gives it a clean `SR-1_1280x192@59.92` at 15.64kHz.

## Checking for per-game overrides

ES writes lines like `n64["Super Mario 64 (USA).z64"].videomode=...` when
Advanced Game Options is saved for a title, and they beat everything above:

```bash
grep -nE '^[a-z0-9]+\[' /userdata/system/batocera.conf
```
