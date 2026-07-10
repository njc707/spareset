# Phase 1.5 — Data Pipeline & Phone Companion Plan

Mission: get every rep off the watch and into a rich, phone-based data experience,
then ship the complete push-up product to the stores. Runs in tandem with Phase 2
(sit-up/squat capture); integration of new exercises waits for Phase 3.

## 0. The architectural truth that orders everything

**All history currently lives in `Application.Storage`, which nothing external can
read** — no USB path, no phone path (established empirically in Phase 1). So the
phone experience decomposes into two dependent layers:

- **1.5a — Watch-side data emission (SHIP BLOCKER).** The watch app must start
  recording sessions as FIT activities with developer fields, and must start
  capturing per-rep timestamps (the detector knows every rep moment today and
  discards it). Until this ships, every user-day of counting is history that can
  never be analyzed. This layer also buys Garmin Connect presence for free
  (activity calendar, strength-training credit) — which Garmin users expect.
- **1.5b — Companion phone app.** Native app using the **Connect IQ Mobile SDK**;
  talks to the watch app via device messaging (`Toybox.Communications`). This is
  where the full data experience lives. Local-first: no backend, no accounts —
  cheaper, simpler, and a privacy selling point.

Precedent that de-risks 1.5a: the Phase 1 QC app ran `ActivityRecording` +
FitContributor developer fields + the live 25 Hz sensor listener simultaneously on
this exact device. The pattern is proven; 1.5a is productionizing it.

## 1. Watch-side emission spec (1.5a) — design targets

Detector, UX, and screens are LOCKED (see `pushup-app-reference.md`); everything
here is additive.

1. **Per-rep timestamps.** In `detect()`, on each counted rep, append the tick
   time to the current set's rep-time array. Convert to wall time using the
   measured ~76 ms/sample reality, anchored at set start. Feeds: rep pace, rep
   intervals, fatigue curves.
2. **Per-set records (Storage schema v1.5).** Extend `"hist"` entries from
   `[epoch, reps]` to `[epoch, reps, durationMs, repTimesArray]` with backward
   compatibility (old 2-field records remain readable). Verify Storage headroom
   empirically (60 sets × ~50 rep times ≈ ~12 kB order — expected fine, but the
   Instinct 2 Storage ceiling must be measured, not assumed).
3. **FIT activity per app session** (recommended over per-set: no activity spam):
   start recording lazily at first countdown, `addLap()` per saved set, stop/save
   on app exit. Sport: strength training.
4. **FIT developer fields** (schema versioned from day one):
   - session: total reps, sets, daily goal, goal % (chartable in Garmin Connect).
   - lap (per set): reps, duration, mean/min/max rep interval.
   - record: monotonic cumulative rep counter (interpolates gracefully under
     sparse recording) + optional decimated trace with a sequence counter.
5. **Smart Recording hazard (shipped users WILL have it on):** record messages may
   be sparse, unlike our Every-Second QC captures. Design rule: nothing essential
   rides only on record cadence. Essentials go in session/lap fields (written
   reliably); record-level data (trace, cumulative counter) must degrade
   gracefully and carry seq numbers so loss is detectable. **Full-resolution
   traces go to the phone via messaging (1.5b), not via FIT.**
6. Recording is silent in the UX — no new screens; the activity appearing in
   Garmin Connect is itself the user-visible feature.

## 2. Companion app (1.5b) — plan

- **First decision of the new chat: platform.** Nate's own phone dictates the
  first target (dogfooding beats strategy). Android: cheaper ($25 once), tooling
  on the existing Windows PC or Mac. iOS: needs the Mac + $99/yr. Second platform
  later.
- **Sync protocol** over CIQ Mobile SDK device messaging: chunked, versioned,
  acknowledged. The watch keeps an unsynced-set queue in Storage (including full
  rep-time arrays and full-res traces for recent sets, pruned oldest-first under
  a Storage budget); on connect, the phone pulls the queue, acks, watch prunes.
  Message size/throughput limits must be measured early — they bound how much
  trace history can realistically sync.
- **Phone-side store:** local database (per-set records + traces), export to
  CSV/JSON (Nate requirement: raw data access always).
- App-store logistics: developer accounts, privacy policy (local-first: "your
  data never leaves your devices"), store listings — tracked in
  `Garmin_App_Submission` alongside the CIQ store listing for the watch app.

## 3. Data & metrics catalog (the product)

Everything below derives from: per-set (epoch, reps, duration), per-rep
timestamps, and per-set traces. Honesty rules: amplitude is a depth *proxy*
(milli-g tilt, not centimeters); all fatigue metrics are proxies and get validated
against real captured data before shipping (the Phase 1 empiricism doctrine
applies to metrics too — if a metric shows no signal in Nate's own data, it
doesn't ship); traces are ~13.2 Hz — "clearer" means full-res rendering, zoom, and
rep markers, not more hertz.

**Calendars & habit:** monthly heatmap by daily total; goal-met calendar; current
and longest streaks; first-set-time-of-day trend (habit consistency); day-of-week
and time-of-day distributions.

**Volume & trends:** daily/weekly/monthly totals; rolling 7/30-day averages; goal
adherence %; goal history (goal changes over time vs achievement); sets per day;
cumulative lifetime counter with projected milestone dates (10k, 50k, 100k).

**Set analytics:** daily max set; all-time PR set (with its trace); set-size
histogram; average set size trend; set count vs set size trade-off view.

**Rep timing:** per-set rep-interval series; average pace per set over time; pace
vs set size; rep-time histogram.

**Fatigue & recovery (candidate metrics, validate before shipping):** within-set
rep-interval slope (%/rep drift); within-set amplitude decay (from trace); set-N
vs set-1 size decay within a day; rest duration between sets vs next-set
performance (recovery curve); a composite "fatigue index" only if the components
prove out.

**Traces:** full-resolution per-set viewer with zoom/pan, rep markers overlaid,
body-oriented (consistent with watch); set-vs-set comparison overlay; per-rep
amplitude distribution.

**Data hygiene:** edit/annotate/delete sets on the phone; everything exportable.

## 4. Verify-first list (measure before building deep)

1. Instinct 2 practical `Application.Storage` capacity.
2. ActivityRecording + sensor listener + full UI load coexistence in the shipping
   app (QC precedent exists; re-verify with the real app).
3. CIQ device-messaging size/throughput limits (bounds trace sync design).
4. What Garmin Connect actually renders for our session/lap/record dev fields
   (screenshots; informs how much display effort 1.5a alone buys).
5. Smart Recording loss rate quantified (one capture with Smart ON).

## 5. Ship checklist — push-up product v1 (CIQ store)

- Watch app: final app-id (permanent once shipped), version scheme, crisp 62×62
  launcher icon, store screenshots + description, original branding decision
  (see `Garmin_App_Submission`).
- 1.5a emission built + verified in a real Garmin Connect account.
- On-device regression: counting accuracy across styles, all screens, goal-lock,
  midnight rollover, storage migration from pre-1.5 format.
- Companion app ships when ready — the watch app does NOT wait for it (FIT data
  accrues from day one; the companion reads history forward and backward).
- Post-ship: Phase 2/3 exercises arrive as an update or a separate trio SKU
  (decision deferred to Phase 3).
