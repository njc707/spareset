# Storage Schema — Unified Reference (v1, LOCKED)

The single `"hist"` contract shared by the free push-up app (app-id A), the trio
app (app-id B), and the phone companion's merge layer. Locked 2026-07-17 after
the Phase 3 schema workshop. Any change requires a version-tag bump and an entry
here — never a silent shape change.

## 0. Status

**LOCKED.** Decisions below were workshopped and settled; see §6 for the
rejected alternatives and why (do-not-relitigate). The FIT developer-field
schema (1.5a) is a **separate versioned artifact** — FIT fields are namespaced
by id and do not collide the way `"hist"` does; it is specced with the emission
build, not here.

## 1. Record formats

`Application.Storage` key `"hist"` = rolling array (cap 60) of set records.
Two record shapes may coexist in one array; readers dispatch **per record**.

### v0 — legacy (pre-1.1.0; write path retired, read path permanent)

```
[epoch, reps]
```

Exactly 2 elements, no version tag. Detection rule: `size() == 2`. Normalized
on read as a push-up (`exerciseId = 0`) with no duration and empty repTimes.

### v1 — unified (current; written by app A and app B)

```
[1, epoch, reps, exerciseId, durationMs, repTimes]
 │   │      │     │           │           └─ Array<Number>: per-rep offsets (ms)
 │   │      │     │           │              from the GO moment; may be []
 │   │      │     │           └───────────── counting window, real milliseconds
 │   │      │     └───────────────────────── see enum, §2
 │   │      └─────────────────────────────── final saved count (SOURCE OF TRUTH)
 │   └────────────────────────────────────── Time.now().value(), epoch seconds,
 │                                           captured at save (same as v0)
 └────────────────────────────────────────── SCHEMA_VER = 1
```

Always 6 elements. Detection rule: `rec[0] == 1`.

## 2. exerciseId enum (append-only; matches the QC capture enum)

| id | exercise | status |
|---|---|---|
| 0 | push-up | shipping (app A writes 0 only) |
| 1 | crunch  | shipping (trio) |
| 2 | lunge   | **parked** — gap kept deliberately, never reuse |
| 3 | squat   | shipping (trio) |

The gap at 2 is the price of a 1:1 mapping between shipping data and every QC
capture ever taken. Decided 2026-07-17; do not renumber.

## 3. Time semantics

- **All durations and rep offsets are REAL milliseconds**, measured as
  `System.getTimer()` deltas anchored at the GO moment (countdown completion).
  No tick-space, no conversion factors, watch-independent by construction.
- Rep timestamps are quantized to **batch-arrival instants** (~1.9 s
  granularity on the Instinct 2) because all samples in a batch are processed
  at one wall-clock moment. Coarse but real — honest-feedback doctrine. At
  real cadences (~1.5–1.9 s/rep) this resolves individual reps in practice.
- `epoch` (seconds) marks the SAVE moment, identical to v0 semantics; the
  chart and day-keying are unchanged.

## 4. Invariants (consumers MUST tolerate all of these)

1. `reps` is the sole source of truth for the count. `repTimes.size()` may be
   **less than, equal to, or (never) greater than useful** — manual UP/DOWN
   corrections at COUNTING or REVIEW change `reps` but add/remove no
   timestamps. Analytics must not assume `repTimes.size() == reps`.
2. `repTimes` may be `[]`: the write-failure degrade ladder strips it, and the
   future 1.5b sync prunes synced sets' arrays oldest-first under the Storage
   budget. Empty is a normal state, not an error.
3. `repTimes` is capped at **REP_TIMES_CAP = 300** entries per set (safety net
   only; no real set approaches it — counting continues past the cap).
4. A `"hist"` array may mix v0 and v1 records in any order.
5. Records with an unknown (newer) version tag are **skipped, never guessed**
   (only occurs on a build downgrade).

## 5. Migration & write rules

- **Lazy migration only.** Legacy v0 records are never rewritten; they age out
  of the 60-record cap naturally. Readers normalize per record at read time.
- **Write-failure degrade ladder** (counting comes first; summaries outrank
  rich detail): (1) full record → (2) strip THIS set's repTimes → (3) strip
  ALL repTimes in history → (4) trim history to the most recent 30 records.
  Each step retries the write; failures log via `System.println` only — the
  UX never surfaces a storage error.

## 6. Decision ledger — DO NOT RE-LITIGATE without new data

1. **Explicit version tag over array-length sniffing.** Length-detection was
   the pre-Phase-3 plan and collides the moment two extensions coexist (1.5a's
   4-field push-up shape vs the trio's exerciseId shape are both "longer than
   2"). The tag costs one element and removes the ambiguity permanently. The
   sole length rule retained is the frozen `size()==2` = v0 legacy check.
2. **Real getTimer()-ms over detector tick-ms.** Tick-ms (nominal 40 ms
   samples, ~1.9× compressed vs wall) would require a stored per-watch
   conversion factor and becomes meaningless on any device with a different
   real sample rate. Real clock deltas are watch-independent and need no
   factor. (Raised by Nate 2026-07-17; the tick-ms proposal was wrong.) The
   detector's internal `_t` clock and `MIN_REP_MS` refractory are untouched —
   tick-time remains correct for *detection*; it is only wrong for *storage*.
3. **durationMs kept despite unproven metric utility.** Storage is a one-way
   door: unrecorded timing is unrecoverable for every set ever performed,
   while the cost is one Number per record. Distinct role from repTimes: it is
   the cheap timing summary that SURVIVES pruning (pace + inter-set rest
   remain computable after a set's rep array is stripped).
4. **exerciseId gap at 2 kept** (§2) — QC-enum parity beats a dense enum.
5. **Lazy over eager migration** — bulk rewrite on upgrade buys nothing and
   risks a partial write on a large array.

## 7. Open items adjacent to this schema (tracked, not blocking)

- **Instinct 2 Storage capacity is UNMEASURED** (1.5a verify-first item 1).
  Worst case ~60 sets × ~50 rep times plus serialization overhead. The degrade
  ladder is the safety net until capacity is measured on-device; measurement
  decides where the 1.5b pruning budget engages.
- **Goals / goalLock are app-local settings, not shared history** — outside
  this contract. Per-exercise goals are Phase 3 workshop item 3.
- **Companion merge rule:** the phone keys history to the USER, reads both
  app-ids, and merges into one timeline; `exerciseId` makes app A's records
  trio-compatible with zero conversion.
