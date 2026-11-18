# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The hash test (docs/milestones/sound.md, section 6):  python3 -m unittest discover -s tools

Every generated sound in the repository is baked from its recipe as it is now: no stale
`recipe_hash`, no missing file or manifest entry, and no `.ogg` that no recipe makes unless its
manifest entry names another source. Reads no audio and needs no ffmpeg (`tools/sound.py check`
is the same check). The rest checks the check on a repository of its own.
"""

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sound  # noqa: E402

RECIPE = {"version": 1, "kind": "sfx", "family": "combat", "seconds": 0.05, "variants": 2,
          "layers": [{"source": "sine", "pitch": 600, "amp": {"shape": "arch"}}], "notes": "a blip"}


def fake_encode(samples: list[float]) -> bytes:
    return sound.wav_bytes(samples)


class RepositoryTest(unittest.TestCase):
    def test_every_generated_sound_is_up_to_date(self) -> None:
        problems = sound.check()
        self.assertEqual(problems, [], "\n".join(problems))


class CheckTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, True)
        (self.root / "docs").mkdir()
        shutil.copy(sound.ROOT / sound.STYLE, self.root / sound.STYLE)
        self.folder = self.root / "audio/sfx/blip"
        self.folder.mkdir(parents=True)
        self.write(RECIPE)

    def write(self, recipe: dict, folder: Path | None = None, name: str = "blip") -> sound.Recipe:
        path = (folder or self.folder) / f"{name}.sound.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(recipe), encoding="utf-8")
        return sound.read_recipe(path.relative_to(self.root), self.root)

    def bake(self, name: str = "blip") -> list[Path]:
        recipe = next(r for r in sound.find_recipes(self.root) if r.id == name)
        return sound.bake(recipe, self.root, fake_encode, say=lambda _: None)

    def test_a_baked_sound_passes(self) -> None:
        self.assertNotEqual(sound.check(self.root), [], "unbaked, it is missing")
        self.bake()
        self.assertEqual(sound.check(self.root), [])

    def test_a_changed_recipe_is_stale_and_names_the_command(self) -> None:
        self.bake()
        self.write(dict(RECIPE, seconds=0.06))
        problems = sound.check(self.root)
        self.assertEqual(len(problems), 2, problems)
        self.assertIn("audio/sfx/blip/variants/1.ogg: stale", problems[0])
        self.assertIn("tools/sound.py bake audio/sfx/blip/blip.sound.json", problems[0])

    def test_a_changed_patch_or_generator_is_stale(self) -> None:
        patches = self.root / sound.PATCHES
        patches.mkdir(parents=True)
        patch = {"version": 1, "notes": "a tone", "layer": {"source": "sine", "pitch": 500}}
        (patches / "tone.patch.json").write_text(json.dumps(patch), encoding="utf-8")
        self.write(dict(RECIPE, layers=[{"patch": "tone"}]))
        self.bake()
        self.assertEqual(sound.check(self.root), [])
        patch["layer"]["pitch"] = 520
        (patches / "tone.patch.json").write_text(json.dumps(patch), encoding="utf-8")
        self.assertIn("stale", sound.check(self.root)[0])
        recipe = sound.find_recipes(self.root)[0]
        family = sound.families(self.root)["combat"]
        before = sound.recipe_hash(recipe.data, sound.load_patches(self.root), family)
        old = sound.sound_synth.GENERATOR
        sound.sound_synth.GENERATOR = old + 1
        try:
            self.assertNotEqual(sound.recipe_hash(recipe.data, sound.load_patches(self.root), family), before)
        finally:
            sound.sound_synth.GENERATOR = old

    def test_a_changed_family_row_in_the_style_guide_is_stale(self) -> None:
        self.bake()
        style = self.root / sound.STYLE
        text = style.read_text(encoding="utf-8")
        row = "| `combat` (cast, hit, small effects) | -20 momentary |"
        self.assertIn(row, text)
        style.write_text(text.replace(row, "| `combat` (cast, hit, small effects) | -14 momentary |"), encoding="utf-8")
        self.assertIn("docs/STYLE.md", sound.check(self.root)[0])

    def test_variants_left_behind_by_a_deleted_recipe_are_named(self) -> None:
        self.bake()
        (self.folder / "blip.sound.json").unlink()
        problems = sound.check(self.root)
        self.assertEqual(len(problems), 2, problems)
        self.assertIn("audio/sfx/blip/variants/1.ogg: no recipe or score makes it", problems[0])

    def test_a_kind_change_names_the_files_of_the_old_kind(self) -> None:
        self.bake()
        self.write(dict(RECIPE, kind="held", family="held", variants=1))
        self.assertIn("audio/sfx/blip/blip.tres: left from when it was a one-shot", "\n".join(sound.check(self.root)))
        self.bake()
        self.assertEqual(sound.check(self.root), [])
        self.assertFalse((self.folder / "blip.tres").exists())
        self.assertFalse((self.folder / "variants/1.ogg").exists())
        self.write(RECIPE)
        self.assertIn("audio/sfx/blip/blip.ogg: left from when it was a held sound", "\n".join(sound.check(self.root)))
        self.bake()
        self.assertEqual(sound.check(self.root), [])
        self.assertFalse((self.folder / "blip.ogg").exists())

    def test_a_recipe_in_a_content_items_own_folder_is_refused(self) -> None:
        folder = self.root / "content/spells/carriers/atom"
        folder.mkdir(parents=True)
        (folder / "atom.sound.json").write_text(json.dumps(RECIPE), encoding="utf-8")
        problems = sound.check(self.root)
        self.assertTrue(any("content item's sounds/atom/" in p for p in problems), problems)

    def test_an_ambience_file_with_a_recipe_must_leave_unreciped(self) -> None:
        ambience = Path(sound.UNRECIPED[0])
        sound_id = ambience.stem
        recipe = dict(RECIPE, kind="held", family="held", variants=1)
        folder = self.root / ambience.parent / sound_id
        self.write(recipe, folder, sound_id)
        with mock.patch.object(sound, "UNRECIPED", (f"{ambience.parent}/{sound_id}/{sound_id}.ogg",)):
            self.bake(sound_id)
            self.assertIn("take it off tools/sound.py's UNRECIPED", "\n".join(sound.check(self.root)))

    def test_a_missing_file_or_entry_is_named(self) -> None:
        self.bake()
        (self.folder / "variants/2.ogg").unlink()
        self.assertEqual(sound.check(self.root), [
            "audio/sfx/blip/variants/2.ogg: missing; run: tools/sound.py bake audio/sfx/blip/blip.sound.json"])
        self.bake()
        (self.folder / "assets.json").write_text('{"assets": []}', encoding="utf-8")
        self.assertIn("no entry in", sound.check(self.root)[0])

    def test_an_ogg_with_no_recipe_needs_another_source(self) -> None:
        self.bake()
        stray = self.root / "audio/sfx/stray.ogg"
        stray.write_bytes(b"x")
        problems = sound.check(self.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("audio/sfx/stray.ogg: no recipe or score makes it", problems[0])
        (self.root / sound.MANIFEST).write_text(json.dumps({"assets": [
            {"path": "audio/sfx/stray.ogg", "origin": "human", "author": "Someone", "license": "CC0-1.0"}]}),
            encoding="utf-8")
        self.assertEqual(sound.check(self.root), [], "a hand-made sound has no recipe")

    def test_the_unreciped_ambience_is_allowed_until_it_has_a_recipe(self) -> None:
        ambience = self.root / sound.UNRECIPED[0]
        ambience.parent.mkdir(parents=True)
        ambience.write_bytes(b"x")
        self.bake()
        self.assertEqual(sound.check(self.root), [])

    def test_a_recipe_that_does_not_validate_is_named(self) -> None:
        self.write(dict(RECIPE, wobble=1))
        problems = sound.check(self.root)
        self.assertEqual(len(problems), 1, problems)
        self.assertTrue(problems[0].startswith("audio/sfx/blip/blip.sound.json: wobble: unknown key"), problems)

    def test_a_recipe_outside_a_folder_of_its_id_is_refused(self) -> None:
        (self.root / "audio/sfx/other.sound.json").write_text(json.dumps(RECIPE), encoding="utf-8")
        self.assertIn("a folder of its own", sound.check(self.root)[0])

    def test_a_variant_the_recipe_dropped_is_named(self) -> None:
        self.bake()
        self.write(dict(RECIPE, variants=1))
        problems = sound.check(self.root)
        self.assertTrue(any("variants/2.ogg: a variant the recipe no longer has" in p for p in problems), problems)


if __name__ == "__main__":
    unittest.main()
