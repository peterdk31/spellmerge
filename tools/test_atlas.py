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
        # A card kind is listed once its folder has content (multicast cards come with staffs C).
        present = {k for k, folder in atlas.KIND_FOLDERS.items() if any((self.tmp / atlas.SPELLS / folder).glob("*/*.tres"))}
        self.assertEqual(set(kinds), present | {"combo", "reaction"})
        self.assertTrue(set(kinds) <= set(atlas.KIND_ORDER))
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
                self.assertTrue(e["description"], f"no builder description: add content/story/lore/components/{e['id']}.json: {e}")

    def test_a_fake_combo_file_appears(self) -> None:
        path = self.tmp / atlas.COMBOS / "fake_combo.json"
        path.write_text(json.dumps({"id": "fake_combo", "name": "Fake combo", "does": "Does a fake thing."}))
        row = next(e for e in self.entries() if e["id"] == "fake_combo")
        self.assertEqual((row["kind"], row["name"], row["does"]), ("combo", "Fake combo", "Does a fake thing."))
        self.assertEqual(row["clips"], ["combo_fake_combo"])
        self.assertEqual(row["source"], f"{atlas.COMBOS}/fake_combo.json")

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
        self.assertIn("void on burning", row["does"].lower())
        self.assertIn("4 damage", row["does"])

    def add_reaction(self, reaction: str, *rows: tuple[str, str, str]) -> dict:
        """Appends rows (status, element, other lines) to the temp reactions.tres; returns the entry."""
        path = self.tmp / atlas.REACTIONS
        extra = ""
        for i, (status, element, lines) in enumerate(rows):
            extra += (f'\n[sub_resource type="Resource" id="Resource_{reaction}_{i}"]\nreaction_id = &"{reaction}"\n'
                      f'display_name = "{reaction.capitalize()}"\nstatus_id = &"{status}"\nelement_id = &"{element}"\n{lines}\n')
        path.write_text(path.read_text() + extra)
        return next(e for e in self.entries() if e["id"] == reaction)

    def test_extend_says_which_row_freezes(self) -> None:
        row = self.add_reaction("t_ext", ("chill", "fire", "effect = 2\nduration = 3.0\n"),
                                ("hex", "void", "effect = 2\nduration = 4.0\nstrength = 20.0\n"))
        self.assertIn("Fire on chilled: freezes the target for 3 seconds", row["does"])
        self.assertIn("Void on hexed: extends the hexed status by 4 seconds and its strength by 20", row["does"])
        self.assertEqual(row["does"].count(": "), 2)

    def test_rows_that_do_the_same_share_one_sentence(self) -> None:
        row = self.add_reaction("t_same", ("burn", "void", "damage = 5\nradius = 40.0\n"),
                                ("hex", "fire", "damage = 5\nradius = 40.0\n"))
        self.assertEqual(row["does"], "Void on burning or Fire on hexed: bursts for 5 damage within 40 pixels.")

    def test_a_burst_leaves_out_a_zero_damage_or_radius(self) -> None:
        row = self.add_reaction("t_zero", ("burn", "void", "pull = 1.0\n"), ("hex", "fire", "pull = 1.0\n"))
        self.assertEqual(row["does"], "Void on burning or Fire on hexed: bursts, pulling targets in.")

    def test_consume_says_the_bonus_doubles_on_a_frozen_target(self) -> None:
        row = self.add_reaction("t_con", ("chill", "fire", "effect = 1\ndamage = 9\n"),
                                ("burn", "void", "effect = 1\ndamage = 9\n"))
        self.assertIn("uses up the status for 9 bonus damage (doubled while the target is frozen)", row["does"])

    def test_spread_names_its_radius(self) -> None:
        row = self.add_reaction("t_spr", ("burn", "fire", "effect = 3\nradius = 60.0\n"),
                                ("hex", "void", "effect = 3\nradius = 60.0\n"))
        self.assertIn("spreads the status to other targets within 60 pixels", row["does"])

    def test_the_real_reactions_get_one_sentence_per_distinct_effect(self) -> None:
        for e in atlas.build()["entries"]:
            if e["kind"] == "reaction":
                self.assertTrue(e["does"].endswith("."), e)
                self.assertGreaterEqual(e["does"].count(": "), 1, e)

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
        combos = list((REPO / atlas.COMBOS).glob("*.json"))
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
