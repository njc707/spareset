# Phase 2 — Sit-Up & Squat Capture Plan

Mission: extend the push-up methodology to sit-ups and squats, **capture-first**.
No detector is designed from assumption; no integration happens before per-exercise
detectors are proven on-device. Product-split (push-up-only SKU vs trio) is a
Phase 3 decision and is deliberately deferred.

## 0. Why form definition comes first

The watch is on the **wrist**, so the signal is entirely a function of what the
forearm does — which, for sit-ups and squats, depends on **arm position**, not just
the exercise. The push-up was easy: hands planted, forearm tilt is mechanically
coupled to the rep. Sit-ups and squats are not. So step one for each exercise is
choosing ONE standard form — ideally the most common variant — that (a) users can
follow from a one-line description, (b) mechanically couples the watch wrist to the
rep, and (c) proves out in QC. The app will describe this form to the user (like
the push-up's calibration posture), so clean capture is a UX contract, not a hope.

**Decision principle:** prefer the most common/natural form; if it yields a weak or
unrepeatable wrist signal in QC, fall back to the next-most-common form that works.
QC arbitrates — capture two candidate forms per exercise if they're cheap to do in
one session.

### Sit-up — candidate forms (workshop, then QC)
- **(A) Hands crossed on chest** — common standard, avoids neck strain. Hypothesis:
  forearm rides the torso through a ~90° arc → large gravity-projection swing on
  one axis, push-up-like signal quality. Detail to standardize: WHICH arm crosses
  on top (watch-arm placement must be identical every session).
- **(B) Hands behind head** — classic but discouraged form (neck pull); watch
  orientation differs, elbow flare adds variance.
- **(C) Arms reaching (butterfly/reach-up)** — large wrist travel but form varies
  wildly rep to rep.
- Working recommendation to test first: **A**, with B as backup capture if A is
  ambiguous.
- Calibration posture candidate: lying flat, hands in position, still (the
  "top-hold" equivalent is the LYING position; note the rep's rest pose is lying,
  unlike the push-up where rest = up).

### Squat — candidate forms (workshop, then QC) — THE RISK CASE
- **(A) Arms extended straight forward** (common air-squat counterbalance).
  Hypothesis: forearms stay near-horizontal through the rep → gravity tilt may be
  SMALL; the signal may instead be vertical translation impulses. At ~13 Hz,
  impulse-based detection is a different beast than tilt-based — this must be
  measured, not argued.
- **(B) Hands clasped at chest** — forearm pitch changes modestly with torso lean.
- **(C) Arms at sides** — near-pure vertical translation; likely the weakest tilt
  signal.
- Honest pre-registration: the squat may produce a fundamentally different signal
  class (translation spikes rather than sustained gravity swing). If per-axis
  spans in QC look weak everywhere, the fallback conversation is: different form,
  magnitude-based detection, or descoping squats — in that order.
- Calibration posture candidate: standing still, arms in form position.

## 1. QC pipeline (built, proven in Phase 1 — extend, don't rebuild)

**QC app** (`pushup-qc/`, separate app-id, permissions Sensor + Fit +
FitContributor). Protocol per session, hands-free after GPS press, all transitions
buzzed: GET SET 5 s → HOLD pose-A 3 s → MOVE 3 s → HOLD pose-B 3 s → MOVE 3 s →
long buzz → REPS (known count) → GPS to finish. SET aborts. Blinking record dot in
sub-screen. "Sync failed" toasts are Garmin Connect noise — irrelevant; files pull
via USB.

**Capture path** = the exact same API the shipping app uses
(`registerSensorDataListener`, 25 Hz request / 1 s period), written to FIT as
developer fields on RECORD messages. **Watch must be set to Data Recording =
Every Second.** Field schema (PAD sentinel 32767):

| field | id | type | mesg |
|---|---|---|---|
| batch_seq | 0 | uint16 | record |
| batch_n | 1 | uint8 | record |
| ay / ax / az | 2/3/4 | sint16[25] | record |
| phase | 5 | uint8 | record |
| poll_y / poll_n / poll_seq | 6/7/8 | sint16[25]/uint8/uint16 | record |
| style / wrist / planned_reps | 9/10/11 | uint8 | session |

**Decode:** Mac, `python3 fit_qc_extract.py <file>.fit` (needs `pip3 install
fitdecode`) → `_25hz.csv` (seq, t_ms, phase, x, y, z) + `_poll.csv`, with
diagnostics: seq gaps/dups (completeness proof), per-phase counts, poll freshness,
Y sparkline. Real timing rule: **samples are ~76 ms apart** regardless of the
40 ms nominal tick.

**Required Phase 2 build task (small, do first):** QC app v2.1 —
1. add an EXERCISE setup field (PUSHUP/SITUP/SQUAT[/variant]) stored as session
   dev field id 12;
2. generalize hold labels to the per-exercise poses (or neutral POSE A / POSE B);
3. keep the style list (NORMAL/SLOW/FAST/PARTIAL + false-positive analogs below).
Update `fit_qc_extract.py` to read field 12.

## 2. Capture matrix (per exercise, per chosen form)

- Pose holds: start-pose 3 s + end-pose 3 s (both bracket the excursion AND test
  whether calibration pose == in-set rest — in the push-up they differed, which
  broke an algorithm once; assume nothing).
- Rep styles, known counts (5–10 each): NORMAL ×2 sessions (repeatability), SLOW,
  FAST, PARTIAL.
- **False-positive analogs** (the "REACH" equivalents — capture them even though
  Phase 1 proved discrimination may be impossible; we still need to know the
  phantom rate and shape):
  - Sit-up: getting into / out of lying position; rolling to one side; head
    scratch / face wipe while lying; the end-of-set watch reach.
  - Squat: walking a few steps; sitting into and standing from a chair;
    bending to pick something up; the end-of-set watch reach.
- Same wrist every session (LEFT was used throughout Phase 1).
- One smoke capture decoded and sanity-checked BEFORE running any full matrix
  (Phase 1 rule; it caught real problems three times).

## 3. Characterization checklist (offline, per exercise)

1. Pipeline health: seq gaps = 0, per-phase counts sane, sample rate from
   wall-clock-fixed phases.
2. Per-axis spans, holds vs reps → dominant axis + sign (do NOT inherit Y from the
   push-up).
3. Baseline value + noise at the calibration pose; in-set rest level vs that
   baseline; drift across the session; smoothing undershoot behavior.
4. Per-rep amplitude distribution across styles → is it speed-independent? (It was
   for push-ups; that's what makes a fixed threshold viable.)
5. Inter-rep timing distribution (informs MIN_REP refractory in real-ms).
6. Detector simulation vs known counts: amplitude-cycle first (the proven family),
   candidate thresholds swept for plateau (a config that only works at one magic
   number loses to one with margin).
7. False-positive analog runs through the candidate detector → phantom rate, and
   whether any feature separates them (report negative results; Phase 1's ledger
   shows the full set of dead ends for reaches — expect similar).
8. Only then: detector spec (axis, smoothing, thresholds, calibration pose,
   refractory) with the evidence cited in comments.

## 4. Validation gate (per exercise, before ANY integration)

Sideload a minimal counting build (reuse the push-up app with the new constants —
detector core is ~40 lines) and hit **≥ 10/10 across normal, slow, and fast** on
real reps, plus a sanity pass on the false-positive analogs (phantoms acceptable
only where correctable at REVIEW, matching the push-up precedent).

## 5. Carry-over doctrine (settled — do not re-open casually)

- No per-rep feedback of any kind (hardware: ~1.9 s batch delivery, stale getInfo).
  This applies to sit-ups and squats identically. Milestone cues (go, goal) are fine.
- Detection family: EMA (α 0.5 starting point) + amplitude-from-trailing-extreme +
  refractory. Different exercises may need different axes/signs/thresholds/poses —
  the FAMILY carries, the constants don't.
- Fresh per-set calibration beats stored calibration (baselines drift between
  sessions). A one-time user calibration "tutorial" remains banked for the
  phone-settings era — if used, lock RELATIVE metrics, not absolute levels.
- Live trace + review waveform (body-oriented) generalize to any exercise; keep.
- Design language: solid=done / dotted=remaining, inversion=decisions, one hero,
  GPS is always the safe primary.

## 6. Phase 3 preview (park until detectors are proven)

Exercise selection UX (likely from idle: UP/DOWN or a page cycle — workshop);
per-exercise goals + goal-locks + rings; storage schema v2 `[epoch, reps,
exerciseId]` with legacy migration (old 2-field records = push-ups); chart
treatment for three goals (per-exercise view vs combined — workshop); product
split: one trio app vs separate SKUs (separate app-ids if split; shared source
strategy TBD); crisp 62×62 launcher icon(s); publishing prep per
`Garmin_App_Submission` — original name/branding, trader verification if paid.
