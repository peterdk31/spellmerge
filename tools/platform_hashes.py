#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The same game on every platform (online-ready N2b and N8, docs/milestones/online-ready.md).

Runs the replay hashes (tests/platforms/replay_hashes_runner.gd: a scripted sandbox fight, a horde
run of a bot and two bots in the waves, recorded and played back, every tick's state hash per area
printed) in the test exports on Linux, Windows and the web, and names the first tick and area where a
platform parts from Linux, with both hashes of each area. When one parts, `run` plays that scene
again on both, keeping the parting tick's leaves, and names the members that differ.

  tools/platform_hashes.py run [--platforms linux,windows,web] [--ticks 600] [--scenes sandbox,horde]
  tools/platform_hashes.py play NAME --build DIR [--ticks 600] [--scenes sandbox,horde] [--log FILE]
  tools/platform_hashes.py compare build/platforms/linux.log build/platforms/web.log ...

`run` needs one `ci/build/build.sh --quick` in the checkout (the pinned Godot and the Linux native
module). It builds the web native module (ci/build/native.sh web, Emscripten from its cache), exports
Linux Test, Windows Test and Web Test, and writes the logs to build/platforms/. Besides each
platform's run, Linux runs once more with `--no-native` (the GDScript twins of the kernels):
- **Windows** runs the export through WSL's interop from a folder under %TEMP%. Its export has no
  native module unless ci/build/native.sh windows built one (MinGW-w64), so it is compared with
  the Linux GDScript run as well.
- **The web** runs in headless Chromium (smbot.websmoke, SwiftShader), the native module built by
  Emscripten.

`play` runs one export that is already built (NAME: linux, linux-gdscript, windows or web) and
writes its log; `compare` then compares saved logs with the first. The daily build's `platforms`
job does that (.github/workflows/platforms.yml, N8): each platform on its own runner, Windows on a
Windows runner, then one compare. Exit status: 0 when every platform agrees with Linux, 1 when one
parts (or a run's own replay parts from its recording), 2 when a run did not finish.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "platforms"
# The pinned Godot that ci/build/build.sh unpacks.
GODOT = next(iter(sorted((ROOT / "build" / "godot").glob("Godot_v*_linux.x86_64"))), ROOT / "build/godot/Godot_linux.x86_64")
ARGUMENT = "--replay-hashes"
DONE = "REPLAY HASHES"
WINDOWS_TEMP_NAME = "spellmerge-platforms"
# Members a report names at most, per area.
MAX_MEMBERS = 24


@dataclass
class Scene:
    """One scene of one log: its start line, its inputs' md5, each tick's hashes and the kept leaves."""
    start: str = ""
    input: str = ""
    ticks: list[tuple[str, dict[str, str]]] = field(default_factory=list)
    leaves: dict[tuple[str, str], tuple[str, str]] = field(default_factory=dict)
    self_check: str = ""


@dataclass
class Run:
    """One platform's log."""
    name: str
    scenes: dict[str, Scene] = field(default_factory=dict)
    result: str = ""


def parse(name: str, text: str) -> Run:
    """The REPLAY lines of a log (websmoke's `console.log: ` prefix and anything before are skipped)."""
    run = Run(name)
    for line in text.splitlines():
        at = line.find("REPLAY ")
        if at < 0:
            continue
        fields = line[at:].rstrip("\r").split("\t")
        kind = fields[0]
        if kind.startswith(DONE):
            run.result = kind
            continue
        if len(fields) < 2:
            continue
        scene = run.scenes.setdefault(fields[1], Scene())
        if kind == "REPLAY START":
            scene.start = "\t".join(fields[2:])
        elif kind == "REPLAY INPUT" and len(fields) >= 3:
            scene.input = fields[2]
        elif kind == "REPLAY TICK" and len(fields) >= 4:
            areas = dict(part.split("=", 1) for part in fields[4:] if "=" in part)
            tick = int(fields[2])
            if tick != len(scene.ticks):
                raise ValueError(f"{name}: {fields[1]}: tick {tick} after {len(scene.ticks)} ticks")
            scene.ticks.append((fields[3], areas))
        elif kind == "REPLAY LEAF" and len(fields) >= 6:
            scene.leaves[(fields[2], fields[4])] = (fields[3], "\t".join(fields[5:]))
        elif kind == "REPLAY SELF" and len(fields) >= 3:
            scene.self_check = fields[2]
    return run


@dataclass
class Parting:
    """Where a scene of one run parts from the reference's."""
    scene: str
    tick: int  # -1: they agree; otherwise the first tick that differs (or the shorter run's length)
    areas: list[str] = field(default_factory=list)
    same_input: bool = True
    note: str = ""


def first_parting(ref: Scene, other: Scene, scene: str) -> Parting:
    """The first tick whose whole hash differs, and the areas that differ there."""
    out = Parting(scene, -1, same_input=ref.input == other.input)
    for tick, ((ref_whole, ref_areas), (whole, areas)) in enumerate(zip(ref.ticks, other.ticks)):
        if ref_whole != whole:
            out.tick = tick
            names = list(ref_areas) + [a for a in areas if a not in ref_areas]
            out.areas = [a for a in names if ref_areas.get(a) != areas.get(a)]
            return out
    if len(ref.ticks) != len(other.ticks):
        out.tick = min(len(ref.ticks), len(other.ticks))
        out.note = f"one run has {len(ref.ticks)} ticks, the other {len(other.ticks)}"
    return out


def compare(ref: Run, other: Run) -> list[Parting]:
    """Each scene both runs played, as a Parting of `other` from `ref`."""
    return [first_parting(ref.scenes[s], other.scenes[s], s) for s in ref.scenes if s in other.scenes]


def members_parting(ref: Scene, other: Scene, areas: list[str]) -> list[str]:
    """The kept leaves of `areas` that differ, as 'area: path: ref vs other' (values as shown)."""
    out: list[str] = []
    for area in areas:
        named = 0
        keys = [k for k in ref.leaves if k[0] == area] + [k for k in other.leaves if k[0] == area and k not in ref.leaves]
        for key in keys:
            a, b = ref.leaves.get(key), other.leaves.get(key)
            if a is not None and b is not None and a[0] == b[0]:
                continue
            if named >= MAX_MEMBERS:
                out.append(f"{area}: ... and more")
                break
            shown_a = a[1] if a else "(missing)"
            shown_b = b[1] if b else "(missing)"
            out.append(f"{area}: {key[1]}: {shown_a} vs {shown_b}")
            named += 1
    return out


def report(ref: Run, other: Run) -> tuple[str, bool]:
    """Lines saying where `other` parts from `ref`, and whether every scene agrees."""
    lines = [f"{other.name} against {ref.name}:"]
    agree = True
    for parting in compare(ref, other):
        if not parting.same_input:
            lines.append(f"  {parting.scene}: the inputs differ (the replays' bytes), so the runs are not the same game")
        if parting.tick < 0:
            lines.append(f"  {parting.scene}: agrees at all {len(ref.scenes[parting.scene].ticks)} ticks")
            continue
        agree = False
        where = parting.note
        if parting.areas:
            # Each area with both its hashes: CI keeps no leaves, so this is what its report shows.
            ref_areas = ref.scenes[parting.scene].ticks[parting.tick][1]
            areas = other.scenes[parting.scene].ticks[parting.tick][1]
            where = ", ".join(f"{a} ({ref_areas.get(a, 'missing')} vs {areas.get(a, 'missing')})"
                              for a in parting.areas)
        lines.append(f"  {parting.scene}: parts at tick {parting.tick}, in {where}")
        for member in members_parting(ref.scenes[parting.scene], other.scenes[parting.scene], parting.areas):
            lines.append(f"    {member}")
    missing = [s for s in ref.scenes if s not in other.scenes]
    if missing:
        agree = False
        lines.append(f"  not played: {', '.join(missing)}")
    return "\n".join(lines), agree


def run_problems(run: Run) -> tuple[list[str], int]:
    """What is wrong with one run on its own, and the exit status it calls for: 2 when it did not
    finish, 1 when a scene's replay parted from its own recording (REPLAY SELF), else 0."""
    if run.result != "REPLAY HASHES OK":
        return [f"{run.name}: the run did not finish ({run.result or 'no result line'})"], 2
    lines = [f"{run.name}: {name}: its replay {scene.self_check or 'printed no self check'} against its recording"
             for name, scene in run.scenes.items() if scene.self_check != "agree"]
    return lines, 1 if lines else 0


def print_problems(run: Run, where: Path | None = None) -> int:
    """Prints `run_problems` (with the log they came from) and returns its exit status."""
    lines, status = run_problems(run)
    for line in lines:
        print(f"{line} ({where})" if where else line)
    return status


# --- Running the exports -------------------------------------------------------------------------


def sh(*args: str | Path, log: Path | None = None, timeout: float | None = None, env: dict | None = None) -> int:
    print("$ " + " ".join(str(a) for a in args), flush=True)
    with open(log, "w") if log else open(os.devnull, "w") as out:
        try:
            return subprocess.run([str(a) for a in args], cwd=ROOT, stdout=out, stderr=subprocess.STDOUT,
                                  timeout=timeout, env=env).returncode
        except subprocess.TimeoutExpired:
            return 124


def export(preset: str, path: str) -> None:
    target = ROOT / path
    shutil.rmtree(target.parent, ignore_errors=True)
    target.parent.mkdir(parents=True)
    # Godot's data (the export templates build.sh unpacked) inside build/, as build.sh keeps it.
    xdg = ROOT / "build" / "godot" / "xdg"
    env = {**os.environ, "XDG_DATA_HOME": str(xdg / "data"), "XDG_CONFIG_HOME": str(xdg / "config"),
           "XDG_CACHE_HOME": str(xdg / "cache")}
    status = sh(GODOT, "--headless", "--path", ".", "--export-release", preset, path,
                log=OUT / f"export-{preset.replace(' ', '-')}.log", env=env)
    if status != 0 or not target.exists():
        sys.exit(f"platform_hashes: the {preset} export failed (build/platforms/export-{preset.replace(' ', '-')}.log)")


def windows_temp() -> Path:
    text = subprocess.run(["/mnt/c/Windows/System32/cmd.exe", "/c", "echo %TEMP%"], capture_output=True,
                          text=True, cwd="/mnt/c").stdout.strip()
    return Path(subprocess.run(["wslpath", "-u", text], capture_output=True, text=True).stdout.strip())


# The exports' folders that `run` makes, by player.
BUILDS = {"linux": "build/linux-test", "linux-gdscript": "build/linux-test", "windows": "build/windows-test",
          "web": "build/web-test"}


def program(build: Path, pattern: str) -> Path:
    """The export's program in `build`, found by its extension (its name is the game's, ci/config.json)."""
    found = sorted(p for p in build.glob(pattern) if not p.name.endswith(".console.exe"))
    if not found:
        sys.exit(f"platform_hashes: no {pattern} in {build}")
    return found[0]


def play_linux(build: Path, args: list[str], timeout: float, log: Path) -> None:
    exe = program(build, "*.x86_64")
    exe.chmod(exe.stat().st_mode | 0o111)  # a downloaded CI artifact loses the mode
    sh(exe, "--headless", "--", ARGUMENT, *args, log=log, timeout=timeout,
       env={**os.environ, "XDG_DATA_HOME": str(log.parent / f"data-{log.stem}")})


def play_windows(build: Path, args: list[str], timeout: float, log: Path) -> None:
    folder = build
    if sys.platform != "win32":
        # Through WSL's interop, from a copy under %TEMP%, so the game does not start in a \\wsl$ path.
        folder = windows_temp() / WINDOWS_TEMP_NAME
        shutil.rmtree(folder, ignore_errors=True)
        shutil.copytree(build, folder)
    exe = program(folder, "*.exe")
    print(f"$ {exe} --headless -- {ARGUMENT} {' '.join(args)}", flush=True)
    with open(log, "w") as out:
        try:
            subprocess.run([str(exe), "--headless", "--", ARGUMENT, *args], cwd=folder, stdout=out,
                           stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired:
            out.write("\nplatform_hashes: timed out\n")


def play_web(build: Path, args: list[str], timeout: float, log: Path) -> None:
    page_args = [f"--page-args={a}" for a in [ARGUMENT, *args]]
    sh(sys.executable, "-m", "smbot.websmoke", build, *page_args, "--expect", DONE,
       "--timeout", str(timeout), log=log, env={**os.environ, "PYTHONPATH": str(ROOT / "ci")})


PLAYERS = {"linux": play_linux, "linux-gdscript": lambda b, a, t, l: play_linux(b, a + ["--no-native"], t, l),
           "windows": play_windows, "web": play_web}


def play(name: str, build: Path, args: list[str], timeout: float, log: Path) -> Path:
    """Plays the replay hashes in one export, the log written to `log`."""
    # Whole paths: the programs run in another folder (ROOT, or the Windows export's own).
    build, log = build.resolve(), log.resolve()
    log.parent.mkdir(parents=True, exist_ok=True)
    PLAYERS[name](build, args, timeout, log)
    return log


def main_run(opts: argparse.Namespace) -> int:
    if not GODOT.exists():
        sys.exit("platform_hashes: run ci/build/build.sh --quick first (the pinned Godot)")
    platforms = opts.platforms.split(",")
    OUT.mkdir(parents=True, exist_ok=True)
    args = [f"--ticks={opts.ticks}", f"--scenes={opts.scenes}"]
    if not opts.no_export:
        natives = ["linux"] + (["web"] if "web" in platforms else [])
        if sh("ci/build/native.sh", *natives, log=OUT / "native.log") != 0:
            sys.exit("platform_hashes: the native module did not build (build/platforms/native.log)")
        export("Linux Test", "build/linux-test/Spellmerge.x86_64")
        if "windows" in platforms:
            export("Windows Test", "build/windows-test/Spellmerge.exe")
        if "web" in platforms:
            export("Web Test", "build/web-test/index.html")
    # A run's log is build/platforms/<name>.log; a run again keeping a tick's leaves writes
    # <name>-keep-<other>.log beside it.
    def runner(name: str, a: list[str], tag: str = "") -> Path:
        return play(name, ROOT / BUILDS[name], a, opts.timeout, OUT / f"{name}{tag}.log")

    names = ["linux", "linux-gdscript"] + [p for p in platforms if p not in ("linux", "linux-gdscript")]
    logs = {name: runner(name, args) for name in names}
    runs = {name: parse(name, logs[name].read_text(errors="replace")) for name in names}
    status = 0
    for name in names:
        status = max(status, print_problems(runs[name], logs[name]))
    ref = runs["linux"]
    for name in names[1:]:
        refs = [ref] + ([runs["linux-gdscript"]] if name == "windows" else [])
        for against in refs:
            text, agree = report(against, runs[name])
            if not agree:
                # Again, keeping the parting tick's leaves on both, so the report names the members.
                partings = [p for p in compare(against, runs[name]) if p.tick >= 0]
                keeps = [f"--keep={p.scene}:{p.tick}" for p in partings]
                if keeps:  # none when only a scene was not played
                    # Only the scenes that part, each up to its parting tick.
                    again_args = [f"--ticks={max(p.tick for p in partings) + 1}",
                                  f"--scenes={','.join(p.scene for p in partings)}"] + keeps
                    pair = (against.name, name)
                    again = {n: parse(n, runner(n, again_args, f"-keep-{pair[1 - pair.index(n)]}").read_text(errors="replace"))
                             for n in pair}
                    text, agree = report(again[against.name], again[name])
                status = max(status, 1)
            print(text)
    return status


def main_compare(logs: list[Path]) -> int:
    """Compares saved logs with the first; prints each run's own problems and each parting."""
    status = 0
    runs: list[Run] = []
    for path in logs:
        if path.exists():
            runs.append(parse(path.stem, path.read_text(errors="replace")))
        else:  # its job failed before writing one
            print(f"{path.stem}: no log ({path})")
            status = 2
    if logs and not logs[0].exists():
        return status  # nothing to compare with
    for run in runs:
        status = max(status, print_problems(run))
    for other in runs[1:]:
        text, agree = report(runs[0], other)
        print(text)
        status = max(status, 0 if agree else 1)
    return status


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)

    def run_options(p: argparse.ArgumentParser) -> None:
        p.add_argument("--ticks", type=int, default=600)
        p.add_argument("--scenes", default="sandbox,horde")
        p.add_argument("--timeout", type=float, default=1800.0, help="seconds per run")

    r = sub.add_parser("run", help="export, run on each platform and compare")
    r.add_argument("--platforms", default="linux,windows,web")
    run_options(r)
    r.add_argument("--no-export", action="store_true", help="run the exports already in build/")
    p = sub.add_parser("play", help="run one export already built and write its log")
    p.add_argument("name", choices=sorted(PLAYERS))
    p.add_argument("--build", type=Path, help="the export's folder (default: where `run` exports it)")
    p.add_argument("--log", type=Path, help="the log to write (default: build/platforms/NAME.log)")
    run_options(p)
    c = sub.add_parser("compare", help="compare logs, the first one the reference")
    c.add_argument("logs", nargs="+", type=Path)
    opts = ap.parse_args(argv)
    if opts.command == "run":
        return main_run(opts)
    if opts.command == "play":
        log = play(opts.name, opts.build or ROOT / BUILDS[opts.name],
                   [f"--ticks={opts.ticks}", f"--scenes={opts.scenes}"], opts.timeout, opts.log or OUT / f"{opts.name}.log")
        return print_problems(parse(opts.name, log.read_text(errors="replace")), log)
    return main_compare(opts.logs)


if __name__ == "__main__":
    sys.exit(main())
