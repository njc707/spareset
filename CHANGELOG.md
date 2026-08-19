# Changelog

Development history for **SpareSet**, a bodyweight rep counter for the Garmin
Instinct 2. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

Note: this repository is a methodology showcase, not the shipping source. Entries
describe product milestones; the detector implementation itself remains withheld
until Connect IQ Store approval.

---

## [Unreleased] — pre-store

Both applications are feature-complete and in daily use. Remaining work before
store submission: the data emission layer, a counting-accuracy regression on the
ship candidate, and final launcher art.

### Added
- Multi-exercise application: push-ups, squats, and crunches on one shared
  detector family with per-exercise constants.
- Burn-up progress chart with a horizontal goal bar drawn on the 100% line,
  replacing the earlier arc gauge.
- Reps-remaining readout in the sub-screen, set in a custom 5×7 bitmap font
  authored for this project (`Dc.setScale` is unavailable on this device).
- Goal celebration with three auto-rotating styles: grow, spin, and sparkle.
- Product name and identity: **SpareSet**.

### Changed
- Chart geometry corrected to measured display values rather than estimates,
  clearing the bezel occlusion boundary.
- Header type sized against the longest exercise name so no label truncates.
- Prompt grammar unified to a single colon-and-caps convention across every
  screen.

### Removed
- Rep-count blink animation, superseded by the goal bar treatment.

---

## Phase 2 — multi-exercise detection

### Added
- Squat detector, constants locked after on-device validation.
- Crunch detector, constants locked after on-device validation.
- Purpose-built display-mapping application to measure real panel geometry,
  sub-screen bounds, and bezel occlusion on hardware.

### Removed
- **Lunge detection, cut.** Calibration measured roughly a 10 mg usable signal
  window at the wrist; an upright torso produces no forearm gravity-tilt arc.
  Replaced by a leaning squat with a sternum grip (379 mg calibration swing,
  ~886 mg peak-to-peak).
- **End-of-set false-positive filter, cut.** Four independent discrimination
  methods tested across 18 captured sets; all four failed the false-flag test.
  The artifact remains correctable at the review screen. Written up as a
  documented negative result.

---

## Phase 1.5 — analysis pipeline

### Added
- FIT capture application writing raw per-axis accelerometer data through
  FitContributor developer fields.
- Python FIT decoder (`fitdecode`) producing per-axis CSV traces for offline
  signal analysis.
- Versioned on-watch storage schema: capped rolling set history plus daily goal
  state, with a documented migration path for multi-exercise records.

---

## Phase 1 — push-up counter

### Added
- Push-up rep detection from the wrist accelerometer: EMA smoothing, Y-axis rise
  detection with amplitude and re-arm thresholds, and a minimum rep interval.
- Stillness calibration before each set, with abort on an unusable baseline.
- Daily goal with a same-day floor, set review with discard, and history that
  survives restart and rolls over at local midnight.
- On-device counting-accuracy validation; Phase 1 configuration locked.

### Measured
- Accelerometer delivers ~13.2 Hz (~76 ms/sample) against a 25 Hz request, in
  25-sample batches roughly every 1.9 s.
- `Sensor.getInfo()` refreshes at ~0.2 Hz; no low-latency sensor path exists.
- Application RAM ceiling ~91.8 kB.

### Removed
- **Per-rep haptic feedback, cut.** Measured delivery latency of 0–1.9 s makes
  the cue dishonest; predictive and scheduled alternatives were rejected rather
  than risk buzzing for a rep that never occurred.
