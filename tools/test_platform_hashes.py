# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/platform_hashes.py: reading the runner's lines and naming where two runs part."""

from __future__ import annotations

import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import platform_hashes as ph  # noqa: E402


def log(*ticks: tuple[str, dict[str, str]], scene: str = "sandbox", inputs: str = "abc",
        leaves: list[tuple[str, str, str, str]] | None = None, result: str = "REPLAY HASHES OK",
        prefix: str = "", self_check: str = "agree") -> str:
    lines = [f"{prefix}REPLAY START\t{scene}\tLinux\tticks={len(ticks)}\tnative=on\tcap=1000",
             f"{prefix}REPLAY INPUT\t{scene}\t{inputs}"]
    for tick, (whole, areas) in enumerate(ticks):
        lines.append(f"{prefix}REPLAY TICK\t{scene}\t{tick}\t{whole}\t" + "\t".join(f"{a}={h}" for a, h in areas.items()))
    for area, digest, path, shown in leaves or []:
        lines.append(f"{prefix}REPLAY LEAF\t{scene}\t{area}\t{digest}\t{path}\t{shown}")
    lines.append(f"{prefix}REPLAY SELF\t{scene}\t{self_check}")
    lines.append(prefix + result)
    return "\n".join(lines)


class ParseTest(unittest.TestCase):
    def test_reads_ticks_leaves_and_result(self) -> None:
        run = ph.parse("linux", log(("w0", {"Spells": "1", "actor 0": "2"}), ("w1", {"Spells": "3", "actor 0": "2"}),
                                    leaves=[("Spells", "d1", "Spells._walk_turn", "PackedFloat32Array(0.5)")]))
        scene = run.scenes["sandbox"]
        self.assertEqual(run.result, "REPLAY HASHES OK")
        self.assertEqual(scene.input, "abc")
        self.assertEqual(scene.ticks[1], ("w1", {"Spells": "3", "actor 0": "2"}))
        self.assertEqual(scene.leaves[("Spells", "Spells._walk_turn")], ("d1", "PackedFloat32Array(0.5)"))
        self.assertEqual(scene.self_check, "agree")

    def test_skips_the_browser_console_prefix(self) -> None:
        run = ph.parse("web", log(("w0", {"A": "1"}), prefix="console.log: "))
        self.assertEqual(len(run.scenes["sandbox"].ticks), 1)
        self.assertEqual(run.result, "REPLAY HASHES OK")

    def test_a_missing_tick_is_an_error(self) -> None:
        text = log(("w0", {"A": "1"})).replace("REPLAY TICK\tsandbox\t0", "REPLAY TICK\tsandbox\t3")
        with self.assertRaises(ValueError):
            ph.parse("linux", text)


class CompareTest(unittest.TestCase):
    def test_runs_that_agree(self) -> None:
        a = ph.parse("linux", log(("w0", {"A": "1"}), ("w1", {"A": "2"})))
        b = ph.parse("web", log(("w0", {"A": "1"}), ("w1", {"A": "2"})))
        text, agree = ph.report(a, b)
        self.assertTrue(agree)
        self.assertIn("sandbox: agrees at all 2 ticks", text)

    def test_names_the_first_tick_and_its_areas(self) -> None:
        a = ph.parse("linux", log(("w0", {"A": "1", "B": "1"}), ("w1", {"A": "2", "B": "2"}), ("w2", {"A": "3", "B": "3"})))
        b = ph.parse("windows", log(("w0", {"A": "1", "B": "1"}), ("x1", {"A": "2", "B": "9"}), ("x2", {"A": "8", "B": "9"})))
        parting = ph.compare(a, b)[0]
        self.assertEqual((parting.tick, parting.areas), (1, ["B"]))
        text, agree = ph.report(a, b)
        self.assertFalse(agree)
        self.assertIn("sandbox: parts at tick 1, in B (2 vs 9)", text)

    def test_names_the_members_from_kept_leaves(self) -> None:
        leaves_a = [("B", "d1", "B.x", "1.0"), ("B", "d2", "B.y", "2.0")]
        leaves_b = [("B", "d1", "B.x", "1.0"), ("B", "d3", "B.y", "2.0000002"), ("B", "d4", "B.z", "3")]
        a = ph.parse("linux", log(("w0", {"B": "1"}), leaves=leaves_a))
        b = ph.parse("windows", log(("x0", {"B": "2"}), leaves=leaves_b))
        text, _ = ph.report(a, b)
        self.assertIn("B: B.y: 2.0 vs 2.0000002", text)
        self.assertIn("B: B.z: (missing) vs 3", text)
        self.assertNotIn("B.x", text)

    def test_says_when_the_inputs_differ_or_a_run_is_short(self) -> None:
        a = ph.parse("linux", log(("w0", {"A": "1"}), ("w1", {"A": "2"})))
        b = ph.parse("web", log(("w0", {"A": "1"}), inputs="other"))
        text, agree = ph.report(a, b)
        self.assertFalse(agree)
        self.assertIn("the inputs differ", text)
        self.assertIn("parts at tick 1, in one run has 2 ticks, the other 1", text)

    def test_a_scene_not_played_is_a_parting(self) -> None:
        a = ph.parse("linux", log(("w0", {"A": "1"})) + "\n" + log(("w0", {"A": "1"}), scene="wave"))
        b = ph.parse("web", log(("w0", {"A": "1"})))
        text, agree = ph.report(a, b)
        self.assertFalse(agree)
        self.assertIn("not played: wave", text)


class RunProblemsTest(unittest.TestCase):
    def test_a_finished_run_that_agrees_with_itself(self) -> None:
        self.assertEqual(ph.run_problems(ph.parse("linux", log(("w0", {"A": "1"})))), ([], 0))

    def test_a_run_that_did_not_finish(self) -> None:
        lines, status = ph.run_problems(ph.parse("web", log(("w0", {"A": "1"}), result="REPLAY HASHES FAILED: boom")))
        self.assertEqual(status, 2)
        self.assertIn("did not finish (REPLAY HASHES FAILED: boom)", lines[0])
        self.assertEqual(ph.run_problems(ph.parse("web", "nothing"))[1], 2)

    def test_an_export_without_webrtc_is_its_own_problem(self) -> None:
        good = log(("w0", {"A": "1"}))
        on = ph.parse("windows", "console.log: REPLAY BUILD\twebrtc=on\n" + good)
        self.assertEqual(on.build, {"webrtc": "on"})
        self.assertEqual(list(on.scenes), ["sandbox"])  # the build line is no scene
        self.assertEqual(ph.run_problems(on), ([], 0))
        lines, status = ph.run_problems(ph.parse("windows", "REPLAY BUILD\twebrtc=off\n" + good))
        self.assertEqual(status, 2)
        self.assertIn("windows: the export has no WebRTC", lines[0])
        self.assertNotIn("did not finish", lines[0])

    def test_a_replay_parting_from_its_own_recording(self) -> None:
        lines, status = ph.run_problems(ph.parse("windows", log(("w0", {"A": "1"}), self_check="parts at tick 7")))
        self.assertEqual(status, 1)
        self.assertEqual(lines, ["windows: sandbox: its replay parts at tick 7 against its recording"])


class CommandsTest(unittest.TestCase):
    """`compare` on saved logs and `play` on an export, as the daily build's platforms job runs them."""

    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())

    def write(self, name: str, text: str) -> Path:
        path = self.dir / name
        path.write_text(text)
        return path

    def main(self, *argv: str) -> tuple[int, str]:
        out = io.StringIO()
        with redirect_stdout(out):
            status = ph.main(list(argv))
        return status, out.getvalue()

    def test_compare_agrees_parts_and_does_not_finish(self) -> None:
        linux = self.write("linux.log", log(("w0", {"A": "1"}), ("w1", {"A": "2"})))
        same = self.write("web.log", log(("w0", {"A": "1"}), ("w1", {"A": "2"}), prefix="console.log: "))
        other = self.write("windows.log", log(("w0", {"A": "1"}), ("x1", {"A": "5"})))
        broken = self.write("broken.log", "REPLAY HASHES FAILED: no wizard")
        self.assertEqual(self.main("compare", str(linux), str(same))[0], 0)
        status, text = self.main("compare", str(linux), str(same), str(other))
        self.assertEqual(status, 1)
        self.assertIn("windows against linux:\n  sandbox: parts at tick 1, in A (2 vs 5)", text)
        status, text = self.main("compare", str(linux), str(other), str(broken))
        self.assertEqual(status, 2)
        self.assertIn("broken: the run did not finish (REPLAY HASHES FAILED: no wizard)", text)
        # A platform whose job wrote no log: the rest are still compared.
        status, text = self.main("compare", str(linux), str(self.dir / "windows-gone.log"), str(other))
        self.assertEqual(status, 2)
        self.assertIn("windows-gone: no log", text)
        self.assertIn("parts at tick 1", text)
        self.assertEqual(self.main("compare", str(self.dir / "gone.log"), str(linux))[0], 2)

    @unittest.skipIf(os.name != "posix", "the fake export is a shell script")
    def test_play_runs_an_export_and_writes_its_log(self) -> None:
        build = self.dir / "linux-test"
        build.mkdir()
        # A stand-in export: prints a finished run and the arguments it was given. Not executable,
        # as a downloaded CI artifact comes.
        lines = log(("w0", {"A": "1"})).replace("\t", "\\t").splitlines()
        program = "#!/bin/sh\n" + "".join(f"printf '{line}\\n'\n" for line in lines) + 'echo "ARGS $*"\n'
        self.write("linux-test/Game.x86_64", program)
        out = self.dir / "logs" / "linux-gdscript.log"
        status, _ = self.main("play", "linux-gdscript", "--build", str(build), "--log", str(out),
                              "--ticks=9", "--scenes=wave")
        self.assertEqual(status, 0)
        text = out.read_text()
        self.assertIn("ARGS --headless -- --replay-hashes --ticks=9 --scenes=wave --no-native", text)
        self.assertEqual(ph.parse("linux-gdscript", text).result, "REPLAY HASHES OK")
        self.write("linux-test/Game.x86_64", "#!/bin/sh\necho crashed\n")
        self.assertEqual(self.main("play", "linux", "--build", str(build), "--log", str(out))[0], 2)


if __name__ == "__main__":
    unittest.main()
