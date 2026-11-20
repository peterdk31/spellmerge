# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/sound.py's bake, manifest writer and sheet:  python3 -m unittest discover -s tools

The bake is run on a repository of its own with an encoder that writes WAV, so no test needs
ffmpeg (tools/README.md).
"""

import json
import math
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sound  # noqa: E402
from sound_synth import RATE  # noqa: E402

BLIP = {"version": 1, "kind": "sfx", "family": "combat", "seconds": 0.05, "variants": 3,
        "vary": {"pitch": 0.02, "seed": 4},
        "layers": [{"source": "sine", "pitch": 600, "amp": {"shape": "arch"}}], "notes": "a blip"}
HUM = {"version": 1, "kind": "held", "family": "held", "seconds": 0.2,
       "layers": [{"source": "sine", "pitch": 100}, {"source": "noise", "filter": {"type": "low", "from": 400}, "gain": -12}],
       "notes": "a hum"}


def fake_encode(samples: list[float]) -> bytes:
    return sound.wav_bytes(samples)


class BakeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, True)
        (self.root / "docs").mkdir()
        shutil.copy(sound.ROOT / sound.STYLE, self.root / sound.STYLE)
        self.said: list[str] = []

    def write(self, recipe: dict, sound_id: str = "blip", top: str = "audio/sfx") -> sound.Recipe:
        path = self.root / top / sound_id / f"{sound_id}.sound.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(recipe), encoding="utf-8")
        return sound.read_recipe(path.relative_to(self.root), self.root)

    def bake(self, recipe: sound.Recipe) -> list[Path]:
        return sound.bake(recipe, self.root, fake_encode, say=self.said.append)

    def entries(self, folder: str) -> dict[str, dict]:
        data = json.loads((self.root / folder / "assets.json").read_text(encoding="utf-8"))
        return {e["path"]: e for e in data["assets"]}

    def test_a_one_shot_writes_its_variants_randomizer_and_manifest(self) -> None:
        written = self.bake(self.write(BLIP))
        folder = "audio/sfx/blip"
        self.assertEqual({p.as_posix() for p in written},
                         {f"{folder}/variants/{i}.ogg" for i in (1, 2, 3)} | {f"{folder}/assets.json", f"{folder}/blip.tres"})
        tres = (self.root / folder / "blip.tres").read_text(encoding="utf-8")
        self.assertIn('[gd_resource type="AudioStreamRandomizer" load_steps=4 format=3]', tres)
        self.assertIn(f'path="res://{folder}/variants/3.ogg" id="3"', tres)
        self.assertIn("random_pitch = 1.04", tres, "combat's ±4%, as a scale")
        self.assertIn("random_volume_offset_db = 1.5", tres)
        self.assertIn("streams_count = 3", tres)
        self.assertIn('stream_2/stream = ExtResource("3")', tres)
        entry = self.entries(folder)[f"{folder}/variants/2.ogg"]
        self.assertEqual({k: entry[k] for k in ("origin", "author", "license", "tier", "prompt")},
                         {"origin": "ai", "author": "Claude", "license": "CC-BY-SA-4.0", "tier": "good",
                          "prompt": f"{folder}/blip.sound.json"})
        self.assertEqual(entry["tool"], f"tools/sound.py (procedural synthesis, generator {sound.sound_synth.GENERATOR})")
        self.assertTrue(entry["recipe_hash"].startswith("sha256:"))
        self.assertAlmostEqual(entry["loudness"], -26.0, delta=1.0)
        self.assertLessEqual(entry["peak"], -4.0)
        self.assertFalse((self.root / folder / "variants/1.ogg.import").exists(), "Godot writes a one-shot's .import")

    def test_a_rebake_with_the_same_audio_writes_nothing(self) -> None:
        recipe = self.write(BLIP)
        self.bake(recipe)
        self.assertEqual(self.bake(recipe), [])

    def test_a_held_sound_is_one_looping_file(self) -> None:
        written = self.bake(self.write(HUM, "hum"))
        folder = "audio/sfx/hum"
        self.assertEqual({p.as_posix() for p in written}, {f"{folder}/hum.ogg", f"{folder}/hum.ogg.import", f"{folder}/assets.json"})
        self.assertIn("loop=true", (self.root / folder / "hum.ogg.import").read_text(encoding="utf-8"))
        self.assertFalse((self.root / folder / "hum.tres").exists())
        godot_own = '[remap]\nimporter="oggvorbisstr"\nuid="uid://x"\n[params]\nloop=true\nloop_offset=0\n'
        (self.root / folder / "hum.ogg.import").write_text(godot_own, encoding="utf-8")
        self.write(dict(HUM, seconds=0.3), "hum")
        self.bake(sound.read_recipe(Path(f"{folder}/hum.sound.json"), self.root))
        self.assertEqual((self.root / folder / "hum.ogg.import").read_text(encoding="utf-8"), godot_own,
                         "an existing .import is never rewritten")

    def test_a_promoted_sound_keeps_final_until_its_audio_changes(self) -> None:
        recipe = self.write(BLIP)
        self.bake(recipe)
        path = self.root / "audio/sfx/blip/assets.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        for entry in data["assets"]:
            entry["tier"] = "final"
        path.write_text(json.dumps(data), encoding="utf-8")
        self.bake(recipe)
        self.assertEqual({e["tier"] for e in self.entries("audio/sfx/blip").values()}, {"final"})
        self.bake(self.write(dict(BLIP, seconds=0.06)))
        self.assertEqual({e["tier"] for e in self.entries("audio/sfx/blip").values()}, {"good"})
        self.assertTrue(any("back to tier good" in s for s in self.said))

    def test_fewer_variants_remove_the_extra_files_and_entries(self) -> None:
        self.bake(self.write(BLIP))
        extra = self.root / "audio/sfx/blip/variants/3.ogg"
        Path(str(extra) + ".import").write_text("x", encoding="utf-8")
        self.bake(self.write(dict(BLIP, variants=2)))
        self.assertFalse(extra.exists())
        self.assertFalse(Path(str(extra) + ".import").exists())
        self.assertEqual(set(self.entries("audio/sfx/blip")), {f"audio/sfx/blip/variants/{i}.ogg" for i in (1, 2)})
        self.assertIn("streams_count = 2", (self.root / "audio/sfx/blip/blip.tres").read_text(encoding="utf-8"))

    def test_a_hand_written_entry_in_the_folder_is_kept(self) -> None:
        recipe = self.write(BLIP)
        self.bake(recipe)
        (self.root / "audio/sfx/blip/extra.ogg").write_bytes(b"x")
        path = self.root / "audio/sfx/blip/assets.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["assets"].append({"path": "audio/sfx/blip/extra.ogg", "origin": "human", "author": "A", "license": "CC0-1.0"})
        path.write_text(json.dumps(data), encoding="utf-8")
        self.bake(self.write(dict(BLIP, seconds=0.06)))
        self.assertEqual(self.entries("audio/sfx/blip")["audio/sfx/blip/extra.ogg"]["origin"], "human")

    def test_a_content_items_sound_bakes_in_its_folder(self) -> None:
        self.bake(self.write(BLIP, "zap", "content/spells/zap/sounds"))
        self.assertTrue((self.root / "content/spells/zap/sounds/zap/variants/1.ogg").is_file())
        self.assertIn("content/spells/zap/sounds/zap/variants/1.ogg", self.entries("content/spells/zap/sounds/zap"))
        self.assertEqual(sound.check(self.root), [])

    def test_a_peak_over_the_familys_limit_fails(self) -> None:
        # A click train: loud peaks, little loudness.
        clicks = dict(BLIP, seconds=0.5, layers=[{"source": "square", "pitch": 20, "duty": 0.05,
                                                  "filter": {"type": "high", "from": 4000}}])
        with self.assertRaises(sound.BakeError) as caught:
            self.bake(self.write(clicks))
        self.assertIn("true peak", str(caught.exception))
        self.assertIn("audio/sfx/blip/blip.sound.json variant 1", str(caught.exception))

    def test_a_top_over_the_familys_ceiling_fails(self) -> None:
        # A high tone: all of it above 2 kHz, so its top is as loud as the sound.
        tone = dict(BLIP, layers=[{"source": "sine", "pitch": 5000, "amp": {"shape": "arch"}}])
        with self.assertRaises(sound.BakeError) as caught:
            self.bake(self.write(tone))
        self.assertIn("its top (above 2000 Hz)", str(caught.exception))
        self.assertIn("the combat ceiling of -10.0", str(caught.exception))
        self.assertIn("audio/sfx/blip/blip.sound.json variant 1", str(caught.exception))
        # The same tone far under a low one that carries the sound passes: the top is measured against the whole.
        self.bake(self.write(dict(BLIP, layers=[{"source": "sine", "pitch": 300, "amp": {"shape": "arch"}},
                                                dict(tone["layers"][0], gain=-30)])))

    def test_a_recipes_own_top_is_its_ceiling(self) -> None:
        tone = dict(BLIP, top=0.0, notes="a high tone, bright on purpose: a fixture",
                    layers=[{"source": "sine", "pitch": 5000, "amp": {"shape": "arch"}}])
        self.bake(self.write(tone))
        dull = dict(BLIP, top=-50.0, notes="a blip held darker than its family")
        with self.assertRaises(sound.BakeError) as caught:
            self.bake(self.write(dull))
        self.assertIn("ceiling of -50.0", str(caught.exception))

    def test_a_family_with_no_ceiling_checks_no_top(self) -> None:
        style = self.root / sound.STYLE
        text = style.read_text(encoding="utf-8")
        row = next(line for line in text.splitlines() if line.startswith("| `combat`"))
        style.write_text(text.replace(row, row.rsplit("|", 2)[0] + "| none |"), encoding="utf-8")
        self.assertIsNone(sound.families(self.root)["combat"].top)
        self.bake(self.write(dict(BLIP, layers=[{"source": "sine", "pitch": 5000, "amp": {"shape": "arch"}}])))

    def test_a_held_loops_top_is_checked_as_it_plays(self) -> None:
        bright = dict(HUM, layers=[{"source": "sine", "pitch": 5000}])
        with self.assertRaises(sound.BakeError) as caught:
            self.bake(self.write(bright, "hum"))
        self.assertIn("the held ceiling of -9.0", str(caught.exception))
        self.bake(self.write(HUM, "hum"))

    def test_a_family_row_that_does_not_read_is_named(self) -> None:
        style = self.root / sound.STYLE
        text = style.read_text(encoding="utf-8")
        row = next(line for line in text.splitlines() if line.startswith("| `combat`"))
        for bad, said in ((row.rsplit("|", 2)[0] + "|", "`combat`"),  # the column left out
                          (row.rsplit("|", 2)[0] + "| 10 LU |", "'10 LU'")):  # a top over the sound itself
            style.write_text(text.replace(row, bad), encoding="utf-8")
            with self.assertRaises(ValueError) as caught:
                sound.families(self.root)
            self.assertIn(said, str(caught.exception))
        style.write_text(text.replace("Top (above 2 kHz)", "Top (above 1.5 kHz)"), encoding="utf-8")
        self.assertEqual(sound.families(self.root)["combat"].top_hz, 1500.0, "the corner is the header's")
        music = next(line for line in text.splitlines() if line.startswith("| `music`"))
        style.write_text(text.replace(music, music.rsplit("|", 2)[0] + "| -9 LU |"), encoding="utf-8")
        with self.assertRaises(sound.BakeError) as caught:
            sound.checked_score(sound.find_scores()[0], sound.load_patches(), sound.families(self.root))
        self.assertIn("music row has a top", str(caught.exception))

    def test_gain_places_the_level_off_the_target(self) -> None:
        self.bake(self.write(dict(BLIP, gain=-3, notes="a blip, quieter: it is heard under every step")))
        for entry in self.entries("audio/sfx/blip").values():
            self.assertAlmostEqual(entry["loudness"], -29.0, delta=1.0)

    def test_a_variant_unlike_the_others_fails(self) -> None:
        # Each variant a quarter of the one before: far apart in level, though silent at both ends.
        with mock.patch.object(sound.sound_synth, "render", side_effect=lambda data, i: [0.0] + [0.5 / i ** 2] * 4000 + [0.0]):
            with self.assertRaises(sound.BakeError) as caught:
                self.bake(self.write(BLIP))
        self.assertIn("LU from the others", str(caught.exception))

    def test_variants_default_to_the_familys_count(self) -> None:
        recipe = dict(BLIP)
        del recipe["variants"]
        self.bake(self.write(recipe))
        self.assertEqual(len(self.entries("audio/sfx/blip")), 4, "combat's four")

    def test_a_short_loop_is_measured_as_it_plays(self) -> None:
        self.bake(self.write(dict(HUM, seconds=0.1), "hum"))
        entry = self.entries("audio/sfx/hum")["audio/sfx/hum/hum.ogg"]
        self.assertAlmostEqual(entry["loudness"], -24.0, delta=0.5)
        samples = sound.render_placed(sound.read_recipe(Path("audio/sfx/hum/hum.sound.json"), self.root),
                                      sound.sound_synth.validate(dict(HUM, seconds=0.1)), sound.families()["held"])[0][0]
        tiled = sound.sound_meter.integrated(samples * 40, RATE)
        self.assertAlmostEqual(tiled, -24.0, delta=0.5, msg="looped round, it is on its target")

    def test_another_encoder_rewrites_nothing_and_demotes_nothing(self) -> None:
        recipe = self.write(BLIP)
        self.bake(recipe)
        path = self.root / "audio/sfx/blip/assets.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        for entry in data["assets"]:
            entry["tier"] = "final"
        path.write_text(json.dumps(data), encoding="utf-8")
        written = sound.bake(recipe, self.root, lambda samples: b"other encoder " + sound.wav_bytes(samples),
                             say=self.said.append)
        self.assertNotIn(Path("audio/sfx/blip/variants/1.ogg"), written)
        self.assertEqual({e["tier"] for e in self.entries("audio/sfx/blip").values()}, {"final"})

    def test_the_manifest_is_tab_indented_like_the_others(self) -> None:
        self.bake(self.write(BLIP))
        self.assertTrue((self.root / "audio/sfx/blip/assets.json").read_text(encoding="utf-8").startswith('{\n\t"assets"'))

    def test_a_recipe_outside_the_repository_is_not_baked(self) -> None:
        outside = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, outside, True)
        (outside / "blip").mkdir()
        (outside / "blip/blip.sound.json").write_text(json.dumps(BLIP), encoding="utf-8")
        with self.assertRaises(sound.BakeError):
            self.bake(sound.read_recipe(outside / "blip/blip.sound.json", self.root))

    def test_a_kind_and_its_family_agree(self) -> None:
        with self.assertRaises(sound.BakeError):
            self.bake(self.write(dict(BLIP, family="held")))
        with self.assertRaises(sound.BakeError):
            self.bake(self.write(dict(BLIP, family="music")))
        with self.assertRaises(sound.BakeError):
            self.bake(self.write(dict(BLIP, family="loud")))

    def test_without_ffmpeg_the_bake_says_what_to_install(self) -> None:
        with mock.patch.object(sound.shutil, "which", return_value=None):
            with self.assertRaises(sound.BakeError) as caught:
                sound.ffmpeg_encode([0.0] * 10)
        self.assertIn("ffmpeg", str(caught.exception))
        self.assertIn("libvorbis", str(caught.exception))


class FamiliesTest(unittest.TestCase):
    def test_the_top_is_how_far_under_the_sound_its_part_above_2_khz_is(self) -> None:
        combat = sound.families()["combat"]
        low = [0.1 * math.sin(2.0 * math.pi * 200.0 * i / RATE) for i in range(RATE // 2)]
        high = [0.1 * math.sin(2.0 * math.pi * 5000.0 * i / RATE) for i in range(RATE // 2)]
        self.assertAlmostEqual(combat.top_of(high), 0.0, delta=0.2)
        self.assertLess(combat.top_of(low), -50.0)
        both = [a + 0.1 * b for a, b in zip(low, high)]  # the high tone 20 dB down, K-weighted about 4 dB up
        self.assertAlmostEqual(combat.top_of(both), -16.0, delta=1.5)

    def test_the_families_are_read_from_the_style_guide(self) -> None:
        fams = sound.families()
        self.assertEqual(set(fams), {"combat", "big", "boss", "held", "ambience", "ui", "music"})
        self.assertEqual(fams["combat"], sound.Family("combat", -26.0, "momentary", -3.0, 4, 0.04, 1.5, -10.0, 2000.0))
        self.assertEqual(fams["held"], sound.Family("held", -24.0, "integrated", -6.0, 1, 0.0, 0.0, -9.0, 2000.0))
        self.assertIsNone(fams["music"].top, "music has no ceiling on its top")
        self.assertEqual(fams["ui"].pitch, 0.02)
        self.assertEqual(fams["ui"].volume, 0.0)


class SheetTest(unittest.TestCase):
    def test_the_sheet_plays_each_variant_then_four_at_once_then_all(self) -> None:
        a = [[0.1] * 100, [0.2] * 100]
        b = [[0.3] * 50]
        out = sound.sheet_timeline([("a", a), ("b", b)])
        gap = round(sound.GAP * RATE)
        crowd = round(sound.CROWD[-1] * RATE)
        expected = (100 + gap) * 2 + (crowd + 100) + 2 * gap + (50 + gap) + (crowd + 50) + 2 * gap + 100 + gap
        self.assertEqual(len(out), expected)
        self.assertEqual(out[0], 0.1)
        self.assertEqual(out[100 + gap], 0.2)
        self.assertLessEqual(max(abs(v) for v in out), 0.99, "never clips")

    def test_the_sheet_is_never_written_in_the_repository(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            recipe = Path(tmp) / "blip/blip.sound.json"
            recipe.parent.mkdir()
            recipe.write_text(json.dumps(BLIP), encoding="utf-8")
            with mock.patch.object(sound, "sheet") as sheet, mock.patch("sys.stderr"):
                self.assertEqual(sound.main(["sheet", str(recipe), "--out", str(sound.ROOT / "build/sheet")]), 1)
                sheet.assert_not_called()
            with mock.patch.object(sound, "sheet", return_value=[]) as sheet:
                self.assertEqual(sound.main(["sheet", str(recipe), "--out", str(Path(tmp) / "out")]), 0)
                sheet.assert_called_once()

    @unittest.skipUnless(shutil.which("ffmpeg"), "the sheet needs ffmpeg")
    def test_the_sheet_writes_its_ogg_and_mp4(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            recipe = Path(tmp) / "blip/blip.sound.json"
            recipe.parent.mkdir()
            recipe.write_text(json.dumps(BLIP), encoding="utf-8")
            found = sound.sheet([sound.read_recipe(recipe)] * 2, Path(tmp) / "out")
            self.assertEqual([p.name for p in found], ["sheet.ogg", "sheet.mp4"])
            self.assertTrue(all(p.stat().st_size > 1000 for p in found))
            self.assertEqual(sorted(p.name for p in (Path(tmp) / "out").iterdir()), ["sheet.mp4", "sheet.ogg"])


if __name__ == "__main__":
    unittest.main()
