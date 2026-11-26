#!/usr/bin/env python3
"""Sanity-check the generated audio against the contract.

    python3 tools/audio/verify_audio.py            # table + problems
    python3 tools/audio/verify_audio.py --spectro /abs/out/dir   # also PNG spectrograms (ffmpeg)

Checks per file: exists, 44.1 kHz / 16-bit / channel count, peak & RMS dBFS,
DC offset, clipped samples, leading/trailing sample level for one-shots
(click risk), and for loops the 'smpl' chunk plus a seam test: the jump from
the last sample back to the first must look like any ordinary neighbouring
sample step (ratio to the 99.9th percentile of |x[n+1]-x[n]|).
"""
import math
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import read_wav, db  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio")

EXPECTED = (
    ["engine_main_loop", "engine_boost_loop", "rcs_hiss_loop"]
    + ["rcs_puff_%d" % i for i in (1, 2, 3)]
    + ["engine_ignite", "boost_kick", "low_hull_alarm"]
    + ["impact_light_%d" % i for i in (1, 2, 3, 4)]
    + ["impact_medium_%d" % i for i in (1, 2, 3)]
    + ["impact_heavy_%d" % i for i in (1, 2, 3)]
    + ["scrape_loop"] + ["container_clunk_%d" % i for i in (1, 2, 3)]
    + ["explosion_ship", "debris_rattle", "gate_pass", "race_countdown", "race_go",
       "race_finish", "dock_clamp", "dock_chime", "boundary_warning", "ui_click",
       "ambient_space_drone", "station_hum_loop", "traffic_engine_loop", "beacon_ping",
       "door_servo"]
    # on foot
    + ["step_suit_%d" % i for i in (1, 2, 3, 4)] + ["step_deck_%d" % i for i in (1, 2, 3, 4)]
    + ["hatch_open", "hatch_close", "airlock_cycle", "door_slide", "switch_click", "light_on",
       "light_buzz_loop", "room_tone_loop", "vending_dispense", "console_beep", "holo_on"]
)
STEREO = {"ambient_space_drone"}


def main(argv):
    problems = []
    total = 0
    print("%-22s %3s %6s %7s %7s %8s %6s %s" % ("file", "ch", "dur", "peak", "rms", "dc", "clip", "loop/seam"))
    for name in EXPECTED:
        path = os.path.join(AUDIO, name + ".wav")
        if not os.path.exists(path):
            problems.append("%s: MISSING" % name)
            continue
        total += os.path.getsize(path)
        chans, sr, loop = read_wav(path)
        is_loop = name.endswith("_loop") or name in ("low_hull_alarm", "boundary_warning",
                                                     "ambient_space_drone")
        want_ch = 2 if name in STEREO else 1
        if sr != 44100:
            problems.append("%s: sample rate %d" % (name, sr))
        if len(chans) != want_ch:
            problems.append("%s: %d channels, want %d" % (name, len(chans), want_ch))
        pk = max(max(abs(v) for v in c) for c in chans)
        rm = max(math.sqrt(sum(v * v for v in c) / len(c)) for c in chans)
        dc = max(abs(sum(c) / len(c)) for c in chans)
        clip = sum(1 for c in chans for v in c if abs(v) >= 0.9999)
        n = len(chans[0])
        info = ""
        if is_loop:
            if loop is None:
                problems.append("%s: loop without smpl chunk" % name)
                info = "NO SMPL"
            else:
                worst = 0.0
                for c in chans:
                    diffs = sorted(abs(c[i + 1] - c[i]) for i in range(len(c) - 1))
                    p999 = diffs[int(len(diffs) * 0.999)] or 1e-9
                    worst = max(worst, abs(c[0] - c[-1]) / p999)
                info = "smpl[%d..%d] seam=%.2f" % (loop[1], loop[2], worst)
                if loop[1] != 0 or loop[2] != n:  # exclusive end, as Godot reads it
                    problems.append("%s: smpl range %s vs %d samples" % (name, loop, n))
                if worst > 1.0:
                    problems.append("%s: seam jump %.2fx the 99.9th pct step" % (name, worst))
        else:
            edge = max(max(abs(c[0]), abs(c[-1])) for c in chans)
            info = "edges=%.4f" % edge
            if edge > 0.01:
                problems.append("%s: non-silent edge %.4f (click risk)" % (name, edge))
        target = -3.0 if is_loop else -1.0
        if abs(db(pk) - target) > 0.3:
            problems.append("%s: peak %.2f dBFS, want %.1f" % (name, db(pk), target))
        if dc > 0.002:
            problems.append("%s: DC offset %.4f" % (name, dc))
        if clip:
            problems.append("%s: %d clipped samples" % (name, clip))
        print("%-22s %3d %6.2f %7.2f %7.2f %8.5f %6d %s" % (name, len(chans), n / sr, db(pk), db(rm), dc, clip, info))
    print("total size: %.2f MB" % (total / 1e6))
    if "--spectro" in argv:
        out = argv[argv.index("--spectro") + 1]
        os.makedirs(out, exist_ok=True)
        for name in EXPECTED:
            src = os.path.join(AUDIO, name + ".wav")
            dst = os.path.join(out, name + ".png")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-lavfi",
                            "showspectrumpic=s=800x300:legend=1:scale=log:fscale=log:gain=2",
                            dst], check=False)
        print("spectrograms ->", out)
    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  -", p)
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
