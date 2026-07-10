#!/usr/bin/env python3
"""
fit_qc_extract.py  —  Extractor for the Push-Up QC v2 FIT format.

The QC v2 app writes two streams as developer fields on record messages:

  BATCH stream (ground truth, 25 Hz, same path as the shipping app):
    batch_seq (uint16), batch_n (uint8), ay/ax/az (sint16[25], PAD=32767),
    phase (uint8: 0 GET SET, 1 HOLD TOP, 2 MOVE DOWN, 3 HOLD BTM,
                  4 MOVE UP, 5 REPS)

  POLL stream (Sensor.getInfo() polled every 50 ms — the low-latency candidate):
    poll_y (sint16[25]), poll_n (uint8), poll_seq (uint16)

  Session metadata: style (uint8), wrist (uint8), planned_reps (uint8)

Records are written by the watch ~1/s, unsynchronized with the batches, so the
same batch can be written twice (dedupe by batch_seq) or a batch can be missed
(seq gap — counted and reported). Set the watch to Data Recording = EVERY
SECOND, or most batches will be lost; this script will tell you if that
happened.

Usage:
    python3 fit_qc_extract.py <input.fit>

Outputs:
    <input>_25hz.csv   seq, t_ms, phase, x, y, z      (t_ms = sample_index*40)
    <input>_poll.csv   seq, t_ms, phase, y            (t_ms = sample_index*50)

Diagnostics printed: batches kept/duplicated/gapped, per-phase sample counts,
poll freshness (does getInfo actually refresh fast?), and a Y sparkline.
"""

import sys
import csv

try:
    import fitdecode
except ImportError:
    print("Missing dependency. Run:  pip3 install fitdecode")
    sys.exit(1)

PAD = 32767
STYLES = ["NORMAL", "SLOW", "FAST", "PARTIAL", "REACH"]
WRISTS = ["LEFT", "RIGHT"]
PHASES = ["GET_SET", "HOLD_TOP", "MOVE_DOWN", "HOLD_BTM", "MOVE_UP", "REPS"]


def as_list(v):
    if v is None:
        return []
    if isinstance(v, (list, tuple)):
        return list(v)
    return [v]


def valid(vals, n):
    out = []
    for i, v in enumerate(vals):
        if i >= n:
            break
        if v is None or v == PAD:
            continue
        out.append(int(v))
    return out


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fit_qc_extract.py <input.fit>")
        sys.exit(1)

    in_path = sys.argv[1]
    base = in_path.rsplit(".", 1)[0]

    batch_rows = []     # [x, y, z, phase]
    poll_rows = []      # [y, phase]
    meta = {}
    last_seq = None
    dups = 0
    gaps = 0
    gap_batches = 0
    kept = 0
    records_seen = 0
    records_with_data = 0

    with fitdecode.FitReader(in_path) as fit:
        for frame in fit:
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue

            values = {}
            for fld in frame.fields:
                values[fld.name] = fld.value

            if frame.name == "session":
                if values.get("style") is not None:
                    meta["style"] = int(values["style"])
                if values.get("wrist") is not None:
                    meta["wrist"] = int(values["wrist"])
                if values.get("planned_reps") is not None:
                    meta["planned_reps"] = int(values["planned_reps"])
                continue

            if frame.name != "record":
                continue
            records_seen += 1

            seq = values.get("batch_seq")
            if seq is None:
                continue
            seq = int(seq)
            if seq < 1:
                continue
            records_with_data += 1

            if last_seq is not None:
                if seq == last_seq:
                    dups += 1
                    continue                       # same batch written twice
                jump = (seq - last_seq) % 65536
                if jump > 1:
                    gaps += 1
                    gap_batches += (jump - 1)      # batches lost between records
            last_seq = seq

            n = int(values.get("batch_n") or 0)
            phase = int(values.get("phase") or 0)
            ax = valid(as_list(values.get("ax")), n)
            ay = valid(as_list(values.get("ay")), n)
            az = valid(as_list(values.get("az")), n)
            m = max(len(ax), len(ay), len(az))
            for i in range(m):
                xv = ax[i] if i < len(ax) else ""
                yv = ay[i] if i < len(ay) else ""
                zv = az[i] if i < len(az) else ""
                batch_rows.append([xv, yv, zv, phase])
            kept += 1

            pn = int(values.get("poll_n") or 0)
            py = valid(as_list(values.get("poll_y")), pn)
            for v in py:
                poll_rows.append([v, phase])

    # ---- write outputs ----
    p25 = base + "_25hz.csv"
    with open(p25, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["seq", "t_ms", "phase", "x", "y", "z"])
        for i, (x, y, z, ph) in enumerate(batch_rows):
            w.writerow([i, i * 40, ph, x, y, z])

    ppoll = base + "_poll.csv"
    with open(ppoll, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["seq", "t_ms", "phase", "y"])
        for i, (y, ph) in enumerate(poll_rows):
            w.writerow([i, i * 50, ph, y])

    # ---- diagnostics ----
    print("Decoded:", in_path)
    if meta:
        s = STYLES[meta.get("style", 0)] if meta.get("style", 0) < len(STYLES) else "?"
        wr = WRISTS[meta.get("wrist", 0)] if meta.get("wrist", 0) < len(WRISTS) else "?"
        print("  metadata      : style=%s  wrist=%s  planned_reps=%s"
              % (s, wr, meta.get("planned_reps", "?")))
    else:
        print("  metadata      : NOT FOUND (old-format fit?)")

    print("  records       : %d seen, %d carried data" % (records_seen, records_with_data))
    print("  batches kept  : %d  (dup skipped: %d)" % (kept, dups))
    print("  seq gaps      : %d gaps, ~%d batches lost" % (gaps, gap_batches))
    if kept > 0 and gap_batches > kept / 4:
        print("  *** HEAVY LOSS: set watch Data Recording = EVERY SECOND ***")
    print("  25Hz samples  : %d  (~%.1fs)" % (len(batch_rows), len(batch_rows) / 25.0))
    print("  poll samples  : %d  (~%.1fs at 20/s)" % (len(poll_rows), len(poll_rows) / 20.0))

    # per-phase sample counts
    from collections import Counter
    pc = Counter(r[3] for r in batch_rows)
    parts = []
    for k in sorted(pc.keys()):
        nm = PHASES[k] if k < len(PHASES) else str(k)
        parts.append("%s=%d" % (nm, pc[k]))
    print("  per-phase     :", "  ".join(parts))

    # poll freshness: does getInfo actually update between 50 ms polls?
    ys = [r[0] for r in poll_rows if r[0] != ""]
    if len(ys) > 10:
        changes = sum(1 for i in range(1, len(ys)) if ys[i] != ys[i - 1])
        frac = changes / float(len(ys) - 1)
        est_hz = frac * 20.0
        print("  poll freshness: %.0f%% of consecutive polls changed  (~%.1f Hz effective)"
              % (frac * 100, est_hz))
        if est_hz < 5:
            print("     -> getInfo is STALE; low-latency polling is NOT viable as-is")
        else:
            print("     -> getInfo refreshes usefully; polling is a viable buzz path")

    # sparkline of batch Y
    bys = [r[1] for r in batch_rows if r[1] != ""]
    if bys:
        lo, hi = min(bys), max(bys)
        chars = " .:-=+*#@"
        W = 120
        line = ""
        for i in range(W):
            j = int(i * len(bys) / W)
            t = (bys[j] - lo) / (hi - lo) if hi > lo else 0
            t = max(0.0, min(0.999, t))
            line += chars[int(t * 8)]
        print("  Y trace (25Hz stream), range [%d,%d]:" % (lo, hi))
        print("   |" + line + "|")


if __name__ == "__main__":
    main()
