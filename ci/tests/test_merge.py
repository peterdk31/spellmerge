import tempfile
import unittest
from pathlib import Path
from unittest import mock

from smbot import config, gh, merge

CFG = config.load()


class OwnerReviewTest(unittest.TestCase):
    def setUp(self) -> None:
        self.policy = Path(tempfile.mkdtemp())
        (self.policy / ".github").mkdir()
        (self.policy / ".github" / "CODEOWNERS").write_text(
            f"/docs/DESIGN.md  @{CFG.owner.login}\n/ci/  @{CFG.owner.login}\n")

    def files(self, *names: str) -> mock._patch:
        return mock.patch.object(gh, "api_paginated", return_value=[{"filename": n} for n in names])

    def test_only_owner_paths_need_the_owners_review(self) -> None:
        with self.files("docs/NEXT.md", "core/a.gd"):
            self.assertEqual(merge.owner_reviewed(CFG, 7, self.policy), [])
        with self.files("docs/NEXT.md", "docs/DESIGN.md"):
            self.assertEqual(merge.owner_reviewed(CFG, 7, self.policy), ["docs/DESIGN.md"])

    def test_asking_the_owner_requests_a_review_and_says_what_to_do(self) -> None:
        with mock.patch.object(gh, "run") as run:
            text = merge.ask_the_owner(CFG, 7, ["docs/DESIGN.md"])
        self.assertIn("--add-reviewer", run.call_args.args)
        self.assertTrue(text.startswith(merge.OWNER_REVIEW))
        self.assertIn(f"@{CFG.owner.login}", text)
        with mock.patch.object(gh, "run", side_effect=gh.GhError("no")):
            self.assertIn("docs/DESIGN.md", merge.ask_the_owner(CFG, 7, ["docs/DESIGN.md"]))


if __name__ == "__main__":
    unittest.main()
