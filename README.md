# Bodyweight Exercise Rep Counter — Garmin Instinct 2

*Working name — final branding in progress.*

An on-device rep counter for the Garmin Instinct 2 that counts **push-ups,
squats, and crunches** from the wrist alone — built by measuring what the
hardware actually does instead of trusting what the datasheet says.

> **Status:** the watch app is feature-complete and validated on-device; the
> application source will be published here when v1 ships on the Connect IQ
> Store. In the meantime this repository is the full engineering record — the
> as-built design references, the measurement methodology and its findings, and
> the QC capture tooling (Monkey C + Python) used to characterize the hardware.

Three exercises, one counting core. Each detector was tuned and validated on the
watch against real accelerometer captures with known ground truth — never from
intuition, never from the simulator (whose accelerometer is static). The push-up
detector hit **10/10 across normal, slow, and fast rep styles** in on-device
validation; the squat and crunch detectors were derived and locked by the same
measure-first method.

Runs entirely on the watch. No phone required, no accounts, no backend.

<p align="center">
  <img src="media/squatgoal.png" width="240" alt="Squat progress: fill-to-goal bar, reps-to-go in the sub-screen, daily burn-up chart">
</p>
<p align="center"><i>Daily progress for one exercise: a fill-to-goal bar on the
chart's 100% line, live reps-to-go in the round sub-screen, and a burn-up chart
from the first set to midnight. Simulator renders of the shipping code, populated
from real training data.</i></p>

## Three exercises, per-exercise goals

Each exercise has its own daily goal, its own history, and its own progress
view; a page-per-exercise carousel switches between them. The same at-a-glance
layout — goal bar, reps-to-go, burn-up chart — is shared across all three, laid
out within measured safe-draw bounds around the round sub-screen.

<p align="center">
  <img src="media/pushupgoal.png" width="240" alt="Push-up progress screen with goal bar and burn-up chart">
  <img src="media/crunchgoal.png" width="240" alt="Crunch progress screen, goal exceeded, celebration star in the sub-screen">
  <img src="media/setgoal.png" width="240" alt="Goal-edit screen: set the daily target">
</p>
<p align="center"><i>Push-up progress · crunch with the daily goal exceeded
(celebration marker in the sub-screen) · setting a daily goal.</i></p>

## How it counts

The counting method is shared across all three exercises — only the per-exercise
thresholds and the calibration posture differ.

1. **Fresh calibration every set.** A 5-second countdown measures a baseline
   over its final 3 seconds while you hold the start position; a jitter guard
   aborts if you weren't still.
2. **EMA smoothing** on the primary axis — captures showed the off-axes carry no
   usable signal for these movements on the left wrist.
3. **Amplitude-from-trailing-extreme detection.** The detector arms, tracks the
   running minimum, and counts a rep when the smoothed signal rises a tuned
   amount above that trailing trough; it re-arms after falling from the running
   peak. A refractory window suppresses double-counts.
4. **Nothing is compared against absolute levels.** Baselines drift between
   sessions, and in-set rest settles away from the calibration posture — both
   measured facts. Everything is relative to trailing extremes.

Design bias: **never miss a real rep.** An occasional false positive —
correctable in two button presses at the review screen — is the accepted lesser
evil.

<p align="center">
  <img src="media/holdstill.png" width="240" alt="Calibration countdown with a HOLD STILL cue">
  <img src="media/reps.png" width="240" alt="Live counting: real accelerometer trace advancing as reps are counted">
  <img src="media/savereps.png" width="240" alt="Review screen: full-set waveform envelope before saving">
</p>
<p align="center"><i>Per-set baseline calibration · live rep trace (real
accelerometer data, advancing in real sensor batches — no interpolated
animation) · full-set review waveform before saving.</i></p>

## What's in this repository

| Path | Contents |
|---|---|
| [`CHANGELOG.md`](CHANGELOG.md) | Versioned release history of the watch app |
| [`docs/storage-schema-reference.md`](docs/storage-schema-reference.md) | Versioned on-watch storage record format, shared across exercises |
| [`docs/instinct2-display-constraints.md`](docs/instinct2-display-constraints.md) | Measured display map: sub-screen geometry, bezel occlusion, safe drawing zones, rendering-API limits |
| [`docs/phase1_5-companion-plan.md`](docs/phase1_5-companion-plan.md) | Architecture plan for FIT data emission and a local-first phone companion |
| [`qc-app/QcView.mc`](qc-app/QcView.mc) | The QC capture app (Monkey C): accelerometer logging into FIT developer fields with a hands-free, vibration-cued protocol |
| [`tools/fit_qc_extract.py`](tools/fit_qc_extract.py) | FIT decoder for QC captures, with completeness proofs (sequence-gap detection), per-phase diagnostics, and poll-freshness measurement |
| [`tools/fit_accel_to_csv.py`](tools/fit_accel_to_csv.py) | Earlier-generation decoder for raw FIT accelerometer streams |

## Methodology

The project runs on a strict empiricism-over-assumption doctrine:

1. **Characterize before designing.** No detector logic is written until the
   signal is measured from real hardware via QC captures with known ground
   truth (fixed-duration holds, known rep counts, labeled protocol phases).
2. **Pre-register the questions.** Uncertain signal questions are written down
   before capture, so each session is designed to answer something specific.
3. **Log negative results.** Failed approaches go into an evidence ledger with
   the data that killed them, so they are never re-argued from intuition.
4. **Validate on-device.** The simulator's accelerometer is static; no accuracy
   claim is made without a sideloaded build counting real reps.
5. **Honest feedback only.** No cue ships unless it responds to real data.

The same doctrine was later turned on the *display itself*: when layout kept
failing against the watch's octagonal bezel, the fix was a purpose-built
on-device measurement app rather than another guess (see
[`docs/instinct2-display-constraints.md`](docs/instinct2-display-constraints.md)).

## The hardware, as measured

Established with the QC capture app in this repo, which writes raw accelerometer
batches into FIT developer fields for offline analysis:

| What the API accepts | What the hardware does |
|---|---|
| `sampleRate: 25` Hz | ~13.2 Hz real (~76 ms/sample) |
| 1-second listener period | 25-sample batches delivered every ~1.9 s |
| `Sensor.getInfo()` for instantaneous accel | Refreshes at ~0.2 Hz (6 distinct values across 499 polls at 50 ms) |

Consequence: **real-time per-rep feedback is physically impossible on this
device.** Any buzz or flash tied to a rep would land 0–1.9 s late. The app
therefore ships no per-rep cue at all — a scheduled/predictive buzz that merely
*pretends* to be responsive was rejected on principle.

## The display, as measured

The Instinct 2 pairs a 176×176 monochrome main display with a round sub-screen,
behind an octagonal bezel that occludes more of the screen than is obvious.
Several layouts were lost to that occlusion before it was mapped — so it was
mapped, with an on-device tool that draws numbered rulers and reports the raw
geometry, read straight off a photo:

- **Sub-screen** resolves to centre (144, 31), radius 31 — flush to the
  top-right corner, so there is *no* usable screen above or right of it.
- **Peripheral graphics** are only reliably visible from ~5 to ~10 o'clock; the
  bezel occludes out to ~16 px past the sub-screen edge, uniformly.
- **Corner-safe inset** for the octagon is ~16 px; flat horizontal elements at
  mid-height can sit much closer.
- **`Dc.setScale` does not exist** on this device/API — sub-minimum text needs a
  custom bitmap font resource, not a scaled system font.

## What didn't work (kept for the record)

- **Fixed-threshold trough crossing.** Smoothing flattens the raw downstroke
  spike; any fixed-line approach fails.
- **End-of-set watch-reach rejection — span-based features.** Reaching for the
  stop button can trip a rep; the reach's amplitude, cross-axis *swing
  magnitude*, rise time, and trough depth all overlapped real reps in captured
  data, so no magnitude threshold separates them. The review screen exists at
  exactly the only moment such a phantom can occur, so today the app corrects
  rather than rejects. **Under active investigation:** whether cross-axis
  *co-movement* and vector-magnitude deviation distinguish a compound reach from
  a single-axis rep, and a count-neutral "abnormal rep" flag at review. Result
  will be logged either way.

## Roadmap

- **v1 store release** (Connect IQ Store) — in submission prep; source lands
  here when it ships
- **Data emission:** sets recorded as FIT activities with developer fields
  (per-rep timestamps, per-set stats) for Garmin Connect presence and offline
  analysis
- **Phone companion:** local-first analytics over Connect IQ device messaging —
  no backend, no accounts — reconciling history per user across the product

## License

MIT — see [LICENSE](LICENSE).

This project is not affiliated with or endorsed by Garmin Ltd.
