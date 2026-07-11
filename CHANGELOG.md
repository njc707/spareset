# Changelog — Push-Up Counter (Garmin Instinct 2 watch app)

Versions are newest-first. Each shipped version carries the same number in the
source file header and the app manifest, and is tagged in source control.
The detection core has been **locked since 1.0.0** — visual and data-layer work
never touches the validated counting configuration.

## 1.0.2 — 2026-07-11

- **Chart:** midnight (12a) hour label dropped; tick mark kept. The chart's
  right edge is always midnight by construction, so the label was redundant —
  and its inward justification collided with the 9p label on days with an
  early first set (found with real data: first set 7:43am).
- **Review waveform:** fill-from-baseline area silhouette replaces the min/max
  envelope bars. Columns render solid from the axis to each column's max, so
  rep humps use the full panel height; the per-column min/max thickness was
  not legible at this width.
- Introduced the in-file version header + changelog convention (every source
  file identifiable from its header alone).
- Detector, UX flow, and persistence schema unchanged.

## 1.0.1

- Aesthetics pass: today's total as the progress-screen headline (with small
  /goal, width-guarded against the sub-screen); every 3 h chart tick labeled
  in 12-hour am/pm; goal-picker chevrons stacked left of the number; SAVED
  splash shows the fresh daily total and lengthened to 900 ms; hint text
  unified to two-column grammar.

## 1.0.0

- First locked build: 10/10 hardware-validated push-up counting.
- Detector: EMA smoothing (α 0.5) + amplitude-from-trailing-minimum
  (200 mg threshold, 150 mg re-arm) + ~1 s refractory, Y axis only.
- Per-set baseline calibration with countdown and jitter guard.
- Daily goal with goal lock, burn-up chart, live smoothed trace during
  counting, review waveform, manual rep correction, 60-set rolling history.
