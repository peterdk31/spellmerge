# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Loudness and true peak of a mono buffer (sound plan AU2, docs/milestones/sound.md, section 6).

ITU-R BS.1770: K-weighting (a high shelf and a high pass, its coefficients worked out for the
buffer's own rate as libebur128 does), the loudness of a block -0.691 + 10 log10(mean square),
momentary loudness (the loudest 400 ms window, a window every 100 ms), integrated loudness (400 ms
blocks overlapping by 75%, gated at -70 LUFS and then 10 LU under the mean of what passed) and
true peak (4x oversampled by a windowed sinc). `above(x, rate, hz)` is the part of a buffer over a
frequency, for measuring how loud a sound's top is on its own (docs/STYLE.md, "Sound": the top). Standard library only; a buffer is a sequence of
floats, full scale 1.0.
"""

from __future__ import annotations

import math
from typing import Sequence

SILENCE = -120.0  # what a buffer with no sound in it measures, in LUFS or dBTP
ABSOLUTE_GATE = -70.0
RELATIVE_GATE = -10.0
OVERSAMPLE = 4
TAPS_PER_PHASE = 12


def _biquad(x: Sequence[float], b: tuple[float, float, float], a: tuple[float, float]) -> list[float]:
    b0, b1, b2 = b
    a1, a2 = a
    out = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, x0 in enumerate(x):
        y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out[i] = y0
        x2, x1, y2, y1 = x1, x0, y1, y0
    return out


def k_weight(x: Sequence[float], rate: int) -> list[float]:
    """The buffer through BS.1770's two filters, for any sample rate."""
    # Stage 1: the head's high shelf, +4 dB above about 1.7 kHz.
    gain, q, fc = 3.999843853973347, 0.7071752369554196, 1681.974450955533
    k = math.tan(math.pi * fc / rate)
    vh = 10.0 ** (gain / 20.0)
    vb = vh ** 0.4996667741545416
    a0 = 1.0 + k / q + k * k
    shelf = _biquad(x, ((vh + vb * k / q + k * k) / a0, 2.0 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0),
                    (2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0))
    # Stage 2: the RLB high pass at about 38 Hz.
    q, fc = 0.5003270373238773, 38.13547087602444
    k = math.tan(math.pi * fc / rate)
    a0 = 1.0 + k / q + k * k
    return _biquad(shelf, (1.0, -2.0, 1.0), (2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0))


def above(x: Sequence[float], rate: int, hz: float) -> list[float]:
    """The buffer's part above `hz`: a fourth-order Butterworth high pass (24 dB an octave), so
    what is well under `hz` counts for nothing and what is over it is whole."""
    out: Sequence[float] = x
    k = math.tan(math.pi * hz / rate)
    for q in (0.5411961001461969, 1.3065629648763766):  # a Butterworth's two sections
        a0 = 1.0 + k / q + k * k
        out = _biquad(out, (1.0 / a0, -2.0 / a0, 1.0 / a0), (2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0))
    return list(out)


def _lufs(mean_square: float) -> float:
    return -0.691 + 10.0 * math.log10(mean_square) if mean_square > 0.0 else SILENCE


def _blocks(x: Sequence[float], rate: int, hop_seconds: float) -> list[float]:
    """The mean square of every 400 ms window of the K-weighted buffer, a window each hop; a
    buffer shorter than one window is measured as if silence followed it."""
    weighted = k_weight(x, rate)
    size = round(0.4 * rate)
    hop = max(1, round(hop_seconds * rate))
    squares = [0.0] * (len(weighted) + 1)
    total = 0.0
    for i, v in enumerate(weighted):
        total += v * v
        squares[i + 1] = total
    found: list[float] = []
    start = 0
    while True:
        end = min(start + size, len(weighted))
        found.append((squares[end] - squares[start]) / size)
        if start + size >= len(weighted):
            return found
        start += hop


def momentary_max(x: Sequence[float], rate: int) -> float:
    """The loudest momentary loudness (a 400 ms window, one every 100 ms), in LUFS."""
    return _lufs(max(_blocks(x, rate, 0.1)))


def integrated(x: Sequence[float], rate: int) -> float:
    """Gated integrated loudness, in LUFS."""
    blocks = [m for m in _blocks(x, rate, 0.1) if _lufs(m) > ABSOLUTE_GATE]
    if not blocks:
        return SILENCE
    gate = _lufs(sum(blocks) / len(blocks)) + RELATIVE_GATE
    kept = [m for m in blocks if _lufs(m) > gate]
    return _lufs(sum(kept) / len(kept))


def _phases() -> list[list[float]]:
    """The interpolating filter, a list of taps for each of the oversampled phases."""
    half = TAPS_PER_PHASE // 2
    phases: list[list[float]] = []
    for p in range(OVERSAMPLE):
        frac = p / OVERSAMPLE
        taps: list[float] = []
        for j in range(-half + 1, half + 1):
            t = j - frac  # where the tap's sample is, in input samples from the point made
            sinc = 1.0 if t == 0 else math.sin(math.pi * t) / (math.pi * t)
            window = 0.5 + 0.5 * math.cos(math.pi * t / half)  # Hann over the filter's span
            taps.append(sinc * window)
        phases.append(taps)
    return phases


_PHASES = _phases()


def true_peak(x: Sequence[float]) -> float:
    """The peak of the buffer oversampled four times, in dBTP (dB of full scale)."""
    half = TAPS_PER_PHASE // 2
    padded = [0.0] * half + list(x) + [0.0] * half
    peak = 0.0
    for taps in _PHASES[1:]:  # phase 0 is the samples themselves
        for i in range(len(x)):
            # The point a phase after input i; tap j pairs with input i + j - half + 1, which is
            # padded[i + j + 1].
            window = padded[i + 1:i + 1 + TAPS_PER_PHASE]
            v = sum(t * s for t, s in zip(taps, window))
            if abs(v) > peak:
                peak = abs(v)
    sample_peak = max((abs(v) for v in x), default=0.0)
    peak = max(peak, sample_peak)
    return 20.0 * math.log10(peak) if peak > 0.0 else SILENCE
