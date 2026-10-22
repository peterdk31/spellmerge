from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from smbot import config, inbox

CFG = config.load()
Q = {"title": "Allow X?", "question": "Why @someone needs X.", "options": ["Yes", "No"],
     "recommendation": "Yes", "meanwhile": "The next task.", "owner_change": True, "change": "a diff"}


class InboxTest(unittest.TestCase):
    def setUp(self) -> None:
        for patcher in (mock.patch("smbot.labels.ensure"),  # labels are covered in test_intake
                        mock.patch("smbot.state.load", return_value=({"pending_instructions": []}, "sha"))):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_render_mentions_only_the_owner(self) -> None:
        body = inbox.render(CFG, Q, "a session")
        self.assertTrue(body.startswith(f"@{CFG.owner.login},"))
        self.assertNotIn("@someone", body)
        self.assertIn("/claude <your answer>", body)
        self.assertIn("a diff", body)

    def test_a_question_names_the_pr_it_was_raised_in(self) -> None:
        body = inbox.render(CFG, Q, "the session working on \"X\"", pr=12)
        self.assertIn("Raised by the session working on \"X\", in PR #12.", body)
        self.assertIn("<!-- smbot:question key= -->", body)
        body = inbox.render(CFG, Q, "the revision of PR #12", pr=12)
        self.assertIn("Raised by the revision of PR #12.", body)

    def test_the_pictures_come_right_after_the_question(self) -> None:
        body = inbox.render(CFG, Q, "s", pictures="**Samples**\n\n![A](https://x/a.png)")
        self.assertLess(body.index("## Question"), body.index("## What it looks like"))
        self.assertLess(body.index("![A](https://x/a.png)"), body.index("## Options"))
        self.assertNotIn("## What it looks like", inbox.render(CFG, Q, "s"))

    def test_a_new_question_is_asked_with_its_pictures_and_without_them_if_they_fail(self) -> None:
        """The owner reads a question after its PR merged: it must show what it's about itself."""
        bodies: list = []

        def api(path: str, *args: str, input: dict | None = None, token: object = None) -> object:
            if "issues?state=" in path:
                return [{"number": 7, "title": "Allow X?", "state": "open", "body": ""}]
            bodies.append(input["body"])
            return {"number": 8}

        asked: list = []

        def pictures(q: dict) -> str:
            asked.append(q["title"])
            if q["title"] == "Pick Z?":
                raise inbox.gh.GhError("push refused")
            return "![shot](https://x/s.png)"

        with mock.patch.object(inbox.gh, "api", api):
            inbox.ask(CFG, [Q, {**Q, "title": "Pick Y?"}, {**Q, "title": "Pick Z?"}], pictures=pictures)
        self.assertEqual(asked, ["Pick Y?", "Pick Z?"])  # not for a question that isn't asked again
        self.assertIn("![shot](https://x/s.png)", bodies[0])
        self.assertNotIn("## What it looks like", bodies[1])

    def test_pictures_are_the_questions_own_shots_or_else_the_prs(self) -> None:
        with mock.patch.object(inbox.screenshots, "for_question", return_value="own") as own, \
                mock.patch.object(inbox.screenshots, "for_log", return_value="the PR's") as pr_shots, \
                tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(inbox.pictures_for(CFG, "t", Path(tmp), "abc1234", 7)(Q), "own")
            own.return_value = ""
            self.assertEqual(inbox.pictures_for(CFG, "t", Path(tmp), "abc1234", 7)(Q), "the PR's")
            self.assertEqual(inbox.pictures_for(CFG, "t", None, "", None)(Q), "")
        self.assertEqual(own.call_count, 2)  # not without a folder of shots
        pr_shots.assert_called_once_with(CFG, 7)

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
            self.assertEqual(inbox.ask(CFG, [Q]), ['Not asked again: "Allow X?" is #7, still waiting for the owner'])
            log = inbox.ask(CFG, [{**Q, "title": "Pick Y?", "owner_change": False}, {"title": "", "question": "x"}])
        self.assertEqual(log, ["Question for the owner: #8 Pick Y?"])
        created = [c for c in calls if c[0].endswith("/issues") and c[2]]
        self.assertIn("<!-- smbot:question key= -->", created[-1][2]["body"])
        self.assertEqual(created[-1][2]["labels"], [inbox.LABEL])

    def test_answered_keys(self) -> None:
        def q(number: int, key: str, state: str = "open") -> dict:
            return {"number": number, "title": f"Q{number}", "state": state,
                    "body": f"text\n<!-- smbot:question key={key} -->"}

        open_ = [q(1, "still-open"), q(2, "replied"), q(3, "dup-open")]
        closed = [q(4, "closed-by-pr", "closed"), q(5, "dup-open", "closed"), q(6, "", "closed")]

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            return open_ if "state=open" in path else closed

        st = {"pending_instructions": [{"kind": "claude", "number": 2, "url": "u"},
                                       {"kind": "ask", "number": 1, "url": "v"}]}
        with mock.patch.object(inbox.gh, "api", api):
            # A closed duplicate doesn't answer a key whose question is still open (#178/#179 were twins).
            self.assertEqual(inbox.answered_keys(CFG, st), {"closed-by-pr", "replied"})

        def broken(*a: object, **k: object) -> object:
            raise inbox.gh.GhError("down")

        with mock.patch.object(inbox.gh, "api", broken):
            self.assertEqual(inbox.answered_keys(CFG, st), set())

    def test_only_questions_still_waiting_for_the_owner_stop_a_new_one(self) -> None:
        """#72/#73 and #79/#80/#83 asked the same open question in other words; #192 was a next round of #190."""
        keyed = {"number": 80, "title": "Something else entirely", "state": "open",
                 "body": "text\n<!-- smbot:question key=build-sh-four-bot -->"}
        reworded = {"number": 81, "title": "Make the daily build run the unit tests?", "state": "open", "body": ""}
        answered = {"number": 190, "title": "Pick an art direction?", "state": "open",
                    "body": "text\n<!-- smbot:question key=art-direction-pick -->"}

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            if "issues?state=open" in path:
                return [keyed, reworded, answered]
            return {"number": 99}

        st = {"pending_instructions": [{"kind": "claude", "number": 190, "url": "u"}]}
        rephrased = {**Q, "title": "Make the daily build run the unit tests and fail when one fails?"}
        same_key = {**Q, "title": "Add the 4-bot step to ci/build/build.sh?", "key": "Build-sh four bot"}
        next_round = {**Q, "title": "Pick an art direction?", "key": "art-direction-pick"}
        with mock.patch.object(inbox.gh, "api", api), mock.patch.object(inbox.state, "load", return_value=(st, "sha")):
            log = inbox.ask(CFG, [rephrased, same_key, next_round])
        self.assertEqual(log, [f'Not asked again: "{rephrased["title"]}" is #81, still waiting for the owner',
                               f'Not asked again: "{same_key["title"]}" is #80, still waiting for the owner',
                               "Question for the owner: #99 Pick an art direction?"])

    def test_a_closed_question_never_stops_a_new_one(self) -> None:
        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            if "issues?state=closed" in path:
                raise AssertionError("closed questions aren't read")
            return [] if "issues?state=open" in path else {"number": 99}

        with mock.patch.object(inbox.gh, "api", api):
            self.assertEqual(inbox.ask(CFG, [Q]), ["Question for the owner: #99 Allow X?"])

if __name__ == "__main__":
    unittest.main()
