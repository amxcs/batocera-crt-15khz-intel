# Sony Trinitron — service menu values (as found, before any change)

Transcribed from a photo of the service menu while the TV was fed the
`720x480i` 15.68kHz RGB signal over SCART. **Verify against the set before
relying on this** — it is read off a photograph, not dumped from the TV.

Geometry group:

| Parameter | Range | Value |
|---|---|---|
| V-Linearity | 0–63 | 38 |
| V-Scroll | 0–63 | 31 |
| Left-HBlk | 0–15 | 0 |
| Right-HBlk | 0–15 | 0 |
| V-Angle | 0–63 | 28 |
| V-Bow | 0–63 | 30 |
| H-Centre | 0–63 | 36 |
| H-Size | 0–63 | 40 |
| Pin-Amp | 0–63 | 18 |
| U-Corner-Pin | 0–63 | 0 |
| L-Corner-Pin | 0–63 | 0 |
| Pin Phase | 0–63 | 28 |
| V-Slope | 0–63 | 35 |
| V-Size | 0–63 | 49 |
| S-Correction | 0–63 | 10 |
| V-Centre | 0–63 | 35 |
| V-Zoom | 0–63 | 23 |
| Magenta | 0–63 | 0 |

## Notes

- Geometry on many chassis is stored **per signal system**. These were read
  with a 60Hz RGB SCART source; 50Hz PAL may use a separate set.
- Only H-Size / H-Centre / V-Size / V-Centre are needed for overscan work.
  V-Linearity, V-Slope, S-Correction, V-Bow, V-Angle, Pin-Amp, Pin Phase and
  the Corner-Pin pair shape the raster and should be left alone unless there
  is a visible defect.
- Nothing here touches high voltage, G2/screen, focus or white balance.
