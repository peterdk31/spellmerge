# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the sequencer (tools/sound_score.py) and the bake of a score (tools/sound.py; sound
plan AU7):  python3 -m unittest discover -s tools

Its scores are dicts here, short and fast; the bake writes WAV in place of Vorbis, so no test
needs ffmpeg.
"""

import json
import math
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sound  # noqa: E402
import sound_score  # noqa: E402
from sound_synth import RATE, SoundError  # noqa: E402

TONE = {"source": "sine", "amp": {"attack": 0.003, "shape": "perc", "power": 2}}
TICK = {"source": "noise", "filter": {"type": "high", "from": 4000}, "amp": {"shape": "perc", "power": 3}}


def score(**over: object) -> dict:
    """A short score: two bars of 4/4 at 240 (one second round), a tone and a tick."""
    base = {"version": 1, "tempo": 240, "beats": 4, "bars": 2,
            "instruments": {"tone": dict(TONE), "tick": dict(TICK)},
            "patterns": {"a": {"tone": "A4 . C5 . E5 - . .", "tick": "x x x x"},
                         "b": {"tone": "A4+C5+E5 - - - . . . ."}},
            "layers": [{"id": "low_layer", "play": ["a", "b"]}, {"id": "top_layer", "play": ["b", "a"], "gain": -6}],
            "notes": "a test score"}
    base.update(over)
    return base


def render(data: dict, index: int = 0) -> list[float]:
    return sound_score.render_layer(sound_score.validate(data), index)


def rms(x: list[float]) -> float:
    return math.sqrt(sum(v * v for v in x) / max(len(x), 1))


class NoteTest(unittest.TestCase):
    def test_notes_are_equal_tempered_from_a4(self) -> None:
        self.assertAlmostEqual(sound_score.hz("A4"), 440.0)
        self.assertAlmostEqual(sound_score.hz("C4"), 261.6256, places=3)
        self.assertAlmostEqual(sound_score.hz("A#3"), sound_score.hz("Bb3"))
        self.assertAlmostEqual(sound_score.hz("D2") * 4, sound_score.hz("D4"))

    def test_a_score_names_its_patches(self) -> None:
        data = score(instruments={"pad": {"patch": "warm"}, "tone": dict(TONE), "pad2": {"patch": "warm"}})
        self.assertEqual(sound_score.patches_named(data), ["warm"])


class ValidateTest(unittest.TestCase):
    def fails(self, data: dict, where: str, patches: dict | None = None) -> str:
        with self.assertRaises(SoundError) as caught:
            sound_score.validate(data, patches)
        self.assertEqual(caught.exception.where, where, str(caught.exception))
        return caught.exception.message

    def test_a_good_score_validates(self) -> None:
        self.assertEqual(len(sound_score.validate(score())["layers"]), 2)

    def test_an_unknown_key_is_named(self) -> None:
        self.fails(score(swing=0.2), "swing")
        self.fails(score(instruments={"tone": {**TONE, "wobble": 1}}, patterns={"a": {"tone": "A4"}},
                         layers=[{"id": "l", "play": ["a", "a"]}]), "instruments.tone.wobble")

    def test_a_pattern_names_only_its_instruments(self) -> None:
        self.assertIn("no instrument", self.fails(score(patterns={"a": {"harp": "A4"}, "b": {"tone": "A4"}}),
                                                  "patterns.a.harp"))

    def test_a_line_of_an_odd_count_of_steps_is_a_typo(self) -> None:
        self.assertIn("7 steps", self.fails(score(patterns={"a": {"tone": "A4 . . . . . ."}, "b": {"tone": "A4"}}),
                                            "patterns.a.tone"))

    def test_a_step_that_is_no_note_is_named(self) -> None:
        self.fails(score(patterns={"a": {"tone": "H4 . . ."}, "b": {"tone": "A4"}}), "patterns.a.tone")

    def test_a_layer_plays_one_pattern_a_bar(self) -> None:
        self.assertIn("2 patterns", self.fails(score(layers=[{"id": "l", "play": ["a"]}]), "layers[0].play"))
        self.fails(score(layers=[{"id": "l", "play": ["a", "c"]}]), "layers[0].play[1]")

    def test_layers_are_at_most_a_music_tracks(self) -> None:
        self.fails(score(layers=[{"id": f"l{i}", "play": ["a", "b"]} for i in range(5)]), "layers")
        self.fails(score(layers=[{"id": "l", "play": ["a", "b"]}, {"id": "l", "play": ["b", "a"]}]), "layers[1].id")

    def test_a_hold_needs_a_note_before_it(self) -> None:
        self.assertIn("holds no note", self.fails(score(patterns={"a": {"tone": "- A4"}, "b": {"tone": "A4"}}),
                                                   "patterns.a.tone"))
        self.fails(score(patterns={"a": {"tone": "A4 . - ."}, "b": {"tone": "A4"}}), "patterns.a.tone")

    def test_white_noise_takes_no_note_and_a_tone_needs_a_pitch_for_x(self) -> None:
        self.assertIn("no pitch", self.fails(score(patterns={"a": {"tick": "A4"}, "b": {"tone": "A4"}}),
                                             "patterns.a.tick"))
        self.assertIn("has none", self.fails(score(patterns={"a": {"tone": "x"}, "b": {"tone": "A4"}}),
                                             "patterns.a.tone"))

    def test_a_note_never_rings_longer_than_the_loop(self) -> None:
        self.assertIn("longer than the loop", self.fails(score(instruments={"tone": {**TONE, "ring": 3.0}, "tick": TICK}),
                                                         "layers[0]"))

    def test_a_note_is_in_the_synths_range_where_it_plays(self) -> None:
        self.fails(score(patterns={"a": {"tone": "C0"}, "b": {"tone": "A4"}}), "patterns.a.tone.pitch")
        kick = {"source": "sine", "pitch": {"from": 120, "to": 42}}
        self.fails(score(instruments={"tone": kick, "tick": TICK}, patterns={"a": {"tone": "C1"}, "b": {"tone": "x"}}),
                   "patterns.a.tone.pitch.to")

    def test_an_instrument_takes_no_start_or_length(self) -> None:
        for key in ("start", "length"):
            self.fails(score(instruments={"tone": {**TONE, key: 0.1}, "tick": TICK}), f"instruments.tone.{key}")

    def test_a_bad_play_entry_is_named(self) -> None:
        self.fails(score(layers=[{"id": "l", "play": [["a"], "b"]}]), "layers[0].play[0]")

    def test_the_layers_limit_is_a_music_tracks(self) -> None:
        text = (Path(__file__).resolve().parent.parent / "core/base/music_track.gd").read_text(encoding="utf-8")
        found = re.search(r"const LAYERS_MOST: int = (\d+)", text)
        self.assertIsNotNone(found)
        self.assertEqual(int(found.group(1)), sound_score.LAYERS_MOST)

    def test_a_layer_plays_a_note(self) -> None:
        self.assertIn("plays no note", self.fails(score(patterns={"a": {"tone": ". . . ."}, "b": {"tone": "."}}),
                                                  "layers[0].play"))

    def test_an_instruments_patch_is_merged_and_checked(self) -> None:
        patches = {"bell": {"version": 1, "layer": {"source": "sine", "amp": {"shape": "perc"}}, "notes": "a bell"}}
        data = sound_score.validate(score(instruments={"tone": {"patch": "bell", "gain": -3}, "tick": TICK}), patches)
        self.assertEqual(data["instruments"]["tone"]["layer"], {"source": "sine", "amp": {"shape": "perc"}, "gain": -3})
        self.fails(score(instruments={"tone": {"patch": "nope"}, "tick": TICK}), "instruments.tone.patch", patches)


class RenderTest(unittest.TestCase):
    def test_every_layer_is_exactly_its_bars_long(self) -> None:
        for tempo in (240, 97, 133.3):
            data = score(tempo=tempo)
            want = round(2 * 4 * 60.0 / tempo * RATE)
            layers = sound_score.render(sound_score.validate(data))
            self.assertEqual([len(x) for x in layers.values()], [want, want], f"tempo {tempo}")

    def test_the_loop_is_what_playing_it_round_and_round_sounds_like(self) -> None:
        # The tone rings past the loop's end; laid out three times round with no wrap, the middle
        # round is the steady state, which the loop must be.
        data = sound_score.validate(score(instruments={"tone": {**TONE, "ring": 0.6}, "tick": TICK}))
        loop = sound_score.render_layer(data, 0)
        n = len(loop)
        long = [0.0] * (3 * n)
        for event in sound_score._events(data, data["layers"][0]):
            inst = data["instruments"][event["inst"]]
            size = round((event["seconds"] + inst["ring"]) * RATE)
            for c, freq in enumerate(event["freqs"] or [None]):
                note = sound_score.sound_synth.render_layer(sound_score._note_layer(inst, freq), size, sound_score.zlib.crc32(
                    f"low_layer/{event['key']}/{c}".encode()))
                for rnd in range(3):
                    start = round(event["start"] * RATE) + rnd * n
                    for j, v in enumerate(note):
                        if start + j < len(long):
                            long[start + j] += v * event["level"]
        middle = long[n:2 * n]
        self.assertLess(max(abs(a - b) for a, b in zip(loop, middle)), 1e-9)
        # The room and the low pass too: the loop is the middle of the long layout through them,
        # up to the reverb's level, which is scaled to what it is run over.
        fx = {"reverb": {"mix": 0.4, "size": 0.6}, "lowpass": 5000}
        wet = sound_score.render_layer({**data, "fx": fx}, 0)
        steady = sound_score.sound_synth.apply_fx(long, fx)[n:2 * n]
        ratio = rms(wet) / rms(steady)
        self.assertLess(max(abs(a - b * ratio) for a, b in zip(wet, steady)), 0.01 * max(abs(v) for v in wet))

    def test_a_note_ringing_past_the_end_is_heard_at_the_start(self) -> None:
        data = score(bars=1, instruments={"tone": {**TONE, "ring": 0.3}, "tick": TICK},
                     patterns={"a": {"tone": ". . . . . . . A4"}}, layers=[{"id": "l", "play": ["a"]}])
        loop = render(data)
        self.assertGreater(rms(loop[: round(0.05 * RATE)]), 0.01, "the last step's note rings on at the start")

    def test_the_rooms_tail_at_the_end_is_heard_at_the_start(self) -> None:
        data = score(bars=1, patterns={"a": {"tone": ". . . . . . A4 ."}}, layers=[{"id": "l", "play": ["a"]}])
        dry = render(data)
        wet = render({**data, "fx": {"reverb": {"mix": 0.5, "size": 1.0}}})
        head = round(0.1 * RATE)
        self.assertLess(rms(dry[:head]), 1e-6)
        self.assertGreater(rms(wet[:head]), 1e-3)

    def test_the_seam_steps_no_more_than_the_loop_does_inside(self) -> None:
        data = score(fx={"reverb": {"mix": 0.3, "size": 0.8}, "lowpass": 6000})
        for i in (0, 1):
            loop = render(data, i)
            inside = max(abs(loop[j + 1] - loop[j]) for j in range(len(loop) - 1))
            self.assertLessEqual(abs(loop[0] - loop[-1]), inside)

    def test_a_hold_lengthens_its_note_across_a_bar(self) -> None:
        data = sound_score.validate(score(patterns={"a": {"tone": ". . . A4"}, "b": {"tone": "- - . ."}},
                                          layers=[{"id": "l", "play": ["a", "b"]}]))
        events = sound_score._events(data, data["layers"][0])
        self.assertEqual(len(events), 1)
        self.assertAlmostEqual(events[0]["seconds"], 0.75)

    def test_a_chord_plays_every_note_and_velocity_goes_round(self) -> None:
        data = sound_score.validate(score(instruments={"tone": dict(TONE), "tick": {**TICK, "velocity": [1, 0.5]}}))
        events = sound_score._events(data, data["layers"][0])
        self.assertEqual([round(e["level"], 2) for e in events if e["inst"] == "tick"], [1, 0.5, 1, 0.5])
        chord = [e for e in events if e["inst"] == "tone" and e["start"] >= 1.0 - 1e-9]
        self.assertEqual([len(e["freqs"]) for e in chord], [3])

    def test_a_layers_gain_sets_its_level_in_the_track(self) -> None:
        plain = score(layers=[{"id": "l", "play": ["a", "b"]}])
        quiet = score(layers=[{"id": "l", "play": ["a", "b"], "gain": -6}])
        self.assertAlmostEqual(20 * math.log10(rms(render(quiet)) / rms(render(plain))), -6.0, places=6)

    def test_the_same_score_renders_the_same(self) -> None:
        self.assertEqual(render(score()), render(score()))


class BakeScoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, True)
        (self.root / "docs").mkdir()
        shutil.copy(sound.ROOT / sound.STYLE, self.root / sound.STYLE)
        self.said: list[str] = []

    def write(self, data: dict, track: str = "tune") -> sound.Score:
        path = self.root / "audio/music" / track / f"{track}.score.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")
        return sound.read_score(path.relative_to(self.root), self.root)

    def bake(self, s: sound.Score) -> list[Path]:
        return sound.bake_score(s, self.root, sound.wav_bytes, say=self.said.append)

    def test_a_score_bakes_a_loop_a_layer_and_its_manifest(self) -> None:
        written = {p.as_posix() for p in self.bake(self.write(score()))}
        folder = "audio/music/tune"
        self.assertEqual(written, {f"{folder}/{i}.ogg" for i in ("low_layer", "top_layer")}
                         | {f"{folder}/{i}.ogg.import" for i in ("low_layer", "top_layer")} | {f"{folder}/assets.json"})
        self.assertIn("loop=true", (self.root / folder / "low_layer.ogg.import").read_text(encoding="utf-8"))
        entries = {e["path"]: e for e in json.loads((self.root / folder / "assets.json").read_text())["assets"]}
        entry = entries[f"{folder}/top_layer.ogg"]
        self.assertEqual({k: entry[k] for k in ("origin", "tier", "prompt")},
                         {"origin": "ai", "tier": "good", "prompt": f"{folder}/tune.score.json"})
        self.assertEqual(sound.check(self.root), [])
        self.assertEqual(self.bake(self.write(score())), [], "a rebake with the same audio writes nothing")

    def test_the_layers_together_are_on_the_music_target_and_keep_their_balance(self) -> None:
        s = self.write(score())
        data, family = sound.checked_score(s, {}, sound.families(self.root))
        placed = sound.render_score_placed(s, data, family)
        together = sound_score.mixed([x for _, x, _, _ in placed])
        self.assertAlmostEqual(family.level_of(together, loop=True), family.loudness, delta=0.05)
        raw = sound_score.render(data)
        self.assertAlmostEqual(rms(placed[1][1]) / rms(placed[0][1]), rms(raw["top_layer"]) / rms(raw["low_layer"]))
        self.assertEqual({len(x) for _, x, _, _ in placed}, {sound_score.loop_samples(data)})

    def test_a_changed_score_is_stale_until_it_is_baked(self) -> None:
        self.bake(self.write(score()))
        self.write(score(tempo=200))
        problems = sound.check(self.root)
        self.assertEqual(len(problems), 2)
        self.assertIn("stale", problems[0])
        self.assertIn("tools/sound.py bake audio/music/tune/tune.score.json", problems[0])

    def test_a_changed_patch_makes_its_score_stale(self) -> None:
        patch = self.root / "audio/patches/bell.patch.json"
        patch.parent.mkdir(parents=True)
        patch.write_text(json.dumps({"version": 1, "layer": {"source": "sine"}, "notes": "a bell"}), encoding="utf-8")
        self.bake(self.write(score(instruments={"tone": {"patch": "bell"}, "tick": TICK})))
        self.assertEqual(sound.check(self.root), [])
        patch.write_text(json.dumps({"version": 1, "layer": {"source": "triangle"}, "notes": "a bell"}), encoding="utf-8")
        self.assertIn("stale", "\n".join(sound.check(self.root)))

    def test_a_peak_at_any_intensity_fails_the_bake(self) -> None:
        # Placed 20 LU over the music target, the track peaks over its limit at intensity 1
        # already, which is named. (The bake checks every intensity, its first n layers together,
        # and each layer alone.)
        s = self.write(score(gain=20))
        checked, family = sound.checked_score(s, {}, sound.families(self.root))
        with self.assertRaises(sound.BakeError) as caught:
            sound.render_score_placed(s, checked, family)
        self.assertIn("its first layer peak", str(caught.exception))

    def test_a_layer_the_score_no_longer_has_is_named_and_removed(self) -> None:
        self.bake(self.write(score()))
        one = score(layers=[{"id": "low_layer", "play": ["a", "b"]}])
        self.write(one)
        self.assertIn("audio/music/tune/top_layer.ogg: no recipe or score makes it",
                      "\n".join(sound.check(self.root)))
        self.bake(self.write(one))
        self.assertFalse((self.root / "audio/music/tune/top_layer.ogg").exists())
        self.assertFalse((self.root / "audio/music/tune/top_layer.ogg.import").exists())
        self.assertEqual(sound.check(self.root), [])

    def test_a_score_outside_a_folder_of_its_own_is_refused(self) -> None:
        path = self.root / "audio/music/tune.score.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(score()), encoding="utf-8")
        with self.assertRaises(sound.BakeError):
            sound.read_score(path.relative_to(self.root), self.root)

    def test_a_score_is_found_by_its_track_a_layer_or_music(self) -> None:
        self.write(score())
        for name in ("tune", "top_layer", "music"):
            self.assertEqual([s.id for s in sound.resolve([name], self.root)], ["tune"], name)

    def test_the_sheet_plays_each_intensity_round_twice(self) -> None:
        layers = [[0.1] * 100, [0.2] * 100]
        timeline = sound.music_timeline(layers)
        gap = round(sound.GAP * RATE)
        self.assertEqual(len(timeline), 2 * (200 + gap))
        self.assertAlmostEqual(timeline[0], 0.1)
        self.assertAlmostEqual(timeline[200 + gap], 0.3)


# The sequencer's fingerprint (its RMS each 10 ms, to 0.001) for a reference score: a change to the
# sequencer that changes what a score sounds like fails it until VERSION is raised and it is updated
# (python3 tools/test_sound_score.py --print).
FINGERPRINTED_WITH = 1
GOLDEN_SCORE = score(instruments={"tone": {**TONE, "ring": 0.2, "velocity": [1, 0.6]}, "tick": TICK,
                                  "kick": {"source": "sine", "pitch": {"from": 120, "to": 45}, "amp": {"shape": "perc"}}},
                     patterns={"a": {"tone": "A4 . C5+E5 - . . . G4", "tick": "x x x x", "kick": "x . C3 ."},
                               "b": {"tone": "- . E5 .", "kick": "x . . ."}},
                     layers=[{"id": "l", "play": ["a", "b"], "gain": -3}],
                     fx={"reverb": {"mix": 0.3, "size": 0.5}, "lowpass": 3000})
GOLDEN: list[float] = [
    0.456, 0.458, 0.43, 0.421, 0.398, 0.397, 0.334, 0.336, 0.368, 0.406, 0.381, 0.372, 0.316, 0.308, 0.266,
    0.24, 0.224, 0.243, 0.254, 0.289, 0.209, 0.193, 0.164, 0.17, 0.143, 0.42, 0.419, 0.478, 0.434, 0.408,
    0.503, 0.34, 0.317, 0.307, 0.214, 0.222, 0.164, 0.142, 0.172, 0.16, 0.136, 0.127, 0.11, 0.109, 0.112,
    0.096, 0.083, 0.085, 0.081, 0.08, 0.335, 0.338, 0.304, 0.345, 0.294, 0.286, 0.25, 0.238, 0.239, 0.239,
    0.188, 0.202, 0.227, 0.195, 0.192, 0.13, 0.097, 0.05, 0.04, 0.097, 0.092, 0.164, 0.086, 0.062, 0.05,
    0.072, 0.059, 0.034, 0.03, 0.031, 0.036, 0.033, 0.024, 0.023, 0.021, 0.015, 0.012, 0.116, 0.204, 0.197,
    0.194, 0.203, 0.226, 0.244, 0.26, 0.236, 0.242, 0.241, 0.242, 0.241, 0.366, 0.415, 0.394, 0.371, 0.359,
    0.335, 0.323, 0.298, 0.26, 0.299, 0.299, 0.28, 0.24, 0.211, 0.16, 0.131, 0.129, 0.18, 0.171, 0.216,
    0.16, 0.145, 0.111, 0.134, 0.087, 0.076, 0.063, 0.056, 0.055, 0.061, 0.047, 0.04, 0.036, 0.029, 0.028,
    0.03, 0.027, 0.024, 0.019, 0.018, 0.015, 0.014, 0.011, 0.01, 0.011, 0.007, 0.006, 0.005, 0.007, 0.006,
    0.303, 0.327, 0.303, 0.294, 0.303, 0.316, 0.269, 0.262, 0.236, 0.181, 0.137, 0.089, 0.091, 0.107, 0.099,
    0.08, 0.061, 0.061, 0.047, 0.028, 0.022, 0.021, 0.022, 0.025, 0.019, 0.015, 0.015, 0.012, 0.009, 0.011,
    0.014, 0.016, 0.016, 0.016, 0.017, 0.018, 0.018, 0.019, 0.019, 0.019, 0.019, 0.018, 0.017, 0.016, 0.014,
    0.013, 0.011, 0.009, 0.008, 0.007,
]


def fingerprint() -> list[float]:
    x = render(GOLDEN_SCORE)
    step = RATE // 100
    return [round(rms(x[i:i + step]), 3) for i in range(0, len(x), step)]


class GoldenTest(unittest.TestCase):
    def test_the_sequencer_sounds_as_it_did(self) -> None:
        self.assertEqual(sound_score.VERSION, FINGERPRINTED_WITH,
                         "VERSION was raised: update GOLDEN (--print) and FINGERPRINTED_WITH")
        self.assertEqual(fingerprint(), GOLDEN, "the sequencer's sound changed: raise VERSION in "
                                                "tools/sound_score.py, then update GOLDEN with --print")


if __name__ == "__main__":
    if "--print" in sys.argv:
        print(fingerprint())
    else:
        unittest.main()
