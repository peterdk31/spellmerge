"""Tests for the hard rules check. Run: python3 -m unittest discover -s ci/tests -t ci"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from smbot import rules

ROOT = Path(__file__).resolve().parents[2]
PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 32
OGG = b"OggS" + b"\0" * 32
CONTRIBUTOR, BOT, OWNER = "someone", "spellmerge-bot[bot]", "peterdk31"


def banned(text: str, path: str = "content/spells/x.gd") -> list[str]:
    return [f.message for f in rules.check_banned_apis(path, text)]


class BannedApiTest(unittest.TestCase):
    def test_flags_dangerous_calls(self) -> None:
        for code in [
            'OS.execute("rm", [])',
            'OS.shell_open("https://example.com")',
            "OS . create_process('x', [])",
            'OS.call("execute", "x")',
            'Engine.get_singleton("OS")',
            "var r := HTTPRequest.new()",
            "var p := StreamPeerTCP.new()",
            "IP.resolve_hostname('x')",
            'JavaScriptBridge.eval("alert(1)")',
            "var s := GDScript.new()",
            "s.source_code = src",
            "var e := Expression.new()",
            "node.set_script(s)",
            'ClassDB.instantiate("HTTPRequest")',
            "@tool",
            "extends EditorPlugin",
            'FileAccess.open("res://x.json", FileAccess.READ)',
            "FileAccess.open(path, FileAccess.WRITE)",
            'DirAccess.remove_absolute("/home")',
            "cfg.load(path)",
            "var scene = load(path)",
            'load("user://evil.gd")',
            "ResourceLoader.load(p)",
            'var v = str_to_var(text)',
            'GDExtensionManager.load_extension("res://x.gdextension")',
        ]:
            with self.subTest(code=code):
                self.assertTrue(banned(code), f"not flagged: {code}")

    def test_allows_normal_code(self) -> None:
        for code in [
            'const SCENE := preload("res://content/enemies/slime/slime.tscn")',
            'var tex: Texture2D = load("res://art/ui/icon.png")',
            'ResourceLoader.load("res://content/spells/forms/bolt.tres")',
            'var f := FileAccess.open("user://save.json", FileAccess.WRITE)',
            'cfg.load("user://settings.cfg")',
            'image.save_png("user://shot.png")',
            "# Expression of joy when the spell lands; no JavaScript here",
            "var os_name := OS.get_name()",
            "func reload_spell() -> void:",
            "var ip_count: int = 0",
        ]:
            with self.subTest(code=code):
                self.assertEqual(banned(code), [], f"wrongly flagged: {code}")

    def test_core_and_tests_may_load_dynamically_but_not_execute(self) -> None:
        for path in ("core/registry/registry.gd", "tests/smoke/boot_smoke.gd"):
            self.assertEqual(banned("var res = load(path)", path), [])
            self.assertTrue(banned('OS.execute("x", [])', path))

    def test_reports_line_numbers(self) -> None:
        found = rules.check_banned_apis("a.gd", 'extends Node\n\nfunc _ready() -> void:\n\tOS.execute("x", [])\n')
        self.assertEqual(found[0].line, 4)


class TypedTest(unittest.TestCase):
    def messages(self, text: str) -> list[str]:
        return [f.message for f in rules.check_typed("a.gd", text, "warning")]

    def test_typed_code_passes(self) -> None:
        code = (
            "var speed: float = 3.0\n"
            "var dir := Vector2.ZERO\n"
            "@onready var sprite: Sprite2D = $Sprite\n"
            "@export_range(0, 10) var level: int = 1\n"
            "static var count: int\n"
            "func move(delta: float, target := Vector2(0, 0)) -> void:\n\tpass\n"
            "func pick(items: Array[int],\n\t\tweights: Dictionary[int, float]) -> Array[int]:\n\treturn items\n"
        )
        self.assertEqual(self.messages(code), [])

    def test_untyped_code_is_reported(self) -> None:
        msgs = self.messages("var speed = 3\nvar target\nfunc hit(amount, source: Node):\n\tpass\n")
        self.assertIn("Variable `speed` has no type.", msgs)
        self.assertIn("Variable `target` has no type.", msgs)
        self.assertIn("Parameter `amount` of `hit()` has no type.", msgs)
        self.assertIn("Function `hit()` has no return type.", msgs)
        self.assertEqual(len(msgs), 4)


class LicenseAndSvgTest(unittest.TestCase):
    def test_license_lines(self) -> None:
        self.assertEqual(rules.check_license("a.gd", "# SPDX-License-Identifier: MIT\n"), [])
        self.assertEqual(rules.check_license("art/a.png.license", "SPDX-License-Identifier: CC0-1.0\n"), [])
        self.assertTrue(rules.check_license("art/a.png.license", "SPDX-License-Identifier: CC-BY-NC-4.0\n"))
        self.assertTrue(rules.check_license("audio/a.ogg.license", "SPDX-License-Identifier: GPL-3.0-or-later\n"))
        self.assertTrue(rules.check_license("a.gd", "# SPDX-License-Identifier: LicenseRef-Proprietary\n"))
        # Mentioning the tag inside code is not a license line.
        self.assertEqual(rules.check_license("a.py", 'x = re.compile(r"SPDX-License-Identifier: (.*)")\n'), [])

    def test_svg_scripts(self) -> None:
        change = rules.Change("A", "art/ui/a.svg", "100644")
        clean = b'<svg xmlns="http://www.w3.org/2000/svg"><rect width="4" height="4"/></svg>'
        self.assertEqual(rules.check_content(change, clean, rules.CONTRIBUTOR), [])
        for bad in [b"<svg><script>alert(1)</script></svg>", b'<svg onload="x()"></svg>',
                    b'<svg><image href="https://evil.example/x.png"/></svg>']:
            self.assertTrue(rules.check_content(change, bad, rules.CONTRIBUTOR), bad)


class RepoTest(unittest.TestCase):
    """End-to-end runs against a throwaway git repo with this repo's policy files."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.git("init", "-q", "-b", "main")
        for rel in (".github/CODEOWNERS", "ci/config.json"):
            self.write(rel, (ROOT / rel).read_bytes())
        self.write("core/events/.gitkeep", b"")
        self.commit("base")
        self.git("switch", "-q", "-c", "pr")
        # In CI the policy files come from a separate checkout of the base branch.
        self.trusted = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.trusted)
        for rel in (".github/CODEOWNERS", "ci/config.json"):
            (self.trusted / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(self.tmp / rel, self.trusted / rel)

    def git(self, *args: str) -> None:
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
               "GIT_COMMITTER_EMAIL": "t@t"}
        subprocess.run(["git", "-C", str(self.tmp), *args], check=True, capture_output=True, env=env)

    def write(self, rel: str, data: bytes | str) -> None:
        path = self.tmp / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data.encode() if isinstance(data, str) else data)

    def commit(self, msg: str = "change") -> None:
        self.git("add", "-A")
        self.git("commit", "-q", "-m", msg)

    def check(self, author: str = CONTRIBUTOR, worktree: bool = False) -> list[tuple[str, str, str]]:
        found = rules.run(self.tmp, self.trusted, "main", author, worktree)
        return [(f.rule, f.severity, f.path) for f in found]

    def test_clean_contribution_passes(self) -> None:
        self.write("content/spells/forms/bolt/bolt.gd", "extends Node\n\nfunc cast(power: float) -> void:\n\tpass\n")
        self.write("content/spells/forms/bolt/icon.png", PNG)
        self.write("content/spells/forms/bolt/cast.ogg", OGG)
        self.write("content/spells/forms/bolt/bolt.tres", '[gd_resource type="Resource" format=3]\n')
        self.commit()
        self.assertEqual(self.check(), [])

    def test_path_tiers(self) -> None:
        self.write(".github/workflows/x.yml", "on: push\n")
        self.write("core/events/bus.gd", "extends Node\n")
        self.write("docs/NEXT.md", "# Next\n")
        self.commit()
        found = self.check()
        self.assertIn(("protected-path", "error", ".github/workflows/x.yml"), found)
        self.assertIn(("bot-path", "error", "core/events/bus.gd"), found)
        self.assertIn(("bot-path", "error", "docs/NEXT.md"), found)

    def test_bot_may_change_bot_paths_but_not_owner_paths(self) -> None:
        self.write("core/events/bus.gd", "extends Node\n")
        self.write("docs/NEXT.md", "# Next\n")
        self.write("ci/evil.py", "print()\n")
        self.commit()
        found = self.check(BOT)
        self.assertEqual([f for f in found if f[2] != "ci/evil.py"], [])
        self.assertIn(("protected-path", "error", "ci/evil.py"), found)

    def test_deleting_protected_files_is_a_change_too(self) -> None:
        self.git("rm", "-q", ".github/CODEOWNERS")
        self.commit()
        self.assertIn(("protected-path", "error", ".github/CODEOWNERS"), self.check())

    def test_policy_comes_from_trusted_checkout(self) -> None:
        # The PR empties CODEOWNERS and edits a workflow in the same change.
        self.write(".github/CODEOWNERS", "")
        self.write(".github/workflows/x.yml", "on: push\n")
        self.commit()
        self.assertIn(("protected-path", "error", ".github/workflows/x.yml"), self.check())

    def test_file_types_binaries_and_sizes(self) -> None:
        self.write("content/relics/a/tool.exe", b"MZ\0\0")
        self.write("content/relics/a/fake.png", b"MZ\0\0not a png")
        self.write("content/relics/a/data.json", b'{"a": 1}\0\0')
        self.write("audio/music/long.ogg", OGG + b"\0" * 5_000_001)
        self.write("content/relics/a/a.gdextension", "[configuration]\n")
        self.commit()
        found = self.check()
        self.assertIn(("file-type", "error", "content/relics/a/tool.exe"), found)
        self.assertIn(("binary", "error", "content/relics/a/fake.png"), found)
        self.assertIn(("binary", "error", "content/relics/a/data.json"), found)
        self.assertIn(("file-size", "error", "audio/music/long.ogg"), found)
        self.assertIn(("file-type", "error", "content/relics/a/a.gdextension"), found)

    def test_symlinks_are_rejected(self) -> None:
        (self.tmp / "content").mkdir()
        os.symlink("/etc/passwd", self.tmp / "content/link.json")
        self.commit()
        self.assertIn(("symlink", "error", "content/link.json"), self.check())

    def test_untyped_is_warning_for_contributors_and_error_for_bot(self) -> None:
        self.write("content/relics/a/a.gd", "var x = 1\n")
        self.commit()
        self.assertEqual(self.check(), [("untyped", "warning", "content/relics/a/a.gd")])
        self.assertEqual(self.check(BOT), [("untyped", "error", "content/relics/a/a.gd")])

    def test_owner_findings_are_only_warnings(self) -> None:
        self.write(".github/workflows/x.yml", "on: push\n")
        self.write("addons/steam/steam.gd", 'extends Node\nfunc a() -> void:\n\tOS.execute("x", [])\n')
        self.commit()
        found = self.check(OWNER)
        self.assertEqual([f[1] for f in found], ["warning"])

    def test_dependabot_may_only_touch_workflows(self) -> None:
        self.write(".github/workflows/x.yml", "uses: actions/checkout@abc\n")
        self.commit()
        self.assertEqual(self.check("dependabot[bot]"), [])
        self.write("content/x.gd", "extends Node\n")
        self.commit()
        self.assertEqual(self.check("dependabot[bot]"), [("dependency-bot", "error", "content/x.gd")])

    def test_worktree_includes_untracked_files(self) -> None:
        self.write("content/relics/a/tool.exe", b"MZ")
        self.assertEqual(self.check(worktree=False), [])
        self.assertIn(("file-type", "error", "content/relics/a/tool.exe"), self.check(worktree=True))


if __name__ == "__main__":
    unittest.main()
