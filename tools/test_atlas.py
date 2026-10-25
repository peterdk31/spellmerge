# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/atlas.py:  python3 -m unittest discover -s tools -p 'test_*.py'"""

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import atlas  # noqa: E402

REPO = atlas.ROOT


class AtlasTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        shutil.copytree(REPO / "content/spells", self.tmp / "content/spells")
        shutil.copytree(REPO / "content/story/lore/components", self.tmp / "content/story/lore/components")

    def entries(self) -> list[dict]:
        return atlas.build(self.tmp)["entries"]

    def test_every_kind_is_listed_and_grouped(self) -> None:
        kinds = [e["kind"] for e in self.entries()]
        self.assertEqual(set(kinds), set(atlas.KIND_ORDER))
        self.assertEqual(kinds, sorted(kinds, key=atlas.KIND_ORDER.index))

    def test_the_real_content_has_every_field(self) -> None:
        for e in atlas.build()["entries"]:
            self.assertTrue(e["id"] and e["name"] and e["source"], e)
            self.assertTrue((REPO / e["source"]).is_file(), e)
            if e["kind"] == "combo":
                self.assertTrue(e["does"], e)
            if e["kind"] == "reaction":
                self.assertEqual(len(e["clips"]), 2, e)
            elif e["kind"] != "combo":
                self.assertTrue(e["description"], f"no builder description: {e}")

    def test_a_fake_combo_row_appears(self) -> None:
        path = self.tmp / atlas.COMBOS
        data = json.loads(path.read_text())
        data["combos"].append({"id": "fake_combo", "name": "Fake combo", "does": "Does a fake thing."})
        path.write_text(json.dumps(data))
        row = next(e for e in self.entries() if e["id"] == "fake_combo")
        self.assertEqual((row["kind"], row["name"], row["does"]), ("combo", "Fake combo", "Does a fake thing."))
        self.assertEqual(row["clips"], ["combo_fake_combo"])
        self.assertEqual(row["source"], atlas.COMBOS)

    def test_a_new_component_folder_appears_with_its_description(self) -> None:
        folder = self.tmp / "content/spells/elements/acid"
        folder.mkdir()
        (folder / "acid.tres").write_text('[resource]\nid = &"acid"\ndisplay_name = "Acid"\n')
        (self.tmp / "content/story/lore/components/acid.json").write_text(
            json.dumps({"id": "acid", "about": "component", "text": "Eats armour."}))
        row = next(e for e in self.entries() if e["id"] == "acid")
        self.assertEqual((row["kind"], row["name"], row["description"]), ("element", "Acid", "Eats armour."))
        self.assertEqual(row["clips"], ["element_acid"])
        self.assertEqual(row["source"], "content/spells/elements/acid/acid.tres")

    def test_a_new_reaction_pair_appears_with_a_coop_clip(self) -> None:
        path = self.tmp / atlas.REACTIONS
        extra = ""
        for status, element in (("burn", "void"), ("hex", "fire")):
            extra += (f'\n[sub_resource type="Resource" id="Resource_x_{status}"]\nreaction_id = &"fizzle"\n'
                      f'display_name = "Fizzle"\nstatus_id = &"{status}"\nelement_id = &"{element}"\n'
                      "damage = 4\nradius = 30.0\n")
        path.write_text(path.read_text() + extra)
        row = next(e for e in self.entries() if e["id"] == "fizzle")
        self.assertEqual(row["clips"], ["reaction_fizzle", "reaction_fizzle_coop"])
        self.assertIn("void hit on a burning target", row["does"])
        self.assertIn("4 damage", row["does"])

    def test_stillness_says_which_row_freezes(self) -> None:
        row = next(e for e in self.entries() if e["id"] == "stillness")
        self.assertIn("freezes the target for 2 seconds", row["does"])
        self.assertIn("extends the hexed status by 2 seconds and its strength by 25", row["does"])
        self.assertEqual(row["does"].count(" hit on a "), 2)

    def test_rows_that_do_the_same_share_one_sentence(self) -> None:
        row = next(e for e in self.entries() if e["id"] == "rift")
        self.assertEqual(row["does"].count(": "), 1)
        self.assertEqual(row["does"].count("bursts for"), 1)
        self.assertIn(" or ", row["does"])

    def test_shatter_says_the_bonus_doubles_on_a_frozen_target(self) -> None:
        row = next(e for e in self.entries() if e["id"] == "shatter" and e["kind"] == "reaction")
        self.assertIn("doubled while the target is frozen", row["does"])

    def test_an_unreadable_component_file_is_skipped(self) -> None:
        folder = self.tmp / "content/spells/forms/bad"
        folder.mkdir(parents=True)
        (folder / "bad.tres").write_bytes(b"\xff\xfe\x00 id = broken")
        self.assertNotIn("bad", [e["id"] for e in self.entries()])

    def test_a_single_row_reaction_has_no_clips(self) -> None:
        path = self.tmp / atlas.REACTIONS
        path.write_text(path.read_text() + '\n[sub_resource type="Resource" id="Resource_solo"]\n'
                        'reaction_id = &"solo"\ndisplay_name = "Solo"\nstatus_id = &"burn"\n'
                        'element_id = &"fire"\ndamage = 1\n')
        self.assertEqual(next(e for e in self.entries() if e["id"] == "solo")["clips"], [])

    def test_a_deeper_component_is_found(self) -> None:
        folder = self.tmp / "content/spells/forms/deep/inner"
        folder.mkdir(parents=True)
        (folder / "deep.tres").write_text('[resource]\nid = &"deep"\ndisplay_name = "Deep"\n')
        row = next(e for e in self.entries() if e["id"] == "deep")
        self.assertEqual((row["kind"], row["clips"]), ("form", ["form_deep"]))

    def test_clip_ids_match_the_recorder(self) -> None:
        entries = atlas.build()["entries"]
        ids = [c for e in entries for c in e["clips"]]
        self.assertEqual(len(ids), len(set(ids)))
        # The recorder's rule (tests/clips/scenarios.gd): one clip per combo and per component,
        # two per reaction that has at least two rows.
        combos = json.loads((REPO / atlas.COMBOS).read_text(encoding="utf-8"))["combos"]
        count = {k: sum(1 for e in entries if e["kind"] == k) for k in atlas.KIND_ORDER}
        paired = sum(1 for e in entries if e["kind"] == "reaction" and e["clips"])
        components = sum(count[k] for k in atlas.KIND_FOLDERS)
        self.assertEqual(count["combo"], len(combos))
        self.assertEqual(len(ids), len(combos) + components + 2 * paired)
        for e in entries:
            for c in e["clips"]:
                self.assertTrue(c.startswith(f"{e['kind']}_{e['id']}"), c)

    def test_the_output_file_is_written(self) -> None:
        out = self.tmp / "deep/atlas.json"
        self.assertEqual(atlas.main(["atlas.py", str(out)]), 0)
        self.assertEqual(json.loads(out.read_text()), atlas.build())
        self.assertEqual(atlas.main(["atlas.py"]), 2)


if __name__ == "__main__":
    unittest.main()
