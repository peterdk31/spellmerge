from __future__ import annotations

import copy
import datetime as dt
import json
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

    def test_review_and_revise_prompts(self) -> None:
        self.assertIn("#7 at commit abc", session.review_prompt(CFG, 7, "abc", "final"))
        p = session.revise_prompt(CFG, 7, {"summary": "s", "problems": [
            {"severity": "major", "file": "a.gd", "line": 3, "problem": "p", "fix": "f"}]})
        self.assertIn("[major] a.gd:3: p Fix: f", p)

    def test_mergeable(self) -> None:
        self.assertTrue(session.mergeable({"verdict": "approve", "problems": [{"severity": "minor"}]}))
        self.assertFalse(session.mergeable({"verdict": "approve", "problems": [{"severity": "major"}]}))
        self.assertFalse(session.mergeable({"verdict": "revise", "problems": []}))


class FinishTest(unittest.TestCase):
    """finish() decides whether the next session starts right away."""

    APPROVE = json.dumps({"verdict": "approve", "problems": []})
    REVISE = json.dumps({"verdict": "revise", "problems": [{"severity": "major", "problem": "p", "fix": "f"}]})

    def run_finish(self, st: dict, queue: list[str], **env: str) -> tuple[dict[str, str], dict]:
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
                    mock.patch.object(session.dailylog, "post"), \
                    mock.patch.object(session.nexttask, "next_task", lambda path_=None, skip=(): real(path, skip)):
                return session.finish(CFG, base), st

    def test_continues_after_a_merge(self) -> None:
        out, _ = self.run_finish(copy.deepcopy(state.DEFAULT), ["B"], PR="5", FINAL_REVIEW=self.APPROVE,
                                 MERGED="true")
        self.assertEqual(out["again"], "true")

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
        self.assertEqual(out["again"], "false")  # only the parked task is left

    def test_blocked_and_refused_merges_are_parked(self) -> None:
        out, st = self.run_finish(copy.deepcopy(state.DEFAULT), ["A", "B"], IMPLEMENT_STATUS="blocked")
        self.assertIn("parked_until", st["task_failures"]["A"])
        self.assertEqual(out["again"], "true")
        out, st = self.run_finish(copy.deepcopy(state.DEFAULT), ["A", "B"], PR="5", FINAL_REVIEW=self.APPROVE,
                                  MERGED="false", MERGE_RESULT="Not merged: GitHub refused the merge")
        self.assertIn("refused", st["task_failures"]["A"]["parked_reason"])
        self.assertEqual(out["again"], "true")

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

    def test_stops_on_errors_paused_merging_and_plan_runs(self) -> None:
        for env in ({"IMPLEMENT_STATUS": "error"}, {"IMPLEMENT_STATUS": "limit"},
                    {"IMPLEMENT_STATUS": "nothing_to_do"},
                    {"PR": "5", "FINAL_REVIEW": self.APPROVE, "MERGED": ""},
                    {"TASK_KIND": "plan", "PR": "5", "FINAL_REVIEW": self.APPROVE, "MERGED": "true"}):
            out, _ = self.run_finish(copy.deepcopy(state.DEFAULT), ["A", "B"], **env)
            self.assertEqual(out["again"], "false", env)


class PublishTest(unittest.TestCase):
    def test_open_pr_finds_only_the_bots_pr(self) -> None:
        own = {"number": 19, "user": {"login": CFG.bot.login}, "head": {"sha": "abc", "repo": {"full_name": CFG.repo}}}
        other = {"number": 20, "user": {"login": "someone"}, "head": {"sha": "def", "repo": {"full_name": CFG.repo}}}
        with mock.patch.object(session.gh, "api", return_value=[other, own]):
            self.assertEqual(session.open_pr(CFG, "claude/20261016-x"),
                             {"pr": "19", "sha": "abc", "branch": "claude/20261016-x"})
        with mock.patch.object(session.gh, "api", return_value=[other]):
            self.assertEqual(session.open_pr(CFG, "claude/20261016-x"), {})
        self.assertEqual(session.open_pr(CFG, "main"), {})

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
