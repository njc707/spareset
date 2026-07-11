# Push-Up App — As-Built Reference (Phase 1, locked)

The definitive record of the shipped push-up counter: architecture, tuned constants,
design language, and the evidence ledger. Supersedes `pushup-project-context.md`.

## 1. Detector (locked — the proven configuration)

Runs on **smoothed Y only**, per ~13.2 Hz sample, inside 1.9 s batches:

- EMA smoothing, `SMOOTH_ALPHA = 0.5`.
- **Amplitude cycle:** armed → track running minimum (trailing trough); count when
  smoothed Y rises `AMP_THRESH = 200` mg above it; disarm; re-arm after falling
  `REARM_DROP = 150` mg from the running peak.
- `MIN_REP_MS = 500` tick-ms refractory. Ticks are nominal 40 ms but real samples
  are ~76 ms, so this behaves as **~950 ms wall** — that is the configuration that
  was proven; do not "fix" it without on-device revalidation.
- **No gates. No per-rep buzz or flash.** (See ledger.)

**Calibration:** GPS-start → 5 s countdown (`COUNTDOWN_START=5`); baseline Y
averaged over the final 3 s (`MEASURE_AT=3`); jitter guard `JITTER_LIMIT=150` mg
spread aborts with double-buzz + HOLD STILL screen (X in sub-screen). Countdown
buzzes do not corrupt the baseline (verified). Sensor runs ONLY during
countdown+counting; `onHide()` is the cleanup net.

## 2. Signal facts (measured from FIT captures)

- Orientation: **rest / top of push-up = LOW Y** (~50–135 mg, session-dependent);
  **bottom of push-up = HIGH Y** (~316–362 mg). A rep = Y rises then returns.
- Amplitude 209–302 mg (medians 230–280), **speed-independent** across
  normal/slow/fast.
- Baseline drifts **between** sessions (48→135 mg observed) but is stable within
  one (~30–45 mg hold noise) → measuring it fresh each countdown is correct.
- **In-set rest sits BELOW the calibration baseline** (user settles lower than the
  posture held during countdown), and the smoothed signal **undershoots** after a
  fast ascent. Any logic assuming rest == calibration baseline will misbehave.
- X and Z carry no useful push-up signal (spans dwarfed by Y everywhere).
- Rep cadence example (10 continuous normal reps): ~1.75 s ± 0.15 s.

## 3. Evidence ledger — DO NOT RE-LITIGATE without new data

1. **True sample rate ~13.2 Hz; delivery in 25-sample batches every ~1.9 s** (both
   measured via wall-clock-fixed QC protocol phases). Requesting 25 Hz does not
   change this.
2. **`Sensor.getInfo()` is stale (~0.2 Hz)** — measured 6 distinct values across
   499 polls at 50 ms. No low-latency polling path exists.
3. **Per-rep buzz removed.** Any real-time cue lands 0–1.9 s late (batch delivery).
   A predictive/scheduled buzz was explicitly rejected by Nate on principle:
   *"if it isn't responding to real data, we don't ship it"* — cadence drifts with
   fatigue and a metronome pretending to be a sensor is worse than silence.
4. **Watch-reach discrimination is impossible in this signal.** Every candidate
   failed against real captures (6 recorded reaches + all rep styles):
   amplitude identical (reps 200–240 mg vs reaches 200–243); cross-axis X/Z
   overlapping in both full-cycle and travel windows; total rise-time separates on
   continuous sets but conflates rest pauses (hover gaps reach 100–199 mg above the
   ratcheted min via undershoot/drift → rejected REAL paced/slow reps on-device);
   locally-anchored travel time forgives pauses but collapses reach travels to
   8–10 samples = rep territory; trough depth overlaps (reps −4..−58 mg, reaches
   −1..−70). **Accepted trade:** occasional end-of-set phantom, correctable at the
   REVIEW screen (which exists at exactly the only moment the phantom can occur).
5. **Detection is amplitude-from-trailing-extreme, not trough/threshold-crossing** —
   smoothing flattens the raw downstroke spike (~−250 raw → ~−26 smoothed), so
   fixed-line approaches fail.
6. Vibration during baseline measurement does not corrupt it.

## 4. App structure

Files: `manifest.xml` (type watch-app, minSdkVersion 3.3.0, product instinct2,
Sensor permission only), `monkey.jungle`, `source/PushupApp.mc` (trivial entry),
`source/PushupView.mc` (ALL logic + drawing — the only file that normally changes),
`source/PushupDelegate.mc` (button forwarding), `resources/strings/strings.xml`,
`resources/drawables/` (launcher icon; a crisp 62×62 replacement is still wanted —
current art auto-scales with a build warning).

**States:** IDLE → COUNTDOWN → COUNTING → REVIEW ⇄ CONFIRM → SAVED.

**Buttons:** GPS = start → stop → save (the single through-line; always the safe
primary). SET/BACK = discard path (REVIEW→CONFIRM→discard) or app exit from idle.
UP/DOWN = goal ±10 at idle (goal-lock floor applies), rep ±1 during
counting/review.

## 5. Screens & design language

Design language: **solid = done, dotted = remaining** (all rings); **inversion
(black-on-white) is reserved for decision screens** (REVIEW, CONFIRM); one hero
element per screen; the sub-screen always shows state-appropriate content;
two-column hint grammar ("GPS  save", "SET  discard", "GPS  begin", "GPS  retry").

- **IDLE, pre-first-set (goal picker):** goal in FONT_NUMBER_HOT below the
  sub-screen, small UP/DOWN chevrons stacked LEFT of the number (no vertical room
  above/below), "DAILY GOAL" + "GPS  begin"; sub ring at 0 %.
- **IDLE, post-first-set (progress):** headline total in FONT_NUMBER_MILD + small
  "/goal" top-left (width-guarded vs sub-screen; drops to TINY if needed); burn-up
  chart: X spans [first-set-time − 4 % margin (≥10 min) → midnight], clock-locked
  3 h ticks labeled in 12-hour am/pm (noon tick taller; **midnight tick unlabeled**
  since v1.0.2 — the right edge is always midnight by construction, and the
  inward-justified label collided with 9p on early-start days), dashed 100 % line,
  step line with endpoint dot at the wall clock, Y ceiling steps 115→150→200→300→next-hundred; drawn in TWO
  clipped passes so nothing paints under the sub-screen; sub ring shows uncapped %.
- **COUNTDOWN:** two-zone ring offset down-left (`COUNTDOWN_OFFSET −14,+16`;
  radius auto-fit from getSubscreen, cap 70): dotted positioning zone, thick solid
  measurement fill, boundary tick, smoothly animated pointer (repeating 50 ms
  timer off `System.getTimer()`); two-line cue in ring (GET/SET → HOLD/STILL);
  countdown number in sub-screen.
- **COUNTING:** count lives in the **sub-screen** (NUMBER_MILD/TINY); the main
  area is the **live trace**: last 160 smoothed samples (~12 s), full width below
  the sub-screen, 3 px line, **body-oriented (low Y = arms extended = top of
  strip)**, auto-scaled with 300 mg floor, no baseline line (it misled — see §2).
  Advances in ~2 s batch hops — real data only. "GOAL" text appears at top on
  goal-cross (with celebration buzz, once, live, re-fire-guarded).
- **REVIEW (inverted):** "SAVE SET?" top-left; whole-set waveform = min/max
  envelope captured during counting, decimated on the fly to ≤160 columns
  (adjacent-pair merge, decimation doubles when full), rendered since v1.0.2 as a
  **fill-from-baseline area silhouette** (solid from the axis to each column's
  max — the per-column min/max thickness was not legible at this width), same
  body orientation; count in sub-screen; hints bottom.
- **CONFIRM (inverted):** "DISCARD?", count centered, "GPS  keep / SET  discard"
  (GPS is always the safe/keep action).
- **SAVED splash (900 ms):** checkmark, "SAVED", and the fresh total —
  "today N", or "GOAL!  N" on the crossing set; sub ring.
- **Abort (bad baseline):** HOLD STILL rows below sub-screen; bold X in sub-screen;
  "GPS  retry".

Remaining vibes: countdown 3-2-1 cues, long "go", double-buzz error, goal
celebration (long double-pulse, once per day, save-time backstop).

## 6. Persistence

`Application.Storage`: `"hist"` = rolling array of `[epochSeconds, reps]`, cap 60;
`"goal"` = daily target (default 100, step 10, min 10); `"goalLock"` =
`[dayKey, lockedGoal]` — after the first save of the day the morning goal becomes a
floor (UP can raise, DOWN can't go below) until the next day. Day key = local
YYYYMMDD int via `Gregorian.info`. Today's total = sum of today's sets; rolls over
at midnight; survives restart.
**Phase 3 note:** the trio will need schema v2 (`[epoch, reps, exerciseId]`) with
migration treating legacy 2-field records as push-ups.

## 7. Tuning constants (top of PushupView.mc)

Detector: SMOOTH_ALPHA 0.5, AMP_THRESH 200, REARM_DROP 150, MIN_REP_MS 500,
SAMPLE_MS 40 (nominal). Countdown: COUNTDOWN_START 5, MEASURE_AT 3,
JITTER_LIMIT 150. UI: COUNTDOWN_RING_R 70, COUNTDOWN_OFFSET_X −14 / Y 16,
SAVE_SPLASH_MS 900, CD_ANIM_MS 50, SUB_RING_INSET 3 / THICK 4 / DOT_THICK 2 /
DASH 14° / GAP 16°, WAVE_MAX 160, TRACE_LEN 160, TRACE_MIN_RANGE 300, TRACE_PEN 3.

## 8. Status & version

**LOCKED** detector; current app version **1.0.2** (chart midnight-label fix +
review waveform fill — see `CHANGELOG.md`; detector, UX flow, and persistence
schema untouched). Final on-device QC passed at 1.0.0; the 1.0.2 visual changes
still require a counting-accuracy regression pass on hardware before store
submission.

**1.5a status (ground truth as of 2026-07-11):** the data-emission layer (FIT
activity, per-rep timestamps, Storage v1.5) is **designed but NOT in the build
tree** — it existed only as a delivered artifact that was never landed in
`source/`. Treat it as a future milestone per `phase1_5-companion-plan.md`, not
as shipped code. Any file claiming to contain it must say so in its version
header (see §9).

This document is the authoritative record of the shipped configuration. Changes
from here forward belong to Phase 1.5 (data emission — additive, detector
untouched) or Phase 3 (trio integration).

## 9. Versioning & file hygiene

Adopted 2026-07-11, after a three-way mixup of identically named source files.

1. **In-file version header.** Line 2 of `PushupView.mc` carries
   `App version X.Y.Z | phase + detector status`; below it, a newest-first
   changelog, the Storage schema in effect, and an explicit note of what is
   NOT in the file (e.g. "1.5a emission NOT present"). A file must be
   identifiable in five seconds from its header alone.
2. **Manifest lockstep.** The manifest/store version is bumped to match the
   file header on every ship.
3. **Git tag per shipped version.** `git tag -a vX.Y.Z` in the private repo at
   each ship; recovery is `git show vX.Y.Z:source/PushupView.mc`, never a hunt
   through Downloads.
4. **The build tree is the only truth.** Delivered artifacts get moved into
   `~/garmin-dev/pushup/source/` and committed, or they don't exist. No editing
   outside the repo.
