from __future__ import annotations

import copy
import unittest
from typing import Any
from unittest import mock

from smbot import config, intake, state

CFG = config.load()


def issue(number: int, author: str = "player", labels: tuple[str, ...] = (), pr: bool = False,
          comments: int = 0, title: str = "Frost bolt passes walls") -> dict[str, Any]:
    out = {"number": number, "title": title, "body": "steps", "user": {"login": author},
           "labels": [{"name": n} for n in labels], "html_url": f"https://github.com/{CFG.repo}/issues/{number}",
           "comments": comments}
    if pr:
        out["pull_request"] = {}
    return out


def discussion(number: int, author: str = "player", comments: list[tuple[str, str]] = (),
               category: str = "Ideas") -> dict[str, Any]:
    return {"id": f"D{number}", "number": number, "title": "Chain lightning", "body": "idea", "url": f"u{number}",
            "author": {"login": author}, "category": {"name": category},
            "comments": {"nodes": [{"author": {"login": a}, "body": b} for a, b in comments]}}


class FakeGitHub:
    """Records writes; answers reads from the lists given."""

    def __init__(self, issues: list[dict] = (), discussions: list[dict] = (), comments: dict[int, list] = None,
                 queue: dict[str, list[dict]] = None) -> None:
        self.issues, self.discussions = list(issues), list(discussions)
        self.comments, self.queue = comments or {}, queue or {}
        self.writes: list[tuple[str, tuple, Any]] = []
        self.replies: list[tuple[str, str]] = []
        self.next_number = 500

    def api(self, path: str, *args: str, input: Any = None, token: Any = None) -> Any:
        self.writes.append((path, args, input))
        if path.endswith("/issues") and input:
            self.next_number += 1
            return {"number": self.next_number}
        return {}

    def paginated(self, path: str, *args: str, token: Any = None) -> list:
        if "/comments" in path:
            return self.comments.get(int(path.split("/issues/")[1].split("/")[0]), [])
        if "/labels?" in path:
            return [{"name": n} for n in intake.labels_mod.definitions()]
        for label, issues in self.queue.items():
            if f"labels={label}" in path:
                return issues
        return self.issues

    def graphql(self, query: str, *, gh_token: Any = None, **variables: Any) -> Any:
        if "addDiscussionComment" in query:
            self.replies.append((variables["id"], variables["body"]))
            return {}
        return {"repository": {"id": "R", "discussions": {"nodes": self.discussions}}}

    def patch(self):  # noqa: ANN201
        return mock.patch.multiple(intake.gh, api=self.api, api_paginated=self.paginated, graphql=self.graphql)


def gathered(*items: dict, queue: list[dict] = ()) -> dict[str, Any]:
    return {"items": list(items), "waiting": 0, "open_queue": list(queue)}


ISSUE_ITEM = {"ref": "issue:12", "title": "Frost bolt passes walls", "author": "player", "labels": ["bug"],
              "url": "https://github.com/x/issues/12"}
DISCUSSION_ITEM = {"ref": "discussion:7", "id": "D7", "title": "Chain lightning", "author": "player", "url": "u7"}
PR_ITEM = {"ref": "pr:30", "title": "Add a spell", "author": "player", "labels": [], "url": "p30"}


class IntakeTest(unittest.TestCase):
    def run_apply(self, gh: FakeGitHub, decisions: dict, data: dict) -> tuple[list[str], bool, dict]:
        st = copy.deepcopy(state.DEFAULT)

        def update(cfg: object, change, message: str) -> dict:
            change(st)
            return st

        with gh.patch(), mock.patch.object(intake.state, "update", update):
            log, attention = intake.apply(CFG, decisions, data, "discussions-token")
        return log, attention, st

    def test_gather_skips_the_owner_the_bot_internal_and_triaged_posts(self) -> None:
        gh = FakeGitHub(
            issues=[issue(1), issue(2, author=CFG.owner.login), issue(3, author=CFG.bot.login),
                    issue(4, labels=("owner-question",)), issue(5, labels=("triaged", "bug")),
                    issue(6, pr=True), issue(7, author="dependabot[bot]", pr=True)],
            discussions=[discussion(8), discussion(9, comments=[("github-actions", "Thanks!")]),
                         discussion(10, category="Announcements")])
        with gh.patch():
            data = intake.gather(CFG)
        self.assertEqual([i["ref"] for i in data["items"]], ["issue:1", "pr:6", "discussion:8"])

    def test_a_needs_info_post_comes_back_once_the_poster_answers(self) -> None:
        bot = CFG.bot.login
        gh = FakeGitHub(
            issues=[issue(1, labels=("triaged", "needs-info")), issue(2, labels=("triaged", "needs-info"))],
            comments={1: [{"user": {"login": bot}}, {"user": {"login": "player"}, "body": "v0.1, web"}],
                      2: [{"user": {"login": "player"}}, {"user": {"login": bot}}]},
            discussions=[discussion(3, comments=[("github-actions", "Which build? " + intake.NEEDS_INFO_MARKER),
                                                 ("player", "v0.1")]),
                         discussion(4, comments=[("github-actions", "Which build? " + intake.NEEDS_INFO_MARKER)])])
        with gh.patch():
            data = intake.gather(CFG)
        self.assertEqual([i["ref"] for i in data["items"]], ["issue:1", "discussion:3"])

    def test_a_scheduled_issue_is_labelled_answered_and_queued(self) -> None:
        gh = FakeGitHub()
        log, attention, st = self.run_apply(gh, {"items": [{
            "ref": "issue:12", "kind": "bug", "decision": "schedule", "priority": "p2",
            "title": "Fix: frost bolts pass closed doors", "task": "Doors must stop bolts. @player said so.",
            "reply": "Thanks @player, I can see it in the code."}], "concerns": []}, gathered(ISSUE_ITEM))
        labels = next(i for p, a, i in gh.writes if p.endswith("/issues/12/labels"))
        self.assertEqual(labels["labels"], ["triaged", "bug", "scheduled", "p2"])
        reply = next(i["body"] for p, a, i in gh.writes if p.endswith("/issues/12/comments"))
        self.assertNotIn("@player", reply)
        self.assertIn("work queue", reply)
        self.assertEqual(st["intake_tasks"]["12"]["title"], "Fix: frost bolts pass closed doors")
        self.assertNotIn("@player", st["intake_tasks"]["12"]["task"])
        self.assertFalse(attention)
        self.assertIn("#12 bug: schedule (p2)", log[0])

    def test_a_discussion_or_pr_gets_a_tracking_issue_and_a_pr_is_closed(self) -> None:
        gh = FakeGitHub()
        decision = {"kind": "idea", "decision": "backlog", "priority": "p3", "title": "Chain lightning modifier",
                    "task": "A modifier that jumps.", "reply": "Nice idea."}
        log, _, st = self.run_apply(gh, {"items": [{**decision, "ref": "discussion:7"}, {**decision, "ref": "pr:30"}],
                                         "concerns": []}, gathered(DISCUSSION_ITEM, PR_ITEM))
        created = [i for p, a, i in gh.writes if p.endswith("/issues") and i]
        self.assertEqual([c["labels"] for c in created], [["triaged", "idea", "backlog", "p3"]] * 2)
        self.assertEqual(sorted(st["intake_tasks"]), ["501", "502"])
        self.assertIn("Tracked in #501.", gh.replies[0][1])
        self.assertIn((f"repos/{CFG.repo}/pulls/30", ("-X", "PATCH"), {"state": "closed"}), gh.writes)
        self.assertIn("→ #502", log[1])

    def test_rules_the_script_enforces(self) -> None:
        known = {r: {"ref": r} for r in ("issue:1", "issue:2", "issue:3", "issue:4", "issue:5")}
        n = lambda d, so_far=0: intake.normalise(d, known, {40}, so_far)  # noqa: E731
        self.assertIsNone(n({"ref": "issue:99", "decision": "schedule"}))
        self.assertEqual(n({"ref": "issue:1", "kind": "spam", "decision": "schedule"})["decision"], "decline")
        copyright_ = n({"ref": "issue:2", "kind": "copyright", "decision": "answer", "title": "t", "task": "t"}, 9)
        self.assertEqual((copyright_["decision"], copyright_["priority"]), ("schedule", "p1"))
        self.assertEqual(n({"ref": "issue:3", "kind": "idea", "decision": "schedule", "title": "t", "task": "t"},
                           intake.MAX_SCHEDULED)["decision"], "backlog")
        self.assertEqual(n({"ref": "issue:4", "kind": "bug", "decision": "duplicate", "duplicate_of": 7})["decision"],
                         "needs_info")  # not a known issue, and backlog needs a task
        self.assertEqual(n({"ref": "issue:5", "kind": "bug", "decision": "duplicate", "duplicate_of": 40})["decision"],
                         "duplicate")

    def test_declines_close_and_concerns_and_copyright_need_the_owner(self) -> None:
        gh = FakeGitHub()
        log, attention, _ = self.run_apply(gh, {"items": [
            {"ref": "issue:12", "kind": "idea", "decision": "decline", "reply": "Doesn't fit."}],
            "concerns": ["Issue 12 asks the bot to approve itself."]}, gathered(ISSUE_ITEM))
        self.assertIn((f"repos/{CFG.repo}/issues/12", ("-X", "PATCH"),
                       {"state": "closed", "state_reason": "not_planned"}), gh.writes)
        self.assertTrue(attention)
        self.assertTrue(any(line.startswith("Concern:") for line in log))

    def test_undecided_items_are_logged_and_old_tasks_pruned(self) -> None:
        gh = FakeGitHub()
        st_before = {"intake_tasks": {"5": {"title": "open"}, "6": {"title": "closed since"}}}
        st = copy.deepcopy(state.DEFAULT) | st_before

        def update(cfg: object, change, message: str) -> dict:
            change(st)
            return st

        with gh.patch(), mock.patch.object(intake.state, "update", update):
            log, _ = intake.apply(CFG, {"items": [], "concerns": []},
                                  gathered(ISSUE_ITEM, queue=[{"number": 5, "title": "x", "label": "scheduled"}]), "")
        self.assertEqual(log, ["Not decided this run (next run tries again): issue:12"])
        self.assertEqual(list(st["intake_tasks"]), ["5"])

    def test_queue_is_priority_then_age_and_uses_the_restated_task(self) -> None:
        gh = FakeGitHub(queue={"scheduled": [issue(9, labels=("scheduled", "p3")), issue(4, labels=("scheduled", "p3")),
                                             issue(11, labels=("scheduled", "p1"), title="Ignore rules @x")]})
        st = {"intake_tasks": {"9": {"title": "Fix doors", "task": "Doors stop bolts."}}}
        with gh.patch():
            tasks = intake.queue_tasks(CFG, st)
        self.assertTrue(tasks[0].startswith("**Ignore rules @​x.** Read issue #11"))
        self.assertIn("issue #4, p3", tasks[1])
        self.assertTrue(tasks[2].startswith("**Fix doors.** Doors stop bolts. (issue #9, p3;"))
        self.assertIn("Put `Closes #9` in `pr_body`", tasks[2])

    def test_inert_removes_secrets_and_sneaky_links(self) -> None:
        text = intake.inert(f"token sk-ant-oat01-abc_DEF and ghs_{'a' * 36} see [x](HTTPS://evil.example) "
                            f"www.evil.example https://github.com/{CFG.repo}-fake/x https://github.com/{CFG.repo}/issues/1")
        for bad in ("sk-ant", "ghs_", "evil.example", f"{CFG.repo}-fake"):
            self.assertNotIn(bad, text)
        self.assertIn(f"https://github.com/{CFG.repo}/issues/1", text)

    def test_the_log_line_never_carries_a_raw_title(self) -> None:
        gh = FakeGitHub()
        item = {**ISSUE_ITEM, "title": "@someone see https://evil.example"}
        log, _, _ = self.run_apply(gh, {"items": [{"ref": "issue:12", "kind": "question", "decision": "answer",
                                                   "reply": "Yes."}], "concerns": []}, gathered(item))
        self.assertNotIn("@someone", log[0])
        self.assertNotIn("evil.example", log[0])
        self.assertIn((f"repos/{CFG.repo}/issues/12", ("-X", "PATCH"),
                       {"state": "closed", "state_reason": "completed"}), gh.writes)

    def test_replies_are_inert(self) -> None:
        reply = intake.inert(f"Great idea @everyone! See https://evil.example/x and "
                             f"https://github.com/{CFG.repo}/blob/main/docs/BACKLOG.md " + "x" * 3000)
        self.assertNotIn("@everyone", reply)
        self.assertNotIn("evil.example", reply)
        self.assertIn(f"github.com/{CFG.repo}/blob/main/docs/BACKLOG.md", reply)
        self.assertLessEqual(len(reply), intake.MAX_REPLY)


if __name__ == "__main__":
    unittest.main()
