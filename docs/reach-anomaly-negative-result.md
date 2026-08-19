# Negative Result — Terminal-Reach Anomaly Detection

**Date:** 2026-07-30
**Status:** Closed, negative. Not to be reopened without a new capture protocol (see §6).
**Scope:** push-up, squat, crunch.

**Bottom line:** the end-of-set watch-reach that produces phantom counts **cannot
be separated from a normal rep** in the captured signal, by any multi-axis method
tried. The phantom exists precisely *because* the reach is, to every sensor axis,
indistinguishable from a rep. The design stands as-is: the terminal phantom is
corrected by the user at the set-review screen, not auto-detected.

This extends earlier work in the same direction — rise-time, cross-axis swing,
trough depth, and travel time were each tested previously and each found to
overlap real reps — with four more methods, all landing in the same place.

---

## 1. What was proposed

A **count-neutral review flag**: watch the axes that stay quiet during normal
reps; if the terminal rep shows a sudden acceleration on those axes — a reach
breaking the metronomic 3D pattern — flag the set at review as "abnormal rep
detected, check your count."

The flag would never change the count, so it carried no risk against the
governing rule that a real rep must never be lost. It only points the user's eye.
It was intended as the low-risk first half of the work, with the count-changing
retroactive decrement deferred behind a much higher bar.

---

## 2. Data used

Real captures from the QC app (FitContributor developer-field batches; a 25 Hz
request that the hardware actually services at ~13.2 Hz), decoded with
`fit_qc_extract.py` v2.2. Analysis windows are taken from the rep-counting phase
of each capture. Unique sets after dedupe:

| Exercise | Sets | Composition |
| --- | --- | --- |
| Crunch | 7 | 4 normal across sessions, plus slow / fast / reach-style / get-up / wipe |
| Squat | 6 | normal / slow / fast / partial / reach-style, plus head and hip variants |
| Push-up | 5 | normal / slow / fast / partial / reach-style (earlier capture generation) |

Every set is terminated by a genuine reach to the stop button, so a terminal
reach is present in the tail of **every** file, not only the reach-style
captures. Confirmed on-device: the tail always shows a large multi-axis
excursion. The reach survives in the data — it must, since it produces the
phantom.

---

## 3. The framing correction (why early results were misleading)

A first pass compared **reach-style files** — where the user deliberately
performs repeated reach-like motions — against normal reps, and got clean
separation, AUC near 1.0 on off-axis magnitude, duration, and other features.

**This was the wrong test.** Reach-style files characterize repeated deliberate
reaching, which is a different activity. They do not characterize the single
**terminal reach** that actually causes phantoms in production. When the analysis
was redone against the real terminal reach — the last detected rep, and the
window after it, in every set — the separation vanished.

The reach-style file is a poor proxy for the production phantom. Only the
terminal-reach test reflects what the live app sees. This correction is the most
transferable lesson in the document: a proxy that produces a beautiful result is
worth more suspicion than a messy one.

---

## 4. Methods tried against the terminal reach, and results

All are within-set self-referential where possible — each set is its own baseline
— which is also the only thing a live flag could do.

**1. Off-axis energy.** RMS of the X and Z axes relative to Y motion. The
terminal reach is not separable from body reps.

**2. Per-axis jerk against the set's own p95 envelope.** The "quiet axis lights
up at the end" hypothesis. AUC for terminal-above-body was **0.14 push-up, 0.59
crunch, 0.61 squat** — at or below chance. Body reps are as jerky as the terminal
reach; normal reps routinely spike an axis as much as the reach does.

**3. 3D fingerprint against the set's own reps.** Robust z-score of the last
rep's per-axis excursion versus the set median and MAD. *Some* reaches are large
outliers — up to 6.7σ on squat — but inconsistently: 3 of 7 squat, 1 of 15
crunch, and a small push-up sample.

**4. Leave-one-out per-set outlier test.** The decisive one: score **every** rep,
legitimate and reach alike, by the same method.

| Exercise | Reach recall at 3σ | False-flag rate on legitimate reps at 3σ |
| --- | --- | --- |
| Push-up | 0% | 35% |
| Crunch | 7% | 15% |
| Squat | 43% | 15% |

Reach z-medians (1.3–2.0) are equal to or *below* legitimate-rep z-medians
(1.4–2.1) for every exercise. There is no threshold with both acceptable recall
and acceptable false-flag rate. On push-up and crunch, the flag fires on normal
reps **more often** than on reaches.

---

## 5. Why — the mechanism

The phantom is a phantom **because** the reach's signal is rep-like. The detector
counts it because its primary-axis excursion crosses the rep threshold, and the
off-axes at that same moment carry no consistent, separable reach signature
distinct from the natural rep-to-rep variability of a real set.

Normal reps are not smooth metronomic templates. They are noisy, and individual
reps deviate on off-axes as much as the reach does. So "deviation from the set's
pattern" is simply not specific to the reach.

---

## 6. The one unresolved thread

**Truncation confound.** Data arrives in roughly 25-sample batches every ~1.9 s,
and the button press stops recording. It is *possible* that the most distinctive
part of the reach — the arm swing to the button — is consistently cut off before
its batch is written. The signal would exist in the world but never reach the
data.

These files cannot resolve it, because they all end at the reach. Testing it
would require a different capture protocol: either record a beat or two **past**
the button press, or use a dedicated reach-capture mode that does not terminate
on the reach, so a full un-truncated reach can be captured and tested against
reps.

Only reopen this idea with such a protocol. On the data as captured, the answer
is settled: no separable signal.

---

## 7. Decisions locked

- **Do not build the terminal-reach anomaly flag** on off-axis, jerk, spatial,
  per-set-outlier, or 3D-fingerprint features. The false-flag rate is
  unacceptable, and a flag that cries wolf trains the user to ignore it — worse
  than no flag at all.
- **The terminal phantom stays correctable at the review screen.** This was an
  accepted trade before; it is now a validated one, because there is no
  auto-detection to be had here.
- The count-changing **retroactive decrement** is moot for the same reason, and
  stays abandoned unless §6 changes the data.

**Method note.** Rep segmentation for this analysis used an approximate Python
re-implementation of the rep detector rather than the exact shipping code.
Boundary noise slightly inflates body-rep variability, but it does not move the
headline: four independent methods agree, and the false-flag failure is large
rather than marginal.
