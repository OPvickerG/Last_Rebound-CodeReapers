"""
LAST REBOUND: procedural audio generator.

Every sound and every bar of music in the game is synthesized here from
sine waves and noise. Nothing is sampled, so there are no licensing questions.

    pip install numpy scipy
    python tools/make_audio.py          # writes into audio/
    (ffmpeg is used to encode the music to .ogg)

Key: D minor. Tempo: 80 BPM. Music loop: 16 bars = 48 s.
Progression: Dm | Bb | Gm | A  (4 bars each).
"""
import os
import subprocess
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve
from scipy.io import wavfile

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)

BPM = 80
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = 16
LOOP = BAR * BARS  # 48 s


# ---------------------------------------------------------------- helpers
def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def note(name):
    """'D4' -> Hz. Supports sharps (#) and flats (b)."""
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    n = names[name[0]]
    i = 1
    if name[i] == "#":
        n += 1; i += 1
    elif name[i] == "b":
        n -= 1; i += 1
    octave = int(name[i:])
    midi = 12 * (octave + 1) + n
    return 440.0 * 2 ** ((midi - 69) / 12)


def lp(x, hz, order=2):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def hp(x, hz, order=2):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def env(n, a, d, s, r, sustain_time):
    """ADSR envelope, times in seconds, returns array of length n."""
    out = np.zeros(n)
    A, D, R = int(a * SR), int(d * SR), int(r * SR)
    S_end = int((a + d + sustain_time) * SR)
    idx = 0
    seg = np.linspace(0, 1, max(A, 1)); out[idx:idx + len(seg)] = seg[: n - idx]; idx += len(seg)
    if idx < n:
        seg = np.linspace(1, s, max(D, 1)); k = min(len(seg), n - idx); out[idx:idx + k] = seg[:k]; idx += k
    if idx < n:
        k = max(0, min(S_end, n) - idx); out[idx:idx + k] = s; idx += k
    if idx < n:
        seg = np.linspace(s, 0, max(R, 1)); k = min(len(seg), n - idx); out[idx:idx + k] = seg[:k]; idx += k
    return out


def saw(f, t, detune_cents=0.0, max_h=None):
    """Band-limited sawtooth (additive)."""
    f = f * 2 ** (detune_cents / 1200)
    nh = int(min(max_h or 60, 9000 / f))
    phase = rng.uniform(0, 2 * np.pi)
    out = np.zeros_like(t)
    for k in range(1, nh + 1):
        out += np.sin(2 * np.pi * k * f * t + phase * k) / k
    return out * 0.55


def reverb_ir(seconds, damp_hz=5000, seed=1):
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    tt = np.arange(n) / SR
    decay = np.exp(-tt * (6.9 / seconds))
    left = lp(r.standard_normal(n), damp_hz) * decay
    right = lp(r.standard_normal(n), damp_hz) * decay
    pre = int(0.012 * SR)
    left[:pre] = 0; right[:pre] = 0
    return left / np.abs(left).sum() ** 0.5, right / np.abs(right).sum() ** 0.5


IR_HALL = reverb_ir(4.5, 4500, 1)
IR_ROOM = reverb_ir(1.6, 6000, 2)


def reverb(x, ir, mix):
    """x mono or (n,2). Returns stereo (n + len(ir) - 1, 2)."""
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    wet_l = fftconvolve(x[:, 0], ir[0])
    wet_r = fftconvolve(x[:, 1], ir[1])
    wet = np.stack([wet_l, wet_r], axis=1)
    wet *= np.abs(x).max() / (np.abs(wet).max() + 1e-9)
    dry = np.zeros_like(wet); dry[: len(x)] = x
    return dry * (1 - mix) + wet * mix


def stereo(x, pan=0.0):
    l = np.cos((pan + 1) * np.pi / 4); r = np.sin((pan + 1) * np.pi / 4)
    return np.stack([x * l, x * r], axis=1) * 1.414


def place(buf, x, start_s):
    i = int(start_s * SR)
    j = min(len(buf), i + len(x))
    if j > i:
        buf[i:j] += x[: j - i]


def fold_loop(x, length_s):
    """Make a seamless loop: wrap anything past the loop end back onto the start."""
    n = int(length_s * SR)
    out = x[:n].copy()
    tail = x[n:]
    while len(tail):
        k = min(n, len(tail))
        out[:k] += tail[:k]
        tail = tail[k:]
    return out


def normalize(x, peak_db=-1.0):
    peak = np.abs(x).max() + 1e-9
    return x * (10 ** (peak_db / 20) / peak)


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def write_wav(name, x, peak_db=-1.0):
    x = normalize(x, peak_db)
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    path = os.path.join(OUT, name + ".wav")
    wavfile.write(path, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    return path


def write_ogg(name, x, peak_db=-1.0, quality=6):
    wav = write_wav("_tmp_" + name, x, peak_db)
    ogg = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", str(quality), ogg], check=True)
    os.remove(wav)
    print("  ", name + ".ogg")


def fade_edges(x, fin=0.005, fout=0.05):
    a, b = int(fin * SR), int(fout * SR)
    x = x.copy()
    if a: x[:a] *= np.linspace(0, 1, a)[:, None] if x.ndim == 2 else np.linspace(0, 1, a)
    if b: x[-b:] *= np.linspace(1, 0, b)[:, None] if x.ndim == 2 else np.linspace(1, 0, b)
    return x


# ---------------------------------------------------------------- instruments
BELL_PARTIALS = [  # (ratio, amp, decay seconds): a church-bell spectrum
    (0.5, 0.55, 9.0),   # hum
    (1.0, 1.00, 6.0),   # prime / fundamental
    (1.183, 0.55, 4.0), # minor-third "tierce", the sad bell colour
    (1.506, 0.35, 3.0), # quint
    (2.0, 0.60, 2.6),   # nominal
    (2.514, 0.22, 1.8),
    (2.662, 0.18, 1.6),
    (3.011, 0.20, 1.2),
    (4.166, 0.12, 0.8),
    (5.433, 0.08, 0.5),
    (6.796, 0.05, 0.35),
]


def bell(freq, dur, brightness=1.0, strike=0.6):
    t = t_axis(dur)
    out = np.zeros_like(t)
    for ratio, amp, dec in BELL_PARTIALS:
        f = freq * ratio
        if f > 16000:
            continue
        a = amp * (brightness ** (ratio - 1) if ratio > 1 else 1.0)
        beat = 1 + 0.0009 * rng.uniform(-1, 1)  # slight beating between paired modes
        out += a * np.exp(-t / dec) * (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * beat * t + 1.0))
    n = int(0.03 * SR)
    click = hp(rng.standard_normal(n), 1500) * np.exp(-np.arange(n) / (0.004 * SR)) * strike
    out[:n] += click
    return out


def choir(freqs, t, attack=1.6):
    """Formant-filtered detuned saws: a wordless 'aah' choir pad."""
    raw = np.zeros_like(t)
    for f in freqs:
        for c in (-9, 0, 8):
            raw += saw(f, t, c, max_h=40)
    vib = 1 + 0.003 * np.sin(2 * np.pi * 5.1 * t)
    raw = raw * vib
    ah = bp(raw, 600, 850) * 1.0 + bp(raw, 1050, 1300) * 0.6 + bp(raw, 2500, 3000) * 0.25 + lp(raw, 400) * 0.5
    return ah


def taiko(dur=1.6, pitch=62.0, vel=1.0):
    t = t_axis(dur)
    f = pitch * (1 + 1.4 * np.exp(-t / 0.03))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.42)
    skin = lp(rng.standard_normal(len(t)), 1800) * np.exp(-t / 0.035) * 0.5
    return soft_clip((body + skin) * vel, 1.4)


def tick(vel=1.0):
    t = t_axis(0.12)
    return (np.sin(2 * np.pi * 2400 * t) * 0.6 + hp(rng.standard_normal(len(t)), 3000) * 0.4) * np.exp(-t / 0.012) * vel


def bowed(f, dur, vel=1.0):
    t = t_axis(dur)
    x = saw(f, t, 0, 30) + saw(f, t, 6, 30) * 0.7
    x = lp(x, min(3200, f * 6))
    e = env(len(t), 0.03, 0.12, 0.6, 0.18, max(0.0, dur - 0.33))
    return x * e * vel


# ---------------------------------------------------------------- sound effects
def make_sfx():
    print("SFX")
    # Gong / bell hit for the pads. Pitched in-game per pad (base note D4).
    g = bell(note("D4"), 4.0, brightness=0.9, strike=0.8)
    write_wav("bell_hit", fade_edges(reverb(g, IR_ROOM, 0.18)[: int(4.5 * SR)]), -1.5)

    # Great bell at the summit: D2, very long.
    gb = bell(note("D2"), 14.0, brightness=1.1, strike=1.0) + 0.6 * bell(note("D3"), 14.0, 0.9, 0.0)
    write_wav("great_bell", fade_edges(reverb(gb, IR_HALL, 0.35)[: int(16 * SR)], fout=1.0), -0.8)

    # Stone thud: hitting the spine or a beam.
    t = t_axis(0.5)
    f = 95 * (1 + 0.8 * np.exp(-t / 0.02))
    thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09) + lp(rng.standard_normal(len(t)), 900) * np.exp(-t / 0.03) * 0.8
    write_wav("stone_hit", fade_edges(reverb(thud, IR_ROOM, 0.15)[: int(0.9 * SR)]), -2)

    # Slam: falling whoosh.
    t = t_axis(0.55)
    n = rng.standard_normal(len(t))
    sweep = np.zeros_like(t)
    for k, (lo, hi) in enumerate([(2500, 4000), (1500, 2600), (900, 1600), (500, 1000)]):
        seg = bp(n, lo, hi) * np.exp(-((t - k * 0.11 - 0.06) ** 2) / 0.006)
        sweep += seg
    write_wav("slam", fade_edges(sweep), -3)

    # Brazier ignite (checkpoint): whoomph + crackle.
    t = t_axis(1.8)
    whoomph = lp(rng.standard_normal(len(t)), 420) * (np.exp(-t / 0.35) * (1 - np.exp(-t / 0.04)))
    crackle = np.zeros_like(t)
    for _ in range(70):
        st = rng.uniform(0.05, 1.7); amp = rng.uniform(0.1, 0.5) * np.exp(-st / 0.9)
        k = int(st * SR); m = int(0.006 * SR)
        crackle[k:k + m] += hp(rng.standard_normal(m), 2000) * np.exp(-np.arange(m) / (0.0015 * SR)) * amp
    ig = whoomph * 1.6 + crackle + 0.35 * bell(note("A4"), 1.8, 0.7, 0.0)
    write_wav("ignite", fade_edges(reverb(ig, IR_ROOM, 0.25)[: int(2.2 * SR)]), -2)

    # Respawn: a reversed bell swell.
    rb = bell(note("D5"), 1.6, 0.8, 0.0)[::-1]
    write_wav("respawn", fade_edges(reverb(rb, IR_ROOM, 0.3)[: int(2.0 * SR)]), -3)

    # Thunder x3.
    for i in range(3):
        dur = 7.0
        t = t_axis(dur)
        brown = np.cumsum(rng.standard_normal(len(t))); brown = hp(brown, 20); brown /= np.abs(brown).max()
        rumble = lp(brown, 160 + 60 * i) * (np.exp(-t / (1.6 + 0.4 * i)) * (1 - np.exp(-t / 0.08)))
        crack = np.zeros_like(t)
        for _ in range(5 + 2 * i):
            st = rng.uniform(0, 0.6) if _ < 3 else rng.uniform(0.3, 2.5)
            k = int(st * SR); m = int(0.25 * SR)
            crack[k:k + m] += lp(rng.standard_normal(m), 3500) * np.exp(-np.arange(m) / (0.05 * SR)) * rng.uniform(0.3, 1.0)
        th = soft_clip(rumble * 2.2 + crack * 0.6, 1.5)
        write_wav(f"thunder_{i + 1}", fade_edges(reverb(th, IR_HALL, 0.3)[: int(8 * SR)], fout=1.5), -1.5)

    # Collapse: rumble + cracks + debris.
    dur = 7.0
    t = t_axis(dur)
    brown = np.cumsum(rng.standard_normal(len(t))); brown = hp(brown, 18); brown /= np.abs(brown).max()
    rumble = lp(brown, 110) * np.clip(t / 0.4, 0, 1) * np.exp(-np.clip(t - 3.5, 0, None) / 1.3)
    debris = np.zeros_like(t)
    for _ in range(140):
        st = rng.uniform(0.1, 5.5); m = int(rng.uniform(0.02, 0.12) * SR); k = int(st * SR)
        if k + m < len(t):
            debris[k:k + m] += bp(rng.standard_normal(m), 300, rng.uniform(900, 3000)) * np.exp(-np.arange(m) / (0.02 * SR)) * rng.uniform(0.1, 0.6)
    crack = np.zeros_like(t)
    for st in (0.0, 0.35, 1.1):
        k = int(st * SR); m = int(0.4 * SR)
        crack[k:k + m] += lp(rng.standard_normal(m), 5000) * np.exp(-np.arange(m) / (0.06 * SR))
    col = soft_clip(rumble * 3.0 + debris + crack * 0.8, 1.6)
    write_wav("collapse", fade_edges(reverb(col, IR_HALL, 0.35)[: int(8.5 * SR)], fout=1.5), -1)

    # Title impact: sub drop + great bell + noise burst.
    dur = 6.0
    t = t_axis(dur)
    f = 48 * (1 + 2.5 * np.exp(-t / 0.08))
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 1.4)
    burst = lp(rng.standard_normal(len(t)), 2200) * np.exp(-t / 0.12)
    ti = soft_clip(sub * 1.6 + burst * 0.7, 1.3) + 0.8 * bell(note("D3"), dur, 1.0, 0.8)
    write_wav("title_hit", fade_edges(reverb(ti, IR_HALL, 0.4)[: int(7 * SR)], fout=1.2), -0.8)

    # Rain loop (8 s, seamless).
    dur = 8.0
    n = int(dur * SR)
    hiss = hp(rng.standard_normal(n + SR), 1200)
    hiss = lp(hiss, 9000) * 0.25
    drops = np.zeros(n + SR)
    for _ in range(2600):
        k = int(rng.uniform(0, n + SR - 400)); m = 300
        drops[k:k + m] += bp(rng.standard_normal(m), 1500, rng.uniform(3000, 8000)) * np.exp(-np.arange(m) / 40) * rng.uniform(0.05, 0.4)
    rain = hiss + drops
    rain = fold_loop(rain, dur)
    write_wav("rain_loop", stereo(rain, -0.2) * 0.6 + stereo(np.roll(rain, SR // 3), 0.2) * 0.6, -3)

    # Wind loop (10 s, seamless): band noise with slow sweeping centre.
    dur = 10.0
    n = int(dur * SR)
    w = rng.standard_normal(n)
    t = np.arange(n) / SR
    a = bp(w, 200, 700) * (0.6 + 0.4 * np.sin(2 * np.pi * t / dur))
    b = bp(w, 500, 1500) * (0.5 + 0.5 * np.sin(2 * np.pi * 2 * t / dur + 1.3))
    c = bp(w, 1200, 2600) * (0.4 + 0.4 * np.sin(2 * np.pi * 3 * t / dur + 2.1)) * 0.5
    wind = a + b + c
    write_wav("wind_loop", stereo(wind, 0), -3)


# ---------------------------------------------------------------- music
CHORDS = [  # (bass, voicing) per 4-bar block
    ("D2", ["D3", "F3", "A3", "D4"]),
    ("Bb1", ["D3", "F3", "Bb3", "D4"]),
    ("G1", ["D3", "G3", "Bb3", "D4"]),
    ("A1", ["C#3", "E3", "A3", "E4"]),
]
ARP = {  # string ostinato chord tones (8ths)
    0: ["D4", "A4", "F4", "A4", "D5", "A4", "F4", "A4"],
    1: ["D4", "Bb4", "F4", "Bb4", "D5", "Bb4", "F4", "Bb4"],
    2: ["D4", "Bb4", "G4", "Bb4", "D5", "Bb4", "G4", "Bb4"],
    3: ["C#4", "A4", "E4", "A4", "C#5", "A4", "E4", "G4"],
}


def music_drone():
    """Stem 0: low drone + choir. Always playing."""
    total = LOOP + 6
    t = t_axis(total)
    out = np.zeros((len(t), 2))
    # Drone on D, slowly breathing.
    d = (np.sin(2 * np.pi * note("D1") * t) + 0.5 * np.sin(2 * np.pi * note("A1") * t)) * (0.7 + 0.3 * np.sin(2 * np.pi * t / 12))
    d += lp(saw(note("D2"), t, 0, 20), 260) * 0.4
    out += stereo(d * 0.5, 0)
    # Choir chords, 4 bars each, overlapping crossfades.
    block = BAR * 4
    for i, (bass, voicing) in enumerate(CHORDS):
        start = i * block
        dur = block + 2.0
        tt = t_axis(dur)
        c = choir([note(v) for v in voicing], tt)
        c *= env(len(tt), 1.8, 0.5, 0.85, 2.0, dur - 4.3)
        bassline = lp(saw(note(bass), tt, 0, 20), 300) * env(len(tt), 0.6, 0.3, 0.8, 1.5, dur - 2.4) * 0.8
        place(out, stereo(c * 0.32, -0.25) + stereo(np.roll(c, 900) * 0.32, 0.25) + stereo(bassline, 0), start)
    wet = reverb(out, IR_HALL, 0.45)
    return fold_loop(wet, LOOP)


def music_pulse():
    """Stem 1: taiko + tower-clock ticks. Fades in as you climb."""
    total = LOOP + 6
    out = np.zeros((int(total * SR), 2))
    for bar in range(BARS):
        b0 = bar * BAR
        place(out, stereo(taiko(1.6, 58, 1.0), -0.1), b0)
        place(out, stereo(taiko(1.4, 66, 0.55), 0.15), b0 + BEAT * 1.5)
        place(out, stereo(taiko(1.6, 58, 0.85), -0.1), b0 + BEAT * 2)
        if bar % 4 == 3:  # fill
            for k, v in enumerate([0.5, 0.6, 0.75, 0.95]):
                place(out, stereo(taiko(1.0, 72 - k * 3, v), 0.2 - k * 0.1), b0 + BEAT * 3 + k * BEAT / 4)
        else:
            place(out, stereo(taiko(1.2, 70, 0.4), 0.2), b0 + BEAT * 3.5)
        for e in range(8):  # clock ticks on 8ths, alternating pan
            place(out, stereo(tick(0.22 if e % 2 else 0.32), -0.5 if e % 2 else 0.5), b0 + e * BEAT / 2)
    wet = reverb(out, IR_ROOM, 0.3)
    return fold_loop(wet, LOOP)


def music_strings():
    """Stem 2: driving string ostinato + high bell melody. Joins in the upper tower."""
    total = LOOP + 6
    out = np.zeros((int(total * SR), 2))
    for bar in range(BARS):
        block = bar // 4
        pattern = ARP[block]
        for e, n in enumerate(pattern):
            v = 0.9 if e % 4 == 0 else 0.6
            place(out, stereo(bowed(note(n), BEAT / 2 * 0.95, v), -0.3 + 0.6 * (e % 2)), bar * BAR + e * BEAT / 2)
        # Low cello on beat 1
        place(out, stereo(bowed(note(CHORDS[block][0].replace("1", "2")), BAR * 0.9, 0.7), 0), bar * BAR)
    # Bell melody over the top (one phrase per 4-bar block).
    melody = [
        [("A5", 0), ("F5", 1.5), ("E5", 2), ("D5", 3), ("A4", 6)],
        [("Bb5", 0), ("A5", 1.5), ("F5", 2), ("D5", 3), ("F5", 6)],
        [("G5", 0), ("F5", 1.5), ("D5", 2), ("Bb4", 3), ("D5", 6)],
        [("E5", 0), ("C#5", 1.5), ("A4", 2), ("E5", 4), ("A5", 6)],
    ]
    for block, phrase in enumerate(melody):
        for n, beat in phrase:
            place(out, stereo(bell(note(n), 3.0, 0.7, 0.4) * 0.28, 0.35), block * BAR * 4 + beat * BEAT)
    wet = reverb(out, IR_HALL, 0.3)
    return fold_loop(wet, LOOP)


def music_finale():
    """Dawn: the storm breaks. D major, not looping (~26 s)."""
    total = 30.0
    t = t_axis(total)
    out = np.zeros((len(t), 2))
    chords = [(0, ["D3", "F#3", "A3", "D4", "F#4"]), (8, ["D3", "G3", "B3", "D4", "G4"]), (14, ["D3", "F#3", "A3", "D4", "A4"])]
    for i, (start, voicing) in enumerate(chords):
        dur = (chords[i + 1][0] - start + 2.5) if i + 1 < len(chords) else 14.0
        tt = t_axis(dur)
        c = choir([note(v) for v in voicing], tt) * env(len(tt), 2.2, 0.5, 0.9, 3.0 if i < 2 else 6.0, max(0, dur - 5.7 if i < 2 else dur - 8.7))
        place(out, stereo(c * 0.3, -0.2) + stereo(np.roll(c, 1100) * 0.3, 0.2), start)
    # Warm low drone
    d = np.sin(2 * np.pi * note("D2") * t) * 0.35 * np.clip(t / 3, 0, 1) * np.clip((total - t) / 6, 0, 1)
    out += stereo(d, 0)
    # Rising small-bell arpeggio in D major.
    arp = ["D5", "F#5", "A5", "D6", "A5", "F#5", "A5", "D6", "E6", "F#6", "A6", "D7"]
    for k, n in enumerate(arp):
        place(out, stereo(bell(note(n), 4.0, 0.6, 0.3) * 0.22, -0.5 + k / len(arp)), 3.0 + k * 1.2)
    wet = reverb(out, IR_HALL, 0.5)[: int(total * SR)]
    return fade_edges(wet, 0.01, 4.0)


def make_music():
    print("MUSIC")
    stems = {"music_drone": music_drone(), "music_pulse": music_pulse(), "music_strings": music_strings()}
    # Normalize stems relative to each other so they mix well when all are on.
    levels = {"music_drone": -3.0, "music_pulse": -4.5, "music_strings": -5.0}
    for k, x in stems.items():
        write_ogg(k, x, levels[k])
    write_ogg("music_finale", music_finale(), -2.0)


if __name__ == "__main__":
    make_sfx()
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".wav"):
            print("  ", f)
    make_music()
    print("done")
