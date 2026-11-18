# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/sound_meter.py against reference tones:  python3 -m unittest discover -s tools"""

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sound_meter  # noqa: E402

RATE = 44100


def tone(freq: float, db: float, seconds: float, phase: float = 0.0) -> list[float]:
    amp = 10.0 ** (db / 20.0)
    return [amp * math.sin(2.0 * math.pi * freq * i / RATE + phase) for i in range(round(seconds * RATE))]


class MeterTest(unittest.TestCase):
    def test_a_full_scale_1k_tone_reads_minus_3_lufs(self) -> None:
        # BS.1770's own check: a 997 Hz sine at 0 dBFS in one channel is -3.01 LKFS.
        x = tone(997.0, 0.0, 2.0)
        self.assertAlmostEqual(sound_meter.integrated(x, RATE), -3.01, delta=0.05)
        self.assertAlmostEqual(sound_meter.momentary_max(x, RATE), -3.01, delta=0.05)

    def test_level_follows_the_tone(self) -> None:
        for db in (-10.0, -20.0, -40.0):
            self.assertAlmostEqual(sound_meter.integrated(tone(997.0, db, 1.0), RATE), db - 3.01, delta=0.05)

    def test_k_weighting_lifts_highs_and_cuts_lows(self) -> None:
        mid = sound_meter.integrated(tone(997.0, -20.0, 1.0), RATE)
        self.assertAlmostEqual(sound_meter.integrated(tone(4000.0, -20.0, 1.0), RATE) - mid, 3.4, delta=0.5)
        self.assertLess(sound_meter.integrated(tone(30.0, -20.0, 1.0), RATE) - mid, -1.0)

    def test_silence_around_a_tone_is_gated_out(self) -> None:
        x = [0.0] * RATE * 3 + tone(997.0, -20.0, 2.0) + [0.0] * RATE * 3
        # Ungated, 6 s of silence would pull it 6 dB down; gated, only the windows that straddle the
        # tone's ends (partly silent, yet within 10 LU) pull it down a little.
        self.assertAlmostEqual(sound_meter.integrated(x, RATE), -23.01, delta=0.8)
        self.assertEqual(sound_meter.integrated([0.0] * RATE, RATE), sound_meter.SILENCE)

    def test_a_quiet_passage_is_gated_relative_to_the_rest(self) -> None:
        # 2 s at -20 dBFS and 2 s at -40: the quiet part is 20 LU under, past the -10 LU gate, so it
        # is left out (ungated, the mean would be about 2.9 dB lower).
        x = tone(997.0, -20.0, 2.0) + tone(997.0, -40.0, 2.0)
        self.assertAlmostEqual(sound_meter.integrated(x, RATE), -23.01, delta=0.4)

    def test_a_sound_under_the_absolute_gate_reads_as_silence(self) -> None:
        self.assertEqual(sound_meter.integrated(tone(997.0, -75.0, 1.0), RATE), sound_meter.SILENCE)
        self.assertAlmostEqual(sound_meter.integrated(tone(997.0, -60.0, 1.0), RATE), -63.01, delta=0.1)

    def test_momentary_is_the_loudest_window(self) -> None:
        x = tone(997.0, -30.0, 2.0) + tone(997.0, -10.0, 0.5) + tone(997.0, -30.0, 2.0)
        self.assertAlmostEqual(sound_meter.momentary_max(x, RATE), -13.01, delta=0.1)

    def test_a_sound_shorter_than_a_window_is_measured_as_if_silence_followed(self) -> None:
        # 100 ms of tone in a 400 ms window is a quarter of the energy: 6 dB down.
        self.assertAlmostEqual(sound_meter.momentary_max(tone(997.0, -20.0, 0.1), RATE), -29.03, delta=0.1)

    def test_true_peak_finds_the_peak_between_samples(self) -> None:
        # A quarter-rate sine at 45 degrees: every sample is at 0.707 of the wave's peak.
        x = tone(RATE / 4.0, -6.0, 0.1, math.pi / 4.0)
        sample_peak = 20.0 * math.log10(max(abs(v) for v in x))
        self.assertAlmostEqual(sample_peak, -9.01, delta=0.05)
        self.assertAlmostEqual(sound_meter.true_peak(x), -6.0, delta=0.3)

    def test_true_peak_of_a_plain_tone(self) -> None:
        self.assertAlmostEqual(sound_meter.true_peak(tone(997.0, -12.0, 0.2)), -12.0, delta=0.1)
        self.assertEqual(sound_meter.true_peak([0.0] * 100), sound_meter.SILENCE)


if __name__ == "__main__":
    unittest.main()
