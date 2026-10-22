from __future__ import annotations

import datetime as dt
import unittest
from unittest import mock

from smbot import config, inbox

CFG = config.load()
Q = {"title": "Allow X?", "question": "Why @someone needs X.", "options": ["Yes", "No"],
     "recommendation": "Yes", "meanwhile": "The next task.", "owner_change": True, "change": "a diff"}


class InboxTest(unittest.TestCase):
    def setUp(self) -> None:
        patcher = mock.patch("smbot.labels.ensure")  # labels are covered in test_intake
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_render_mentions_only_the_owner(self) -> None:
        body = inbox.render(CFG, Q, "a session")
        self.assertTrue(body.startswith(f"@{CFG.owner.login},"))
        self.assertNotIn("@someone", body)
        self.assertIn("/claude <your answer>", body)
        self.assertIn("a diff", body)

    def test_ask_skips_questions_already_open(self) -> None:
        calls = []

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            calls.append((path, args, input))
            if "issues?state=open" in path:
                return [{"number": 7, "title": "allow x?", "state": "open"}]
            if "issues?state=closed" in path:
                return []
            return {"number": 8}

        with mock.patch.object(inbox.gh, "api", api):
            self.assertEqual(inbox.ask(CFG, [Q]), ['Not asked again: "Allow X?" is #7 (open)'])
            log = inbox.ask(CFG, [{**Q, "title": "Pick Y?", "owner_change": False}, {"title": "", "question": "x"}])
        self.assertEqual(log, ["Question for the owner: #8 Pick Y?"])
        created = [c for c in calls if c[0].endswith("/issues") and c[2]]
        self.assertIn("<!-- smbot:question key= -->", created[-1][2]["body"])
        self.assertEqual(created[-1][2]["labels"], [inbox.LABEL])

    def test_rephrased_or_recently_answered_questions_are_not_asked_again(self) -> None:
        """#72/#73 and #79/#80/#83 asked the same thing in other words."""
        answered = {"number": 73, "title": "Make the daily build run the unit tests?", "state": "closed",
                    "closed_at": "2026-10-20T10:00:00Z", "body": ""}
        keyed = {"number": 80, "title": "Something else entirely", "state": "open",
                 "body": "text\n<!-- smbot:question key=build-sh-four-bot -->"}

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            if "issues?state=open" in path:
                return [keyed]
            if "issues?state=closed" in path:
                return [answered]
            return {"number": 99}

        now = dt.datetime(2026, 10, 22, tzinfo=dt.timezone.utc)
        rephrased = {**Q, "title": "Make the daily build run the unit tests and fail when one fails?"}
        same_key = {**Q, "title": "Add the 4-bot step to ci/build/build.sh?", "key": "Build-sh four bot"}
        new = {**Q, "title": "Pick a palette for the ice biome?"}
        with mock.patch.object(inbox.gh, "api", api):
            log = inbox.ask(CFG, [rephrased, same_key, new], now=now)
        self.assertEqual(log, [f'Not asked again: "{rephrased["title"]}" is #73 (answered or closed)',
                               f'Not asked again: "{same_key["title"]}" is #80 (open)',
                               "Question for the owner: #99 Pick a palette for the ice biome?"])


if __name__ == "__main__":
    unittest.main()
