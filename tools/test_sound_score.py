# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the sequencer (tools/sound_score.py) and the bake of a score (tools/sound.py; sound
plan AU7):  python3 -m unittest discover -s tools

Its scores are dicts here, short and fast; the bake writes WAV in place of Vorbis, so no test
needs ffmpeg.
"""

import json
import math
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
GOLDEN_SCORE = score(bars=1, instruments={"tone": {**TONE, "ring": 0.2, "velocity": [1, 0.6]}, "tick": TICK},
                     patterns={"a": {"tone": "A4 . C5+E5 - . . . G4", "tick": "x x x x"}},
                     layers=[{"id": "l", "play": ["a"], "gain": -3}], fx={"reverb": {"mix": 0.3, "size": 0.5}})
GOLDEN: list[float] = [
    0.403, 0.377, 0.414, 0.287, 0.38, 0.265, 0.297, 0.234, 0.347, 0.277, 0.348, 0.229, 0.285, 0.23, 0.259,
    0.213, 0.222, 0.189, 0.207, 0.18, 0.174, 0.142, 0.142, 0.126, 0.12, 0.476, 0.47, 0.516, 0.458, 0.429,
    0.513, 0.36, 0.336, 0.319, 0.229, 0.236, 0.175, 0.152, 0.18, 0.164, 0.14, 0.132, 0.113, 0.113, 0.113,
    0.096, 0.085, 0.087, 0.08, 0.081, 0.244, 0.215, 0.198, 0.18, 0.161, 0.138, 0.127, 0.111, 0.098, 0.088,
    0.071, 0.066, 0.056, 0.046, 0.041, 0.033, 0.028, 0.028, 0.022, 0.018, 0.018, 0.014, 0.012, 0.012, 0.009,
    0.228, 0.207, 0.179, 0.172, 0.147, 0.136, 0.118, 0.103, 0.093, 0.075, 0.07, 0.056, 0.125, 0.202, 0.188,
    0.18, 0.182, 0.196, 0.207, 0.216, 0.188, 0.188, 0.181, 0.174, 0.168,
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
