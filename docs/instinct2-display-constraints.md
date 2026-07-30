# Instinct 2 Display Constraints — Measured Reference (LOCKED)

The physical drawing limits of the Instinct 2 (base) display, measured on-device
rather than estimated. Every number here replaces an assumption that had been
carried through Phase 3 layout work — several of which were wrong. Structured to
match the detector reference docs; treat §4 as a do-not-relitigate ledger.

## 0. Status

**LOCKED** (measured 2026-07-22 via the `DispMap` app, app-id
`abb5736e178845b09461740d7841d250`). Supersedes all earlier estimates in
`TrioView.mc` headers and chat history. Re-measure only if the target device
changes — `DispMap` still builds and its four screens re-run the whole pass.

Provenance: `DispMap` screens 0 GEOM (raw numbers), 1 RECT (nested inset
rectangles), 2 RADIAL (12 clock-hour spokes of dot rulers around the
sub-screen), 3 FONT (font comparison).

## 1. Core geometry

| quantity | value |
|---|---|
| `dc.getWidth()` / `getHeight()` | **176 x 176** |
| `WatchUi.getSubscreen()` | **x=113, y=0, w=62, h=62** |
| sub-screen centre | **(144, 31)** |
| sub-screen radius | **31** |
| gap above sub-screen | **0 px** |
| gap right of sub-screen | **1 px** |

**Never hardcode these.** Always derive from `getSubscreen()` — the values are
recorded here for *reasoning* about layout, not for pasting into code.

## 2. The exposed periphery (why the sub-screen is a hard wall)

The sub-screen sits **flush to the top-right corner**. There is no display above
it and effectively none to its right. Consequently:

- **Exposed periphery = ~5 o'clock to ~10 o'clock only** (the long way, down the
  left/bottom flank). From ~11 through ~4 o'clock there is **no screen at all** —
  this is geometry, not an occluding coating, and no amount of margin recovers it.
- Within the exposed window, the bezel occludes out to **subR + 16 px**,
  **uniformly** — measured at every one of the six exposed clock-hour spokes,
  with no angular variation. The +16 dot and everything beyond was visible on all
  six; +4, +8, +12 were hidden on all six.
- True boundary lies in `(subR+12, subR+16]`. **Use +16** as the working figure.

**Derived clearances** (from centre (144,31), R=31, boundary radius 47):

| direction | first clear pixel |
|---|---|
| straight below the sub-screen (6 o'clock) | **y >= 78** |
| any peripheral graphic hugging the sub-screen | **radius >= subR + 16** |

## 3. Main-area safe insets (the octagon corner cut)

Nested-rectangle test, insets 2..20 px step 2:

- **Safe CORNER inset ~= 16 px.** Two independent counts off the same photo
  landed on 14 and 16; 16 is adopted as the conservative figure. Corroborated by
  history: text at `x=10` was clipped ("USH-UP", "SQUAT" losing its S) and `x=18`
  was clean, bracketing the boundary at 14-16.
- **Flat edges at mid-height can sit far closer.** The rectangle test measures
  *corners*; a horizontal rule at vertical mid-screen is unaffected by the
  octagon cut. The chart's `_cL = 8` has always rendered correctly and stays.
- Practical rule: **corner-adjacent content >= 16 px in; full-width horizontal
  elements at mid-height may use ~8 px.**

## 4. Ledger — DO NOT RE-LITIGATE without new measurement

1. **`Dc.setScale` does not exist on Instinct 2 / CIQ 3.x.** Hard build error:
   *"Invalid symbol ':setScale' ... No function exists with the given symbol
   name."* A `dc has :setScale` guard does NOT degrade gracefully — the symbol is
   undefined for the target, so the compile fails outright. Fractional-scale text
   rendering is unavailable; **FONT_XTINY is the smallest built-in font**.
2. **Custom bitmap font resources DO work** and are the only path below XTINY.
   `TrioTiny` (5x7 glyphs, A-Z 0-9 and punctuation) compiles and renders
   correctly; adopted for the trio's "TO GO" label in 0.1.12. It cannot be
   Garmin's actual system font (not extractable), so it is a close-match pixel
   font — judged acceptable on-device before adoption.
3. **Peripheral sub-screen graphics are a dead end for progress indication.**
   Two designs were lost to §2 before it was measured: the sub-screen progress
   ring and then the arc gauge (which needed a calibration build just to find
   `GAUGE_GAP=16`). Both were ultimately replaced by a horizontal goal bar in the
   main panel, which has none of these constraints. **Prefer main-area layout for
   anything that must be reliably visible.**
4. **Effective animation refresh ceiling ~15 fps (~66 ms/frame).** Frames issued
   faster than this are dropped, not queued: star frames at 45 ms lost their
   overshoot/settle steps entirely and the animation appeared to snap to its final
   state. 65 ms/frame renders every step. Budget animation timing against ~66 ms,
   not against the timer resolution.
5. **The launcher icon is 62x62** for this device. The current 101x116 art scales
   with a build warning — cosmetic, tracked as a publishing task.

## 5. Consequences already applied (trio 0.1.12)

- `CHART_TOP = 69` -> the chart's 100% row lands at y=80, 2px clear of the y=78
  boundary; `GOAL_BAR_Y_DEFAULT = 80` matches. (Earlier conservative values of
  74/85 wasted 5px of chart height.)
- `HDR_TEXT_X = 18` (>= the 16px corner inset).
- Header band is `sub.x - HDR_TEXT_X` = **~95 px**, materially wider than the ~76
  previously assumed — enough that FONT_SMALL is a candidate for exercise names.
- Sub-screen text sizing uses a **chord-aware** fit: for a block of height `fh`
  centred `dy` from the sub-screen centre, the binding constraint is the block's
  furthest row, `|dy| + fh/2`, where usable half-width is
  `sqrt(R^2 - (|dy| + fh/2)^2)`. Flat width guesses over-estimate the room.

## 6. Open

- The 14-vs-16 corner-inset ambiguity (§3) could be closed with one more RECT
  photo if a future layout needs those 2px. Not currently blocking.
