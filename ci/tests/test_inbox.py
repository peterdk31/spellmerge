from __future__ import annotations

import unittest
from unittest import mock

from smbot import config, inbox

CFG = config.load()
Q = {"title": "Allow X?", "question": "Why @someone needs X.", "options": ["Yes", "No"],
     "recommendation": "Yes", "meanwhile": "The next task.", "owner_change": True, "change": "a diff"}


class InboxTest(unittest.TestCase):
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
                return [{"number": 7, "title": "allow x?"}]
            return {"number": 8}

        with mock.patch.object(inbox.gh, "api", api):
            self.assertEqual(inbox.ask(CFG, [Q]), [])
            log = inbox.ask(CFG, [{**Q, "title": "Pick Y?", "owner_change": False}, {"title": "", "question": "x"}])
        self.assertEqual(log, ["Question for the owner: #8 Pick Y?"])
        created = [c for c in calls if c[0].endswith("/issues") and c[2]]
        self.assertEqual(created[-1][2]["labels"], [inbox.LABEL])


if __name__ == "__main__":
    unittest.main()
