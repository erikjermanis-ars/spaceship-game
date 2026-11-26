#!/usr/bin/env python3
"""Procedural sound design for Meridian Approach - every sound from scratch.

    Regenerate everything (from the project root):
        python3 tools/audio/gen_audio.py
    Only some sounds:
        python3 tools/audio/gen_audio.py impact_heavy engine_main_loop
    Then refresh Godot's import cache:
        /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
    Check levels / loop seams:
        python3 tools/audio/verify_audio.py

Output: res://assets/audio/*.wav - 44.1 kHz 16-bit PCM, mono except the
ambient bed (stereo). Loops carry a RIFF 'smpl' chunk so Godot imports them
looping, and are seamless by construction (see dsp.py docstring).

Design conceit: "you are in the cockpit". Space is silent, but the hull
transmits structure-borne sound, so engines are felt as deep rumble and
collisions are heard as the ship's own metal ringing. UI/race cues are clean
FM/additive bells tuned to D major so they sit inside the ambient music bed
(Dmaj9 - Gmaj9 - Bm9 - Asus2).

Pure stdlib Python (no numpy); recipes run in parallel worker processes.
Everything is seeded, so the output is reproducible bit-for-bit.
"""
import math
import os
import random
import sys
import time
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import *  # noqa: E402,F401,F403

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio")

# D major frequencies used by musical cues (equal temperament, A4 = 440).
D3, Fs3, A3 = 146.83, 185.00, 220.00
D4, Fs4, A4 = 293.66, 369.99, 440.00
D5, E5, Fs5, A5, B5 = 587.33, 659.26, 739.99, 880.00, 987.77
D6, E6, Fs6, A6, B6 = 1174.66, 1318.51, 1479.98, 1760.00, 1975.53
D7, E7 = 2349.32, 2637.02


# ================================================================ helpers ==
def norm(x, p=1.0):
    """Scale a layer to a given peak (layers are balanced by peak or RMS)."""
    pk = peak(x)
    return [v * p / pk for v in x] if pk > 0 else x


def pnoise(P, reps, rng):
    """White noise that repeats every P samples (for seamless loops)."""
    return white(P, rng) * reps


def finish_oneshot(x, fade_in_s=0.002, fade_out_s=0.03, hp=20.0, peak_db=-1.0):
    """DC/rumble-safe high-pass, click-free edges, peak normalise to ~-1 dBFS."""
    x = biquad(x, "hp", hp, 0.7071)
    if fade_in_s > 0:
        fade_in(x, fade_in_s)
    fade_out(x, fade_out_s)
    return at_peak(x, peak_db)


def finish_loop(x, P, peak_db=-3.0):
    """Keep the steady-state last period, remove DC, normalise to ~-3 dBFS."""
    x = remove_dc(last(x, P))
    return at_peak(x, peak_db)


def wet_mix(x, t60, size, wet, damp_hz=5500.0, predelay=0.012):
    """Add a mono reverb tail in place (same length as input)."""
    w = reverb_mono(x, t60=t60, size=size, damp_hz=damp_hz, predelay=predelay)
    return [a + wet * b for a, b in zip(x, w)]


def periodic_reverb(x, P, t60, size, wet, damp_hz=5000.0):
    """Reverb for a loop: run it over enough repeats that the tail from the
    previous cycle is present, then keep the steady-state last period."""
    reps = max(2, int(math.ceil(t60 * 1.6 * SR / P)) + 1)
    xx = last(x, P) * reps
    w = reverb_mono(xx, t60=t60, size=size, damp_hz=damp_hz)
    return [a + wet * b for a, b in zip(xx, w)]


def glide(n, f0, f1, glide_s, power=0.5):
    """Frequency list: exponential glide f0->f1 over glide_s, then hold f1."""
    g = min(n, max(2, ns(glide_s)))
    return sweep(g, f0, f1, "exp", power) + [f1] * (n - g)


def thump(n, f0, f1, glide_s, t60, rng, attack=0.002, drive=1.6):
    """Sub-bass body thump: pitch-dropping sine with a quick attack."""
    x = mul(osc_var(glide(n, f0, f1, glide_s), phase=0.0), env_perc(n, attack, t60))
    return saturate(x, drive)


def burst_events(n, rng, times, lengths, amps):
    """Scatter tiny exponentially decaying noise grains (crackle/crunch)."""
    out = zeros(n)
    for t, ln, a in zip(times, lengths, amps):
        m = max(4, ns(ln))
        k = LN1000 / m
        s0 = ns(t)
        r = rng.random
        for j in range(min(m, n - s0)):
            out[s0 + j] += a * (2.0 * r() - 1.0) * math.exp(-k * j)
    return out


def tinkle(rng, f0, t60, ratios=None, hard=12000.0):
    """One small metallic tinkle (debris / rattle grain)."""
    n = ns(t60 * 1.8 + 0.01)
    parts = metal_modes(rng, f0, ratios or BAR[:3] + [1.52, 2.1], t60, amp_tilt=0.5,
                        decay_tilt=0.4, hardness_hz=hard, split=0.3)
    x = decaying_sines(n, parts)
    add_into(x, noise_burst(n, rng, 0.0008, kind="hp", f=4000), 0.15 * peak(x))
    return x


def bell(n, f, t60, rng, bright=1.0, attack=0.0015):
    """Clean additive/FM bell: mostly harmonic body with a little inharmonic
    shimmer and an FM 'ting' on the attack."""
    parts = [(f, 1.0, t60, 0.0), (f * 2.0, 0.30, t60 * 0.55, rng.uniform(0, TAU)),
             (f * 3.0, 0.09, t60 * 0.35, rng.uniform(0, TAU)),
             (f * 2.76, 0.05 * bright, t60 * 0.30, rng.uniform(0, TAU)),
             (f * 4.16, 0.07 * bright, t60 * 0.22, rng.uniform(0, TAU)),
             (f * 5.43, 0.04 * bright, t60 * 0.14, rng.uniform(0, TAU)),
             (f * 0.5, 0.12, t60 * 0.8, 0.0)]
    x = decaying_sines(n, parts)
    k = 1.0 / (0.05 * SR)
    idx = [1.6 * math.exp(-i * k) for i in range(n)]
    ting = mul(fm_sine(n, f, f * 3.5, idx), env_perc(n, attack, t60 * 0.25))
    add_into(x, ting, 0.22 * bright)
    fade_in(x, attack)
    return x


def soft_mallet(n, f, t60, rng, attack=0.004):
    """Mellow marimba-ish voice (tuned bar: 1, ~3.9, ~9.2 partials)."""
    parts = [(f, 1.0, t60, 0.0), (f * 3.93, 0.16, t60 * 0.25, rng.uniform(0, TAU)),
             (f * 2.0, 0.07, t60 * 0.5, rng.uniform(0, TAU)), (f * 9.2, 0.025, 0.06, 0.0),
             (f * 0.5, 0.05, t60 * 0.6, 0.0)]
    x = decaying_sines(n, parts)
    fade_in(x, attack)
    return x


def tone_env(n, attack, sustain_end, release_end, sustain=0.85):
    return env_points(n, [(0.0, 0.0), (attack, 1.0), (sustain_end, sustain), (release_end, 0.0)])


# ================================================================ engine ===
def engine_main_loop(rng):
    """Deep warm rumble: detuned low harmonics with slow beating + brown-noise
    body + combustion throb + faint turbine whine. Tonally neutral enough to
    be pitch-shifted by throttle."""
    P = ns(3.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    core = zeros(N)
    # pairs 1/3 Hz apart -> one slow beat per loop; 27.67 Hz sub-octave adds weight
    for f, a in [(55.0, 1.0), (55.333, 0.75), (110.0, 0.55), (110.667, 0.4), (82.667, 0.22),
                 (165.0, 0.25), (220.333, 0.12), (27.667, 0.35), (330.0, 0.05)]:
        add_into(core, sine(N, q(f), rng.uniform(0, TAU)), a)
    breathe = lfo(N, 1, P)
    core = saturate(norm([c * (1.0 + 0.12 * b) for c, b in zip(core, breathe)]), 1.8)
    core = at_rms(core, -12)

    rumble = biquad(onepole_lp(pnoise(P, 2, rng), 70.0), "lp", 320, 0.6)
    rumble = biquad(rumble, "hp", 22, 0.7)
    sway = smooth_random(N, 3.0, rng, P, 0.75, 1.15)
    rumble = at_rms(mul(rumble, sway), -13)

    throb_src = biquad(pnoise(P, 2, rng), "bp", 320, 0.8)
    am = lfo(N, 83, P)  # 27.67 Hz combustion throb (integer cycles per loop)
    throb = at_rms([v * (0.7 + 0.3 * (0.5 + 0.5 * a)) for v, a in zip(throb_src, am)], -21)

    whine = fm_sine(N, q(1180), q(3.0), 2.0, rng.uniform(0, TAU))
    add_into(whine, fm_sine(N, q(2360), q(3.0), 4.0, rng.uniform(0, TAU)), 0.35)
    whine = at_rms(mul(whine, smooth_random(N, 2.0, rng, P, 0.6, 1.0)), -31)

    air = at_rms(biquad(pnoise(P, 2, rng), "bp", 2600, 0.6), -37)

    mix = [a + b + c + d + e for a, b, c, d, e in zip(core, rumble, throb, whine, air)]
    mix = saturate(biquad(mix, "lp", 7000, 0.7), 1.2)
    return [finish_loop(mix, P)], True


def engine_boost_loop(rng):
    """Afterburner: ragged broadband roar, low rumble, crackle grains and a
    bright fizzing top, driven hard into saturation."""
    P = ns(3.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    roar = biquad(biquad(pnoise(P, 2, rng), "lp", 3200, 0.6), "hp", 90, 0.7)
    roar = at_rms(mul(roar, smooth_random(N, 38.0, rng, P, 0.5, 1.0)), -14)

    low = at_rms(biquad(onepole_lp(pnoise(P, 2, rng), 90.0), "lp", 260, 0.7), -14)

    core = zeros(N)
    for f, a in [(55.0, 1.0), (55.667, 0.7), (110.333, 0.5), (41.333, 0.5), (82.667, 0.3)]:
        add_into(core, sine(N, q(f), rng.uniform(0, TAU)), a)
    core = at_rms(saturate(norm(core), 2.2), -17)

    count = 3 * 75
    times = [rng.random() * 3.0 for _ in range(count)]
    crack = burst_events(P + ns(0.01), rng, times, [rng.uniform(0.0006, 0.004) for _ in times],
                         [rng.random() ** 2 for _ in times])
    crack = at_rms(biquad(fold(crack, P) * 2, "hp", 1400, 0.7), -21)

    top = biquad(pnoise(P, 2, rng), "bp", 6500, 0.8)
    top = at_rms(mul(top, smooth_random(N, 60.0, rng, P, 0.35, 1.0)), -27)

    mix = [a + b + c + d + e for a, b, c, d, e in zip(roar, low, core, crack, top)]
    mix = saturate(norm(mix), 2.0)
    return [finish_loop(mix, P)], True


def rcs_hiss_loop(rng):
    """Cold-gas jet: band-limited hiss (~2-7 kHz) with valve flutter, a soft
    low whoosh and a barely-there nozzle whistle."""
    P = ns(2.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    flutter = [1.0 + 0.13 * a + 0.06 * b
               for a, b in zip(smooth_random(N, 18.0, rng, P), lfo(N, 7, P))]
    hiss = biquad(biquad(pnoise(P, 2, rng), "hp", 1800, 0.7), "lp", 7500, 0.7)
    hiss = at_rms(mul(biquad(hiss, "peak", 3800, 1.0, 5.0), flutter), -14)
    low = at_rms(mul(biquad(pnoise(P, 2, rng), "bp", 700, 0.8), flutter), -24)
    whistle = mul(fm_sine(N, q(4620), q(2.5), 3.0), smooth_random(N, 3.0, rng, P, 0.2, 1.0))
    whistle = at_rms(whistle, -36)
    mix = [a + b + c for a, b, c in zip(hiss, low, whistle)]
    return [finish_loop(mix, P)], True


def rcs_puff(rng, dur, fc0, fc1, decay, click_f, close_click):
    """Valve 'pfft': solenoid click, then a short gas burst whose band-pass
    sweeps down as pressure drops."""
    n = ns(dur)
    x = zeros(n)
    gas = mul(white(n, rng), env_perc(n, 0.002, decay, delay=0.0015))
    body = biquad_tv(gas, "bp", sweep(n, fc0, fc1, "exp", 0.6), 0.9)
    add_into(body, biquad(gas, "lp", 1400, 0.7), 0.35)
    add_into(x, norm(body))
    click = decaying_sines(ns(0.03), [(click_f, 1.0, 0.006, 0.0), (click_f * 1.73, 0.5, 0.004, 1.0),
                                      (950.0, 0.6, 0.014, 0.0)])
    add_into(x, norm(click), 0.32)
    if close_click:
        c2 = decaying_sines(ns(0.02), [(click_f * 0.86, 1.0, 0.005, 0.0), (820.0, 0.5, 0.01, 0.0)])
        add_into(x, norm(c2), 0.18, n - ns(0.035))
    x = biquad(x, "hp", 300, 0.7)
    return [finish_oneshot(x, fade_in_s=0.0003, fade_out_s=0.012)], False


def engine_ignite(rng):
    """Igniter sparks -> low thump -> rising whoosh that hands over to the loop."""
    n = ns(0.75)
    x = zeros(n)
    for t, a in [(0.0, 0.5), (0.032, 0.35), (0.07, 0.45)]:
        m = ns(0.03)
        spark = noise_burst(m, rng, 0.0015, kind="hp", f=3000)
        decaying_sines(m, [(3200 * rng.uniform(0.9, 1.1), 0.5 * peak(spark), 0.01, 0.0)], spark)
        add_into(x, norm(spark), a, ns(t))
    m = n - ns(0.07)
    add_into(x, norm(thump(m, 95, 38, 0.18, 0.35, rng)), 1.0, ns(0.07))
    add_into(x, norm(noise_burst(m, rng, 0.03, kind="lp", f=400)), 0.4, ns(0.07))
    w = white(m, rng)
    whoosh = biquad_tv(w, "bp", sweep(m, 250, 2400, "exp", 1.3), 1.1)
    whoosh = mul(whoosh, env_points(m, [(0, 0), (0.38, 1.0), (0.55, 0.45), (m / SR, 0.0)], 1.0))
    add_into(x, norm(whoosh), 0.5, ns(0.07))
    rum = mul(onepole_lp(white(m, rng), 80), env_points(m, [(0, 0), (0.4, 1.0), (m / SR, 0.0)]))
    add_into(x, norm(rum), 0.45, ns(0.07))
    tone = mul(sine(m, 55.0), env_points(m, [(0, 0), (0.15, 0.0), (0.45, 1.0), (m / SR, 0.0)]))
    add_into(x, norm(tone), 0.3, ns(0.07))
    return [finish_oneshot(x, fade_in_s=0.0003, fade_out_s=0.08)], False


def boost_kick(rng):
    """Afterburner light-off: crack, sub drop and a flame burst whose low-pass
    closes as it fades."""
    n = ns(0.75)
    x = zeros(n)
    add_into(x, norm(noise_burst(n, rng, 0.004, kind="hp", f=2000)), 0.7)
    add_into(x, norm(thump(n, 130, 36, 0.3, 0.55, rng, drive=2.0)), 1.0)
    flame = biquad_tv(white(n, rng), "lp", sweep(n, 7500, 700, "exp", 0.5), 0.7)
    add_into(x, norm(mul(flame, env_perc(n, 0.004, 0.45))), 0.75)
    times = [0.35 * rng.random() ** 1.6 for _ in range(90)]
    crack = burst_events(n, rng, times, [rng.uniform(0.0005, 0.003) for _ in times],
                         [(1.0 - t / 0.35) * rng.random() for t in times])
    add_into(x, norm(biquad(crack, "hp", 1500, 0.7)), 0.35)
    x = saturate(norm(x), 1.6)
    return [finish_oneshot(x, fade_in_s=0.0003, fade_out_s=0.06, hp=25)], False


def low_hull_alarm(rng):
    """Klaxon pulse: square/saw horn tone sweeping up 330->440 Hz then holding,
    through a horn-like resonance. One pulse per 1 s loop."""
    P = ns(1.0)
    x = zeros(P)
    m = ns(0.46)
    fr = glide(m, 330, 440, 0.11, 0.7)
    tone = osc_var(fr, table=square_table(9))
    add_into(tone, osc_var(fr, table=saw_table(12)), 0.4)
    horn = scale(biquad(tone, "bp", 1100, 1.0), 0.6)
    add_into(horn, biquad(tone, "lp", 2600, 0.7), 0.7)
    horn = saturate(norm(horn), 1.4)
    # the saw+square mix is asymmetric, so tanh creates DC: strip it before gating
    horn = biquad(horn, "hp", 70, 0.7071)
    horn = mul(horn, env_points(m, [(0, 0), (0.008, 1.0), (0.40, 0.9), (0.46, 0.0)]))
    add_into(x, horn)
    x = periodic_reverb(x, P, 0.4, 0.6, 0.12)
    return [finish_loop(x, P)], True


# ============================================================== impacts ===
def impact_light(rng, v):
    """Light hull taps/clinks: short bright modal hits + contact transient."""
    n = ns(0.4 if v == 3 else 0.3)
    x = zeros(n)
    cfg = [  # f0, ratios, t60, hardness
        (760, PLATE[:9], 0.13, 3000),
        (1650, BAR[:4] + [1.31, 3.9], 0.28, 9000),
        (1100, PLATE[:12], 0.18, 6000),
        (2150, PLATE[:8], 0.45, 12000),
    ][v]
    f0, ratios, t60, hard = cfg
    hits = [(0.0, 1.0)] + ([(0.028, 0.6)] if v == 2 else [])
    for t, a in hits:
        parts = metal_modes(rng, f0 * rng.uniform(0.95, 1.05), ratios, t60, amp_tilt=0.6,
                            decay_tilt=0.5, hardness_hz=hard, split=0.5)
        hit = norm(decaying_sines(n, parts))
        add_into(hit, norm(noise_burst(n, rng, rng.uniform(0.002, 0.003), kind="hp", f=2500)), 0.4)
        body = mul(sine(n, rng.uniform(180, 260)), env_perc(n, 0.0005, 0.03))
        add_into(hit, body, 0.25)
        add_into(x, hit, a, ns(t))
    return [finish_oneshot(x, fade_in_s=0.0002, fade_out_s=0.03, hp=60)], False


def impact_medium(rng, v):
    """Solid clangs (~0.9 s): ringing plate modes, a neighbouring panel, a
    contact crack and a low body thump. v1 adds a loose-fitting rattle, v2 is
    a pipe-like structural member."""
    n = ns(1.0)
    x = zeros(n)
    f0 = [215, 300, 370][v]
    ratios = PLATE if v != 2 else TUBE + [1.6, 3.3]
    parts = metal_modes(rng, f0, ratios, 0.8, amp_tilt=0.55, decay_tilt=0.5,
                        hardness_hz=5000, split=0.45)
    add_into(x, norm(decaying_sines(n, parts)), 1.0)
    parts2 = metal_modes(rng, f0 * rng.uniform(1.7, 2.3), PLATE[:10], 0.35, hardness_hz=6000)
    add_into(x, norm(decaying_sines(n, parts2)), 0.4)
    add_into(x, norm(noise_burst(n, rng, 0.008, kind="lp", f=6000)), 0.6)
    add_into(x, norm(noise_burst(n, rng, 0.02, kind="bp", f=1800, q=0.6)), 0.25)
    add_into(x, norm(thump(ns(0.4), 110, 70, 0.08, 0.15, rng)), 0.6)
    if v == 1:
        for t in sorted(rng.uniform(0.05, 0.16) for _ in range(3)):
            add_into(x, norm(tinkle(rng, rng.uniform(2000, 3500), 0.06)), 0.15, ns(t))
    x = saturate(norm(x), 1.3)
    return [finish_oneshot(x, fade_in_s=0.0002, fade_out_s=0.08, hp=35)], False


def creak(n, rng, t0, t1, rate0, rate1, peak_t, modes):
    """Stick-slip creak: a jittered impulse train (rising rate) exciting a
    resonant bank - how real metal groans under stress."""
    imp = zeros(n)
    t = t0
    while t < t1:
        u = (t - t0) / (t1 - t0)
        a = (u / (peak_t)) if u < peak_t else max(0.0, 1.0 - (u - peak_t) / (1.0 - peak_t))
        i = ns(t)
        if i < n:
            imp[i] += a * rng.uniform(0.5, 1.0) * (1 if rng.random() < 0.5 else -1)
        rate = rate0 + (rate1 - rate0) * u
        t += (1.0 / rate) * rng.uniform(0.88, 1.12)
    return resonator_bank(imp, modes)


def heavy_hit(rng, n, f_low, f_mid, crunch_len):
    x = zeros(n)
    add_into(x, norm(thump(n, 75, 42, 0.28, 0.7, rng)), 1.0)
    hull = metal_modes(rng, f_low, PLATE, 1.7, amp_tilt=0.5, decay_tilt=0.45,
                       hardness_hz=3500, split=0.5)
    add_into(x, norm(decaying_sines(n, hull)), 0.85)
    mid = metal_modes(rng, f_mid, PLATE[:14], 0.7, hardness_hz=7000, split=0.4)
    add_into(x, norm(decaying_sines(n, mid)), 0.55)
    times = [crunch_len * rng.random() ** 1.8 for _ in range(int(700 * crunch_len))]
    crunch = burst_events(n, rng, times, [rng.uniform(0.0002, 0.0025) for _ in times],
                          [(1.0 - t / crunch_len) * rng.random() for t in times])
    crunch = biquad(biquad(crunch, "bp", 1600, 0.5), "hp", 300, 0.7)
    add_into(x, norm(saturate(norm(crunch), 3.0)), 0.7)
    add_into(x, norm(noise_burst(n, rng, 0.06, kind="lp", f=2500)), 0.5)
    return x


def impact_heavy(rng, v):
    """Big hull crunch (~2 s): sub thump, low hull modes, mid clang, crunchy
    grain burst, a stress creak tail and a few loose bits tinkling."""
    n = ns(1.9 + 0.1 * v)
    f_low, f_mid, crunch_len = [(70, 290, 0.18), (84, 330, 0.14), (61, 245, 0.26)][v]
    x = heavy_hit(rng, n, f_low, f_mid, crunch_len)
    if v == 1:  # double crunch: the hull buckles a second time
        second = heavy_hit(rng, n - ns(0.13), f_low * 1.08, f_mid * 0.93, 0.1)
        add_into(x, norm(second), 0.55 * peak(x), ns(0.13))
    modes = [(340 * rng.uniform(0.9, 1.1), 8, 1.0), (790 * rng.uniform(0.9, 1.1), 10, 0.7),
             (1260 * rng.uniform(0.9, 1.1), 12, 0.5), (2080, 10, 0.35), (3150, 9, 0.2)]
    cr = creak(n, rng, 0.22, 1.7 + 0.1 * v, 28 + 6 * v, 50 + 8 * v, 0.3, modes)
    add_into(x, norm(cr), 0.28 * peak(x))
    for _ in range(4):
        t = rng.uniform(0.25, 1.3)
        add_into(x, norm(tinkle(rng, rng.uniform(1800, 5000), rng.uniform(0.05, 0.12))),
                 0.12 * peak(x), ns(t))
    x = saturate(norm(x), 1.8)
    return [finish_oneshot(x, fade_in_s=0.0002, fade_out_s=0.25, hp=28)], False


def scrape_loop(rng):
    """Metal-on-metal grinding: stick-slip impulse train (rate wanders 60-150 Hz)
    plus friction noise, amplitude jitter, a bank of high-Q metal resonances
    and a feedback comb for that screech."""
    P = ns(2.0)
    N = 2 * P
    exc = zeros(P)
    rate = smooth_random(P, 6.0, rng, P, 60.0, 150.0)
    t = 0
    while t < P:
        exc[t] += rng.uniform(0.2, 1.0) ** 1.5 * (1 if rng.random() < 0.5 else -1)
        t += max(1, int(SR / rate[t] * rng.uniform(0.6, 1.4)))
    exc = exc * 2
    fr = pnoise(P, 2, rng)
    jit = smooth_random(N, 22.0, rng, P, 0.35, 1.0)
    slow = smooth_random(N, 1.5, rng, P, 0.7, 1.0)
    src = [(e + f * 0.25) * j * s for e, f, j, s in zip(exc, fr, jit, slow)]
    metal = resonator_bank(src, [(520, 18, 1.0), (1130, 20, 0.8), (1790, 22, 0.7),
                                 (2480, 24, 0.6), (3370, 25, 0.45), (4520, 22, 0.35),
                                 (6100, 18, 0.25), (7900, 16, 0.15)])
    metal = at_rms(comb_fb(metal, 1.0 / 430.0, 0.5, damp_hz=5000), -16)
    grind = at_rms(biquad(src, "bp", 230, 1.5), -20)
    hiss = at_rms(biquad(mul(fr, jit), "hp", 3000, 0.7), -26)
    mix = saturate(norm([a + b + c for a, b, c in zip(metal, grind, hiss)]), 1.5)
    return [finish_loop(mix, P)], True


def container_clunk(rng, v):
    """Hollow cargo box knock: boomy cavity mode, soft-struck panel modes, a
    hint of metal, and a short comb for the box's internal reflection."""
    n = ns(0.75)
    f_box = [104, 122, 92][v]
    f_panel = [168, 205, 150][v]

    def knock(rng, scale_f=1.0):
        y = zeros(n)
        fb = f_box * scale_f
        boom = mul(osc_var(sweep(n, fb * 1.04, fb * 0.97, "exp", 0.3)), env_perc(n, 0.002, 0.38))
        add_into(y, norm(boom), 1.0)
        panel = metal_modes(rng, f_panel * scale_f, PLATE[:10], 0.42, amp_tilt=0.6,
                            decay_tilt=0.95, hardness_hz=1400, split=0.3)
        add_into(y, norm(decaying_sines(n, panel)), 0.7)
        top = metal_modes(rng, f_panel * 6.1, BAR[:3] + [1.7], 0.07, hardness_hz=8000)
        add_into(y, norm(decaying_sines(n, top)), 0.12)
        add_into(y, norm(noise_burst(n, rng, 0.005, kind="lp", f=2200)), 0.7)
        return comb_fb(y, 0.0047, 0.35, damp_hz=2500)

    x = knock(rng)
    if v == 1:  # bounce: a second, softer knock
        add_into(x, knock(rng, 1.02), 0.5, ns(0.105))
    if v == 2:  # loose cargo shifts inside a moment later
        m = ns(0.3)
        shift = noise_burst(m, rng, 0.05, attack_s=0.004, kind="lp", f=350)
        add_into(shift, mul(sine(m, 68), env_perc(m, 0.003, 0.15)), 0.6 * peak(shift))
        add_into(x, norm(shift), 0.45 * peak(x), ns(0.17))
        for t in (0.19, 0.215, 0.26):
            add_into(x, norm(tinkle(rng, rng.uniform(600, 1100), 0.05, PLATE[:5], 4000)),
                     0.1 * peak(x), ns(t))
    x = saturate(norm(x), 1.2)
    return [finish_oneshot(x, fade_in_s=0.0002, fade_out_s=0.06, hp=40)], False


def explosion_ship(rng):
    """Ship destruction (~3.4 s): crack, deep pitch-dropping boom, a burning
    body whose low-pass closes, rumbling tail, crackle, two secondary fuel-cell
    pops and scattered debris pings - glued with a short reverb."""
    n = ns(3.4)
    x = zeros(n)
    add_into(x, norm(noise_burst(n, rng, 0.012, kind="hp", f=1200)), 1.0)
    add_into(x, norm(noise_burst(n, rng, 0.004)), 0.8)
    boom = thump(n, 64, 26, 0.9, 1.5, rng, attack=0.004, drive=2.5)
    add_into(boom, thump(n, 128, 52, 0.9, 0.9, rng, attack=0.004), 0.3)
    add_into(x, norm(boom), 1.0)
    body = biquad_tv(white(n, rng), "lp", sweep(n, 3000, 160, "exp", 0.45), 0.8)
    body = mul(mul(body, env_perc(n, 0.006, 2.6)), smooth_random(n, 7.0, rng, None, 0.6, 1.0))
    add_into(x, norm(body), 0.9)
    rum = biquad(onepole_lp(white(n, rng), 55), "lp", 140, 0.7)
    rum = mul(rum, env_points(n, [(0, 0), (0.08, 0.6), (0.45, 1.0), (3.4, 0.0)], 1.0))
    rum = mul(rum, smooth_random(n, 4.0, rng, None, 0.6, 1.0))
    add_into(x, norm(rum), 0.8)
    times = [2.8 * rng.random() ** 2.2 for _ in range(500)]
    crack = burst_events(n, rng, times, [rng.uniform(0.0003, 0.002) for _ in times],
                         [math.exp(-t / 0.8) * rng.random() for t in times])
    add_into(x, norm(biquad(crack, "hp", 1800, 0.7)), 0.45)
    for t, a in [(0.52, 0.45), (1.15, 0.3)]:
        m = ns(0.8)
        pop = thump(m, 90, 40, 0.15, 0.3, rng)
        add_into(pop, norm(noise_burst(m, rng, 0.03, kind="lp", f=1500)), 0.6 * peak(pop))
        add_into(x, norm(pop), a, ns(t))
    for _ in range(7):
        add_into(x, norm(tinkle(rng, rng.uniform(1200, 4000), rng.uniform(0.08, 0.16))),
                 rng.uniform(0.1, 0.18), ns(rng.uniform(0.35, 2.6)))
    x = saturate(norm(x), 2.0)
    x = wet_mix(x, 2.0, 1.3, 0.25)
    return [finish_oneshot(x, fade_in_s=0.0002, fade_out_s=0.4, hp=22)], False


def debris_rattle(rng):
    """Small metallic tinkles scattered like bouncing debris (~1.2 s)."""
    n = ns(1.25)
    x = zeros(n)
    t = 0.0
    for k in range(18):
        a = (0.9 ** k) * rng.uniform(0.5, 1.0)
        if rng.random() < 0.3:
            g = tinkle(rng, rng.uniform(700, 1200), 0.04, PLATE[:5], 5000)
        else:
            g = tinkle(rng, rng.uniform(1900, 6500), rng.uniform(0.03, 0.11))
        add_into(x, norm(g), a, ns(t))
        t += rng.uniform(0.02, 0.06) * (1.0 + k * 0.12)
    x = biquad(x, "hp", 300, 0.7)
    x = wet_mix(x, 0.8, 0.7, 0.15)
    return [finish_oneshot(x, fade_in_s=0.0002, fade_out_s=0.05)], False


# ============================================================ race / UI ===
def gate_pass(rng):
    """Bright two-note chime, A5 -> D6 (rising fourth, inside D major)."""
    n = ns(1.4)
    x = zeros(n)
    add_into(x, bell(n, A5, 1.0, rng), 0.75)
    add_into(x, bell(n - ns(0.085), D6, 1.2, rng), 1.0, ns(0.085))
    x = wet_mix(x, 1.2, 0.9, 0.22)
    return [finish_oneshot(x, fade_in_s=0.0, fade_out_s=0.15)], False


def race_countdown(rng):
    """Clean 880 Hz beep."""
    n = ns(0.32)
    x = sine(n, 880.0)
    add_into(x, sine(n, 1760.0), 0.12)
    add_into(x, sine(n, 2640.0), 0.04)
    x = mul(x, tone_env(n, 0.004, 0.17, 0.30))
    x = wet_mix(x, 0.5, 0.6, 0.1)
    return [finish_oneshot(x, fade_in_s=0.0, fade_out_s=0.02)], False


def race_go(rng):
    """Higher, longer 1760 Hz beep with an 880 Hz body."""
    n = ns(0.9)
    x = sine(n, 1760.0)
    add_into(x, sine(n, 880.0), 0.25)
    add_into(x, sine(n, 3520.0), 0.06)
    x = mul(x, tone_env(n, 0.004, 0.5, 0.88, 0.8))
    x = wet_mix(x, 0.7, 0.7, 0.12)
    return [finish_oneshot(x, fade_in_s=0.0, fade_out_s=0.02)], False


def race_finish(rng):
    """Triumphant D-major arpeggio of bells, a sparkle run, and a warm
    detuned-saw pad chord underneath, with a reverb bloom."""
    n = ns(2.4)
    x = zeros(n)
    for t, f, a in [(0.0, D5, 0.7), (0.09, Fs5, 0.75), (0.18, A5, 0.8), (0.27, D6, 1.0)]:
        add_into(x, bell(n - ns(t), f, 1.1, rng), a, ns(t))
    for t, f in [(0.36, Fs6), (0.42, A6), (0.48, D7)]:
        add_into(x, bell(n - ns(t), f, 0.6, rng, bright=0.6), 0.35, ns(t))
    m = n - ns(0.27)
    saw = saw_table(16, 1.1)
    pad = zeros(m)
    for f in (D4, D5, Fs5, A5):
        for det in (0.9985, 1.0015):
            add_into(pad, wt_osc(m, f * det, saw, rng.uniform(0, TAU)), 0.25)
    pad = biquad(pad, "lp", 2600, 0.7)
    pad = mul(pad, env_points(m, [(0, 0), (0.05, 1.0), (0.9, 0.6), (2.1, 0.0)]))
    add_into(x, norm(pad), 0.45 * peak(x), ns(0.27))
    sub = mul(sine(m, D3), env_points(m, [(0, 0), (0.05, 1.0), (0.9, 0.6), (2.1, 0.0)]))
    add_into(x, sub, 0.25 * peak(x), ns(0.27))
    x = wet_mix(x, 1.8, 1.1, 0.3)
    return [finish_oneshot(x, fade_in_s=0.0, fade_out_s=0.2)], False


def dock_clamp(rng):
    """Docking clamp: latch tick, heavy clamp clunk, secondary lock clunk,
    then a hydraulic pressure-release hiss with a pump whirr underneath."""
    n = ns(1.45)
    x = zeros(n)
    add_into(x, norm(tinkle(rng, 2400, 0.05, BAR[:3], 9000)), 0.3)
    m = n - ns(0.07)
    main = norm(thump(m, 80, 48, 0.12, 0.35, rng))
    add_into(main, norm(decaying_sines(m, metal_modes(rng, 128, PLATE, 0.55, decay_tilt=0.8,
                                                         hardness_hz=2500))), 0.8)
    add_into(main, norm(noise_burst(m, rng, 0.012, kind="lp", f=1800)), 0.6)
    add_into(x, main, 1.0, ns(0.07))
    m2 = n - ns(0.30)
    lock = norm(thump(m2, 70, 50, 0.08, 0.2, rng))
    add_into(lock, norm(decaying_sines(m2, metal_modes(rng, 190, PLATE[:12], 0.3,
                                                         hardness_hz=4000))), 1.1)
    add_into(lock, norm(noise_burst(m2, rng, 0.006, kind="lp", f=2500)), 0.8)
    add_into(x, norm(lock), 0.5, ns(0.30))
    m3 = n - ns(0.36)
    hiss = biquad_tv(white(m3, rng), "bp", sweep(m3, 4600, 2600, "exp", 0.5), 0.8)
    hiss = biquad(mul(hiss, env_perc(m3, 0.012, 0.85)), "hp", 1500, 0.7)
    add_into(x, norm(hiss), 0.5, ns(0.36))
    m4 = ns(0.64)
    pump = sine(m4, 46.0)
    add_into(pump, sine(m4, 92.0), 0.5)
    pump = mul(pump, [0.6 + 0.4 * s for s in sine(m4, 23.0)])
    pump = mul(pump, env_points(m4, [(0, 0), (0.05, 1.0), (0.5, 0.8), (0.64, 0.0)]))
    add_into(x, norm(biquad(pump, "lp", 300, 0.7)), 0.25, ns(0.36))
    x = saturate(norm(x), 1.3)
    return [finish_oneshot(x, fade_in_s=0.0002, fade_out_s=0.08, hp=30)], False


def dock_chime(rng):
    """Soft mallet confirmation: F#5 then a D6/A5 dyad (warm, unhurried)."""
    n = ns(1.5)
    x = zeros(n)
    add_into(x, soft_mallet(n, Fs5, 1.0, rng), 0.8)
    t = 0.14
    add_into(x, soft_mallet(n - ns(t), D6, 1.2, rng), 1.0, ns(t))
    add_into(x, soft_mallet(n - ns(t), A5, 1.0, rng), 0.4, ns(t))
    x = biquad(x, "lp", 6000, 0.7)
    x = wet_mix(x, 1.3, 1.0, 0.25)
    return [finish_oneshot(x, fade_in_s=0.0, fade_out_s=0.15)], False


def boundary_warning(rng):
    """Two-tone alert G5 -> D5 (a falling 'turn back' fourth), soft-edged so
    it stays urgent without being grating. 1 s loop."""
    P = ns(1.0)
    x = zeros(P)

    def tone(f, dur):
        m = ns(dur)
        y = sine(m, f)
        add_into(y, sine(m, 2 * f), 0.18)
        add_into(y, sine(m, 3 * f), 0.08)
        return mul(y, tone_env(m, 0.012, dur - 0.05, dur))

    add_into(x, tone(784.0, 0.17), 1.0, ns(0.02))
    add_into(x, tone(587.0, 0.22), 1.0, ns(0.24))
    x = biquad(x, "lp", 4500, 0.7)
    x = periodic_reverb(x, P, 0.5, 0.6, 0.12)
    return [finish_loop(x, P)], True


def ui_click(rng):
    """Subtle soft tick: tiny high ping + low body + air transient."""
    n = ns(0.06)
    x = decaying_sines(n, [(2350, 1.0, 0.018, 0.0), (3900, 0.4, 0.01, 0.3), (5200, 0.2, 0.006, 0.0)])
    decaying_sines(n, [(420, 0.5, 0.02, 0.0)], x)
    add_into(x, norm(noise_burst(n, rng, 0.0012, kind="hp", f=3500)), 0.5 * peak(x))
    return [finish_oneshot(x, fade_in_s=0.0002, fade_out_s=0.01, hp=80)], False


# ============================================================ ambience ===
def ambient_space_drone(rng):
    """30 s stereo music bed. Four slowly crossfading chords in D
    (Dmaj9 -> Gmaj9 -> Bm9 -> Asus2) voiced as detuned band-limited saw stacks
    spread across the stereo field with slowly orbiting pans, a breathing
    low-pass, a D1/D2 sub drone, pentatonic shimmer partials that twinkle in
    and out, a faint 'solar wind' noise bed, and a long FDN reverb. Every
    frequency/LFO completes whole cycles in 30 s, so it loops seamlessly."""
    P = ns(30.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    import array as _array
    padL = _array.array("d", bytes(8 * P))
    padR = _array.array("d", bytes(8 * P))
    chords = [
        [D3, A3, 277.18, 329.63, Fs4],          # Dmaj9  (D A C# E F#)
        [196.00, 246.94, D4, Fs4, A4],          # Gmaj9  (G B D F# A)
        [123.47, Fs3, A3, 277.18, D4],          # Bm9    (B F# A C# D)
        [110.00, 164.81, 246.94, 277.18, 329.63],  # Asus2 add6 (A E B C# E)
    ]
    seg = P // 4
    xf = ns(3.4)
    h = xf // 2
    table = saw_table(24, 1.25)
    size = len(table)
    floor = math.floor
    for k, notes in enumerate(chords):
        start = k * seg
        idx = []
        env = []
        for i in range(-h, seg + h):
            if i < h:
                e = 0.5 - 0.5 * math.cos(math.pi * (i + h) / xf)
            elif i > seg - h:
                e = 0.5 + 0.5 * math.cos(math.pi * (i - (seg - h)) / xf)
            else:
                e = 1.0
            idx.append((start + i) % P)
            env.append(e)
        for ni, f in enumerate(notes):
            amp = 0.9 if ni == 0 else (0.75 if ni < 4 else 0.6)
            for det, base_pan in ((-0.2, -0.75), (0.0, 0.05), (0.2333, 0.75)):
                fq = q(f + det)
                inc = fq / SR
                p0 = rng.random()
                pan_cyc = rng.choice((1, 2))
                pan_ph = rng.uniform(0, TAU)
                block = 512
                for b0 in range(0, len(idx), block):
                    ii = idx[b0]
                    pan = max(-1.0, min(1.0, base_pan + 0.25 * math.sin(TAU * pan_cyc * ii / P + pan_ph)))
                    gl, gr = pan_gains(pan)
                    gl *= amp
                    gr *= amp
                    for j in range(b0, min(len(idx), b0 + block)):
                        i = idx[j]
                        ph = p0 + inc * i
                        v = table[int((ph - floor(ph)) * size)] * env[j]
                        padL[i] += v * gl
                        padR[i] += v * gr
    padL = list(padL) * 2
    padR = list(padR) * 2
    cut = lambda i: 950.0 + 750.0 * (0.5 + 0.5 * math.sin(TAU * 2 * (i % P) / P - 1.2))
    padL = biquad(biquad_tv(padL, "lp", cut, 0.55, block=64), "lp", 3600, 0.6)
    padR = biquad(biquad_tv(padR, "lp", cut, 0.55, block=64), "lp", 3600, 0.6)
    padL = at_rms(padL, -20)
    padR = at_rms(padR, -20)

    # sub drone: D1 + D2, breathing 3x per loop
    sub = sine(N, q(36.71))
    add_into(sub, sine(N, q(73.42), 0.7), 0.45)
    sub = mul(sub, [0.8 + 0.2 * v for v in lfo(N, 3, P, 0.4)])
    sub = at_rms(sub, -24)

    # shimmer: D-major pentatonic partials twinkling in and out
    shL = zeros(N)
    shR = zeros(N)
    for f in (D6, E6, Fs6, A6, B6, D7, E7, 2959.96):
        s = sine(N, q(f), rng.uniform(0, TAU))
        tw = smooth_random(N, 0.35, rng, P, -0.6, 1.0)
        gl, gr = pan_gains(rng.uniform(-0.9, 0.9))
        for i in range(N):
            a = tw[i]
            if a > 0.0:
                v = s[i] * a * a * a
                shL[i] += v * gl
                shR[i] += v * gr
    rshine = max(rms(shL), rms(shR)) or 1.0
    g = undb(-31) / rshine
    shL = scale(shL, g)
    shR = scale(shR, g)

    # solar-wind air bed, decorrelated L/R
    swell = [0.6 + 0.4 * v for v in lfo(N, 2, P, 2.0)]
    # soft 'solar wind': band-passed then low-passed so it is a breath, not a hiss
    airL = biquad(biquad(pnoise(P, 2, rng), "bp", 900, 0.5), "lp", 2400, 0.6)
    airR = biquad(biquad(pnoise(P, 2, rng), "bp", 1100, 0.5), "lp", 2400, 0.6)
    airL = at_rms(mul(airL, swell), -38)
    airR = at_rms(mul(airR, swell), -38)

    revL = [a + b + c for a, b, c in zip(padL, shL, airL)]
    revR = [a + b + c for a, b, c in zip(padR, shR, airR)]
    wL, wR = reverb(revL, revR, t60=6.0, size=1.8, damp_hz=4500, predelay=0.03)
    del revL, revR
    outL = [0.75 * p + 0.6 * s + a + 0.7 * w + d
            for p, s, a, w, d in zip(padL, shL, airL, wL, sub)]
    outR = [0.75 * p + 0.6 * s + a + 0.7 * w + d
            for p, s, a, w, d in zip(padR, shR, airR, wR, sub)]
    outL = remove_dc(last(outL, P))
    outR = remove_dc(last(outR, P))
    g = undb(-3.0) / max(peak(outL), peak(outR))
    return [scale(outL, g), scale(outR, g)], True


def station_hum_loop(rng):
    """Big station machinery: 50/100 Hz hum with beating, transformer buzz,
    air handling with fan-blade flutter, and a distant low rumble."""
    P = ns(4.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    hum = zeros(N)
    for f, a in [(50, 0.55), (100, 1.0), (100.5, 0.45), (150, 0.35), (200, 0.28), (250, 0.08),
                 (300, 0.14), (400, 0.06), (49.75, 0.2)]:
        add_into(hum, sine(N, q(f), rng.uniform(0, TAU)), a)
    hum = at_rms(mul(hum, [1.0 + 0.08 * v for v in lfo(N, 1, P)]), -15)
    buzz = biquad(saturate(sine(N, q(100.0)), 6.0), "bp", 900, 0.7)
    buzz = at_rms(mul(buzz, smooth_random(N, 0.8, rng, P, 0.4, 1.0)), -30)
    air_src = pnoise(P, 2, rng)
    air = biquad(air_src, "lp", 900, 0.7)
    add_into(air, biquad(air_src, "bp", 1400, 0.6), 0.4)
    flutter = [1.0 + 0.07 * a + 0.15 * b
               for a, b in zip(lfo(N, 53, P), smooth_random(N, 0.6, rng, P))]
    air = at_rms(mul(air, flutter), -17)
    rumble = at_rms(onepole_lp(pnoise(P, 2, rng), 45), -21)
    mix = [a + b + c + d for a, b, c, d in zip(hum, buzz, air, rumble)]
    return [finish_loop(mix, P)], True


def traffic_engine_loop(rng):
    """Small craft passing by: buzzy drone, turbine whine with vibrato, jet noise."""
    P = ns(2.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    tbl = saw_table(14, 1.3)
    drone = wt_osc(N, q(146.5), tbl, rng.uniform(0, TAU))
    add_into(drone, wt_osc(N, q(147.5), tbl, rng.uniform(0, TAU)), 0.7)
    drone = at_rms(biquad(drone, "lp", 1400, 0.8), -15)
    whine = fm_sine(N, q(1760), q(5), 1.2)
    add_into(whine, fm_sine(N, q(3520), q(5), 2.4), 0.3)
    whine = at_rms(whine, -22)
    turb = at_rms(mul(sine(N, q(2637.5)), smooth_random(N, 4.0, rng, P, 0.3, 1.0)), -32)
    jet = biquad(biquad(pnoise(P, 2, rng), "bp", 950, 0.7), "lp", 3200, 0.7)
    jet = at_rms(mul(jet, smooth_random(N, 9.0, rng, P, 0.8, 1.0)), -17)
    mix = saturate(norm([a + b + c + d for a, b, c, d in zip(drone, whine, turb, jet)]), 1.3)
    mix = biquad(mix, "lp", 7000, 0.7)
    return [finish_loop(mix, P)], True


def beacon_ping(rng):
    """Sonar-like navigation ping with a slight pitch fall, echoes and tail."""
    n = ns(1.6)
    fr = sweep(n, 1250, 1236, "exp", 0.4)
    x = mul(osc_var(fr), env_perc(n, 0.002, 0.75))
    add_into(x, mul(osc_var([f * 2.003 for f in fr]), env_perc(n, 0.002, 0.3)), 0.12)
    add_into(x, mul(sine(n, 625.0), env_perc(n, 0.004, 0.9)), 0.18)
    dry = list(x)
    echo = biquad(dry, "lp", 2500, 0.7)
    add_into(x, echo, 0.28, ns(0.27))
    add_into(x, echo, 0.10, ns(0.54))
    x = wet_mix(x, 1.4, 1.2, 0.35)
    return [finish_oneshot(x, fade_in_s=0.001, fade_out_s=0.2)], False


def door_servo(rng):
    """Heavy blast-door / crane servo: motor spins up, runs with gear whine and
    rattle, spins down, then a heavy clunk and a latch tick."""
    n = ns(1.65)
    run_end = ns(1.30)
    f_run = 118.0
    wob = smooth_random(run_end, 5.0, rng, None, -1.0, 1.0)
    fmot = []
    for i in range(run_end):
        t = i / SR
        if t < 0.2:
            f = 55.0 * (f_run / 55.0) ** ((t / 0.2) ** 0.7)
        elif t < 1.12:
            f = f_run * (1.0 + 0.015 * wob[i])
        else:
            f = f_run * (62.0 / f_run) ** ((t - 1.12) / 0.18)
        fmot.append(f)
    motor_raw = osc_var(fmot, table=saw_table(30, 1.0))
    motor = scale(biquad(motor_raw, "bp", 650, 1.0), 0.7)
    add_into(motor, biquad(motor_raw, "lp", 1800, 0.7), 0.5)
    motor = saturate(norm(motor), 1.5)
    gear = osc_var([f * 9.0 for f in fmot])
    add_into(motor, gear, 0.12)
    # gear-mesh rattle: an impulse every third motor revolution
    imp = zeros(run_end)
    ph = 0.0
    for i, f in enumerate(fmot):
        ph += f / 3.0 / SR
        if ph >= 1.0:
            ph -= 1.0
            imp[i] = rng.uniform(0.5, 1.0)
    rattle = norm(biquad(imp, "bp", 2300, 3.0))
    add_into(motor, rattle, 0.25)
    add_into(motor, norm(biquad(white(run_end, rng), "lp", 450, 0.7)), 0.35)
    motor = mul(motor, env_points(run_end, [(0, 0), (0.06, 0.8), (0.2, 1.0), (1.12, 1.0), (1.3, 0.0)]))
    x = zeros(n)
    add_into(x, norm(motor), 0.7)
    m = n - ns(1.29)
    clunk = norm(thump(m, 70, 42, 0.1, 0.3, rng))
    add_into(clunk, norm(decaying_sines(m, metal_modes(rng, 105, PLATE, 0.5, hardness_hz=2000))), 0.8)
    add_into(clunk, norm(noise_burst(m, rng, 0.01, kind="lp", f=1600)), 0.6)
    add_into(x, norm(clunk), 1.0, ns(1.29))
    add_into(x, norm(tinkle(rng, 2600, 0.04, BAR[:3], 9000)), 0.2, ns(1.37))
    x = saturate(norm(x), 1.3)
    return [finish_oneshot(x, fade_in_s=0.003, fade_out_s=0.1, hp=30)], False



# ================================================================ on foot ===
# Same conceit, now outside the cockpit. In vacuum you hear only what your
# suit carries: footsteps are muffled thuds through the mag-boots (low-passed,
# no air). Indoors the air is back: crisp heel-and-sole steps on deck plate,
# the hum of the room, doors and switches you can actually hear.

def step_suit(rng, v):
    """Mag-boot footstep heard from inside a suit: a soft low thud through
    the leg, the boot magnet's damped clack, a whisper of suit fabric."""
    n = ns(0.32)
    x = zeros(n)
    add_into(x, norm(thump(n, rng.uniform(105, 130), 62, 0.05, 0.09, rng, attack=0.003, drive=1.3)), 1.0)
    m = n - ns(0.012)
    clack = decaying_sines(m, metal_modes(rng, rng.uniform(380, 460), PLATE[:6], 0.05,
                                          hardness_hz=1400, split=0.2))
    clack = biquad(norm(clack), "lp", 1300, 0.7)
    add_into(x, clack, 0.35, ns(0.012))
    rustle = biquad(mul(white(n, rng), env_points(n, [(0, 0), (0.02, 1.0), (0.12, 0.25), (0.3, 0)])), "bp", 900, 0.8)
    add_into(x, norm(rustle), 0.12)
    x = biquad(x, "lp", 1800, 0.7)
    return [finish_oneshot(x, fade_in_s=0.001, fade_out_s=0.05, hp=35)], False


def step_deck(rng, v):
    """Indoor step on metal deck plate: heel tap, a short plate ring under the
    rubber sole, then the toe and a little scuff."""
    n = ns(0.36)
    x = zeros(n)
    heel = norm(noise_burst(n, rng, 0.006, kind="bp", f=rng.uniform(1700, 2400), q=0.9))
    add_into(heel, norm(thump(n, rng.uniform(150, 190), 95, 0.02, 0.05, rng, attack=0.0008, drive=1.2)), 0.8)
    ring = decaying_sines(n, metal_modes(rng, rng.uniform(520, 640), PLATE[:10], 0.11,
                                         hardness_hz=3500, split=0.4))
    add_into(heel, norm(ring), 0.22)
    add_into(x, heel, 1.0)
    toe_t = rng.uniform(0.055, 0.075)
    m = n - ns(toe_t)
    toe = norm(noise_burst(m, rng, 0.004, kind="bp", f=rng.uniform(2600, 3200), q=0.9))
    add_into(toe, norm(thump(m, 210, 130, 0.015, 0.03, rng, attack=0.0006, drive=1.1)), 0.4)
    add_into(x, toe, 0.45, ns(toe_t))
    scuff = biquad(mul(white(m, rng), env_perc(m, 0.004, 0.06)), "bp", 3800, 0.7)
    add_into(x, norm(scuff), 0.08, ns(toe_t))
    return [finish_oneshot(x, fade_in_s=0.0003, fade_out_s=0.05, hp=70)], False


def _servo(n, rng, f0, f1, run_s, level=1.0):
    """Small electric actuator: spin-up, run, spin-down (gear whine)."""
    run = ns(run_s)
    fr = []
    for i in range(run):
        t = i / SR
        k = min(1.0, t / 0.08) * min(1.0, (run_s - t) / 0.1)
        fr.append((f0 + (f1 - f0) * t / run_s) * (0.6 + 0.4 * max(0.0, k)))
    raw = osc_var(fr, table=saw_table(24, 1.0))
    y = scale(biquad(raw, "bp", 900, 1.2), 0.6)
    add_into(y, biquad(raw, "lp", 600, 0.7), 0.5)
    add_into(y, osc_var([f * 7.0 for f in fr]), 0.06)
    y = mul(y, env_points(run, [(0, 0), (0.04, 1.0), (run_s - 0.08, 1.0), (run_s, 0.0)]))
    out = zeros(n)
    add_into(out, norm(y), level)
    return out


def hatch_open(rng):
    """Ship boarding hatch: latch clunk, seal hiss, door servo, stairs servo,
    then the stair foot thunking onto the deck."""
    n = ns(1.6)
    x = zeros(n)
    latch = norm(thump(n, 95, 60, 0.05, 0.18, rng))
    add_into(latch, norm(decaying_sines(n, metal_modes(rng, 240, PLATE[:10], 0.25, hardness_hz=2500))), 0.6)
    add_into(x, latch, 0.8)
    m = n - ns(0.05)
    hiss = biquad_tv(white(m, rng), "bp", sweep(m, 5200, 2400, "exp", 0.6), 0.9)
    hiss = mul(hiss, env_points(m, [(0, 0), (0.01, 1.0), (0.35, 0.3), (0.6, 0.0)]))
    add_into(x, norm(hiss), 0.45, ns(0.05))
    add_into(x, _servo(n - ns(0.15), rng, 150, 175, 0.5), 0.45, ns(0.15))
    add_into(x, _servo(n - ns(0.55), rng, 120, 150, 0.75), 0.4, ns(0.55))
    m2 = n - ns(1.32)
    foot = norm(thump(m2, 85, 50, 0.06, 0.2, rng))
    add_into(foot, norm(decaying_sines(m2, metal_modes(rng, 180, PLATE[:10], 0.3, hardness_hz=2200))), 0.5)
    add_into(x, foot, 0.75, ns(1.32))
    x = saturate(norm(x), 1.2)
    return [finish_oneshot(x, fade_in_s=0.0005, fade_out_s=0.08, hp=30)], False


def hatch_close(rng):
    """Stairs retract, door slides shut, seal locks with a thunk and a puff."""
    n = ns(1.4)
    x = zeros(n)
    add_into(x, _servo(n, rng, 150, 120, 0.7), 0.4)
    add_into(x, _servo(n - ns(0.55), rng, 175, 150, 0.45), 0.4, ns(0.55))
    m = n - ns(1.02)
    seal = norm(thump(m, 90, 55, 0.05, 0.22, rng))
    add_into(seal, norm(decaying_sines(m, metal_modes(rng, 210, PLATE[:10], 0.3, hardness_hz=2400))), 0.6)
    add_into(x, seal, 0.9, ns(1.02))
    m2 = n - ns(1.06)
    puff = biquad(mul(white(m2, rng), env_perc(m2, 0.005, 0.18)), "bp", 3000, 0.8)
    add_into(x, norm(puff), 0.3, ns(1.06))
    x = saturate(norm(x), 1.2)
    return [finish_oneshot(x, fade_in_s=0.003, fade_out_s=0.08, hp=30)], False


def airlock_cycle(rng):
    """Airlock pressurisation. Sound needs air: the roar of incoming gas
    starts as a dull rumble felt through the boots and opens up (low-pass
    sweeping 250 Hz -> 7 kHz) as the pressure rises, then settles, a valve
    clunks shut and a soft D-major chime says it's safe."""
    n = ns(3.2)
    x = zeros(n)
    valve = norm(thump(n, 80, 50, 0.06, 0.25, rng))
    add_into(valve, norm(decaying_sines(n, metal_modes(rng, 150, PLATE, 0.4, hardness_hz=1800))), 0.6)
    add_into(x, valve, 0.7)
    m = ns(2.5)
    src = white(m, rng)
    roar = biquad_tv(src, "lp", sweep(m, 250, 7000, "exp", 0.8), 0.7)
    add_into(roar, biquad_tv(src, "bp", sweep(m, 400, 3000, "exp", 0.7), 1.2), 0.4)
    roar = mul(roar, env_points(m, [(0, 0), (0.25, 0.6), (1.4, 1.0), (2.1, 0.5), (2.5, 0.0)]))
    add_into(x, norm(roar), 0.8, ns(0.08))
    pump = mul(add_sines(m, [(55.0, 1.0), (110.0, 0.5), (165.0, 0.2)]),
               env_points(m, [(0, 0), (0.3, 1.0), (2.0, 0.8), (2.5, 0.0)]))
    add_into(x, norm(pump), 0.25, ns(0.08))
    m2 = n - ns(2.55)
    shut = norm(thump(m2, 90, 55, 0.04, 0.18, rng))
    add_into(shut, norm(decaying_sines(m2, metal_modes(rng, 260, PLATE[:10], 0.2, hardness_hz=3000))), 0.5)
    add_into(x, shut, 0.6, ns(2.55))
    m3 = n - ns(2.7)
    chime = soft_mallet(m3, A5, 0.6, rng)
    add_into(chime, soft_mallet(m3, D6, 0.8, rng), 0.9)
    add_into(x, norm(chime), 0.35, ns(2.7))
    x = saturate(norm(x), 1.15)
    return [finish_oneshot(x, fade_in_s=0.002, fade_out_s=0.12, hp=30)], False


def add_sines(n, parts):
    y = zeros(n)
    for f, a in parts:
        add_into(y, sine(n, f), a)
    return y


def door_slide(rng):
    """Interior sliding door: pneumatic whoosh with a soft motor under it and
    a gentle rubber-stop thud."""
    n = ns(0.62)
    x = zeros(n)
    m = ns(0.42)
    wh = biquad_tv(white(m, rng), "bp", sweep(m, 1500, 650, "exp", 0.7), 0.9)
    wh = mul(wh, env_points(m, [(0, 0), (0.06, 1.0), (0.3, 0.6), (0.42, 0.0)]))
    add_into(x, norm(wh), 0.6)
    add_into(x, _servo(n, rng, 210, 230, 0.42), 0.25)
    m2 = n - ns(0.4)
    stop = norm(thump(m2, 130, 80, 0.02, 0.07, rng, attack=0.001, drive=1.1))
    add_into(x, stop, 0.35, ns(0.4))
    return [finish_oneshot(x, fade_in_s=0.004, fade_out_s=0.06, hp=60)], False


def switch_click(rng):
    """Rocker switch: plastic snap with a tiny spring ping."""
    n = ns(0.09)
    x = decaying_sines(n, [(3300, 1.0, 0.012, 0.0), (5100, 0.5, 0.008, 0.3), (1900, 0.35, 0.02, 0.0)])
    add_into(x, norm(noise_burst(n, rng, 0.0015, kind="hp", f=2500)), 0.6 * peak(x))
    m = n - ns(0.018)
    y = decaying_sines(m, [(2600, 0.5, 0.01, 0.0), (4300, 0.3, 0.006, 0.0)])
    add_into(x, y, 1.0, ns(0.018))
    return [finish_oneshot(x, fade_in_s=0.0002, fade_out_s=0.01, hp=200)], False


def light_on(rng):
    """Panel light starting: starter tick, two flicker tinks with a burst of
    buzz each, then the steady hum swelling in and fading."""
    n = ns(0.75)
    x = zeros(n)
    for t, a in [(0.0, 0.7), (0.07, 0.5), (0.23, 0.6), (0.43, 0.9)]:
        tick = tinkle(rng, rng.uniform(2800, 3600), 0.03)
        add_into(x, norm(tick), a * 0.6, ns(t))
        m = ns(0.05)
        bz = biquad(saturate(sine(m, 100.0), 5.0), "bp", 1200, 0.8)
        add_into(x, mul(bz, env_perc(m, 0.002, 0.05)), a * 0.25, ns(t))
    m = n - ns(0.43)
    hum = biquad(saturate(sine(m, 100.0), 3.0), "bp", 600, 0.7)
    add_into(hum, sine(m, 200.0), 0.2)
    hum = mul(hum, env_points(m, [(0, 0), (0.05, 1.0), (0.32, 0.0)]))
    add_into(x, norm(hum), 0.18, ns(0.43))
    return [finish_oneshot(x, fade_in_s=0.0005, fade_out_s=0.05, hp=80)], False


def light_buzz_loop(rng):
    """A failing light: mains buzz with irregular arcing crackle (1 s loop)."""
    P = ns(1.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    bz = saturate(sine(N, q(100.0)), 6.0)
    add_into(bz, saturate(sine(N, q(200.0)), 3.0), 0.3)
    bz = biquad(bz, "bp", 1100, 0.6)
    bz = mul(bz, smooth_random(N, 6.0, rng, P, 0.3, 1.0))
    times = [rng.uniform(0, 1.0) for _ in range(7)]
    cr = zeros(P)
    add_into(cr, burst_events(P, rng, times, [rng.uniform(0.002, 0.01) for _ in times],
                              [rng.uniform(0.4, 1.0) for _ in times]))
    cr = biquad(tile(cr, 2), "hp", 2000, 0.7)   # two periods, like the buzz (seamless)
    mix = [a + 0.5 * b for a, b in zip(norm(bz), norm(cr))]
    return [finish_loop(mix, P)], True


def room_tone_loop(rng):
    """Interior room tone (8 s loop): air handling through vents with slow
    breathing, faint 50/100 Hz station hum, a whisper of electronics."""
    P = ns(8.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    src = pnoise(P, 2, rng)
    air = biquad(src, "lp", 650, 0.7)
    add_into(air, biquad(src, "bp", 1700, 0.5), 0.15)
    air = at_rms(mul(air, [0.85 + 0.15 * a for a in lfo(N, 2, P)]), -18)
    hum = zeros(N)
    for f, a in [(50, 0.5), (100, 1.0), (150, 0.25), (200, 0.15)]:
        add_into(hum, sine(N, q(f), rng.uniform(0, TAU)), a)
    hum = at_rms(hum, -30)
    el = at_rms(mul(sine(N, q(4200.0)), smooth_random(N, 0.3, rng, P, 0.0, 1.0)), -48)
    mix = [a + b + c for a, b, c in zip(air, hum, el)]
    return [finish_loop(mix, P)], True


def vending_dispense(rng):
    """Drinks machine: motor turns the spiral, the can drops with a hollow
    clunk into the tray and rolls to a stop."""
    n = ns(1.5)
    x = zeros(n)
    add_into(x, _servo(n, rng, 70, 80, 0.55), 0.5)
    m = n - ns(0.62)
    clunk = norm(thump(m, 140, 70, 0.03, 0.12, rng))
    add_into(clunk, norm(decaying_sines(m, metal_modes(rng, 330, PLATE[:12], 0.18, hardness_hz=3500))), 0.7)
    add_into(clunk, norm(noise_burst(m, rng, 0.008, kind="lp", f=2500)), 0.5)
    add_into(x, clunk, 1.0, ns(0.62))
    roll_t = [0.74 + 0.07 * i + rng.uniform(-0.01, 0.01) for i in range(7)]
    for i, t in enumerate(roll_t):
        add_into(x, norm(tinkle(rng, rng.uniform(900, 1300), 0.05)), 0.25 * (1.0 - i / 8.0), ns(t))
    x = saturate(norm(x), 1.2)
    return [finish_oneshot(x, fade_in_s=0.003, fade_out_s=0.08, hp=40)], False


def console_beep(rng):
    """Friendly two-note console blip, A5 -> D6 (inside D major)."""
    n = ns(0.3)
    x = zeros(n)
    for t, f in [(0.0, A5), (0.075, D6)]:
        m = ns(0.08)
        y = sine(m, f)
        add_into(y, sine(m, 2 * f), 0.12)
        y = mul(y, tone_env(m, 0.004, 0.05, 0.08))
        add_into(x, y, 1.0, ns(t))
    x = wet_mix(x, 0.4, 0.5, 0.15)
    return [finish_oneshot(x, fade_in_s=0.0, fade_out_s=0.04, hp=150)], False


def holo_on(rng):
    """Hologram projector: a rising FM shimmer and a quick D-major arpeggio
    of glassy bells with a sparkle of noise."""
    n = ns(1.3)
    x = zeros(n)
    m = ns(0.6)
    fr = sweep(m, 300, 1200, "exp", 0.8)
    sh = mul(osc_var(fr), env_points(m, [(0, 0), (0.1, 0.6), (0.5, 0.4), (0.6, 0.0)]))
    add_into(sh, mul(osc_var([f * 1.5 for f in fr]), env_perc(m, 0.05, 0.5)), 0.3)
    add_into(x, norm(sh), 0.4)
    for i, f in enumerate([D5, Fs5, A5, D6]):
        t = 0.12 + i * 0.07
        add_into(x, norm(bell(n - ns(t), f, 0.7, rng, bright=1.3)), 0.35, ns(t))
    sp = biquad(mul(white(n, rng), env_points(n, [(0, 0), (0.2, 0.5), (0.6, 0.2), (1.3, 0.0)])), "hp", 6000, 0.7)
    add_into(x, norm(sp), 0.08)
    x = wet_mix(x, 1.0, 0.8, 0.3)
    return [finish_oneshot(x, fade_in_s=0.002, fade_out_s=0.15, hp=120)], False


# ========================================================== PETREL shuttle ===
# The PETREL is a light twin-engine shuttle: still "in the cockpit", but a
# smaller, better-damped airframe than the WREN, so everything is smoother,
# higher and less saturated. Mechanisms (skids, mag-clamps, the magline winch)
# are small and close, heard as the frame's own clicks and hums.

def petrel_engine_loop(rng):
    """Twin engines: two soft saw cores half a hertz apart (82 / 82.5 Hz ->
    one slow beat per loop, faster at the upper harmonics), a pair of clean
    turbine whines beating 1 Hz apart, a light jet breath and only a little
    low body. Smoother and higher than engine_main_loop."""
    P = ns(2.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    tbl = saw_table(10, 1.9)
    core = zeros(N)
    for f, a in [(82.0, 1.0), (82.5, 0.6)]:
        add_into(core, wt_osc(N, q(f), tbl, rng.uniform(0, TAU)), a)
    add_into(core, sine(N, q(41.0), rng.uniform(0, TAU)), 0.25)
    add_into(core, sine(N, q(123.5), rng.uniform(0, TAU)), 0.12)
    core = at_rms(saturate(norm(biquad(core, "lp", 1300, 0.7)), 1.15), -13)

    whine = fm_sine(N, q(1640.0), q(2.5), 1.2, rng.uniform(0, TAU))
    add_into(whine, sine(N, q(1641.0), rng.uniform(0, TAU)), 0.7)
    add_into(whine, sine(N, q(3281.5), rng.uniform(0, TAU)), 0.15)
    whine = at_rms(mul(whine, smooth_random(N, 1.5, rng, P, 0.7, 1.0)), -29)

    breath = biquad(biquad(pnoise(P, 2, rng), "bp", 720, 0.6), "lp", 2600, 0.7)
    breath = at_rms(mul(breath, smooth_random(N, 2.5, rng, P, 0.8, 1.0)), -21)

    body = at_rms(biquad(onepole_lp(pnoise(P, 2, rng), 60.0), "lp", 220, 0.7), -23)

    mix = [a + b + c + d for a, b, c, d in zip(core, whine, breath, body)]
    mix = saturate(biquad(mix, "lp", 8000, 0.7), 1.1)
    return [finish_loop(mix, P)], True


def petrel_afterburner_loop(rng):
    """Afterburner layer: a bright wide roar with a 2.2 kHz presence lift,
    a mid body, the twin cores pushed into saturation, sparse crackle and a
    fizzing top. Brighter and thinner than engine_boost_loop."""
    P = ns(2.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    roar = biquad(biquad(pnoise(P, 2, rng), "lp", 7000, 0.6), "hp", 160, 0.7)
    roar = biquad(roar, "peak", 2200, 0.8, 6.0)
    roar = at_rms(mul(roar, smooth_random(N, 45.0, rng, P, 0.55, 1.0)), -13)

    body = at_rms(biquad(pnoise(P, 2, rng), "bp", 380, 0.7), -18)

    core = zeros(N)
    for f, a in [(82.0, 1.0), (82.5, 0.7), (164.5, 0.5), (123.0, 0.3)]:
        add_into(core, sine(N, q(f), rng.uniform(0, TAU)), a)
    core = at_rms(saturate(norm(core), 2.2), -19)

    count = 2 * 90
    times = [rng.random() * 2.0 for _ in range(count)]
    crack = burst_events(P + ns(0.01), rng, times, [rng.uniform(0.0004, 0.003) for _ in times],
                         [rng.random() ** 2 for _ in times])
    crack = at_rms(biquad(fold(crack, P) * 2, "hp", 2500, 0.7), -23)

    top = biquad(pnoise(P, 2, rng), "bp", 8500, 0.8)
    top = at_rms(mul(top, smooth_random(N, 70.0, rng, P, 0.35, 1.0)), -24)

    mix = [a + b + c + d + e for a, b, c, d, e in zip(roar, body, core, crack, top)]
    mix = saturate(norm(mix), 1.8)
    return [finish_loop(mix, P)], True


def gyro_whine_loop(rng):
    """Reaction-wheel whine centred on 600 Hz: a smooth near-sine with a
    gentle 5 Hz vibrato, a partner 0.5 Hz away for a slow shimmer, soft
    harmonics, and a faint bearing hum/ripple underneath. Code pitch-shifts
    it 0.5..2.3, so the top stays clean."""
    P = ns(2.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    tone = fm_sine(N, q(600.0), q(5.0), 0.5, rng.uniform(0, TAU))
    add_into(tone, sine(N, q(600.5), rng.uniform(0, TAU)), 0.35)
    add_into(tone, sine(N, q(1200.0), rng.uniform(0, TAU)), 0.16)
    add_into(tone, sine(N, q(1800.5), rng.uniform(0, TAU)), 0.045)
    add_into(tone, sine(N, q(300.0), rng.uniform(0, TAU)), 0.1)
    tone = at_rms(mul(tone, smooth_random(N, 1.0, rng, P, 0.88, 1.0)), -12)

    hum = sine(N, q(100.0), rng.uniform(0, TAU))
    add_into(hum, sine(N, q(200.0), rng.uniform(0, TAU)), 0.4)
    hum = at_rms(hum, -31)
    # bearing ripple: narrow noise band modulated at the wheel's rotation rate
    ripple = biquad(pnoise(P, 2, rng), "bp", 2400, 2.0)
    ripple = at_rms(mul(ripple, [0.55 + 0.45 * v for v in lfo(N, 40, P)]), -40)

    mix = [a + b + c for a, b, c in zip(tone, hum, ripple)]
    return [finish_loop(mix, P)], True


def hover_hum_loop(rng):
    """Station-keeping: soft RCS hiss that breathes in slow, uneven swells
    over a low, calm 55/110 Hz hum and a little air (3 s loop)."""
    P = ns(3.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    swell = [0.35 + 0.65 * (v * v) for v in smooth_random(N, 1.3, rng, P, 0.0, 1.0)]
    hiss = biquad(biquad(pnoise(P, 2, rng), "hp", 1500, 0.7), "lp", 6000, 0.7)
    hiss = biquad(hiss, "peak", 3200, 1.0, 4.0)
    hiss = at_rms(mul(hiss, swell), -19)

    hum = zeros(N)
    for f, a in [(55.0, 1.0), (110.0, 0.5), (110.333, 0.3), (165.0, 0.1)]:
        add_into(hum, sine(N, q(f), rng.uniform(0, TAU)), a)
    hum = at_rms(mul(hum, [0.9 + 0.1 * v for v in lfo(N, 1, P)]), -15)

    air = at_rms(biquad(pnoise(P, 2, rng), "lp", 400, 0.7), -25)
    mix = [a + b + c for a, b, c in zip(hiss, hum, air)]
    return [finish_loop(mix, P)], True


def _clack(n, rng, f0, low=150.0, t60=0.06):
    """Small mechanical clack: tiny body thump, short plate ring, contact tick."""
    y = norm(thump(n, low, low * 0.6, 0.02, 0.06, rng, attack=0.0008, drive=1.3))
    add_into(y, norm(decaying_sines(n, metal_modes(rng, f0, PLATE[:10], t60,
                                                   hardness_hz=5000, split=0.3))), 0.8)
    add_into(y, norm(noise_burst(n, rng, 0.003, kind="bp", f=3000, q=0.8)), 0.5)
    return norm(y)


def skids_deploy(rng):
    """Landing skids: a small servo swings the legs out, then two clacks as
    each leg locks."""
    n = ns(0.5)
    x = zeros(n)
    add_into(x, _servo(n, rng, 180, 220, 0.26), 0.4)
    add_into(x, _clack(n - ns(0.24), rng, 620, 150), 1.0, ns(0.24))
    add_into(x, _clack(n - ns(0.31), rng, 700, 165), 0.85, ns(0.31))
    x = saturate(norm(x), 1.2)
    return [finish_oneshot(x, fade_in_s=0.003, fade_out_s=0.05, hp=40)], False


def touchdown_clunk(rng, v):
    """Magnetic clamp engaging on touchdown: heavy metallic clunk plus the
    magnet's low 'thrum' (a sine burst with a slow flutter). v2 is a double
    clamp (both skids), v3 adds a short magnetic buzz."""
    n = ns(0.4)
    x = zeros(n)
    f_low, f_modes, thrum_f, flutter = [(88, 150, 62, 28.0), (80, 135, 55, 24.0),
                                        (95, 170, 68, 31.0), (74, 125, 50, 22.0)][v]

    def clunk(m, k=1.0):
        y = norm(thump(m, f_low * 1.1 * k, f_low * 0.55 * k, 0.06, 0.18, rng, drive=1.8))
        add_into(y, norm(decaying_sines(m, metal_modes(rng, f_modes * k, PLATE, 0.22,
                                                       hardness_hz=2500, split=0.4))), 0.7)
        add_into(y, norm(noise_burst(m, rng, 0.01, kind="lp", f=2000)), 0.6)
        return norm(y)

    add_into(x, clunk(n), 1.0)
    add_into(x, norm(tinkle(rng, rng.uniform(2200, 2800), 0.04, BAR[:3], 9000)), 0.12, ns(0.004))
    if v == 2:
        add_into(x, clunk(n - ns(0.07), 1.06), 0.5, ns(0.07))
    m = n - ns(0.008)
    th = sine(m, thrum_f)
    add_into(th, sine(m, thrum_f * 2.0), 0.3)
    th = mul(th, [0.75 + 0.25 * s for s in sine(m, flutter)])
    th = mul(th, env_perc(m, 0.012, 0.3))
    add_into(x, norm(th), 0.6, ns(0.008))
    if v == 3:
        mb = ns(0.09)
        bz = biquad(saturate(sine(mb, 120.0), 4.0), "bp", 650, 0.7)
        add_into(x, norm(mul(bz, env_perc(mb, 0.004, 0.08))), 0.18, ns(0.01))
    x = saturate(norm(x), 1.3)
    return [finish_oneshot(x, fade_in_s=0.0003, fade_out_s=0.06, hp=30)], False


def landing_chime_silk(rng):
    """Soft 'landed' confirmation: D6 settling down to A5 over a quiet F#5
    (a D-major triad), mellow mallets with a breath of bell."""
    n = ns(1.2)
    x = zeros(n)
    add_into(x, soft_mallet(n, D6, 0.9, rng, attack=0.006), 0.7)
    add_into(x, bell(n, D6, 0.6, rng, bright=0.3), 0.1)
    t = 0.16
    add_into(x, soft_mallet(n - ns(t), A5, 1.0, rng, attack=0.006), 1.0, ns(t))
    add_into(x, soft_mallet(n - ns(t), Fs5, 0.9, rng, attack=0.006), 0.35, ns(t))
    x = biquad(x, "lp", 5500, 0.7)
    x = wet_mix(x, 1.2, 1.0, 0.28)
    return [finish_oneshot(x, fade_in_s=0.0, fade_out_s=0.15)], False


def landing_abort_warble(rng):
    """Gentle 'not now' cue: a soft sine falling A5 -> D5 with a light warble,
    rounded attack and a short room tail. Informative, not an alarm."""
    n = ns(0.6)
    base = sweep(n, A5, D5, "exp", 0.8)
    fr = [f * (1.0 + 0.022 * math.sin(TAU * 11.0 * i / SR)) for i, f in enumerate(base)]
    x = osc_var(fr)
    add_into(x, osc_var([2.0 * f for f in fr]), 0.1)
    x = mul(x, env_points(n, [(0, 0), (0.03, 1.0), (0.38, 0.7), (0.56, 0.0)]))
    x = biquad(x, "lp", 3500, 0.7)
    x = wet_mix(x, 0.6, 0.6, 0.15)
    return [finish_oneshot(x, fade_in_s=0.0, fade_out_s=0.04, hp=120)], False


def liftoff_whoosh(rng):
    """Liftoff: two light skid-release clacks, then a rising downwash whoosh
    (band-pass sweeping 280 -> 2600 Hz) over a low swell of rumble."""
    n = ns(1.0)
    x = zeros(n)
    add_into(x, _clack(n, rng, 760, 170, 0.045), 0.4)
    add_into(x, _clack(n - ns(0.06), rng, 820, 180, 0.04), 0.32, ns(0.06))
    m = n - ns(0.04)
    src = white(m, rng)
    wh = biquad_tv(src, "bp", sweep(m, 280, 2600, "exp", 1.2), 0.9)
    add_into(wh, biquad_tv(src, "lp", sweep(m, 400, 3500, "exp", 1.0), 0.7), 0.4)
    wh = mul(wh, env_points(m, [(0, 0), (0.55, 1.0), (0.8, 0.6), (0.95, 0.0)]))
    add_into(x, norm(wh), 0.8, ns(0.04))
    rum = mul(onepole_lp(white(m, rng), 90.0), env_points(m, [(0, 0), (0.3, 1.0), (0.9, 0.0)]))
    add_into(x, norm(rum), 0.4, ns(0.04))
    tone = mul(osc_var(sweep(m, 70, 140, "exp", 1.0)), env_points(m, [(0, 0), (0.4, 1.0), (0.9, 0.0)]))
    add_into(x, norm(tone), 0.15, ns(0.04))
    return [finish_oneshot(x, fade_in_s=0.0005, fade_out_s=0.08, hp=30)], False


def magline_fire(rng):
    """Magline launch: coil-discharge click, then a buzzy electromagnetic
    'zip' sweeping 220 -> 3200 Hz with a thin fizz as the head leaves."""
    n = ns(0.35)
    x = zeros(n)
    click = decaying_sines(n, [(1800, 1.0, 0.008, 0.0), (4200, 0.5, 0.005, 0.4)])
    add_into(click, norm(noise_burst(n, rng, 0.0015, kind="hp", f=3000)), 0.6)
    add_into(x, norm(click), 0.5)
    m = ns(0.28)
    fr = sweep(m, 220, 3200, "exp", 0.55)
    buzz = osc_var(fr, table=square_table(9))
    buzz = biquad_tv(buzz, "lp", [f * 3.0 for f in fr], 0.7)
    add_into(buzz, osc_var([f * 1.5 for f in fr]), 0.3)
    buzz = mul(buzz, env_points(m, [(0, 0), (0.005, 1.0), (0.12, 0.7), (0.28, 0.0)]))
    add_into(x, norm(buzz), 0.7, ns(0.003))
    fizz = biquad(mul(white(m, rng), env_points(m, [(0, 0), (0.02, 1.0), (0.25, 0.0)])), "hp", 5000, 0.7)
    add_into(x, norm(fizz), 0.15, ns(0.003))
    x = biquad(x, "lp", 9000, 0.7)
    return [finish_oneshot(x, fade_in_s=0.0003, fade_out_s=0.04, hp=80)], False


def magline_latch(rng):
    """Line head latching on: magnetic clank and a short electric hum."""
    n = ns(0.6)
    x = zeros(n)
    clank = norm(thump(n, 120, 65, 0.04, 0.15, rng))
    add_into(clank, norm(decaying_sines(n, metal_modes(rng, 260, PLATE[:12], 0.3,
                                                       hardness_hz=4000, split=0.4))), 0.8)
    add_into(clank, norm(noise_burst(n, rng, 0.01, kind="lp", f=3000)), 0.6)
    add_into(clank, norm(tinkle(rng, 3000, 0.04, BAR[:3], 9000)), 0.15)
    add_into(x, clank, 1.0)
    m = n - ns(0.01)
    hum = biquad(saturate(sine(m, 120.0), 3.0), "bp", 700, 0.7)
    add_into(hum, sine(m, 240.0), 0.3)
    hum = mul(hum, env_points(m, [(0, 0), (0.02, 1.0), (0.25, 0.7), (0.45, 0.0)]))
    add_into(x, norm(hum), 0.3, ns(0.01))
    x = saturate(norm(x), 1.25)
    return [finish_oneshot(x, fade_in_s=0.0003, fade_out_s=0.06, hp=40)], False


def magline_tension_loop(rng):
    """Cable under load: stick-slip creak (a jittered 22-55 Hz impulse train
    exciting cable/mount resonances, as in scrape_loop but slower and lower),
    a slowly bending strain tone and a little friction noise. Code drives
    pitch and volume from tension."""
    P = ns(1.5)
    N = 2 * P
    q = lambda f: qf(f, P)
    exc = zeros(P)
    rate = smooth_random(P, 3.0, rng, P, 22.0, 55.0)
    t = ns(0.004)  # keep slip onsets off the loop seam
    while t < P:
        exc[t] += rng.uniform(0.3, 1.0) ** 1.3 * (1 if rng.random() < 0.5 else -1)
        t += max(1, int(SR / rate[t] * rng.uniform(0.8, 1.2)))
    exc = exc * 2
    jit = smooth_random(N, 9.0, rng, P, 0.4, 1.0)
    src = mul(exc, jit)
    cr = resonator_bank(src, [(190, 14, 1.0), (430, 16, 0.8), (760, 18, 0.6),
                              (1180, 20, 0.45), (1730, 20, 0.3), (2450, 18, 0.2)])
    cr = at_rms(cr, -16)
    strain = fm_sine(N, q(96.0), q(0.6667), 1.5, rng.uniform(0, TAU))
    add_into(strain, sine(N, q(192.0), rng.uniform(0, TAU)), 0.25)
    strain = at_rms(biquad(strain, "lp", 600, 0.7), -25)
    fric = at_rms(mul(biquad(pnoise(P, 2, rng), "bp", 1500, 0.8), jit), -29)
    mix = saturate(norm([a + b + c for a, b, c in zip(cr, strain, fric)]), 1.3)
    return [finish_loop(mix, P)], True


def clutch_scream_loop(rng):
    """Slip clutch ratcheting under overload: 28 pawl clicks per second (a
    little uneven) ringing small metal modes, a friction squeal and screechy
    comb-filtered grind on top, plus a low knock per pawl."""
    P = ns(1.0)
    N = 2 * P
    q = lambda f: qf(f, P)
    count = 28
    exc = zeros(P)
    for k in range(count):
        t = int((k + 0.5 + rng.uniform(-0.12, 0.12)) * P / count) % P  # onsets off the seam
        exc[t] += rng.uniform(0.6, 1.0)
    exc = exc * 2
    clicks = resonator_bank(exc, [(1650, 25, 1.0), (2900, 28, 0.7), (4300, 30, 0.5),
                                  (6100, 25, 0.3), (820, 12, 0.5)])
    clicks = at_rms(clicks, -15)
    knock = at_rms(biquad(exc, "bp", 180, 2.0), -22)
    jit = smooth_random(N, 10.0, rng, P, 0.3, 1.0)
    squeal = fm_sine(N, q(1480.0), q(7.0), 2.0, rng.uniform(0, TAU))
    add_into(squeal, sine(N, q(2960.0), rng.uniform(0, TAU)), 0.3)
    squeal = at_rms(mul(squeal, jit), -22)
    grind = biquad(pnoise(P, 2, rng), "bp", 2200, 1.2)
    grind = comb_fb(grind, 1.0 / 740.0, 0.45, damp_hz=6000)
    grind = at_rms(mul(grind, smooth_random(N, 16.0, rng, P, 0.4, 1.0)), -21)
    mix = saturate(norm([a + b + c + d for a, b, c, d in zip(clicks, knock, squeal, grind)]), 1.5)
    return [finish_loop(mix, P)], True


def winch_loop(rng):
    """Winch reeling in: geared motor (96 Hz saw, 32 Hz torque ripple, gear
    whine), small cable-lay ticks as the line spools onto the drum, brush
    noise and a low drum rumble."""
    P = ns(1.5)
    N = 2 * P
    q = lambda f: qf(f, P)
    raw = wt_osc(N, q(96.0), saw_table(30, 1.0), rng.uniform(0, TAU))
    motor = scale(biquad(raw, "bp", 700, 1.0), 0.6)
    add_into(motor, biquad(raw, "lp", 1500, 0.7), 0.5)
    motor = saturate(norm(motor), 1.4)
    add_into(motor, sine(N, q(864.0), rng.uniform(0, TAU)), 0.12)
    add_into(motor, sine(N, q(1728.0), rng.uniform(0, TAU)), 0.04)
    motor = at_rms(mul(motor, [0.85 + 0.15 * v for v in lfo(N, 48, P)]), -14)
    ticks = zeros(P)
    for k in range(9):
        ticks[int((k + rng.uniform(-0.1, 0.1)) * P / 9) % P] += rng.uniform(0.5, 1.0)
    ticks = resonator_bank(ticks * 2, [(2400, 18, 1.0), (3600, 20, 0.6), (1300, 10, 0.4)])
    ticks = at_rms(ticks, -27)
    brush = at_rms(mul(biquad(pnoise(P, 2, rng), "lp", 2000, 0.7),
                       smooth_random(N, 12.0, rng, P, 0.6, 1.0)), -26)
    drum = at_rms(biquad(onepole_lp(pnoise(P, 2, rng), 80.0), "lp", 150, 0.7), -24)
    mix = [a + b + c + d for a, b, c, d in zip(motor, ticks, brush, drum)]
    mix = biquad(mix, "lp", 8000, 0.7)
    return [finish_loop(mix, P)], True


def magline_snap(rng):
    """Line parting under load: whip crack, a falling twang as the cable
    recoils, a swish, a second slap as the end whips round, a metallic ring
    from the mount and a low thump, glued with a short reverb."""
    n = ns(1.2)
    x = zeros(n)
    add_into(x, norm(noise_burst(n, rng, 0.003, kind="hp", f=2500)), 1.0)
    add_into(x, norm(noise_burst(n, rng, 0.0015)), 0.6)
    fr = sweep(n, 520, 170, "exp", 0.35)
    tw = osc_var(fr, table=saw_table(16, 1.2))
    tw = biquad_tv(tw, "lp", sweep(n, 4000, 600, "exp", 0.5), 0.9)
    add_into(x, norm(mul(tw, env_perc(n, 0.001, 0.55))), 0.8)
    m = ns(0.18)
    sw = biquad_tv(white(m, rng), "bp", sweep(m, 4000, 900, "exp", 0.6), 0.9)
    add_into(x, norm(mul(sw, env_perc(m, 0.004, 0.15))), 0.35, ns(0.005))
    add_into(x, norm(noise_burst(n, rng, 0.002, kind="hp", f=2000)), 0.4, ns(0.06))
    ring = metal_modes(rng, 780, TUBE + [1.6, 3.3], 1.0, amp_tilt=0.6, decay_tilt=0.5,
                       hardness_hz=8000, split=0.5)
    add_into(x, norm(decaying_sines(n, ring)), 0.55, ns(0.01))
    add_into(x, norm(thump(n, 110, 55, 0.08, 0.2, rng)), 0.5)
    x = saturate(norm(x), 1.4)
    x = wet_mix(x, 1.0, 0.8, 0.15)
    return [finish_oneshot(x, fade_in_s=0.0002, fade_out_s=0.2, hp=35)], False


def magline_release(rng):
    """Soft magnetic release: a small click, a low pop and a short falling zap."""
    n = ns(0.3)
    x = zeros(n)
    click = decaying_sines(n, [(2100, 1.0, 0.012, 0.0), (3400, 0.4, 0.007, 0.5), (1300, 0.3, 0.02, 0.0)])
    add_into(x, norm(click), 0.5)
    add_into(x, norm(thump(n, 180, 90, 0.03, 0.06, rng, attack=0.0008, drive=1.1)), 0.8)
    m = ns(0.12)
    zap = mul(osc_var(sweep(m, 900, 240, "exp", 0.6)), env_perc(m, 0.003, 0.1))
    add_into(x, norm(zap), 0.3, ns(0.004))
    puff = biquad(mul(white(m, rng), env_perc(m, 0.003, 0.04)), "bp", 2500, 0.8)
    add_into(x, norm(puff), 0.1)
    x = biquad(x, "lp", 7000, 0.7)
    return [finish_oneshot(x, fade_in_s=0.0003, fade_out_s=0.04, hp=60)], False


def ramp_servo(rng):
    """PETREL door + fold-down ramp: latch tick, a quick small door servo with
    a soft stop, the ramp servo, then a light thunk as the ramp foot lands.
    Lighter and quicker than hatch_open."""
    n = ns(1.2)
    x = zeros(n)
    add_into(x, norm(tinkle(rng, 2600, 0.04, BAR[:3], 9000)), 0.25)
    add_into(x, _servo(n - ns(0.03), rng, 210, 235, 0.32), 0.35, ns(0.03))
    m = n - ns(0.35)
    add_into(x, norm(thump(m, 160, 100, 0.02, 0.05, rng, attack=0.001, drive=1.1)), 0.3, ns(0.35))
    add_into(x, _servo(n - ns(0.38), rng, 140, 165, 0.62), 0.4, ns(0.38))
    m = n - ns(1.0)
    foot = norm(thump(m, 100, 60, 0.04, 0.14, rng))
    add_into(foot, norm(decaying_sines(m, metal_modes(rng, 230, PLATE[:10], 0.2, hardness_hz=2600))), 0.5)
    add_into(foot, norm(noise_burst(m, rng, 0.006, kind="lp", f=2200)), 0.5)
    add_into(x, norm(foot), 0.65, ns(1.0))
    x = saturate(norm(x), 1.15)
    return [finish_oneshot(x, fade_in_s=0.002, fade_out_s=0.06, hp=35)], False


# ================================================================== jobs ===
JOBS = [
    # (output name, recipe, extra args, seed)
    ("engine_main_loop", engine_main_loop, (), 11),
    ("engine_boost_loop", engine_boost_loop, (), 12),
    ("rcs_hiss_loop", rcs_hiss_loop, (), 13),
    ("rcs_puff_1", rcs_puff, (0.13, 5200, 2600, 0.07, 5600, False), 14),
    ("rcs_puff_2", rcs_puff, (0.15, 4400, 2000, 0.09, 4700, True), 15),
    ("rcs_puff_3", rcs_puff, (0.12, 6000, 3200, 0.055, 6300, False), 16),
    ("engine_ignite", engine_ignite, (), 17),
    ("boost_kick", boost_kick, (), 18),
    ("low_hull_alarm", low_hull_alarm, (), 19),
    ("impact_light_1", impact_light, (0,), 21),
    ("impact_light_2", impact_light, (1,), 22),
    ("impact_light_3", impact_light, (2,), 23),
    ("impact_light_4", impact_light, (3,), 24),
    ("impact_medium_1", impact_medium, (0,), 31),
    ("impact_medium_2", impact_medium, (1,), 32),
    ("impact_medium_3", impact_medium, (2,), 33),
    ("impact_heavy_1", impact_heavy, (0,), 41),
    ("impact_heavy_2", impact_heavy, (1,), 42),
    ("impact_heavy_3", impact_heavy, (2,), 43),
    ("scrape_loop", scrape_loop, (), 51),
    ("container_clunk_1", container_clunk, (0,), 61),
    ("container_clunk_2", container_clunk, (1,), 62),
    ("container_clunk_3", container_clunk, (2,), 63),
    ("explosion_ship", explosion_ship, (), 71),
    ("debris_rattle", debris_rattle, (), 72),
    ("gate_pass", gate_pass, (), 81),
    ("race_countdown", race_countdown, (), 82),
    ("race_go", race_go, (), 83),
    ("race_finish", race_finish, (), 84),
    ("dock_clamp", dock_clamp, (), 85),
    ("dock_chime", dock_chime, (), 86),
    ("boundary_warning", boundary_warning, (), 87),
    ("ui_click", ui_click, (), 88),
    ("ambient_space_drone", ambient_space_drone, (), 91),
    ("station_hum_loop", station_hum_loop, (), 92),
    ("traffic_engine_loop", traffic_engine_loop, (), 93),
    ("beacon_ping", beacon_ping, (), 94),
    ("door_servo", door_servo, (), 95),
    # on foot
    ("step_suit_1", step_suit, (0,), 101),
    ("step_suit_2", step_suit, (1,), 102),
    ("step_suit_3", step_suit, (2,), 103),
    ("step_suit_4", step_suit, (3,), 104),
    ("step_deck_1", step_deck, (0,), 111),
    ("step_deck_2", step_deck, (1,), 112),
    ("step_deck_3", step_deck, (2,), 113),
    ("step_deck_4", step_deck, (3,), 114),
    ("hatch_open", hatch_open, (), 121),
    ("hatch_close", hatch_close, (), 122),
    ("airlock_cycle", airlock_cycle, (), 123),
    ("door_slide", door_slide, (), 124),
    ("switch_click", switch_click, (), 125),
    ("light_on", light_on, (), 126),
    ("light_buzz_loop", light_buzz_loop, (), 127),
    ("room_tone_loop", room_tone_loop, (), 128),
    ("vending_dispense", vending_dispense, (), 129),
    ("console_beep", console_beep, (), 130),
    ("holo_on", holo_on, (), 131),
    # PETREL shuttle
    ("petrel_engine_loop", petrel_engine_loop, (), 141),
    ("petrel_afterburner_loop", petrel_afterburner_loop, (), 142),
    ("gyro_whine_loop", gyro_whine_loop, (), 143),
    ("hover_hum_loop", hover_hum_loop, (), 144),
    ("skids_deploy", skids_deploy, (), 145),
    ("touchdown_clunk_1", touchdown_clunk, (0,), 146),
    ("touchdown_clunk_2", touchdown_clunk, (1,), 147),
    ("touchdown_clunk_3", touchdown_clunk, (2,), 148),
    ("touchdown_clunk_4", touchdown_clunk, (3,), 149),
    ("landing_chime_silk", landing_chime_silk, (), 150),
    ("landing_abort_warble", landing_abort_warble, (), 151),
    ("liftoff_whoosh", liftoff_whoosh, (), 152),
    ("magline_fire", magline_fire, (), 153),
    ("magline_latch", magline_latch, (), 154),
    ("magline_tension_loop", magline_tension_loop, (), 155),
    ("clutch_scream_loop", clutch_scream_loop, (), 156),
    ("winch_loop", winch_loop, (), 157),
    ("magline_snap", magline_snap, (), 158),
    ("magline_release", magline_release, (), 159),
    ("ramp_servo", ramp_servo, (), 160),
]


def run_job(job):
    name, fn, args, seed = job
    t0 = time.time()
    rng = random.Random(seed)
    chans, loop = fn(rng, *args)
    path = os.path.join(OUT, name + ".wav")
    n = write_wav(path, chans, loop=loop)
    return name, n / SR, len(chans), loop, time.time() - t0


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    wanted = [a for a in argv if not a.startswith("-")]
    jobs = [j for j in JOBS if not wanted or any(j[0].startswith(w) for w in wanted)]
    # longest job first so the pool finishes sooner
    jobs.sort(key=lambda j: 0 if j[0].startswith(("ambient", "room_tone")) else 1)
    t0 = time.time()
    with Pool(min(len(jobs), os.cpu_count() or 4)) as pool:
        for name, dur, nch, loop, secs in pool.imap_unordered(run_job, jobs):
            print("%-22s %5.2fs %s %-5s (%.1fs)" % (name, dur, "stereo" if nch == 2 else "mono  ",
                                                   "loop" if loop else "", secs), flush=True)
    print("done: %d files in %.1fs -> %s" % (len(jobs), time.time() - t0, OUT))


if __name__ == "__main__":
    main(sys.argv[1:])
