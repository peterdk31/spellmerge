from __future__ import annotations

import copy
import datetime as dt
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from smbot import config, merge, session, state

CFG = config.load()


def result(**kw: object) -> list[dict]:
    base = {"type": "result", "subtype": "success", "is_error": False, "result": "done",
            "usage": {"input_tokens": 1000, "output_tokens": 500, "cache_creation_input_tokens": 2000,
                      "cache_read_input_tokens": 10000}}
    base.update(kw)
    return [{"type": "system"}, {"type": "assistant"}, base]


class ClassifyTest(unittest.TestCase):
    def test_success_counts_tokens(self) -> None:
        self.assertEqual(session.classify(result(), False), ("ok", 4500, ""))

    def test_usage_limit(self) -> None:
        status, _, _ = session.classify(result(is_error=True, result="Claude AI usage limit reached|1760900000"), True)
        self.assertEqual(status, "limit")
        status, _, _ = session.classify(result(is_error=True, result="You've reached your weekly limit"), True)
        self.assertEqual(status, "limit-weekly")

    def test_session_limit_message(self) -> None:
        """The message of run #43 on 2026-10-16, which was taken for an ordinary error."""
        text = "You've hit your session limit · resets 12am (UTC)"
        self.assertEqual(session.classify(result(is_error=True, result=text), True)[0], "limit")
        now = dt.datetime(2026, 10, 16, 23, 50, tzinfo=dt.timezone.utc)
        self.assertEqual(session.reset_time(text, now), dt.datetime(2026, 10, 17, 0, 0, tzinfo=dt.timezone.utc))

    def test_reset_times(self) -> None:
        now = dt.datetime(2026, 10, 17, 10, 0, tzinfo=dt.timezone.utc)
        utc = dt.timezone.utc
        self.assertEqual(session.reset_time("resets at 3:30pm (UTC)", now), dt.datetime(2026, 10, 17, 15, 30, tzinfo=utc))
        self.assertEqual(session.reset_time("resets 9am", now), dt.datetime(2026, 10, 18, 9, 0, tzinfo=utc))
        # 1pm in Copenhagen (CEST, UTC+2) is 11:00 UTC
        self.assertEqual(session.reset_time("resets 1pm (Europe/Copenhagen)", now),
                         dt.datetime(2026, 10, 17, 11, 0, tzinfo=utc))
        self.assertEqual(session.reset_time("resets 1pm (Mars/Base)", now), dt.datetime(2026, 10, 17, 13, 0, tzinfo=utc))
        self.assertIsNone(session.reset_time("no time here", now))
        self.assertEqual(session.resets_at("error", "resets 9am"), "")

    def test_success_over_the_turn_cap_still_counts(self) -> None:
        """Run #99 finished the task in 206 turns; the action failed the step for passing 150."""
        out = {"status": "ready", "pr_title": "t", "summary": "s"}
        msgs = result(num_turns=206, result=json.dumps(out))
        self.assertEqual(session.classify(msgs, True)[0], "ok")
        self.assertEqual(json.loads(session.structured_result(msgs)), out)
        self.assertEqual(json.loads(session.structured_result(result(structured_output=out, result="done"))), out)
        self.assertEqual(session.structured_result(result(is_error=True, result=json.dumps(out))), "")
        self.assertEqual(session.structured_result(result(result="not json")), "")

    def test_rejected_token(self) -> None:
        status, _, _ = session.classify(result(is_error=True, result="Invalid bearer token"), True)
        self.assertEqual(status, "auth")
        self.assertEqual(session.classify([], True)[0], "error")

    def test_other_failures(self) -> None:
        self.assertEqual(session.classify(result(is_error=True, subtype="error_max_turns", result=""), True)[0], "error")
        self.assertEqual(session.classify([], False)[0], "error")

    def test_reads_json_array_and_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            arr, lines = Path(tmp, "a.json"), Path(tmp, "b.json")
            arr.write_text(json.dumps(result()))
            lines.write_text("\n".join(json.dumps(m) for m in result()))
            self.assertEqual(session.read_messages(arr), session.read_messages(lines))
            self.assertEqual(session.read_messages(Path(tmp, "missing")), [])


FIXTURE_TASK = "**Area READMEs for the content areas.** Write the READMEs."


@mock.patch.object(session.nexttask, "next_task", lambda *a, **k: FIXTURE_TASK)
@mock.patch.object(session, "queue", lambda cfg, st, strict=False: [])
@mock.patch.object(session, "open_checkpoint", lambda cfg: None)
class PromptTest(unittest.TestCase):
    """Uses a fixed task, so the tests don't depend on what docs/NEXT.md says today."""

    def test_render_and_slug(self) -> None:
        self.assertEqual(session.render("a {{X}} {{Y}}", {"X": "1"}), "a 1 {{Y}}")
        self.assertEqual(session.slug("**Area READMEs for the content areas.** Write..."),
                         "area-readmes-for-the-content-areas")

    def test_prepare_continues_an_open_pr_for_the_task(self) -> None:
        pr = {"number": 15, "user": {"login": CFG.bot.login},
              "head": {"ref": "claude/20261016-area-readmes-for-the-content-areas"}}
        with mock.patch.object(session.gh, "api", return_value=[pr]):
            out = session.prepare(CFG, copy.deepcopy(state.DEFAULT), "", dt.date(2026, 10, 17))
        self.assertEqual(out["branch"], "claude/20261016-area-readmes-for-the-content-areas")
        self.assertIn("PR #15 is already open", out["prompt"])
        self.assertIn("git merge origin/main", out["prompt"])  # a continued PR is brought up to date

    def test_prepare_includes_task_and_instructions(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        st["pending_instructions"] = [{"kind": "ask", "text": "how is it going?", "number": 9, "url": "u"}]
        with mock.patch.object(session.gh, "api", return_value=[]):
            out = session.prepare(CFG, st, "bugs first", dt.date(2026, 10, 17))
        self.assertIn("Area READMEs for the content areas", out["prompt"])
        self.assertIn("`/ask` on #9", out["prompt"])
        self.assertIn("bugs first", out["prompt"])
        self.assertNotIn("{{", out["prompt"])
        self.assertTrue(out["branch"].startswith("claude/20261017-area-readmes"))

    def test_prepare_mentions_previous_failure(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        st["task_failures"] = {FIXTURE_TASK: {"count": 1, "pr": 12, "problems": "- missing tests"}}
        with mock.patch.object(session.gh, "api", return_value=[]):
            prompt = session.prepare(CFG, st, "", dt.date(2026, 10, 17))["prompt"]
        self.assertIn("PR #12", prompt)
        self.assertIn("last attempt", prompt)

    def test_prepare_briefs_an_unblocked_task(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        with mock.patch.object(session.gh, "api", return_value=[]), \
                mock.patch.object(session.inbox, "answered_keys", lambda cfg, st: {"some-key"}), \
                mock.patch.object(session.nexttask, "blocked", lambda text: {FIXTURE_TASK: {"some-key"}}):
            prompt = session.prepare(CFG, st, "", dt.date(2026, 10, 22))["prompt"]
        self.assertIn("waiting on the owner question(s) with key `some-key`", prompt)
        self.assertIn("back to the top of \"## Queue\"", prompt)
        with mock.patch.object(session.gh, "api", return_value=[]), \
                mock.patch.object(session.inbox, "answered_keys", lambda cfg, st: set()), \
                mock.patch.object(session.nexttask, "blocked", lambda text: {FIXTURE_TASK: {"some-key"}}):
            self.assertNotIn("owner question(s)", session.prepare(CFG, st, "", dt.date(2026, 10, 22))["prompt"])

    def test_prepare_plan_builds_the_planning_prompt(self) -> None:
        """A parameter named `weekly` once hid the weekly module, so every planning session crashed."""
        st = copy.deepcopy(state.DEFAULT)
        with mock.patch.object(session.weekly, "backlog_text", lambda cfg, st: "[]"), \
                mock.patch.object(session, "open_pr_for", lambda cfg, slug: None):
            out = session.prepare_plan(CFG, st, "", dt.date(2026, 10, 22), weekly_run=False)
            weekly_out = session.prepare_plan(CFG, st, "", dt.date(2026, 10, 25), weekly_run=True)
        self.assertEqual((out["kind"], out["task"]), ("plan", "Planning"))
        self.assertRegex(out["branch"], r"^claude/\d{8}-\d{4}-planning$")
        self.assertIn("the work queue is empty", out["prompt"])
        self.assertIn("weekly run on Sunday", weekly_out["prompt"])
        self.assertNotIn("{{", out["prompt"])

    def test_prepare_plan_continues_an_open_planning_pr(self) -> None:
        pr = {"number": 12, "head": {"ref": "claude/20261022-0900-planning"}}
        with mock.patch.object(session.weekly, "backlog_text", lambda cfg, st: "[]"), \
                mock.patch.object(session, "open_pr_for", lambda cfg, slug: pr if slug == "planning" else None):
            out = session.prepare_plan(CFG, copy.deepcopy(state.DEFAULT), "", dt.date(2026, 10, 22))
        self.assertEqual(out["branch"], "claude/20261022-0900-planning")
        self.assertIn("PR #12", out["prompt"])

    def test_review_and_revise_prompts(self) -> None:
        r = session.review_prompt(CFG, 7, "abc", "final")
        self.assertIn("#7 at commit abc", r)
        self.assertIn(".review/pr.diff", r)  # the saved diff, not `gh pr diff`'s unreadable overflow
        self.assertIn("git show abc:", r)
        p = session.revise_prompt(CFG, 7, {"summary": "s", "problems": [
            {"severity": "major", "file": "a.gd", "line": 3, "problem": "p", "fix": "f"}]})
        self.assertIn("[major] a.gd:3: p Fix: f", p)

    def test_mergeable(self) -> None:
        self.assertTrue(session.mergeable({"verdict": "approve", "problems": [{"severity": "minor"}]}))
        self.assertFalse(session.mergeable({"verdict": "approve", "problems": [{"severity": "major"}]}))
        self.assertFalse(session.mergeable({"verdict": "revise", "problems": []}))


class SchemaTest(unittest.TestCase):
    def test_schemas_survive_the_shell_quoting(self) -> None:
        """The workflows pass each schema inside single quotes (--json-schema '...'), so a quote breaks it."""
        for path in sorted(session.MAINTAINER.joinpath("schemas").glob("*.json")):
            text = path.read_text()
            json.loads(text)
            self.assertNotIn("'", text, f"{path.name} contains a single quote")


class FinishTest(unittest.TestCase):
    """finish() decides whether the next session starts right away."""

    APPROVE = json.dumps({"verdict": "approve", "problems": []})
    REVISE = json.dumps({"verdict": "revise", "problems": [{"severity": "major", "problem": "p", "fix": "f"}]})

    def run_finish(self, st: dict, queue: list[str], posts: list | None = None, checkpoint_issue: int | None = None,
                   extras: list | None = None, shots: str = "", **env: str) -> tuple[dict[str, str], dict]:
        base = {"TASK": "A", "TASK_KIND": "next", "PR": "", "IMPLEMENT_STATUS": "ready", "FINAL_REVIEW": "",
                "MERGED": "", "SETTINGS": "{}"}
        base.update(env)

        def update(cfg: object, change, message: str) -> dict:
            change(st)
            return st

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp, "NEXT.md")
            path.write_text("## Queue\n\n" + "".join(f"- [ ] {t}\n" for t in queue))
            real = session.nexttask.next_task
            with mock.patch.object(session.state, "update", update), \
                    mock.patch.object(session.state, "load", lambda cfg: (st, "sha")), \
                    mock.patch.object(session.dailylog, "post",
                                      lambda cfg, title, lines, **k: ((posts if posts is not None else []).append(lines),
                                                                      (extras if extras is not None else []).append(
                                                                          k.get("extra", "")))), \
                    mock.patch.object(session.screenshots, "for_log", lambda cfg, pr: shots), \
                    mock.patch.object(session, "pr_title", lambda cfg, pr: f"Title of #{pr}" if pr else ""), \
                    mock.patch.object(session, "announce_park",
                                      lambda cfg, task, e: f"Parked until {e['parked_until']}: {e['parked_reason']}"), \
                    mock.patch.object(session, "unlabel_parked", lambda cfg, pr: None), \
                    mock.patch.object(session, "queue", lambda cfg, st, strict=False: []), \
                    mock.patch.object(session, "open_checkpoint", lambda cfg: checkpoint_issue), \
                    mock.patch.object(session.inbox, "answered_keys", lambda cfg, st: set()), \
                    mock.patch.object(session.nexttask, "next_task",
                                      lambda path_=None, skip=(), first=(), answered=(): real(path, skip, first,
                                                                                              answered=answered)):
                return session.finish(CFG, base), st

    def test_continues_after_a_merge(self) -> None:
        out, _ = self.run_finish(copy.deepcopy(state.DEFAULT), ["B"], PR="5", FINAL_REVIEW=self.APPROVE,
                                 MERGED="true")
        self.assertEqual(out["again"], "true")

    def test_log_lines_name_the_pr_and_stay_short(self) -> None:
        posts: list = []
        self.run_finish(copy.deepcopy(state.DEFAULT), ["B"], posts, PR="5", FINAL_REVIEW=self.APPROVE, MERGED="true")
        self.run_finish(copy.deepcopy(state.DEFAULT), ["A", "B"], posts, IMPLEMENT_STATUS="blocked",
                        TASK="**Do the thing.** With a long description", IMPLEMENT_SUMMARY="It waits. " * 100)
        self.assertEqual(posts[0][0], "Merged #5: Title of #5")
        self.assertTrue(posts[1][0].startswith("Blocked, set aside for a week: Do the thing. It waits."))
        self.assertLess(len(posts[1][0]), 400)
        self.assertTrue(posts[1][0].endswith("It waits."))

    def test_the_log_shows_the_prs_screenshots(self) -> None:
        extras: list = []
        self.run_finish(copy.deepcopy(state.DEFAULT), ["B"], extras=extras, shots="**What #5 changes on screen**",
                        PR="5", FINAL_REVIEW=self.APPROVE, MERGED="true")
        self.run_finish(copy.deepcopy(state.DEFAULT), ["A", "B"], extras=extras, IMPLEMENT_STATUS="blocked")
        self.assertEqual(extras, ["**What #5 changes on screen**", ""])

    def test_two_failed_reviews_park_for_a_day_three_for_a_week_and_say_so(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        st["task_failures"] = {"A": {"count": 1, "pr": 5}}
        posts: list = []
        _, st = self.run_finish(st, ["A", "B"], posts, PR="5", FINAL_REVIEW=self.REVISE)
        until = dt.datetime.fromisoformat(st["task_failures"]["A"]["parked_until"].replace("Z", "+00:00"))
        self.assertLess(until - dt.datetime.now(dt.timezone.utc), dt.timedelta(days=1, minutes=1))
        self.assertTrue(any("Parked until" in line for line in posts[-1]))
        st["task_failures"]["A"].pop("parked_until")
        _, st = self.run_finish(st, ["A", "B"], posts, PR="5", FINAL_REVIEW=self.REVISE)
        until = dt.datetime.fromisoformat(st["task_failures"]["A"]["parked_until"].replace("Z", "+00:00"))
        self.assertGreater(until - dt.datetime.now(dt.timezone.utc), dt.timedelta(days=6))

    def test_continues_after_a_failed_review_without_waiting(self) -> None:
        out, st = self.run_finish(copy.deepcopy(state.DEFAULT), ["A", "B"], PR="5", FINAL_REVIEW=self.REVISE)
        self.assertEqual(out["again"], "true")
        self.assertEqual(st["task_failures"]["A"]["count"], 1)
        self.assertNotIn("parked_until", st["task_failures"]["A"])

    def test_a_task_that_failed_twice_is_parked_and_work_moves_on(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        st["task_failures"] = {"A": {"count": 1, "pr": 5}}
        out, st = self.run_finish(st, ["A", "B"], PR="5", FINAL_REVIEW=self.REVISE)
        self.assertIn("parked_until", st["task_failures"]["A"])
        self.assertEqual(out["again"], "true")
        out, _ = self.run_finish(st, ["A"], PR="5", FINAL_REVIEW=self.REVISE)
        self.assertEqual(out["again"], "true")  # only the parked task is left: the next run plans

    def test_blocked_and_refused_merges_are_parked(self) -> None:
        out, st = self.run_finish(copy.deepcopy(state.DEFAULT), ["A", "B"], IMPLEMENT_STATUS="blocked")
        self.assertIn("parked_until", st["task_failures"]["A"])
        self.assertEqual(out["again"], "true")
        out, st = self.run_finish(copy.deepcopy(state.DEFAULT), ["A", "B"], PR="5", FINAL_REVIEW=self.APPROVE,
                                  MERGED="false", MERGE_RESULT="Not merged: GitHub refused the merge")
        self.assertIn("refused", st["task_failures"]["A"]["parked_reason"])
        self.assertEqual(out["again"], "true")

    def test_a_blocked_session_hands_the_owners_instruction_on_once(self) -> None:
        """Run #505 reported blocked on the owner's "more options" answer on #192, which was then lost."""
        st = copy.deepcopy(state.DEFAULT)
        st["pending_instructions"] = [
            {"kind": "claude", "number": 192, "text": "more options", "url": "u", "at": "t"},
            {"kind": "ask", "number": 9, "text": "why?", "url": "u", "at": "t"}]
        posts: list = []
        out, st = self.run_finish(st, ["A", "B"], posts, IMPLEMENT_STATUS="blocked")
        self.assertEqual([(p["number"], p["bounced"]) for p in st["pending_instructions"]], [(192, True)])
        self.assertNotIn("parked_until", st.get("task_failures", {}).get("A", {}))
        self.assertTrue(any("#192" in line and "next session" in line for line in posts[-1]))
        self.assertEqual(out["again"], "true")
        _, st = self.run_finish(st, ["A", "B"], posts, IMPLEMENT_STATUS="blocked")
        self.assertEqual(st["pending_instructions"], [])
        self.assertIn("parked_until", st["task_failures"]["A"])

    def test_the_unblocked_brief_follows_an_answer_that_asks_for_something_else(self) -> None:
        text = session.unblocked_text(["art-direction-pick-2"])
        self.assertIn("The answer is your brief", text)
        self.assertIn("never a reason to report `blocked`", text)

    def test_a_task_with_nothing_to_do_is_set_aside_and_work_moves_on(self) -> None:
        """Run #127: the first task waited on an owner question, so every session stopped at once."""
        out, st = self.run_finish(copy.deepcopy(state.DEFAULT), ["A", "B"], IMPLEMENT_STATUS="nothing_to_do",
                                  IMPLEMENT_SUMMARY="waits on #84")
        self.assertIn("#84", st["task_failures"]["A"]["parked_reason"])
        self.assertEqual(out["again"], "true")
        out, _ = self.run_finish(st, ["A"], IMPLEMENT_STATUS="nothing_to_do")
        self.assertEqual(out["again"], "true")  # only the parked task is left: the next run plans
        out, st = self.run_finish(copy.deepcopy(state.DEFAULT), ["B"], TASK="", IMPLEMENT_STATUS="nothing_to_do")
        self.assertEqual(out["again"], "true")  # an empty queue: the next run plans
        self.assertEqual(st.get("task_failures", {}), {})

    def test_a_conflict_sends_the_pr_back_instead_of_parking_it(self) -> None:
        out, st = self.run_finish(copy.deepcopy(state.DEFAULT), ["A", "B"], PR="19", FINAL_REVIEW=self.APPROVE,
                                  MERGED="false", MERGE_RESULT=f"Not merged: {merge.CONFLICT}: merge origin/main")
        entry = st["task_failures"]["A"]
        self.assertEqual(entry["count"], 1)
        self.assertNotIn("parked_until", entry)
        self.assertIn("git merge origin/main", entry["problems"])
        self.assertEqual(out["again"], "true")

    def test_a_usage_limit_asks_to_resume_at_its_reset(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        until = dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=30)
        st["backoff_until"] = state_iso = until.isoformat(timespec="seconds").replace("+00:00", "Z")
        out, _ = self.run_finish(st, ["A"], IMPLEMENT_STATUS="limit")
        self.assertEqual((out["again"], out["resume_at"]), ("false", state_iso))
        out, _ = self.run_finish(copy.deepcopy(state.DEFAULT), ["A"], IMPLEMENT_STATUS="error")
        self.assertEqual(out["resume_at"], "")

    def test_stops_only_for_limits_pauses_the_token_and_idle_planning(self) -> None:
        for env in ({"IMPLEMENT_STATUS": "limit"}, {"IMPLEMENT_STATUS": "auth"},
                    {"PR": "5", "FINAL_REVIEW": self.APPROVE, "MERGED": ""},
                    {"TASK_KIND": "plan", "TASK": "Weekly planning", "IMPLEMENT_STATUS": "nothing_to_do"}):
            out, _ = self.run_finish(copy.deepcopy(state.DEFAULT), [], **env)
            self.assertEqual(out["again"], "false", env)

    def test_a_merged_plan_flows_into_development(self) -> None:
        out, st = self.run_finish(copy.deepcopy(state.DEFAULT), [], TASK_KIND="plan", TASK="Planning",
                                  PR="7", FINAL_REVIEW=self.APPROVE, MERGED="true")
        self.assertEqual(out["again"], "true")
        self.assertIsNotNone(st["last_plan"])

    def test_weekly_planning_with_no_changes_is_not_idle_while_tasks_remain(self) -> None:
        posts: list = []
        out, _ = self.run_finish(copy.deepcopy(state.DEFAULT), ["A"], posts, TASK_KIND="plan",
                                 TASK="Planning", IMPLEMENT_STATUS="nothing_to_do")
        self.assertFalse(any("idle" in line for lines in posts for line in lines))

    def test_idle_planning_tells_the_owner(self) -> None:
        posts: list = []
        self.run_finish(copy.deepcopy(state.DEFAULT), [], posts, TASK_KIND="plan", TASK="Planning",
                        IMPLEMENT_STATUS="nothing_to_do")
        self.assertTrue(any("Development is idle" in line for lines in posts for line in lines))

    def test_idle_is_told_once_and_cleared_by_progress(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        posts: list = []
        for _ in range(2):
            out, st = self.run_finish(st, [], posts, TASK_KIND="plan", TASK="Planning", IMPLEMENT_STATUS="nothing_to_do")
            self.assertEqual(out["again"], "false")
        self.assertEqual(sum("Development is idle" in line for lines in posts for line in lines), 1)
        self.assertIsNotNone(st["idle"])
        _, st = self.run_finish(st, ["A"], PR="5", FINAL_REVIEW=self.APPROVE, MERGED="true")
        self.assertIsNone(st.get("idle"))

    def test_an_empty_session_clears_its_instructions(self) -> None:
        """An /ask with an empty queue used to start the same session again and again."""
        st = copy.deepcopy(state.DEFAULT)
        st["pending_instructions"] = [{"kind": "ask", "number": 3, "url": "u", "text": "how is M2?"}]
        out, st = self.run_finish(st, [], TASK="", IMPLEMENT_STATUS="nothing_to_do")
        self.assertEqual(st["pending_instructions"], [])

    def test_planning_keeps_the_owners_instructions_for_development(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        st["pending_instructions"] = [{"kind": "ask", "number": 3, "url": "u", "text": "how is M2?"}]
        _, st = self.run_finish(st, ["A"], TASK_KIND="plan", TASK="Planning", IMPLEMENT_STATUS="nothing_to_do")
        _, st = self.run_finish(st, ["A"], TASK_KIND="plan", TASK="Planning", PR="7", FINAL_REVIEW=self.APPROVE,
                                MERGED="true")
        self.assertEqual(len(st["pending_instructions"]), 1)

    def test_the_weekly_planning_stays_due_after_a_usage_limit(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        _, st = self.run_finish(st, ["A"], TASK_KIND="plan", TASK="Planning", WEEKLY="true", IMPLEMENT_STATUS="limit")
        self.assertIsNone(st["last_weekly"])
        _, st = self.run_finish(st, ["A"], TASK_KIND="plan", TASK="Planning", WEEKLY="true",
                                IMPLEMENT_STATUS="nothing_to_do")
        self.assertIsNotNone(st["last_weekly"])

    def test_planning_with_nothing_to_change_carries_on_while_work_remains(self) -> None:
        out, _ = self.run_finish(copy.deepcopy(state.DEFAULT), ["A"], TASK_KIND="plan", TASK="Planning",
                                 IMPLEMENT_STATUS="nothing_to_do")
        self.assertEqual(out["again"], "true")

    def test_an_answer_planning_couldnt_carry_out_goes_back_to_the_owner(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        session.checkpoint.record(st, 50, "iterate", "x", "u", "2026-10-22T10:00:00Z")
        handed: list = []
        posts: list = []
        with mock.patch.object(session, "checkpoint_not_carried_out",
                               lambda cfg, n, summary: handed.append(n) or ["back to you"]):
            _, st = self.run_finish(st, [], posts, checkpoint_issue=50, TASK_KIND="plan", TASK="Planning",
                                    IMPLEMENT_STATUS="nothing_to_do", IMPLEMENT_SUMMARY="unclear")
        self.assertEqual((handed, st["checkpoint_answers"]), ([50], {}))

    def test_a_merged_plan_leaves_a_checkpoint_closed_by_hand_alone(self) -> None:
        calls: list = []

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            calls.append((path, input))
            return {"state": "closed"}

        with mock.patch.object(session.gh, "api", api):
            self.assertEqual(session.close_checkpoint(CFG, 50, "8"), [])
        self.assertEqual([c for c in calls if c[1]], [])

    def test_no_idle_alarm_while_a_checkpoint_waits(self) -> None:
        posts: list = []
        self.run_finish(copy.deepcopy(state.DEFAULT), [], posts, checkpoint_issue=50, TASK_KIND="plan",
                        TASK="Planning", IMPLEMENT_STATUS="nothing_to_do")
        self.assertFalse(any("idle" in line for lines in posts for line in lines))

    def test_a_merged_plan_that_answers_the_checkpoint_closes_it(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        session.checkpoint.record(st, 50, "go", "", "u", "2026-10-22T10:00:00Z")
        closed: list = []
        with mock.patch.object(session, "close_checkpoint", lambda cfg, n, pr: closed.append((n, pr)) or ["x"]):
            out, _ = self.run_finish(st, [], checkpoint_issue=50, TASK_KIND="plan", TASK="Planning", PR="8",
                                     FINAL_REVIEW=self.APPROVE, MERGED="true")
        self.assertEqual((closed, out["again"]), ([(50, "8")], "true"))

    def test_errors_are_retried_then_raise_an_alarm(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        raised: list = []
        with mock.patch.object(session.alarms, "raise_alarm",
                               lambda cfg, st_, name, **k: raised.append(name) or "Alarm raised: #9"):
            for attempt in range(1, state.MAX_ERRORS_IN_A_ROW + 1):
                out, st = self.run_finish(st, ["A"], IMPLEMENT_STATUS="error")
                self.assertEqual(st["errors_in_a_row"], attempt)
                self.assertEqual(out["again"], "true" if attempt < state.MAX_ERRORS_IN_A_ROW else "false")
        self.assertEqual(raised, ["stopped"])
        posts: list = []
        with mock.patch.object(session.alarms, "raise_alarm", lambda *a, **k: None):  # already open
            self.run_finish(st, ["A"], posts, IMPLEMENT_STATUS="error")
        self.assertFalse(any(lines for lines in posts if "Development stopped" in str(lines)))
        _, st = self.run_finish(st, ["A", "B"], PR="5", FINAL_REVIEW=self.APPROVE, MERGED="true")
        self.assertEqual(st["errors_in_a_row"], 0)


class PublishTest(unittest.TestCase):
    def test_a_park_is_announced_on_the_pr_with_the_reviews_points(self) -> None:
        calls: list = []
        entry = {"pr": "156", "parked_until": "2026-10-23T11:08:02Z", "long": False, "problems": "- Fix the comment.",
                 "parked_reason": "the final review didn't approve it 2 times in a row"}
        with mock.patch.object(session.gh, "api", lambda path, *a, input=None, **k: calls.append((path, input)) or {}), \
                mock.patch.object(session.labels_mod, "ensure"):
            line = session.announce_park(CFG, "**Bots build spells (M2 part 20).** more", entry)
        comment = next(i["body"] for p, i in calls if p.endswith("/issues/156/comments"))
        self.assertIn("**Parked until 2026-10-23 11:08 UTC:**", comment)
        self.assertIn("- Fix the comment.", comment)
        self.assertIn("`/retry`", comment)
        self.assertIn((f"repos/{CFG.repo}/issues/156/labels", {"labels": ["parked"]}), calls)
        self.assertTrue(line.startswith("Parked until 2026-10-23 11:08 UTC: Bots build spells (M2 part 20) (#156"))

    def test_open_pr_finds_only_the_bots_pr(self) -> None:
        own = {"number": 19, "user": {"login": CFG.bot.login}, "head": {"sha": "abc", "repo": {"full_name": CFG.repo}}}
        other = {"number": 20, "user": {"login": "someone"}, "head": {"sha": "def", "repo": {"full_name": CFG.repo}}}
        with mock.patch.object(session.gh, "api", return_value=[other, own]):
            self.assertEqual(session.open_pr(CFG, "claude/20261016-x"),
                             {"pr": "19", "sha": "abc", "branch": "claude/20261016-x"})
        with mock.patch.object(session.gh, "api", return_value=[other]):
            self.assertEqual(session.open_pr(CFG, "claude/20261016-x"), {})
        self.assertEqual(session.open_pr(CFG, "main"), {})

    def test_task_title(self) -> None:
        self.assertEqual(session.task_title("**Unit tests for spells.** Add tests for ..."), "Unit tests for spells")
        self.assertEqual(session.task_title("Fix the HUD."), "Fix the HUD")
        self.assertEqual(session.task_title(""), "Claude's work")

    def _publish(self, api: mock.Mock, mode: str, pr: int | None = None) -> dict[str, str]:
        done = mock.Mock(returncode=0, stdout="abcdef1234\n")
        with mock.patch.object(session.subprocess, "run", return_value=done), \
                mock.patch.object(session, "workflow_changes", return_value=[]), \
                mock.patch.object(session.gh, "api", api):
            return session.publish(CFG, Path("work.bundle"), "claude/20261017-x", mode, {}, pr, "t",
                                   unfinished="usage limit", task="**Unit tests.** More words.")

    def test_unfinished_work_is_kept_in_a_draft_pr(self) -> None:
        api = mock.Mock(side_effect=[[], {"number": 70}])
        self.assertEqual(self._publish(api, "new"), {"saved_pr": "70", "branch": "claude/20261017-x"})
        created = api.call_args_list[1].kwargs["input"]
        self.assertTrue(created["draft"])
        self.assertEqual(created["title"], "Unfinished: Unit tests")
        self.assertIn("usage limit", created["body"])

    def test_unfinished_work_on_an_open_pr_comments_without_a_review(self) -> None:
        api = mock.Mock(side_effect=[[{"number": 19}], {}])
        out = self._publish(api, "new")
        self.assertEqual(out, {"saved_pr": "19", "branch": "claude/20261017-x"})
        self.assertNotIn("sha", out)  # no sha: no review starts
        self.assertIn("Pushed abcdef1", api.call_args_list[1].kwargs["input"]["body"])
        pr = {"head": {"ref": "claude/20261017-x"}, "user": {"login": CFG.bot.login}, "state": "open"}
        api = mock.Mock(side_effect=[pr, {}])
        self.assertEqual(self._publish(api, "update", 19), {"saved_pr": "19", "branch": "claude/20261017-x"})

    def test_a_revision_replaces_the_pr_body(self) -> None:
        pr = {"head": {"ref": "claude/20261017-x"}, "user": {"login": CFG.bot.login}, "state": "open"}
        done = mock.Mock(returncode=0, stdout="abcdef1234\n")
        api = mock.Mock(side_effect=[pr, {}, {}])
        with mock.patch.object(session.subprocess, "run", return_value=done), \
                mock.patch.object(session, "workflow_changes", return_value=[]), \
                mock.patch.object(session.gh, "api", api):
            out = session.publish(CFG, Path("work.bundle"), "claude/20261017-x", "update",
                                  {"pr_body": "Tests passed.", "comment": "Fixed."}, 19, "t")
        self.assertEqual(out, {"pr": "19", "sha": "abcdef1234", "branch": "claude/20261017-x"})
        self.assertEqual(api.call_args_list[1].args[0], f"repos/{CFG.repo}/pulls/19")
        self.assertEqual(api.call_args_list[1].kwargs["input"], {"body": "Tests passed."})
        self.assertIn("Fixed.", api.call_args_list[2].kwargs["input"]["body"])

    def test_publish_refuses_the_bots_own_workflow_changes(self) -> None:
        done = mock.Mock(returncode=0, stdout="")
        with mock.patch.object(session.subprocess, "run", return_value=done) as run, \
                mock.patch.object(session, "workflow_changes", return_value=[".github/workflows/x.yml"]), \
                mock.patch.object(session.gh, "api") as api:
            with self.assertRaisesRegex(ValueError, "x.yml"):
                session.publish(CFG, Path("work.bundle"), "claude/20261017-x", "new", {}, None, "t")
        self.assertFalse([c for c in run.call_args_list if "push" in c.args[0]])
        api.assert_not_called()

    def test_only_the_checked_head_of_an_outside_pr_may_be_published(self) -> None:
        bot = f"{CFG.bot.id}+{CFG.bot.login}@users.noreply.github.com"
        with tempfile.TemporaryDirectory() as tmp:
            def git(*args: str, email: str = "x@example.com") -> str:
                return subprocess.run(["git", "-C", tmp, "-c", "user.name=x", "-c", f"user.email={email}", *args],
                                      check=True, capture_output=True, text=True).stdout.strip()

            git("init", "-q", "-b", "main")
            git("commit", "-q", "--allow-empty", "-m", "main")
            git("switch", "-q", "-c", "work")
            git("commit", "-q", "--allow-empty", "-m", "contributor", email="ann@example.com")
            checked = git("rev-parse", "HEAD")
            git("commit", "-q", "--allow-empty", "-m", "bot fix", email=bot)
            cwd = os.getcwd()
            os.chdir(tmp)
            try:
                self.assertEqual(session.unchecked_commits("work", "main", checked, bot), [])
                git("commit", "-q", "--allow-empty", "-m", "pushed later", email="ann@example.com")
                later = git("rev-parse", "HEAD")
                self.assertEqual(session.unchecked_commits("work", "main", checked, bot), [later])
                self.assertEqual(len(session.unchecked_commits("work", "main", "", bot)), 2)  # nothing was checked
            finally:
                os.chdir(cwd)

    def test_workflow_changes_allows_only_mains_the_forks_or_the_branchs_version(self) -> None:
        import os
        import subprocess
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
               "GIT_COMMITTER_EMAIL": "t@t"}
        with tempfile.TemporaryDirectory() as tmp:
            run = lambda *a: subprocess.run(["git", "-C", tmp, *a], check=True, capture_output=True, env=env)

            def commit(name: str, text: str, msg: str) -> None:
                Path(tmp, name).parent.mkdir(parents=True, exist_ok=True)
                Path(tmp, name).write_text(text)
                run("add", "-A")
                run("commit", "-qm", msg)

            run("init", "-q", "-b", "main")
            commit(".github/workflows/w.yml", "old\n", "base")
            run("switch", "-qc", "pr")
            commit("a.gd", "a\n", "work")
            run("branch", "pushed")
            run("switch", "-q", "main")
            commit(".github/workflows/w.yml", "new\n", "main changes a workflow")
            run("switch", "-q", "pr")
            run("merge", "-q", "--no-edit", "main")
            old = os.getcwd()
            os.chdir(tmp)
            try:
                self.assertEqual(session.workflow_changes("pr", ["main", "pushed"]), [])
                # A new branch that started before main changed the workflow keeps the old version.
                self.assertEqual(session.workflow_changes("pushed", ["main"]), [])
                self.assertEqual(session.workflow_changes("pushed", ["main", "pushed"]), [])
                commit(".github/workflows/w.yml", "evil\n", "the bot edits a workflow")
                self.assertEqual(session.workflow_changes("pr", ["main", "pushed"]), [".github/workflows/w.yml"])
                run("switch", "-q", "pushed")
                commit(".github/workflows/w.yml", "evil\n", "the bot edits a workflow on the old base")
                self.assertEqual(session.workflow_changes("pushed", ["main"]), [".github/workflows/w.yml"])
            finally:
                os.chdir(old)

    def test_branch_names(self) -> None:
        self.assertTrue(session.valid_branch("claude/20261017-area-readmes"))
        for bad in ["main", "claude/../main", "claude/", "feature/x", "claude/x;rm -rf", "claude/X"]:
            self.assertFalse(session.valid_branch(bad), bad)

    def test_package_and_publish_roundtrip(self) -> None:
        """Commits made in one clone travel as a bundle and are pushed from another."""
        import os
        import subprocess
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
               "GIT_COMMITTER_EMAIL": "t@t"}
        with tempfile.TemporaryDirectory() as tmp:
            origin, work = Path(tmp, "origin.git"), Path(tmp, "work")
            run = lambda *a, cwd=tmp: subprocess.run(a, cwd=cwd, check=True, capture_output=True, env=env)
            run("git", "init", "-q", "--bare", "-b", "main", str(origin))
            run("git", "clone", "-q", str(origin), str(work))
            Path(work, "a.txt").write_text("a\n")
            run("git", "add", "a.txt", cwd=work)
            run("git", "commit", "-qm", "base", cwd=work)
            run("git", "push", "-q", "origin", "main", cwd=work)
            run("git", "switch", "-qc", "claude/20261017-x", cwd=work)
            Path(work, "b.txt").write_text("b\n")
            run("git", "add", "b.txt", cwd=work)
            run("git", "commit", "-qm", "work", cwd=work)
            old = os.getcwd()
            os.chdir(work)
            try:
                out = session.package(Path(tmp, "out"))
            finally:
                os.chdir(old)
            self.assertEqual(out, {"branch": "claude/20261017-x", "commits": "1"})
            listed = subprocess.run(["git", "bundle", "list-heads", str(Path(tmp, "out/work.bundle"))],
                                    capture_output=True, text=True, check=True).stdout
            self.assertIn("refs/heads/claude/20261017-x", listed)

    def test_sync_with_main_merges_or_leaves_conflicts(self) -> None:
        """The scripted merge of main before Claude starts (Claude's sandbox can't write .github/)."""
        import os
        import subprocess
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
               "GIT_COMMITTER_EMAIL": "t@t"}
        with tempfile.TemporaryDirectory() as tmp:
            origin, work, other = Path(tmp, "origin.git"), Path(tmp, "work"), Path(tmp, "other")
            run = lambda *a, cwd=tmp: subprocess.run(a, cwd=cwd, check=True, capture_output=True, env=env)
            run("git", "init", "-q", "--bare", "-b", "main", str(origin))
            run("git", "clone", "-q", str(origin), str(other))
            Path(other, "a.md").write_text("a\n")
            run("git", "add", "a.md", cwd=other)
            run("git", "commit", "-qm", "base", cwd=other)
            run("git", "push", "-q", "origin", "main", cwd=other)
            for name, text in (("claude/20261016-ok", None), ("claude/20261016-clash", "pr\n")):
                run("git", "switch", "-qc", name, "origin/main", cwd=other)
                Path(other, "b.md" if text is None else "a.md").write_text(text or "b\n")
                run("git", "commit", "-qam" if text else "-qm", "pr", cwd=other) if text else (
                    run("git", "add", "b.md", cwd=other), run("git", "commit", "-qm", "pr", cwd=other))
                run("git", "push", "-q", "origin", name, cwd=other)
            run("git", "switch", "-q", "main", cwd=other)
            Path(other, "a.md").write_text("main\n")
            Path(other, ".github").mkdir()
            Path(other, ".github/w.yml").write_text("on: push\n")
            run("git", "add", "-A", cwd=other)
            run("git", "commit", "-qm", "main moves", cwd=other)
            run("git", "push", "-q", "origin", "main", cwd=other)
            run("git", "clone", "-q", str(origin), str(work))
            old = os.getcwd()
            os.chdir(work)
            try:
                with mock.patch.dict(os.environ, env):
                    ok = session.sync_with_main("claude/20261016-ok")
                    self.assertIn("up to date", ok)
                    self.assertTrue(Path(work, ".github/w.yml").exists())
                    clash = session.sync_with_main("claude/20261016-clash")
                    self.assertIn("`a.md`", clash)
                    self.assertEqual(session.sync_with_main("main"), "")
            finally:
                os.chdir(old)

    def test_package_renames_a_branch_outside_claude(self) -> None:
        """Commits left on e.g. `pr19` (from `gh pr checkout`) are bundled under the expected branch."""
        import os
        import subprocess
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
               "GIT_COMMITTER_EMAIL": "t@t"}
        with tempfile.TemporaryDirectory() as tmp:
            origin, work = Path(tmp, "origin.git"), Path(tmp, "work")
            run = lambda *a, cwd=tmp: subprocess.run(a, cwd=cwd, check=True, capture_output=True, env=env)
            run("git", "init", "-q", "--bare", "-b", "main", str(origin))
            run("git", "clone", "-q", str(origin), str(work))
            Path(work, "a.txt").write_text("a\n")
            run("git", "add", "a.txt", cwd=work)
            run("git", "commit", "-qm", "base", cwd=work)
            run("git", "push", "-q", "origin", "main", cwd=work)
            run("git", "switch", "-qc", "pr19", cwd=work)
            Path(work, "b.txt").write_text("b\n")
            run("git", "add", "b.txt", cwd=work)
            run("git", "commit", "-qm", "work", cwd=work)
            old = os.getcwd()
            os.chdir(work)
            try:
                out = session.package(Path(tmp, "out"), "claude/20261017-x")
                bare = session.package(Path(tmp, "out2"))
            finally:
                os.chdir(old)
            self.assertEqual(out, {"branch": "claude/20261017-x", "commits": "1"})
            self.assertTrue(Path(tmp, "out/work.bundle").exists())
            self.assertFalse(Path(tmp, "out2/work.bundle").exists())  # no expected branch: nothing to push


class MergeTest(unittest.TestCase):
    def runs(self, *items: tuple[str, str, str | None]) -> dict:
        return {"check_runs": [{"name": n, "status": s, "conclusion": c, "started_at": f"2026-10-17T00:00:0{i}Z"}
                               for i, (n, s, c) in enumerate(items)]}

    def test_checks_pass(self) -> None:
        with mock.patch.object(merge.gh, "api", return_value=self.runs(
                ("rules", "completed", "success"), ("ci-tests", "completed", "success"))):
            merge.wait_for_checks("o/r", "sha", None, timeout=0)

    def test_failed_or_missing_checks_refuse(self) -> None:
        with mock.patch.object(merge.gh, "api", return_value=self.runs(
                ("rules", "completed", "failure"), ("ci-tests", "completed", "success"))):
            with self.assertRaises(merge.NotMerged):
                merge.wait_for_checks("o/r", "sha", None, timeout=0)
        with mock.patch.object(merge.gh, "api", return_value=self.runs(("ci-tests", "completed", "success"))):
            with self.assertRaises(merge.NotMerged):
                merge.wait_for_checks("o/r", "sha", None, timeout=0)

    def test_latest_rerun_counts(self) -> None:
        with mock.patch.object(merge.gh, "api", return_value=self.runs(
                ("rules", "completed", "failure"), ("rules", "completed", "success"),
                ("ci-tests", "completed", "success"))):
            merge.wait_for_checks("o/r", "sha", None, timeout=0)

    def test_changed_head_is_refused(self) -> None:
        pr = {"state": "open", "base": {"ref": "main"}, "head": {"sha": "new"}, "user": {"login": "x"}}
        with mock.patch.object(merge.gh, "api", return_value=pr):
            with self.assertRaisesRegex(merge.NotMerged, "changed after review"):
                merge.merge(CFG, 1, "old", None)

    def test_conflicting_pr_is_refused_without_waiting_for_checks(self) -> None:
        pr = {"state": "open", "base": {"ref": "main"}, "head": {"sha": "abc"}, "user": {"login": "x"},
              "mergeable": False}
        with mock.patch.object(merge.gh, "api", return_value=pr), \
                mock.patch.object(merge, "wait_for_checks") as wait:
            with self.assertRaisesRegex(merge.NotMerged, merge.CONFLICT):
                merge.merge(CFG, 1, "abc", None)
        wait.assert_not_called()

    def test_mergeable_is_polled_while_github_computes_it(self) -> None:
        with mock.patch.object(merge.gh, "api", side_effect=[{"mergeable": None}, {"mergeable": False}]):
            self.assertFalse(merge.mergeable_now("o/r", 1, {"mergeable": None}, delay=0))
        with mock.patch.object(merge.gh, "api", return_value={"mergeable": None}):
            self.assertTrue(merge.mergeable_now("o/r", 1, {"mergeable": None}, attempts=2, delay=0))


if __name__ == "__main__":
    unittest.main()
