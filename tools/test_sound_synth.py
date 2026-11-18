# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/sound_synth.py:  python3 -m unittest discover -s tools

Its golden examples are the AU1 interview's three modern-synth samples, remade as recipes
(docs/milestones/sound.md, AU2); they are dicts here because tools/ takes no `.json`.
"""

import copy
import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sound  # noqa: E402
import sound_meter  # noqa: E402
import sound_synth  # noqa: E402
from sound_synth import RATE, SoundError  # noqa: E402

# The three samples the owner chose (2026-11-18): a cast, a fire hit and a glassy reaction ping.
# They are brighter than the game's sounds became after the owner's first
# listen (docs/STYLE.md, "Sound": deep, never piercing); as the synth's samples and the sound
# room's fixtures they stay as they were, each under a ceiling of its own (`top`).
SAMPLES = {
    "whoosh": {
        "version": 1, "kind": "sfx", "family": "combat", "seconds": 0.4, "variants": 4, "top": 0.0,
        "vary": {"pitch": 0.06, "time": 0.08, "seed": 1},
        "layers": [
            {"source": "noise", "filter": {"type": "band", "from": 600, "to": 4100, "q": 3, "curve": "arch"},
             "amp": {"attack": 0.0, "shape": "arch", "power": 1.5}},
            {"source": "noise", "filter": {"type": "low", "from": 900, "to": 2400, "curve": "arch", "q": 0.7},
             "amp": {"shape": "arch", "power": 2.0}, "gain": -8},
            {"source": "fm", "pitch": {"from": 500, "to": 1300}, "ratio": 3.5, "index": {"from": 2.5, "to": 0.4},
             "amp": {"attack": 0.05, "shape": "arch", "power": 2.0}, "gain": -16},
        ],
        "fx": {"reverb": {"mix": 0.35, "size": 1.2}},
        "notes": "A wizard releasing a spell: a soft filtered-noise whoosh with an FM shimmer, heard every cast from four players.",
    },
    "fire_hit": {
        "version": 1, "kind": "sfx", "family": "combat", "seconds": 0.6, "variants": 4, "top": 0.0,
        "vary": {"pitch": 0.05, "time": 0.1, "seed": 2},
        "layers": [
            {"source": "sine", "pitch": {"from": 150, "to": 45}, "length": 0.25, "drive": 1.5, "gain": -6,
             "amp": {"attack": 0.002, "shape": "perc", "power": 2.5}},
            {"source": "noise", "filter": {"type": "band", "from": 1100, "to": 380, "q": 1.4},
             "amp": {"attack": 0.015, "shape": "perc", "power": 1.6}, "drive": 2.0},
            {"source": "noise", "color": "stepped", "pitch": {"from": 90, "to": 25},
             "filter": {"type": "band", "from": 3200, "q": 0.9},
             "amp": {"attack": 0.02, "shape": "perc", "power": 1.2}, "gain": -6},
        ],
        "fx": {"reverb": {"mix": 0.2, "size": 0.8}},
        "notes": "Fire striking: a low thump under a roaring band of noise that falls, and crackles that thin out.",
    },
    "glass_ping": {
        "version": 1, "kind": "sfx", "family": "big", "seconds": 1.2, "variants": 3, "top": 0.0,
        "vary": {"pitch": 0.03, "time": 0.05, "seed": 3},
        "layers": [
            {"source": "partials", "pitch": 1180,
             "partials": [{"ratio": 1, "gain": 0, "decay": 1.1}, {"ratio": 2.76, "gain": -5, "decay": 0.8},
                          {"ratio": 5.4, "gain": -10, "decay": 0.45}, {"ratio": 8.9, "gain": -15, "decay": 0.25}],
             "amp": {"attack": 0.001}},
            {"source": "noise", "filter": {"type": "high", "from": 5000, "q": 0.7}, "length": 0.015,
             "amp": {"shape": "perc", "power": 2}, "gain": -14},
        ],
        "fx": {"reverb": {"mix": 0.3, "size": 1.5}},
        "notes": "A glassy reaction ping: a struck bell of inharmonic partials 1, 2.76, 5.4 and 8.9 ringing in a small room.",
    },
}

HELD = {"version": 1, "kind": "held", "family": "held", "seconds": 1.0,
        "layers": [{"source": "noise", "filter": {"type": "band", "from": 500, "q": 2}},
                   {"source": "sine", "pitch": 110, "gain": -10}],
        "fx": {"reverb": {"mix": 0.2, "size": 0.6}},
        "notes": "A low hum over breathing noise, looped."}


def spectrum_peak(x: list[float], low: float, high: float, step: float = 5.0) -> float:
    """The frequency between low and high where `x` is strongest (a plain DFT, Hz)."""
    best, at = -1.0, low
    f = low
    while f <= high:
        re = sum(v * math.cos(2 * math.pi * f * i / RATE) for i, v in enumerate(x))
        im = sum(v * math.sin(2 * math.pi * f * i / RATE) for i, v in enumerate(x))
        if re * re + im * im > best:
            best, at = re * re + im * im, f
        f += step
    return at


class SamplesTest(unittest.TestCase):
    """The three samples bake: each variant on its family's level, under its peak, silent at
    both ends, and unlike the others."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.families = sound.families()
        cls.rendered: dict[str, list[tuple[list[float], float, float]]] = {}
        for name, recipe in SAMPLES.items():
            data = sound_synth.validate(recipe)
            cls.rendered[name] = sound.render_placed(sound.Recipe(Path(f"{name}/{name}.sound.json"), name, recipe),
                                                     data, cls.families[recipe["family"]])

    def test_each_sample_bakes_within_its_family(self) -> None:
        for name, variants in self.rendered.items():
            family = self.families[SAMPLES[name]["family"]]
            self.assertEqual(len(variants), SAMPLES[name]["variants"])
            for samples, level, peak in variants:
                self.assertAlmostEqual(level, family.loudness, delta=sound.WINDOW, msg=name)
                self.assertLessEqual(peak, family.peak - sound.PEAK_MARGIN, name)
                self.assertLess(abs(samples[0]), sound.EDGE, name)
                self.assertLess(abs(samples[-1]), sound.EDGE, name)

    def test_variants_differ(self) -> None:
        for name, variants in self.rendered.items():
            first = variants[0][0]
            for other, _, _ in variants[1:]:
                self.assertNotEqual(len(first) == len(other) and first == other, True, name)

    def test_the_glass_rings_on_its_inharmonic_partials(self) -> None:
        recipe = copy.deepcopy(SAMPLES["glass_ping"])
        recipe.pop("fx")
        recipe["layers"] = recipe["layers"][:1]
        recipe["vary"] = {"seed": 3}
        x = sound_synth.render(sound_synth.validate(recipe), 1)[:4096]
        for ratio in (1.0, 2.76, 5.4):
            want = 1180 * ratio
            self.assertAlmostEqual(spectrum_peak(x, want - 60, want + 60), want, delta=15)

    def test_the_fire_hit_is_a_thump_then_a_roar(self) -> None:
        samples = self.rendered["fire_hit"][0][0]
        thump = sound_meter.integrated(samples[: RATE // 20], RATE)  # its first 50 ms
        late = sound_meter.integrated(samples[RATE // 2: RATE // 2 + RATE // 20], RATE)
        self.assertGreater(thump, late + 10.0, "it strikes, then dies away")

    def test_the_whoosh_swells_and_falls(self) -> None:
        samples = self.rendered["whoosh"][0][0]
        tenth = RATE // 10
        rms = [math.sqrt(sum(v * v for v in samples[i:i + tenth]) / tenth) for i in range(0, 4 * tenth, tenth)]
        self.assertLess(rms[0], max(rms[1:3]), "it builds")
        self.assertLess(rms[3], max(rms[1:3]), "and falls away")


class RenderTest(unittest.TestCase):
    def test_the_same_recipe_and_variant_renders_the_same(self) -> None:
        data = sound_synth.validate(SAMPLES["fire_hit"])
        self.assertEqual(sound_synth.render(data, 2), sound_synth.render(data, 2))

    def test_every_layer_ramps_in_and_out(self) -> None:
        data = sound_synth.validate({"version": 1, "kind": "sfx", "family": "combat", "seconds": 0.1,
                                     "layers": [{"source": "square", "pitch": 300}], "notes": "a square"})
        x = sound_synth.render(data, 1)
        self.assertEqual(x[0], 0.0)
        self.assertEqual(x[-1], 0.0)
        ramp = round(sound_synth.RAMP * RATE)
        self.assertLess(max(abs(v) for v in x[: ramp // 2]), 0.6, "no full-scale step at the start")

    def test_a_held_loop_has_no_seam(self) -> None:
        x = sound_synth.render(sound_synth.validate(HELD), 1)
        self.assertEqual(len(x), round(HELD["seconds"] * RATE), "exactly its seconds")
        steps = sorted(abs(b - a) for a, b in zip(x, x[1:]))
        typical = steps[int(len(steps) * 0.99)]
        self.assertLessEqual(abs(x[0] - x[-1]), typical, "the end runs on into the start like any other step")
        self.assertGreater(abs(x[0]), sound.EDGE, "a loop does not fade to silence at its seam")

    def test_a_held_tone_keeps_its_level_through_the_fold(self) -> None:
        # Two tones that do not fit the loop in whole cycles as written: one would swell where the
        # tail is folded over the start, the other would cancel itself there.
        for pitch in (997.0, 101.25):
            recipe = {"version": 1, "kind": "held", "family": "held", "seconds": 2.0,
                      "layers": [{"source": "sine", "pitch": pitch}], "notes": "a tone"}
            x = sound_synth.render(sound_synth.validate(recipe), 1)
            window = RATE // 50
            peaks = [max(abs(v) for v in x[i:i + window]) for i in range(0, len(x) - window, window)]
            self.assertGreater(min(peaks), 0.97, pitch)
            self.assertLess(max(peaks), 1.03, pitch)
            self.assertLessEqual(abs(x[0] - x[-1]), 2 * math.pi * pitch / RATE * 1.05, "no step at the seam")

    def test_the_time_and_pitch_of_a_variant_stay_within_vary(self) -> None:
        recipe = SAMPLES["whoosh"]
        for i in range(1, 9):
            pitch, time, _ = sound_synth.variant_scales(recipe, i)
            self.assertLessEqual(abs(pitch - 1.0), recipe["vary"]["pitch"])
            self.assertLessEqual(abs(time - 1.0), recipe["vary"]["time"])

    def test_a_patch_is_merged_under_the_layer(self) -> None:
        patch = {"version": 1, "notes": "a shimmer", "layer": {"source": "fm", "ratio": 3.5, "index": 2,
                                                              "pitch": {"from": 400, "to": 900}, "gain": -10}}
        recipe = {"version": 1, "kind": "sfx", "family": "combat", "seconds": 0.2,
                  "layers": [{"patch": "shimmer", "pitch": {"to": 1300}, "gain": -16}], "notes": "x"}
        layer = sound_synth.validate(recipe, {"shimmer": patch})["layers"][0]
        self.assertEqual(layer["pitch"], {"from": 400, "to": 1300})
        self.assertEqual(layer["gain"], -16)
        self.assertEqual(layer["ratio"], 3.5)
        self.assertEqual(sound_synth.patches_named(recipe), ["shimmer"])


class ValidateTest(unittest.TestCase):
    def broken(self, change: dict, path: tuple = ()) -> SoundError:
        recipe = copy.deepcopy(SAMPLES["whoosh"])
        target = recipe
        for key in path:
            target = target[key]
        target.update(change)
        with self.assertRaises(SoundError) as caught:
            sound_synth.validate(recipe)
        return caught.exception

    def test_an_unknown_key_is_named_with_its_place(self) -> None:
        error = self.broken({"wobble": 3}, ("layers", 0))
        self.assertEqual(error.where, "layers[0].wobble")
        self.assertIn("unknown key", error.message)
        self.assertEqual(self.broken({"colour": "white"}).where, "colour")
        self.assertEqual(self.broken({"spin": 1}, ("fx", "reverb")).where, "fx.reverb.spin")

    def test_a_key_of_another_source_is_unknown(self) -> None:
        self.assertEqual(self.broken({"duty": 0.3}, ("layers", 0)).where, "layers[0].duty")

    def test_a_value_out_of_range_is_named(self) -> None:
        error = self.broken({"q": 300}, ("layers", 0, "filter"))
        self.assertEqual(error.where, "layers[0].filter.q")
        self.assertIn("out of range", error.message)
        self.assertEqual(self.broken({"variants": 2.5}).where, "variants")
        self.assertEqual(self.broken({"kind": "loop"}).where, "kind")

    def test_a_missing_key_or_patch_is_named(self) -> None:
        recipe = copy.deepcopy(SAMPLES["whoosh"])
        del recipe["notes"]
        with self.assertRaises(SoundError) as caught:
            sound_synth.validate(recipe)
        self.assertEqual(caught.exception.where, "notes")
        recipe = copy.deepcopy(SAMPLES["whoosh"])
        recipe["layers"].append({"patch": "nowhere"})
        with self.assertRaises(SoundError) as caught:
            sound_synth.validate(recipe)
        self.assertEqual(caught.exception.where, "layers[3].patch")
        recipe["layers"][3] = {"source": "fm", "pitch": 200}
        with self.assertRaises(SoundError) as caught:
            sound_synth.validate(recipe)
        self.assertEqual(caught.exception.where, "layers[3].ratio")

    def test_the_kinds_rules(self) -> None:
        held = copy.deepcopy(HELD)
        held["variants"] = 2
        with self.assertRaises(SoundError):
            sound_synth.validate(held)
        ui = {"version": 1, "kind": "ui", "family": "ui", "seconds": 0.3, "layers": [{"source": "sine", "pitch": 900}],
              "notes": "a tick"}
        with self.assertRaises(SoundError) as caught:
            sound_synth.validate(ui)
        self.assertEqual(caught.exception.where, "seconds")
        ui["seconds"] = 0.1
        ui["fx"] = {"reverb": {"mix": 0.1}}
        with self.assertRaises(SoundError) as caught:
            sound_synth.validate(ui)
        self.assertEqual(caught.exception.where, "fx.reverb")

    def test_white_noise_has_no_pitch_and_an_adsr_no_power(self) -> None:
        self.assertEqual(self.broken({"pitch": 400}, ("layers", 0)).where, "layers[0].pitch")
        self.assertEqual(self.broken({"amp": {"attack": 0.01, "sustain": 0.5, "power": 2}}, ("layers", 0)).where,
                         "layers[0].amp")

    def test_an_exp_curve_needs_positive_ends(self) -> None:
        self.assertEqual(self.broken({"index": {"from": 0, "to": 2, "curve": "exp"}}, ("layers", 2)).where,
                         "layers[2].index")


if __name__ == "__main__":
    unittest.main()
