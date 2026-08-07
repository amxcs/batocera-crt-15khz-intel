# Sony Trinitron — service menu values (as found, before any change)

> **These are one specific set's numbers, not settings to copy.** A television's
> service menu is not a configuration file: the values are matched to that
> chassis and its individual adjustment at the factory. Entering another set's
> geometry can leave you with a picture you cannot get back without going
> through every parameter, and on some chassis the same menu also reaches
> high-voltage and convergence adjustments that are not geometry at all.
>
> Write down every value you are about to change, before you change it. Read
> your own set's numbers, change only the four listed under *Notes*, and treat
> everything here as an example of the shape of the answer.

Transcribed from a photo of the service menu while the TV was fed the
`720x480i` 15.68kHz RGB signal over SCART. **Verify against the set before
relying on this** — it is read off a photograph, not dumped from the TV.

Geometry group. "as found" is the factory state; "full frame" is after shrinking
the raster until all 720x480 pixels are inside the visible screen area, checked
with the 8px-band test pattern.

| Parameter | Range | As found | Full frame |
|---|---|---|---|
| V-Linearity | 0–63 | 38 | 38 |
| V-Scroll | 0–63 | 31 | 31 |
| Left-HBlk | 0–15 | 0 | 0 |
| Right-HBlk | 0–15 | 0 | 0 |
| V-Angle | 0–63 | 28 | 28 |
| V-Bow | 0–63 | 30 | 30 |
| H-Centre | 0–63 | 36 | **43** |
| H-Size | 0–63 | 40 | **35** |
| Pin-Amp | 0–63 | 18 | 18 |
| U-Corner-Pin | 0–63 | 0 | 0 |
| L-Corner-Pin | 0–63 | 0 | 0 |
| Pin Phase | 0–63 | 28 | 28 |
| V-Slope | 0–63 | 35 | 35 |
| V-Size | 0–63 | 49 | **40** |
| S-Correction | 0–63 | 10 | 10 |
| V-Centre | 0–63 | 35 | **34** |
| V-Zoom | 0–63 | 23 | **22** |
| Magenta | 0–63 | 0 | 0 |

A standard NTSC signal puts 720 active pixels in an 858-pixel line (83.9%),
and TVs are built to overscan that by 5–10% so broadcast edges stay hidden.
Seeing the whole frame therefore *requires* shrinking the raster — centring
alone cannot do it, it only moves which side is clipped.

## Superseded

The "full frame" column above was **not** the final calibration. It was later
redone from scratch against a real 240p source — the PS1 *240p Test Suite*,
which is the right reference because it is what the games actually look like,
rather than a synthetic pattern at desktop resolution. Those final values are
not recorded here; they are whatever the set now holds.

What matters downstream is the residual overscan measured **after** that
calibration, with the ruler pattern at `720x480`:

| edge | hidden |
|---|---|
| top | 10 lines |
| bottom | 10 lines |
| left | none |
| right | none |

The horizontal timing was left alone because nothing was hidden there.

**These numbers do not match the shipped modeline, and the modeline is the one
to trust.** `640x454` trims 26 lines off the 480-line raster, and its porches
(`454 470 476 525`) put 13 of them at the top and 13 at the bottom — not 10 and
10. The table above is an older reading, taken before the calibration was redone
against the 240p Test Suite; the 13/13 in the modeline came from the later
measurement, which was never written down here.

Do not copy either figure. Measure your own set — `tools/calibrate.sh` reads one
number per edge off the ruler and derives the modeline from it — and redo the
measurement after any service-menu change. The reading is the input to the
modeline, not the other way round.

Note also that **V-Zoom is not the parameter to use.** It is a coarser stage
than V-Size, its steps are large, and changing it shifts the centre so V-Centre
has to be redone afterwards. On some chassis it is also tied to the user-facing
picture-mode/aspect setting and can revert on its own. Calibrate with V-Size
and V-Centre; touch V-Zoom only if V-Size runs out of range, and do it first.

## Notes

- Geometry on many chassis is stored **per signal system**. These were read
  with a 60Hz RGB SCART source; 50Hz PAL may use a separate set.
- Only H-Size / H-Centre / V-Size / V-Centre are needed for overscan work.
  V-Linearity, V-Slope, S-Correction, V-Bow, V-Angle, Pin-Amp, Pin Phase and
  the Corner-Pin pair shape the raster and should be left alone unless there
  is a visible defect.
- Nothing here touches high voltage, G2/screen, focus or white balance.
