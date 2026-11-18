# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/sound_fixtures.py (the sound room's fixtures, sound plan AU4):
python3 -m unittest discover -s tools
"""

import copy
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sound  # noqa: E402
import sound_fixtures  # noqa: E402
import sound_synth  # noqa: E402


class FixturesTest(unittest.TestCase):
    def test_every_fixture_is_baked_from_its_recipe_now(self) -> None:
        problems = sound_fixtures.check()
        self.assertEqual(problems, [], "\n".join(problems))

    def test_the_tracks_layers_are_of_one_length(self) -> None:
        lengths = {len(sound_synth.render(sound_synth.validate(layer), 1)) for layer in sound_fixtures.TRACK.values()}
        self.assertEqual(len(lengths), 1, f"the layers differ in length: {lengths}")


class CheckTest(unittest.TestCase):
    """The check on a repository of its own, baked with a stand-in encoder (no ffmpeg)."""

    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, True)
        (self.root / "docs").mkdir()
        shutil.copy(sound.ROOT / sound.STYLE, self.root / sound.STYLE)
        one = {"room_hum": sound_fixtures.FIXTURES["room_hum"]}
        patcher = mock.patch.dict(sound_fixtures.FIXTURES, one, clear=True)
        patcher.start()
        self.addCleanup(patcher.stop)
        sound_fixtures.bake(self.root, sound.wav_bytes, lambda _: None)

    def test_a_fresh_bake_names_its_recipe_and_is_up_to_date(self) -> None:
        self.assertEqual(sound_fixtures.check(self.root), [])
        entries = sound.read_json(self.root / sound_fixtures.FOLDER / "room_hum/assets.json")["assets"]
        self.assertEqual({e["prompt"] for e in entries}, {"tools/test_sound_synth.py HELD"})

    def test_a_changed_recipe_is_stale(self) -> None:
        changed = copy.deepcopy(sound_fixtures.FIXTURES["room_hum"][1])
        changed["seconds"] = 1.5
        sound_fixtures.FIXTURES["room_hum"] = ("tools/test_sound_synth.py HELD", changed)
        problems = sound_fixtures.check(self.root)
        self.assertTrue(any("older" in p for p in problems), problems)

    def test_a_missing_file_is_named(self) -> None:
        (self.root / sound_fixtures.FOLDER / "room_hum/room_hum.ogg").unlink()
        problems = sound_fixtures.check(self.root)
        self.assertTrue(any("missing" in p for p in problems), problems)


if __name__ == "__main__":
    unittest.main()
