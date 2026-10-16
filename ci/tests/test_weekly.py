from __future__ import annotations

import unittest

from smbot import weekly


class WeeklyTest(unittest.TestCase):
    def test_replies_are_inert(self) -> None:
        reply = weekly.safe_reply("Great idea @everyone! See https://evil.example/x and "
                                  "https://github.com/peterdk31/spellmerge/blob/main/docs/BACKLOG.md " + "x" * 3000)
        self.assertNotIn("@everyone", reply)
        self.assertNotIn("evil.example", reply)
        self.assertIn("github.com/peterdk31/spellmerge/blob/main/docs/BACKLOG.md", reply)
        self.assertLessEqual(len(reply), weekly.MAX_REPLY)

    def test_task_issue_has_template_and_brief(self) -> None:
        body = weekly.task_issue_body({
            "milestone": "M1", "area": "art", "skill": "pixel-art", "size": "S", "what": "Draw the slime",
            "where": "content/enemies/slime/slime.png", "specs": "32×32, 4 frames", "done_when": "Matches STYLE.md"})
        for part in ("**Milestone:** M1", "**Where:** `content/enemies/slime/slime.png`", "Brief for your AI",
                     "Done when: Matches STYLE.md", "/claim"):
            self.assertIn(part, body)


if __name__ == "__main__":
    unittest.main()
