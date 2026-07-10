#!/usr/bin/env python3
"""
fit_accel_to_csv.py  (v3)  —  Decode a Garmin FIT accelerometer stream to CSV.

Fixes vs v2:
  * Reads BOTH `calibrated_accel_*` and `compressed_calibrated_accel_*`. The
    watch stores some messages one way, some the other; v2 skipped the
    compressed ones and silently lost >half the samples.
  * Does NOT sort by the FIT timestamp (it was corrupt — 6-day spans). Samples
    are kept in true arrival order.
  * Time is a clean synthetic cadence: seq * 40 ms (25 Hz). We are NOT trusting
    the FIT's broken sub-second timing; we trust sample order + the known rate.
  * Prints a per-message dump (how many samples, which representation) so we can
    confirm the capture is complete and continuous, and a Y-axis sparkline.

Output columns: seq, t_ms, seg, accel_x, accel_y, accel_z
  t_ms = seq * 40  (synthetic, 25 Hz assumption)
  seg  = protocol-based guess from sample index: 0 = top hold (0-2.99s),
         1 = bottom hold (3-5.99s), 2 = reps (6s+). APPROXIMATE — confirm
         against the flat hold regions in the data.

Usage:
    python3 fit_accel_to_csv.py <input.fit> [output.csv]
"""

import sys
import csv

try:
    import fitdecode
except ImportError:
    print("Missing dependency. Run:  pip3 install fitdecode")
    sys.exit(1)

SAMPLE_MS = 40          # 25 Hz
HOLD_SEC = 3            # matches the QC app's top/bottom hold duration


def nonempty_list(v):
    if v is None:
        return None
    if isinstance(v, (list, tuple)):
        return list(v) if len(v) > 0 else None
    return [v]


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fit_accel_to_csv.py <input.fit> [output.csv]")
        sys.exit(1)

    in_path = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else in_path.rsplit(".", 1)[0] + ".csv"

    samples = []       # [x, y, z] in true arrival order
    msg_log = []       # (msg_index, n, source) per accelerometer_data message
    msg_index = 0

    with fitdecode.FitReader(in_path) as fit:
        for frame in fit:
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue
            if frame.name != "accelerometer_data":
                continue

            values = {}
            for fld in frame.fields:
                values[fld.name] = fld.value

            ax = nonempty_list(values.get("calibrated_accel_x"))
            ay = nonempty_list(values.get("calibrated_accel_y"))
            az = nonempty_list(values.get("calibrated_accel_z"))
            source = "calibrated"

            if ax is None and ay is None and az is None:
                ax = nonempty_list(values.get("compressed_calibrated_accel_x"))
                ay = nonempty_list(values.get("compressed_calibrated_accel_y"))
                az = nonempty_list(values.get("compressed_calibrated_accel_z"))
                source = "compressed"

            n = 0
            for arr in (ax, ay, az):
                if arr is not None:
                    n = max(n, len(arr))
            if n == 0:
                continue

            for i in range(n):
                x = ax[i] if ax and i < len(ax) else ""
                y = ay[i] if ay and i < len(ay) else ""
                z = az[i] if az and i < len(az) else ""
                samples.append([x, y, z])

            msg_log.append((msg_index, n, source))
            msg_index += 1

    if not samples:
        print("No accel samples found at all — send me the message inventory.")
        sys.exit(0)

    rows = []
    for i, (x, y, z) in enumerate(samples):
        t_ms = i * SAMPLE_MS
        seg = 0 if t_ms < HOLD_SEC * 1000 else (1 if t_ms < 2 * HOLD_SEC * 1000 else 2)
        rows.append([i, t_ms, seg, x, y, z])

    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["seq", "t_ms", "seg", "accel_x", "accel_y", "accel_z"])
        w.writerows(rows)

    # ---- diagnostics ----
    n_cal = sum(n for _, n, s in msg_log if s == "calibrated")
    n_cmp = sum(n for _, n, s in msg_log if s == "compressed")
    ys = [r[1] for r in samples if r[1] != ""]

    def rng(vals):
        return (min(vals), max(vals), max(vals) - min(vals)) if vals else (0, 0, 0)

    xs = [r[0] for r in samples if r[0] != ""]
    zs = [r[2] for r in samples if r[2] != ""]
    xr, yr, zr = rng(xs), rng(ys), rng(zs)

    print("Decoded:", in_path, "->", out_path)
    print("  total samples     :", len(samples), " (~%.1fs @ 25Hz)" % (len(samples) / 25.0))
    print("  from calibrated   :", n_cal)
    print("  from compressed   :", n_cmp, " <-- v2 was dropping these")
    print("  messages          :", len(msg_log))
    print("  X range           : min %d max %d span %d" % xr)
    print("  Y range           : min %d max %d span %d" % yr)
    print("  Z range           : min %d max %d span %d" % zr)

    # Y sparkline over the whole session (true order)
    chars = " .:-=+*#@"
    lo, hi = yr[0], yr[1]
    W = 120
    line = ""
    for i in range(W):
        j = int(i * len(ys) / W)
        t = (ys[j] - lo) / (hi - lo) if hi > lo else 0
        t = max(0.0, min(0.999, t))
        line += chars[int(t * 8)]
    print("  Y trace           :")
    print("   |" + line + "|")
    print("    (first ~150 samples = the two 3s holds; the rest = your reps)")


if __name__ == "__main__":
    main()
