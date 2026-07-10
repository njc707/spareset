// ============================================================================
// QcView.mc  (v2)  —  Push-Up QC capture app. Replaces source/QcView.mc.
// ============================================================================
// PURPOSE: capture the data needed to choose the per-rep buzz strategy.
// Two independent questions, two streams in one FIT:
//
//   STREAM 1 — "batch" (ground truth, same path as the shipping app):
//     Sensor.registerSensorDataListener @ 25 Hz. Each 1-second batch of raw
//     X/Y/Z samples is written into the FIT as developer fields on the RECORD
//     message, with a batch sequence number (drop/dup detection) and the
//     protocol phase. Offline we simulate every candidate trigger (return-band,
//     direction-change, slope-flattening, %-retrace, multi-axis) against this
//     stream and score fire-time error vs the true top of each rep.
//
//   STREAM 2 — "poll" (the low-latency delivery experiment):
//     A 50 ms timer reads Sensor.getInfo().accel (instantaneous sample) and
//     logs it alongside. If this stream refreshes at a useful rate, the live
//     app can poll it for a near-instant buzz while the proven batched
//     detector keeps counting. If it refreshes slowly, no trigger definition
//     can feel consistent through the 1 Hz batch path — and we will have
//     measured that instead of guessed it.
//
// SESSION METADATA (style / wrist / planned reps) is written INTO the FIT as
// session-level developer fields — no more remembering which file was which.
//
// PROTOCOL (all transitions buzzed; hands stay planted until the very end):
//   GPS press ->
//     phase 0  GET SET    5 s   get into top position (not analyzed)
//     phase 1  HOLD TOP   3 s   arms extended, dead still
//     phase 2  MOVE DOWN  3 s   lower to the bottom
//     phase 3  HOLD BTM   3 s   chest near floor, dead still
//     phase 4  MOVE UP    3 s   back to the top
//     phase 5  REPS       open  long buzz = go; do the planned count
//   GPS press -> save, DONE screen.
//   SET during any phase aborts and discards.
//
// IMPORTANT: set the watch to Settings > System > Data Recording > EVERY
// SECOND. "Smart" recording writes record messages sparsely and would drop
// most batches. The batch_seq field lets the offline extractor prove whether
// anything was lost.
// ============================================================================

import Toybox.Application;
import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class QcView extends WatchUi.View {

    enum {
        ST_SETUP = 0,
        ST_RUN   = 1,
        ST_DONE  = 2,
        ST_ERROR = 3
    }
    private var _state as Number = ST_SETUP;

    // ---- Protocol phases -------------------------------------------------------
    private var _phaseNames as Array = ["GET SET", "HOLD TOP", "MOVE DOWN", "HOLD BTM", "MOVE UP", "REPS"];
    private var _phaseSecs as Array = [5, 3, 3, 3, 3, 0];   // 0 = open-ended (GPS finishes)
    private var _phase as Number = 0;
    private var _phaseStartMs as Number = 0;

    private const POLL_MS  = 50;      // 20 Hz poll of Sensor.getInfo()
    private const BATCH_LEN = 25;     // samples per 25 Hz batch / array field size
    private const PAD = 32767;        // sentinel for unused array slots

    // ---- Setup selections ------------------------------------------------------
    private var _styles as Array = ["NORMAL", "SLOW", "FAST", "PARTIAL", "REACH"];
    private var _wrists as Array = ["LEFT", "RIGHT"];
    private var _styleIdx as Number = 0;
    private var _wristIdx as Number = 0;
    private var _reps as Number = 10;
    private var _field as Number = 0;      // 0 style, 1 wrist, 2 reps

    // ---- Recording session + FIT developer fields -------------------------------
    private var _session = null;
    private var _fBatchSeq = null;   // uint16, record: batch counter (drop/dup detect)
    private var _fBatchN = null;     // uint8,  record: valid samples in this batch
    private var _fAy = null;         // sint16[25], record: raw Y batch (mg)
    private var _fAx = null;         // sint16[25], record: raw X batch (mg)
    private var _fAz = null;         // sint16[25], record: raw Z batch (mg)
    private var _fPhase = null;      // uint8,  record: protocol phase 0-5
    private var _fPollY = null;      // sint16[25], record: polled Y since last batch
    private var _fPollN = null;      // uint8,  record: valid polled samples
    private var _fPollSeq = null;    // uint16, record: total polls so far (stall detect)
    private var _fStyle = null;      // uint8, session: style index
    private var _fWrist = null;      // uint8, session: wrist index
    private var _fReps = null;       // uint8, session: planned rep count

    // ---- Live capture state ------------------------------------------------------
    private var _running as Boolean = false;
    private var _batchSeq as Number = 0;
    private var _pollSeq as Number = 0;
    private var _pollRing as Array = [];
    private var _lastPollY as Number = 0;

    // ---- UI / timing ---------------------------------------------------------------
    private var _tick as Timer.Timer?;
    private var _tickCount as Number = 0;
    private var _blink as Boolean = false;

    // ---- Session bookkeeping ---------------------------------------------------
    private var _sessionNum as Number = 0;
    private var _doneStyle as String = "";
    private var _doneWrist as String = "";
    private var _doneReps as Number = 0;
    private var _doneSaved as Boolean = false;
    private var _errText as String = "";

    function initialize() {
        View.initialize();
        _tick = new Timer.Timer();
    }

    function onShow() as Void {
        var s = Application.Storage.getValue("qcSeq");
        _sessionNum = (s == null) ? 0 : s as Number;
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        stopEverything();
    }

    // ---- Buttons -----------------------------------------------------------------

    function onSelectButton() as Void {           // GPS
        if (_state == ST_SETUP) {
            startCapture();
        } else if (_state == ST_RUN && _phase == 5) {
            finishCapture();
        } else if (_state == ST_DONE || _state == ST_ERROR) {
            _state = ST_SETUP;
            WatchUi.requestUpdate();
        }
    }

    function onBackButton() as Boolean {          // SET
        if (_state == ST_RUN) {
            abortCapture();
            return true;
        }
        if (_state == ST_DONE || _state == ST_ERROR) {
            _state = ST_SETUP;
            WatchUi.requestUpdate();
            return true;
        }
        return false;   // SETUP -> exit app
    }

    function onUpButton() as Void {
        if (_state != ST_SETUP) { return; }
        if (_field == 0) {
            _styleIdx = (_styleIdx + 1) % _styles.size();
        } else if (_field == 1) {
            _wristIdx = (_wristIdx + 1) % _wrists.size();
        } else {
            _reps += 1;
        }
        WatchUi.requestUpdate();
    }

    function onDownButton() as Void {
        if (_state != ST_SETUP) { return; }
        if (_field == 0) {
            _styleIdx = (_styleIdx + _styles.size() - 1) % _styles.size();
        } else if (_field == 1) {
            _wristIdx = (_wristIdx + 1) % _wrists.size();
        } else {
            _reps -= 1;
            if (_reps < 1) { _reps = 1; }
        }
        WatchUi.requestUpdate();
    }

    function onMenuButton() as Void {             // CTRL/MENU long-press
        if (_state != ST_SETUP) { return; }
        _field = (_field + 1) % 3;
        WatchUi.requestUpdate();
    }

    // ---- Capture lifecycle ---------------------------------------------------------

    private function startCapture() as Void {
        _session = null;
        try {
            _session = ActivityRecording.createSession({
                :name => "PushupQC2",
                :sport => Activity.SPORT_TRAINING,
                :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
            });

            // Record-level developer fields (written with each ~1 Hz record)
            _fBatchSeq = _session.createField("batch_seq", 0, FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD});
            _fBatchN = _session.createField("batch_n", 1, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD});
            _fAy = _session.createField("ay", 2, FitContributor.DATA_TYPE_SINT16,
                {:count => BATCH_LEN, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg"});
            _fAx = _session.createField("ax", 3, FitContributor.DATA_TYPE_SINT16,
                {:count => BATCH_LEN, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg"});
            _fAz = _session.createField("az", 4, FitContributor.DATA_TYPE_SINT16,
                {:count => BATCH_LEN, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg"});
            _fPhase = _session.createField("phase", 5, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD});
            _fPollY = _session.createField("poll_y", 6, FitContributor.DATA_TYPE_SINT16,
                {:count => BATCH_LEN, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg"});
            _fPollN = _session.createField("poll_n", 7, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD});
            _fPollSeq = _session.createField("poll_seq", 8, FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD});

            // Session-level metadata (written once at save)
            _fStyle = _session.createField("style", 9, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION});
            _fWrist = _session.createField("wrist", 10, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION});
            _fReps = _session.createField("planned_reps", 11, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION});

            _fStyle.setData(_styleIdx);
            _fWrist.setData(_wristIdx);
            _fReps.setData(_reps);

            _session.start();

            Sensor.registerSensorDataListener(method(:onAccel), {
                :period => 1,
                :accelerometer => {
                    :enabled => true,
                    :sampleRate => 25
                }
            });
            _running = true;
        } catch (ex) {
            _errText = "setup failed";
            cleanupSession(false);
            _state = ST_ERROR;
            WatchUi.requestUpdate();
            return;
        }

        _batchSeq = 0;
        _pollSeq = 0;
        _pollRing = [];
        _phase = 0;
        _phaseStartMs = System.getTimer();
        _tickCount = 0;
        if (_tick != null) {
            _tick.stop();
            _tick.start(method(:onTick), POLL_MS, true);
        }
        _state = ST_RUN;
        buzzCue();
        WatchUi.requestUpdate();
    }

    private function finishCapture() as Void {
        stopEverything();
        var saved = false;
        if (_session != null) {
            try {
                _session.stop();
                _session.save();
                saved = true;
            } catch (ex) {
                saved = false;
            }
        }
        _session = null;

        _sessionNum += 1;
        Application.Storage.setValue("qcSeq", _sessionNum);

        _doneStyle = _styles[_styleIdx] as String;
        _doneWrist = _wrists[_wristIdx] as String;
        _doneReps = _reps;
        _doneSaved = saved;

        _state = ST_DONE;
        buzzDone();
        WatchUi.requestUpdate();
    }

    private function abortCapture() as Void {
        stopEverything();
        cleanupSession(true);
        _state = ST_SETUP;
        WatchUi.requestUpdate();
    }

    private function cleanupSession(discard as Boolean) as Void {
        if (_session != null) {
            try {
                if (discard) { _session.discard(); }
            } catch (ex) {}
        }
        _session = null;
    }

    private function stopEverything() as Void {
        if (_running) {
            try { Sensor.unregisterSensorDataListener(); } catch (ex) {}
            _running = false;
        }
        if (_tick != null) { _tick.stop(); }
    }

    // ---- 50 ms tick: poll stream + phase clock + UI -------------------------------

    function onTick() as Void {
        if (_state != ST_RUN) { return; }

        // STREAM 2: instantaneous accel via getInfo (the low-latency candidate).
        try {
            var info = Sensor.getInfo();
            if (info != null && (info has :accel) && info.accel != null) {
                _lastPollY = info.accel[1];
                _pollRing.add(_lastPollY);
                if (_pollRing.size() > BATCH_LEN) {
                    _pollRing = _pollRing.slice(_pollRing.size() - BATCH_LEN, _pollRing.size());
                }
                _pollSeq += 1;
            }
        } catch (ex) {}

        // Phase clock (wall time; hands-free transitions with buzz cues).
        var secs = _phaseSecs[_phase] as Number;
        if (secs > 0) {
            var el = System.getTimer() - _phaseStartMs;
            if (el >= secs * 1000) {
                _phase += 1;
                _phaseStartMs = System.getTimer();
                if (_phase == 5) {
                    buzzGo();          // long buzz: start your reps
                } else {
                    buzzCue();         // short buzz: next protocol step
                }
            }
        }

        _tickCount += 1;
        if (_tickCount % 10 == 0) { _blink = !_blink; }
        if (_tickCount % 4 == 0) { WatchUi.requestUpdate(); }   // ~5 fps redraw
    }

    // ---- 25 Hz batch arrival: write both streams to the FIT -------------------------

    function onAccel(sensorData as Sensor.SensorData) as Void {
        if (_state != ST_RUN) { return; }
        var accel = sensorData.accelerometerData;
        if (accel == null) { return; }

        var xs = accel.x;
        var ys = accel.y;
        var zs = accel.z;
        var n = 0;
        if (ys != null) { n = ys.size(); }
        if (n > BATCH_LEN) { n = BATCH_LEN; }

        _batchSeq += 1;

        try {
            if (_fBatchSeq != null) { _fBatchSeq.setData(_batchSeq % 65536); }
            if (_fBatchN != null) { _fBatchN.setData(n); }
            if (_fPhase != null) { _fPhase.setData(_phase); }
            if (_fAy != null) { _fAy.setData(padArr(ys, n)); }
            if (_fAx != null) { _fAx.setData(padArr(xs, (xs != null) ? n : 0)); }
            if (_fAz != null) { _fAz.setData(padArr(zs, (zs != null) ? n : 0)); }

            // Flush the poll ring gathered since the previous batch.
            var pn = _pollRing.size();
            if (pn > BATCH_LEN) { pn = BATCH_LEN; }
            if (_fPollY != null) { _fPollY.setData(padArr(_pollRing, pn)); }
            if (_fPollN != null) { _fPollN.setData(pn); }
            if (_fPollSeq != null) { _fPollSeq.setData(_pollSeq % 65536); }
            _pollRing = [];
        } catch (ex) {}
    }

    // Fixed-length array for a :count field: first n from src, PAD after.
    private function padArr(src, n as Number) as Array {
        var out = new [BATCH_LEN];
        for (var i = 0; i < BATCH_LEN; i++) {
            if (src != null && i < n) {
                out[i] = src[i];
            } else {
                out[i] = PAD;
            }
        }
        return out;
    }

    // ---- Vibration -----------------------------------------------------------------

    private function buzzCue() as Void {
        if (Attention has :vibrate) { Attention.vibrate([new Attention.VibeProfile(60, 150)]); }
    }
    private function buzzGo() as Void {
        if (Attention has :vibrate) { Attention.vibrate([new Attention.VibeProfile(100, 500)]); }
    }
    private function buzzDone() as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(80, 150),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(80, 150)
            ]);
        }
    }

    // ---- Drawing -------------------------------------------------------------------

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var CC = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        if (_state == ST_SETUP) {
            drawSetup(dc, cx, h, CC);
        } else if (_state == ST_RUN) {
            drawRun(dc, cx, h, CC);
        } else if (_state == ST_DONE) {
            drawDone(dc, cx, h, CC);
        } else {
            drawError(dc, cx, h, CC);
        }
    }

    private function drawSetup(dc as Graphics.Dc, cx as Number, h as Number, CC as Number) as Void {
        var LC = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.drawText(8, 24, Graphics.FONT_SMALL, "QC CAPTURE v2", LC);

        var y0 = subBottom(dc) + 12;
        drawField(dc, y0,      "STYLE", _styles[_styleIdx] as String, _field == 0);
        drawField(dc, y0 + 20, "WRIST", _wrists[_wristIdx] as String, _field == 1);
        drawField(dc, y0 + 40, "REPS",  _reps.toString(),             _field == 2);

        dc.drawText(cx, h - 46, Graphics.FONT_XTINY, "GPS start   MENU field", CC);
        dc.drawText(cx, h - 28, Graphics.FONT_XTINY, "UP/DOWN change value", CC);
        drawSeqNum(dc);
    }

    private function drawField(dc as Graphics.Dc, y as Number, name as String, val as String, active as Boolean) as Void {
        var LC = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var marker = active ? ">" : " ";
        dc.drawText(10, y, Graphics.FONT_XTINY, marker + name, LC);
        dc.drawText(92, y, Graphics.FONT_XTINY, val, LC);
    }

    private function drawRun(dc as Graphics.Dc, cx as Number, h as Number, CC as Number) as Void {
        var name = _phaseNames[_phase] as String;
        var secs = _phaseSecs[_phase] as Number;
        var t = subBottom(dc);

        dc.drawText(cx, t + 16, Graphics.FONT_SMALL, name, CC);

        if (secs > 0) {
            var el = System.getTimer() - _phaseStartMs;
            var remain = secs - (el / 1000);
            if (remain < 1) { remain = 1; }
            dc.drawText(cx, t + 52, Graphics.FONT_NUMBER_MEDIUM, remain.toString(), CC);
        } else {
            var el = (System.getTimer() - _phaseStartMs) / 1000;
            dc.drawText(cx, t + 52, Graphics.FONT_NUMBER_MEDIUM, _reps.toString(), CC);
            dc.drawText(cx, h - 52, Graphics.FONT_XTINY, el.toString() + "s   GPS = done", CC);
        }

        dc.drawText(cx, h - 34, Graphics.FONT_XTINY,
            "b" + _batchSeq.toString() + "  y " + _lastPollY.toString(), CC);
        dc.drawText(cx, h - 16, Graphics.FONT_XTINY, "SET = abort", CC);
        drawRecDot(dc);
    }

    private function drawDone(dc as Graphics.Dc, cx as Number, h as Number, CC as Number) as Void {
        var t = subBottom(dc);
        dc.drawText(cx, t + 14, Graphics.FONT_SMALL, _doneSaved ? "SAVED" : "SAVE FAIL", CC);
        dc.drawText(cx, t + 38, Graphics.FONT_XTINY, _doneStyle + "  " + _doneWrist, CC);
        dc.drawText(cx, t + 56, Graphics.FONT_XTINY, "reps: " + _doneReps.toString(), CC);
        dc.drawText(cx, h - 40, Graphics.FONT_XTINY, "logged as #" + _sessionNum.toString(), CC);
        dc.drawText(cx, h - 20, Graphics.FONT_XTINY, "GPS new   BACK exit", CC);
        drawSeqNum(dc);
    }

    private function drawError(dc as Graphics.Dc, cx as Number, h as Number, CC as Number) as Void {
        var t = subBottom(dc);
        dc.drawText(cx, t + 20, Graphics.FONT_SMALL, "CAPTURE", CC);
        dc.drawText(cx, t + 44, Graphics.FONT_SMALL, "FAILED", CC);
        dc.drawText(cx, h - 36, Graphics.FONT_XTINY, _errText, CC);
        dc.drawText(cx, h - 16, Graphics.FONT_XTINY, "GPS back", CC);
    }

    private function drawRecDot(dc as Graphics.Dc) as Void {
        var sub = WatchUi.getSubscreen();
        if (sub == null) { return; }
        var scx = sub.x + (sub.width / 2);
        var scy = sub.y + (sub.height / 2);
        dc.drawCircle(scx, scy, 11);
        if (_blink) { dc.fillCircle(scx, scy, 7); }
    }

    private function drawSeqNum(dc as Graphics.Dc) as Void {
        var sub = WatchUi.getSubscreen();
        if (sub == null) { return; }
        var scx = sub.x + (sub.width / 2);
        var scy = sub.y + (sub.height / 2);
        dc.drawText(scx, scy, Graphics.FONT_TINY, "#" + _sessionNum.toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function subBottom(dc as Graphics.Dc) as Number {
        var sub = WatchUi.getSubscreen();
        if (sub == null) { return 30; }
        return sub.y + sub.height;
    }
}