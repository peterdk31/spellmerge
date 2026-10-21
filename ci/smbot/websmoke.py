"""Web smoke test: runs the exported web build in headless Chrome.

  python3 -m smbot.websmoke build/web --expect "main menu ready" [--screenshot shot.png] [--warn-load 10]
  python3 -m smbot.websmoke build/web-test --page-args=--four-bot --expect "SMOKE OK" --timeout 240

Serves the build locally, opens it in Chrome, and passes once a console line
contains the --expect text. Fails on a timeout, an uncaught exception, or any
console error (Godot reports script and engine errors through console.error).
Prints `WEB LOAD: N s`, the time from opening the page to the "main menu ready" line.
Above --warn-load it prints a `::warning::` with likely fixes; a slow load never fails
the test, so it can't block development (the budget is a target, not a gate).

--page-args gives the game a command line: the served index.html has its start config's
`"args":[]` replaced by the list (Godot's web shell passes `args` to the engine, so
`OS.get_cmdline_args()` sees it). Write it with an equals sign, `--page-args=--four-bot`,
because argparse reads a separate value that starts with `--` as another option.
Talks to Chrome over --remote-debugging-pipe, so it needs no extra packages.
"""

from __future__ import annotations

import argparse
import base64
import functools
import http.server
import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

CHROME_NAMES = ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser")
MENU_READY = "main menu ready"
ARGS_SLOT = '"args":[]'


class Chrome:
    """Minimal Chrome DevTools Protocol client over the debugging pipe."""

    def __init__(self, binary: str, profile: str) -> None:
        to_chrome_r, self._to_chrome = os.pipe()
        self._from_chrome, from_chrome_w = os.pipe()
        os.set_inheritable(to_chrome_r, True)
        os.set_inheritable(from_chrome_w, True)
        args = [binary, "--headless=new", "--remote-debugging-pipe", "--no-first-run", "--no-default-browser-check",
                f"--user-data-dir={profile}", "--window-size=1280,720", "--use-angle=swiftshader",
                "--enable-unsafe-swiftshader", "--autoplay-policy=no-user-gesture-required", "about:blank"]
        if os.environ.get("CI"):
            args.insert(1, "--no-sandbox")  # GitHub's runners don't allow Chrome's user-namespace sandbox
        # Chrome expects the pipe on file descriptors 3 (commands in) and 4 (replies out).
        self.proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, pass_fds=(3, 4),
                                     preexec_fn=functools.partial(_dup_pipes, to_chrome_r, from_chrome_w))
        os.close(to_chrome_r)
        os.close(from_chrome_w)
        self._buf = b""
        self._next_id = 0
        self.events: list[dict] = []

    def send(self, method: str, params: dict | None = None, session: str | None = None) -> dict:
        self._next_id += 1
        msg = {"id": self._next_id, "method": method, "params": params or {}}
        if session:
            msg["sessionId"] = session
        os.write(self._to_chrome, json.dumps(msg).encode() + b"\0")
        while True:
            reply = self._read()
            if reply.get("id") == self._next_id:
                if "error" in reply:
                    raise RuntimeError(f"{method}: {reply['error']}")
                return reply.get("result", {})
            self.events.append(reply)

    def poll(self, deadline: float) -> dict | None:
        if self.events:
            return self.events.pop(0)
        ready, _, _ = select.select([self._from_chrome], [], [], max(0.0, deadline - time.monotonic()))
        return self._read() if ready else None

    def _read(self) -> dict:
        while b"\0" not in self._buf:
            chunk = os.read(self._from_chrome, 1 << 16)
            if not chunk:
                raise RuntimeError("Chrome closed the debugging pipe")
            self._buf += chunk
        raw, self._buf = self._buf.split(b"\0", 1)
        return json.loads(raw)

    def close(self) -> None:
        self.proc.kill()
        self.proc.wait()


def _dup_pipes(read_fd: int, write_fd: int) -> None:
    os.dup2(read_fd, 3)
    os.dup2(write_fd, 4)


def with_page_args(page: str, page_args: list[str]) -> str:
    """index.html with the engine's start arguments set; fails if the shell has no args slot."""
    if ARGS_SLOT not in page:
        raise ValueError(f"index.html has no {ARGS_SLOT} in its start config, so --page-args can't be passed")
    return page.replace(ARGS_SLOT, '"args":' + json.dumps(page_args, separators=(",", ":")), 1)


def serve(directory: Path, page_args: list[str] | None = None) -> tuple[http.server.ThreadingHTTPServer, str]:
    index = with_page_args((directory / "index.html").read_text(), page_args).encode() if page_args else None
    handler = functools.partial(_QuietHandler, directory=str(directory), index=index)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"http://127.0.0.1:{server.server_address[1]}/index.html"


class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def __init__(self, *args: object, index: bytes | None = None, **kwargs: object) -> None:
        self._index = index
        super().__init__(*args, **kwargs)  # type: ignore[arg-type]

    def do_GET(self) -> None:
        if self._index is not None and self.path.split("?", 1)[0] in ("/", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(self._index)))
            self.end_headers()
            self.wfile.write(self._index)
            return
        super().do_GET()

    def log_message(self, format: str, *args: object) -> None:
        pass


def _console_text(params: dict) -> str:
    return " ".join(str(a.get("value", a.get("description", ""))) for a in params.get("args", []))


# What usually makes a Godot web build slow to start, in the order worth checking.
LOAD_FIXES = (
    "compare the web zip with its 40 MB budget in the Size budgets step; the engine .wasm is most of it",
    "look for big textures or sounds added since the last fast build (art/manifest.json, audio/manifest.json)",
    "check work at start: autoload _ready() and Registry.scan() load every content .tres; "
    "a build-time manifest or loading on first use (docs/milestones/M1-core-loop.md, Registry) avoids that",
    "keep demo-only content small: the Web preset can exclude more (export_presets.cfg, the demo flag)",
    "a slow runner can add seconds: re-check the next daily build before changing anything",
)


def load_warning(loaded: float, limit: float | None) -> str | None:
    """A warning with likely fixes when the load took longer than `limit` seconds, else None."""
    if limit is None or loaded <= limit:
        return None
    fixes = "; ".join(f"({i}) {fix}" for i, fix in enumerate(LOAD_FIXES, 1))
    return (f"the web build took {loaded:.1f} s to reach the main menu, over the {limit:.0f} s target "
            f"(docs/PLAN.md, Performance). Not a failure. Likely fixes: {fixes}")


def run(build: Path, expect: str, timeout: float, screenshot: Path | None, binary: str,
        page_args: list[str] | None = None, warn_load: float | None = None) -> list[str]:
    """Returns a list of problems; empty means the smoke test passed."""
    server, url = serve(build, page_args)
    profile = tempfile.mkdtemp(prefix="websmoke-")
    chrome = Chrome(binary, profile)
    problems: list[str] = []
    try:
        target = chrome.send("Target.createTarget", {"url": "about:blank"})["targetId"]
        session = chrome.send("Target.attachToTarget", {"targetId": target, "flatten": True})["sessionId"]
        chrome.send("Runtime.enable", session=session)
        chrome.send("Page.enable", session=session)
        started = time.monotonic()
        chrome.send("Page.navigate", {"url": url}, session=session)
        deadline = started + timeout
        seen = False
        loaded: float | None = None
        while time.monotonic() < deadline and not seen:
            event = chrome.poll(deadline)
            if event is None:
                break
            method, params = event.get("method"), event.get("params", {})
            if method == "Runtime.consoleAPICalled":
                text = _console_text(params)
                print(f"console.{params.get('type')}: {text}")
                if params.get("type") == "error":
                    problems.append(f"console error: {text}")
                if loaded is None and MENU_READY in text:
                    loaded = time.monotonic() - started
                    print(f"WEB LOAD: {loaded:.1f} s")
                    warning = load_warning(loaded, warn_load)
                    if warning:
                        print(f"::warning::{warning}")
                if expect in text:
                    seen = True
            elif method == "Runtime.exceptionThrown":
                details = params.get("exceptionDetails", {})
                problems.append(f"uncaught exception: {details.get('exception', {}).get('description', details)}")
        if not seen:
            problems.append(f"no console line containing {expect!r} within {timeout:.0f} s")
        if screenshot:
            time.sleep(1.0)  # let the first frames render
            shot = chrome.send("Page.captureScreenshot", {"format": "png"}, session=session)
            screenshot.write_bytes(base64.b64decode(shot["data"]))
            print(f"screenshot: {screenshot}")
    finally:
        chrome.close()
        server.shutdown()
        shutil.rmtree(profile, ignore_errors=True)
    return problems


def find_chrome() -> str | None:
    return next((p for p in map(shutil.which, CHROME_NAMES) if p), None)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("build", type=Path, help="folder with the exported index.html")
    ap.add_argument("--expect", required=True, help="text a console line must contain")
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--screenshot", type=Path)
    ap.add_argument("--page-args", action="append", default=[], metavar="ARG",
                    help="a start argument for the game, e.g. --page-args=--four-bot (repeatable)")
    ap.add_argument("--warn-load", type=float,
                    help="warn, with likely fixes, if the main menu takes longer than this many seconds")
    args = ap.parse_args(argv)

    binary = find_chrome()
    if binary is None:
        print("websmoke: Chrome or Chromium is not installed", file=sys.stderr)
        return 2
    problems = run(args.build, args.expect, args.timeout, args.screenshot, binary, args.page_args, args.warn_load)
    for problem in problems:
        print(f"::error::web smoke test: {problem}")
    print("WEB SMOKE " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
