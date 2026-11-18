# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The synth's golden fingerprints (docs/milestones/sound.md, section 6):  python3 -m unittest discover -s tools

`GENERATOR` (tools/sound_synth.py) is raised by hand when a change to the synth changes what it
makes, and the hash test then names every sound to rebake. This test is what makes that hard to
forget: it renders a reference recipe for each source and shaper and compares each with a
fingerprint kept here (its RMS each 10 ms, to 0.001). A change that changes the sound fails it
until the fingerprints and GENERATOR are both updated:

    python3 tools/test_sound_golden.py --print      # the fingerprints as the synth makes them now

Only the synth's own numbers are compared, never encoded audio.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sound_synth  # noqa: E402

# The generator these fingerprints were made with.
FINGERPRINTED_WITH = 1
STEP = sound_synth.RATE // 100  # 10 ms


def ref(seconds: float, *layers: dict, kind: str = "sfx", fx: dict | None = None, vary: dict | None = None) -> dict:
    recipe = {"version": 1, "kind": kind, "family": "held" if kind == "held" else "combat", "seconds": seconds,
              "layers": list(layers), "notes": "a reference"}
    if fx:
        recipe["fx"] = fx
    if vary:
        recipe["vary"] = vary
    return recipe


# One reference a source and a shaper, each short.
REFERENCES = {
    "sine_adsr": ref(0.08, {"source": "sine", "pitch": 440,
                            "amp": {"attack": 0.01, "decay": 0.02, "sustain": 0.5, "release": 0.02}}),
    "triangle_perc": ref(0.08, {"source": "triangle", "pitch": {"from": 200, "to": 800},
                                "amp": {"attack": 0.005, "shape": "perc", "power": 2}}),
    "saw_lowpass_sweep": ref(0.08, {"source": "saw", "pitch": 110,
                                    "filter": {"type": "low", "from": 300, "to": 6000, "q": 2}}),
    "square_duty_highpass": ref(0.08, {"source": "square", "pitch": 220, "duty": 0.25,
                                       "filter": {"type": "high", "from": 1500, "curve": "linear", "to": 500}}),
    "noise_band_drive": ref(0.08, {"source": "noise", "drive": 4,
                                   "filter": {"type": "band", "from": 800, "to": 3000, "q": 4, "curve": "arch"}}),
    "noise_stepped_crush": ref(0.08, {"source": "noise", "color": "stepped", "pitch": 600, "crush": 4,
                                      "amp": {"shape": "arch"}}),
    "fm_index_swell": ref(0.08, {"source": "fm", "pitch": 300, "ratio": 1.41,
                                 "index": {"from": 4, "to": 0}, "amp": {"shape": "swell", "power": 0.5}}),
    "partials_start_length": ref(0.08, {"source": "partials", "pitch": 900, "start": 0.02, "length": 0.05,
                                        "partials": [{"ratio": 1, "decay": 0.05}, {"ratio": 2.76, "gain": -6, "decay": 0.03}]}),
    "reverb_lowpass_vary": ref(0.06, {"source": "sine", "pitch": 600, "length": 0.03},
                               fx={"reverb": {"mix": 0.5, "size": 0.3}, "lowpass": 2000},
                               vary={"pitch": 0.1, "time": 0.1, "seed": 7}),
    "held_fold": ref(0.08, {"source": "noise", "filter": {"type": "low", "from": 700}},
                     {"source": "sine", "pitch": 150, "gain": -6}, kind="held"),
}

FINGERPRINTS = {
    "sine_adsr": [0.417, 0.616, 0.44, 0.353, 0.357, 0.356, 0.266, 0.1],
    "triangle_perc": [0.412, 0.375, 0.274, 0.189, 0.111, 0.06, 0.022, 0.004],
    "saw_lowpass_sweep": [0.534, 0.738, 0.618, 0.592, 0.576, 0.568, 0.569, 0.552],
    "square_duty_highpass": [0.21, 0.275, 0.261, 0.276, 0.293, 0.355, 0.395, 0.37],
    "noise_band_drive": [0.229, 0.32, 0.406, 0.406, 0.405, 0.331, 0.453, 0.323],
    "noise_stepped_crush": [0.148, 0.216, 0.506, 0.591, 0.537, 0.5, 0.374, 0.155],
    "fm_index_swell": [0.175, 0.308, 0.387, 0.478, 0.508, 0.597, 0.65, 0.614],
    "partials_start_length": [0.0, 0.0, 0.364, 0.104, 0.026, 0.006, 0.002, 0.0],
    "reverb_lowpass_vary": [0.323, 0.344, 0.313, 0.054, 0.161, 0.196, 0.258, 0.143, 0.206, 0.257, 0.222,
                            0.118, 0.043, 0.071, 0.043, 0.015, 0.022, 0.006, 0.002, 0.002, 0.0, 0.0],
    "held_fold": [0.496, 0.472, 0.366, 0.356, 0.346, 0.388, 0.413, 0.372],
}


def fingerprint(recipe: dict) -> list[float]:
    x = sound_synth.render(sound_synth.validate(recipe), 2)
    return [round((sum(v * v for v in x[i:i + STEP]) / len(x[i:i + STEP])) ** 0.5, 3) for i in range(0, len(x), STEP)]


class GoldenTest(unittest.TestCase):
    def test_every_reference_renders_as_fingerprinted(self) -> None:
        self.assertEqual(set(FINGERPRINTS), set(REFERENCES), "a fingerprint for every reference")
        for name, recipe in REFERENCES.items():
            self.assertEqual(fingerprint(recipe), FINGERPRINTS[name],
                             f"{name}: the synth sounds different. If that is meant, raise GENERATOR in "
                             "tools/sound_synth.py, then update FINGERPRINTS and FINGERPRINTED_WITH here "
                             "(python3 tools/test_sound_golden.py --print) and rebake what the hash test names")

    def test_the_fingerprints_are_of_this_generator(self) -> None:
        self.assertEqual(FINGERPRINTED_WITH, sound_synth.GENERATOR,
                         "GENERATOR was raised: update the fingerprints with it (--print)")


if __name__ == "__main__":
    if "--print" in sys.argv:
        print("FINGERPRINTS = {")
        for key, value in REFERENCES.items():
            print(f'    "{key}": {fingerprint(value)},')
        print("}")
    else:
        unittest.main()
