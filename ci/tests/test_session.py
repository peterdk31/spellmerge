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

    def test_prepare_includes_task_and_instructions(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        st["pending_instructions"] = [{"kind": "ask", "text": "how is it going?", "number": 9, "url": "u"}]
        out = session.prepare(CFG, st, "bugs first", dt.date(2026, 10, 17))
        self.assertIn("Area READMEs for the content areas", out["prompt"])
        self.assertIn("`/ask` on #9", out["prompt"])
        self.assertIn("bugs first", out["prompt"])
        self.assertNotIn("{{", out["prompt"])
        self.assertTrue(out["branch"].startswith("claude/20261017-area-readmes"))

    def test_prepare_mentions_previous_failure(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        st["task_failures"] = {FIXTURE_TASK: {"count": 1, "pr": 12, "problems": "- missing tests"}}
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


class PublishTest(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
