"""Tiny pure-Python DSP toolkit used by gen_audio.py (stdlib only, no numpy).

Signals are plain Python lists of floats at SR = 44100 Hz, nominal range -1..1.

Seamless loops
--------------
Loops are rendered with the "periodic steady state" trick: every *source*
(oscillators, LFOs, noise, scattered events) is made exactly periodic with
period P samples (oscillator frequencies are quantised to multiples of SR/P,
noise/event buffers are generated for P samples and tiled). All processing is
either linear time-invariant (filters, reverb), memoryless (saturation) or a
product of periodic signals. Rendering `reps` periods and keeping only the
last one therefore yields a signal that is mathematically periodic: the last
sample flows into the first one exactly like any other pair of neighbours.
"""
import math
import random
import struct
import array

SR = 44100
TAU = 2.0 * math.pi
LN1000 = math.log(1000.0)  # -60 dB


def ns(seconds):
    """Seconds -> sample count."""
    return int(round(seconds * SR))


def zeros(n):
    return [0.0] * n


# ------------------------------------------------------------ periodicity --
def qf(freq, period):
    """Quantise a frequency so that it completes an integer number of cycles
    in `period` samples (keeps loops seamless)."""
    k = max(1, int(round(freq * period / SR)))
    return k * SR / period


def tile(x, reps):
    return x * reps


def last(x, period):
    return x[len(x) - period:]


def fold(buf, period):
    """Wrap a buffer longer than `period` back onto itself (circular sum) so
    that events placed near the end continue at the start of the loop."""
    out = buf[:period]
    for i in range(period, len(buf)):
        out[i % period] += buf[i]
    return out


# ------------------------------------------------------------- generators --
def white(n, rng):
    r = rng.random
    return [2.0 * r() - 1.0 for _ in range(n)]


def sine(n, freq, phase=0.0, amp=1.0, start=0):
    """Fixed-frequency sine; `start` offsets the time index (useful when a
    voice is rendered only over part of a periodic loop)."""
    w = TAU * freq / SR
    s = math.sin
    return [amp * s(w * (i + start) + phase) for i in range(n)]


def osc_var(freqs, phase=0.0, table=None):
    """Variable-frequency oscillator (phase accumulator). `freqs` is a
    per-sample list in Hz. Uses a wavetable when given (one cycle, any size)."""
    n = len(freqs)
    out = [0.0] * n
    ph = phase / TAU
    inv = 1.0 / SR
    if table is None:
        s = math.sin
        for i in range(n):
            out[i] = s(TAU * ph)
            ph += freqs[i] * inv
            if ph >= 1.0:
                ph -= 1.0
    else:
        size = len(table)
        for i in range(n):
            out[i] = table[int(ph * size) % size]
            ph += freqs[i] * inv
            ph -= math.floor(ph)
    return out


def fm_sine(n, fc, fm, index, phase=0.0, start=0):
    """Closed-form FM: sin(wc t + I sin(wm t)). `index` is a float or list."""
    wc = TAU * fc / SR
    wm = TAU * fm / SR
    s = math.sin
    if isinstance(index, (int, float)):
        return [s(wc * (i + start) + phase + index * s(wm * (i + start))) for i in range(n)]
    return [s(wc * (i + start) + phase + index[i] * s(wm * (i + start))) for i in range(n)]


def make_table(harmonics, size=8192):
    """One-cycle wavetable from [(harmonic_number, amplitude), ...]."""
    t = [0.0] * size
    for h, a in harmonics:
        w = TAU * h / size
        for i in range(size):
            t[i] += a * math.sin(w * i)
    peak = max(abs(v) for v in t) or 1.0
    return [v / peak for v in t]


def saw_table(nharm=24, tilt=1.0, size=8192):
    """Band-limited saw (harmonic amplitude 1/h^tilt)."""
    return make_table([(h, ((-1) ** (h + 1)) / (h ** tilt)) for h in range(1, nharm + 1)], size)


def square_table(nharm=15, size=8192):
    return make_table([(h, 1.0 / h) for h in range(1, nharm + 1, 2)], size)


def wt_osc(n, freq, table, phase=0.0, start=0):
    """Fixed-frequency wavetable oscillator indexed by absolute time
    (start + i) so it is exactly periodic when freq is quantised."""
    size = len(table)
    inc = freq / SR
    p0 = phase / TAU
    out = [0.0] * n
    for i in range(n):
        x = p0 + inc * (i + start)
        out[i] = table[int((x - math.floor(x)) * size) % size]
    return out


def sweep(n, f0, f1, curve="exp", power=1.0):
    """Per-sample frequency list gliding from f0 to f1."""
    if n <= 1:
        return [f0] * n
    out = [0.0] * n
    if curve == "exp":
        r = math.log(f1 / f0)
        for i in range(n):
            out[i] = f0 * math.exp(r * (i / (n - 1)) ** power)
    else:
        for i in range(n):
            out[i] = f0 + (f1 - f0) * (i / (n - 1)) ** power
    return out


def lfo(n, cycles, period, phase=0.0, start=0):
    """Sine LFO that makes exactly `cycles` cycles per `period` samples."""
    w = TAU * cycles / period
    s = math.sin
    return [s(w * (i + start) + phase) for i in range(n)]


def smooth_random(n, rate_hz, rng, period=None, lo=-1.0, hi=1.0):
    """Smooth random control signal (cosine-interpolated random points).
    With `period`, the curve repeats every `period` samples."""
    if period is not None:
        k = max(2, int(round(period * rate_hz / SR)))
        pts = [rng.uniform(lo, hi) for _ in range(k)]
        step = period / k
        out = [0.0] * n
        for i in range(n):
            pos = (i % period) / step
            j = int(pos)
            f = pos - j
            a = pts[j % k]
            b = pts[(j + 1) % k]
            m = (1.0 - math.cos(math.pi * f)) * 0.5
            out[i] = a + (b - a) * m
        return out
    step = SR / rate_hz
    k = int(n / step) + 3
    pts = [rng.uniform(lo, hi) for _ in range(k)]
    out = [0.0] * n
    for i in range(n):
        pos = i / step
        j = int(pos)
        f = pos - j
        m = (1.0 - math.cos(math.pi * f)) * 0.5
        out[i] = pts[j] + (pts[j + 1] - pts[j]) * m
    return out


# -------------------------------------------------------------- envelopes --
def env_points(n, pts, power=1.0):
    """Piecewise envelope from [(time_s, value), ...]; `power` bends segments."""
    out = [0.0] * n
    pts = sorted(pts)
    for i in range(n):
        t = i / SR
        if t <= pts[0][0]:
            out[i] = pts[0][1]
            continue
        if t >= pts[-1][0]:
            out[i] = pts[-1][1]
            continue
        for j in range(len(pts) - 1):
            t0, v0 = pts[j]
            t1, v1 = pts[j + 1]
            if t0 <= t <= t1:
                f = (t - t0) / (t1 - t0) if t1 > t0 else 1.0
                if power != 1.0:
                    f = f ** power
                out[i] = v0 + (v1 - v0) * f
                break
    return out


def env_perc(n, attack, t60, delay=0.0, hold=0.0):
    """Linear attack, optional hold, exponential decay (t60 = time to -60 dB)."""
    out = [0.0] * n
    d = ns(delay)
    a = max(1, ns(attack))
    h = ns(hold)
    k = LN1000 / (t60 * SR)
    for i in range(d, n):
        j = i - d
        if j < a:
            out[i] = j / a
        elif j < a + h:
            out[i] = 1.0
        else:
            out[i] = math.exp(-k * (j - a - h))
    return out


def fade_in(x, seconds):
    m = min(len(x), max(1, ns(seconds)))
    for i in range(m):
        x[i] *= i / m
    return x


def fade_out(x, seconds):
    m = min(len(x), max(1, ns(seconds)))
    n = len(x)
    for i in range(m):
        # raised cosine tail
        x[n - m + i] *= 0.5 * (1.0 + math.cos(math.pi * (i + 1) / m))
    return x


# ---------------------------------------------------------------- algebra --
def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def scale(x, g):
    return [v * g for v in x]


def add_into(dst, src, gain=1.0, offset=0):
    """dst[offset + i] += gain * src[i] (clipped to dst length)."""
    n = min(len(src), len(dst) - offset)
    if offset < 0:
        src = src[-offset:]
        n = min(len(src), len(dst))
        offset = 0
    for i in range(n):
        dst[offset + i] += gain * src[i]
    return dst


def rms(x):
    if not x:
        return 0.0
    return math.sqrt(sum(v * v for v in x) / len(x))


def peak(x):
    return max((abs(v) for v in x), default=0.0)


def db(v):
    return 20.0 * math.log10(max(v, 1e-12))


def undb(d):
    return 10.0 ** (d / 20.0)


def at_rms(x, rms_db):
    """Scale so the RMS equals rms_db dBFS (used to balance layers)."""
    r = rms(x)
    return scale(x, undb(rms_db) / r) if r > 0 else x


def at_peak(x, peak_db):
    p = peak(x)
    return scale(x, undb(peak_db) / p) if p > 0 else x


def saturate(x, drive=1.5):
    """tanh soft clip, gain-compensated for small signals."""
    t = math.tanh
    g = 1.0 / t(drive)
    return [t(drive * v) * g for v in x]


def remove_dc(x):
    m = sum(x) / len(x)
    return [v - m for v in x]


def pan_gains(p):
    """Equal-power pan, p in -1..1 -> (gain_l, gain_r)."""
    a = (p + 1.0) * math.pi / 4.0
    return math.cos(a), math.sin(a)


# ---------------------------------------------------------------- filters --
def biquad_coefs(kind, f, q=0.7071, gain_db=0.0):
    """RBJ cookbook biquads, normalised (b0, b1, b2, a1, a2)."""
    f = min(max(f, 5.0), SR * 0.49)
    w0 = TAU * f / SR
    cw = math.cos(w0)
    sw = math.sin(w0)
    alpha = sw / (2.0 * q)
    A = 10.0 ** (gain_db / 40.0)
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    elif kind == "bp":  # constant 0 dB peak gain
        b0, b1, b2 = alpha, 0.0, -alpha
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    elif kind == "notch":
        b0, b1, b2 = 1.0, -2 * cw, 1.0
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    elif kind == "peak":
        b0, b1, b2 = 1 + alpha * A, -2 * cw, 1 - alpha * A
        a0, a1, a2 = 1 + alpha / A, -2 * cw, 1 - alpha / A
    elif kind == "lowshelf":
        sa = 2 * math.sqrt(A) * alpha
        b0 = A * ((A + 1) - (A - 1) * cw + sa)
        b1 = 2 * A * ((A - 1) - (A + 1) * cw)
        b2 = A * ((A + 1) - (A - 1) * cw - sa)
        a0 = (A + 1) + (A - 1) * cw + sa
        a1 = -2 * ((A - 1) + (A + 1) * cw)
        a2 = (A + 1) + (A - 1) * cw - sa
    elif kind == "highshelf":
        sa = 2 * math.sqrt(A) * alpha
        b0 = A * ((A + 1) + (A - 1) * cw + sa)
        b1 = -2 * A * ((A - 1) + (A + 1) * cw)
        b2 = A * ((A + 1) + (A - 1) * cw - sa)
        a0 = (A + 1) - (A - 1) * cw + sa
        a1 = 2 * ((A - 1) - (A + 1) * cw)
        a2 = (A + 1) - (A - 1) * cw - sa
    else:
        raise ValueError(kind)
    return b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0


def biquad(x, kind, f, q=0.7071, gain_db=0.0):
    """Static biquad, transposed direct form II."""
    b0, b1, b2, a1, a2 = biquad_coefs(kind, f, q, gain_db)
    y = [0.0] * len(x)
    z1 = z2 = 0.0
    for i, v in enumerate(x):
        o = b0 * v + z1
        z1 = b1 * v - a1 * o + z2
        z2 = b2 * v - a2 * o
        y[i] = o
    return y


def biquad_tv(x, kind, freqs, q=0.7071, gain_db=0.0, block=32):
    """Time-varying biquad; `freqs` is a per-sample cutoff list (or callable
    of the sample index). Coefficients are refreshed every `block` samples."""
    n = len(x)
    y = [0.0] * n
    z1 = z2 = 0.0
    get = freqs if callable(freqs) else (lambda i: freqs[i])
    for s0 in range(0, n, block):
        b0, b1, b2, a1, a2 = biquad_coefs(kind, get(s0), q, gain_db)
        for i in range(s0, min(n, s0 + block)):
            v = x[i]
            o = b0 * v + z1
            z1 = b1 * v - a1 * o + z2
            z2 = b2 * v - a2 * o
            y[i] = o
    return y


def onepole_lp(x, fc):
    k = 1.0 - math.exp(-TAU * fc / SR)
    y = [0.0] * len(x)
    s = 0.0
    for i, v in enumerate(x):
        s += k * (v - s)
        y[i] = s
    return y


def onepole_hp(x, fc):
    lp = onepole_lp(x, fc)
    return [a - b for a, b in zip(x, lp)]


def brown(n, rng, fc=60.0):
    """Brown-ish noise: white through a leaky integrator (one-pole LP).
    Linear time-invariant, so tiling white noise keeps it periodic."""
    return onepole_lp(white(n, rng), fc)


def comb_fb(x, delay_s, fb, damp_hz=None):
    """Feedback comb (optionally damped) - metallic/hollow resonance."""
    d = max(1, int(round(delay_s * SR)))
    buf = [0.0] * d
    y = [0.0] * len(x)
    k = 1.0 - math.exp(-TAU * damp_hz / SR) if damp_hz else 1.0
    s = 0.0
    j = 0
    for i, v in enumerate(x):
        o = buf[j]
        s += k * (o - s)
        out = v + fb * s
        buf[j] = out
        y[i] = out
        j += 1
        if j == d:
            j = 0
    return y


def resonator_bank(x, modes):
    """Sum of parallel band-passes [(freq, q, gain), ...] (struck/excited modes)."""
    out = [0.0] * len(x)
    for f, q, g in modes:
        if f >= SR * 0.45:
            continue
        add_into(out, biquad(x, "bp", f, q), g)
    return out


def delay(x, seconds, gain=1.0, extra=0):
    d = ns(seconds)
    return [0.0] * d + [v * gain for v in x] + [0.0] * extra


# ------------------------------------------------------- modal synthesis ---
# Mode frequency ratios.
PLATE = [1.0, 1.594, 2.136, 2.296, 2.653, 2.918, 3.156, 3.501, 3.600, 3.652,
         4.060, 4.154, 4.601, 4.831, 4.903, 5.131, 5.412, 5.976, 6.209, 6.746]
BAR = [1.0, 2.756, 5.404, 8.933, 13.344]          # free-free bar (clinks)
TUBE = [1.0, 2.32, 4.25, 6.63, 9.38, 12.4]        # pipe-like hull members


def decaying_sines(n, partials, out=None, offset=0):
    """Add a bank of exponentially decaying sines into `out`.
    partials: [(freq_hz, amp, t60_s, phase), ...]. Uses complex rotation per
    sample (cheap) and stops each partial once it is below -100 dB."""
    if out is None:
        out = [0.0] * n
    for f, a, t60, ph in partials:
        if f >= SR * 0.47 or a == 0.0:
            continue
        r = math.exp(-LN1000 / (t60 * SR))
        rot = complex(math.cos(TAU * f / SR), math.sin(TAU * f / SR)) * r
        z = complex(math.cos(ph), math.sin(ph)) * a
        length = min(len(out) - offset, int(t60 * SR * 1.7) + 1)
        for i in range(length):
            out[offset + i] += z.imag
            z *= rot
    return out


def metal_modes(rng, f0, ratios, t60, amp_tilt=0.7, decay_tilt=0.6,
                jitter=0.03, hardness_hz=6000.0, split=0.35, max_f=17000.0):
    """Build a randomised inharmonic partial set for a struck metal object.
    - amp_tilt: higher modes are weaker
    - decay_tilt: higher modes decay faster
    - hardness_hz: contact stiffness; softer hits excite fewer high modes
    - split: probability that a mode is a close doublet (beating shimmer)."""
    parts = []
    for r in ratios:
        r *= 1.0 + rng.uniform(-jitter, jitter)
        f = f0 * r
        if f > max_f:
            continue
        a = rng.uniform(0.35, 1.0) / (r ** amp_tilt)
        a /= 1.0 + (f / hardness_hz) ** 2
        t = t60 / (r ** decay_tilt) * rng.uniform(0.75, 1.25)
        ph = rng.uniform(0, TAU)
        parts.append((f, a, t, ph))
        if rng.random() < split:
            parts.append((f * (1.0 + rng.uniform(0.0015, 0.006)), a * rng.uniform(0.4, 0.9),
                          t * rng.uniform(0.8, 1.1), rng.uniform(0, TAU)))
    return parts


def noise_burst(n, rng, length_s, attack_s=0.0005, kind=None, f=None, q=0.7):
    """Short enveloped noise transient (contact / crack)."""
    m = max(2, ns(length_s))
    x = white(m, rng)
    e = env_perc(m, attack_s, length_s)
    x = mul(x, e)
    if kind:
        x = biquad(x, kind, f, q)
    out = [0.0] * n
    add_into(out, x)
    return out


def scatter_events(n, times_s, render, gains=None):
    """Mix rendered events (render(k) -> list) at given times."""
    out = [0.0] * n
    for k, t in enumerate(times_s):
        ev = render(k)
        add_into(out, ev, 1.0 if gains is None else gains[k], ns(t))
    return out


# ------------------------------------------------------------------ reverb --
def reverb(xl, xr=None, t60=2.0, size=1.0, damp_hz=5500.0, predelay=0.012, tail=0.0):
    """8-line feedback delay network (Hadamard mixing, damped loops, input
    diffusion). Returns WET (left, right) of length len(x) + tail seconds.
    Mono in -> decorrelated stereo out; average both for a mono result."""
    if xr is None:
        xr = xl
    extra = ns(tail)
    pd = ns(predelay)
    n = len(xl) + extra + pd
    inl = [0.0] * pd + list(xl) + [0.0] * extra
    inr = [0.0] * pd + list(xr) + [0.0] * extra

    # input diffusion: two short allpasses per channel
    def allpass(x, d, g):
        buf = [0.0] * d
        y = [0.0] * len(x)
        j = 0
        for i, v in enumerate(x):
            b = buf[j]
            w = v + g * b
            y[i] = b - g * w
            buf[j] = w
            j += 1
            if j == d:
                j = 0
        return y

    inl = allpass(allpass(inl, int(142 * size) + 1, 0.6), int(379 * size) + 1, 0.6)
    inr = allpass(allpass(inr, int(107 * size) + 1, 0.6), int(277 * size) + 1, 0.6)

    base = [1031, 1327, 1523, 1801, 2053, 2311, 2633, 2963]
    d = [max(8, int(b * size)) for b in base]
    g = [10.0 ** (-3.0 * di / (SR * t60)) for di in d]
    k = 1.0 - math.exp(-TAU * damp_hz / SR)
    b0, b1, b2, b3, b4, b5, b6, b7 = ([0.0] * di for di in d)
    d0, d1, d2, d3, d4, d5, d6, d7 = d
    g0, g1, g2, g3, g4, g5, g6, g7 = g
    i0 = i1 = i2 = i3 = i4 = i5 = i6 = i7 = 0
    s0 = s1 = s2 = s3 = s4 = s5 = s6 = s7 = 0.0
    yl = [0.0] * n
    yr = [0.0] * n
    h = 1.0 / math.sqrt(8.0)
    for i in range(n):
        o0 = b0[i0]; o1 = b1[i1]; o2 = b2[i2]; o3 = b3[i3]
        o4 = b4[i4]; o5 = b5[i5]; o6 = b6[i6]; o7 = b7[i7]
        s0 += k * (o0 - s0); s1 += k * (o1 - s1); s2 += k * (o2 - s2); s3 += k * (o3 - s3)
        s4 += k * (o4 - s4); s5 += k * (o5 - s5); s6 += k * (o6 - s6); s7 += k * (o7 - s7)
        a0 = s0 * g0; a1 = s1 * g1; a2 = s2 * g2; a3 = s3 * g3
        a4 = s4 * g4; a5 = s5 * g5; a6 = s6 * g6; a7 = s7 * g7
        # fast Walsh-Hadamard transform (orthogonal, lossless mixing)
        c0 = a0 + a1; c1 = a0 - a1; c2 = a2 + a3; c3 = a2 - a3
        c4 = a4 + a5; c5 = a4 - a5; c6 = a6 + a7; c7 = a6 - a7
        e0 = c0 + c2; e2 = c0 - c2; e1 = c1 + c3; e3 = c1 - c3
        e4 = c4 + c6; e6 = c4 - c6; e5 = c5 + c7; e7 = c5 - c7
        l = inl[i]
        r = inr[i]
        b0[i0] = (e0 + e4) * h + l
        b1[i1] = (e1 + e5) * h + r
        b2[i2] = (e2 + e6) * h + l
        b3[i3] = (e3 + e7) * h - r
        b4[i4] = (e0 - e4) * h - l
        b5[i5] = (e1 - e5) * h + r
        b6[i6] = (e2 - e6) * h - l
        b7[i7] = (e3 - e7) * h - r
        yl[i] = (o0 - o2 + o4 + o6) * 0.25
        yr[i] = (o1 + o3 - o5 + o7) * 0.25
        i0 += 1; i1 += 1; i2 += 1; i3 += 1; i4 += 1; i5 += 1; i6 += 1; i7 += 1
        if i0 == d0: i0 = 0
        if i1 == d1: i1 = 0
        if i2 == d2: i2 = 0
        if i3 == d3: i3 = 0
        if i4 == d4: i4 = 0
        if i5 == d5: i5 = 0
        if i6 == d6: i6 = 0
        if i7 == d7: i7 = 0
    return yl, yr


def reverb_mono(x, t60=1.5, size=1.0, damp_hz=5500.0, predelay=0.01, tail=0.0):
    yl, yr = reverb(x, None, t60, size, damp_hz, predelay, tail)
    return [(a + b) * 0.5 for a, b in zip(yl, yr)]


# --------------------------------------------------------------- WAV out ---
def write_wav(path, channels, loop=False):
    """16-bit PCM WAV. `channels` = [mono] or [left, right]. With loop=True a
    RIFF 'smpl' chunk marks the whole file as a forward loop so Godot's
    importer ("Detect From WAV") enables looping automatically."""
    nch = len(channels)
    n = min(len(c) for c in channels)
    pcm = array.array("h", [0] * (n * nch))
    for ci, c in enumerate(channels):
        for i in range(n):
            v = c[i]
            v = 1.0 if v > 1.0 else (-1.0 if v < -1.0 else v)
            pcm[i * nch + ci] = int(round(v * 32767.0))
    if pcm.itemsize != 2:
        raise RuntimeError("array('h') is not 16-bit")
    import sys
    if sys.byteorder != "little":
        pcm.byteswap()
    data = pcm.tobytes()
    fmt = struct.pack("<HHIIHH", 1, nch, SR, SR * nch * 2, nch * 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(data)) + data
    if len(data) % 2:
        chunks += b"\x00"
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        # cue id, type (0 = forward), start, end, fraction, play count.
        # The RIFF spec calls dwEnd inclusive (n - 1), but Godot's importer
        # copies it straight into AudioStreamWAV.loop_end, which is exclusive
        # (verified on 4.7: n - 1 would drop the last sample every cycle).
        # Godot is our only consumer, so write n for a sample-exact period.
        smpl += struct.pack("<6I", 0, 0, 0, n, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)
    return n


def read_wav(path):
    """Minimal reader for our own 16-bit PCM files -> (channels, sr, smpl_loop or None)."""
    with open(path, "rb") as fh:
        raw = fh.read()
    assert raw[:4] == b"RIFF" and raw[8:12] == b"WAVE", path
    pos = 12
    nch = sr = None
    data = None
    loop = None
    while pos + 8 <= len(raw):
        cid = raw[pos:pos + 4]
        size = struct.unpack("<I", raw[pos + 4:pos + 8])[0]
        body = raw[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            _, nch, sr = struct.unpack("<HHI", body[:8])
        elif cid == b"data":
            data = body
        elif cid == b"smpl":
            vals = struct.unpack("<15I", body[:60])
            loop = (vals[10], vals[11], vals[12])  # type, start, end
        pos += 8 + size + (size & 1)
    pcm = array.array("h")
    pcm.frombytes(data)
    chans = [[pcm[i] / 32768.0 for i in range(c, len(pcm), nch)] for c in range(nch)]
    return chans, sr, loop
