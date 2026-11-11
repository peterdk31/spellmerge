# Tools

## Purpose

Scripts that contributors and Claude run on their own checkout. Today that is six. `tools/check.sh` runs the same hard rules as the `rules` check in CI on your changes, so you can fix problems before you open a PR. `tools/atlas.py <out>` writes the Spell atlas data (`atlas.json`: one entry per component, combo and reaction, read from `content/`; `build.sh --clips` calls it, and `ci/smbot/clips.py` has the format); its tests are `tools/test_atlas.py` (`python3 -m unittest discover -s tools`). `tools/pixel_grid.py <name>.grid.json...` draws pixel art from a grid of characters (props W7, docs/milestones/props.md): a grid file, kept beside its art, names a palette colour for each character (docs/STYLE.md's palette, read from there) and the mote-point characters (`*` by default), and it writes `<name>.svg` (rects only, one a run of a colour along a row, as tests/core/test_svg_art.gd wants) and, when the grid has mote points, `<name>_motes.svg` (the points alone, a mask for a prop's look to give off motes from), so a prop's art and where its motes come from are one source; `--check` writes nothing and fails when an SVG differs from its grid. Its tests are `tools/test_pixel_grid.py`, which also checks every grid in the repository against its SVGs. `tools/ptest.sh [jobs] [path-regex]` runs the Godot unit tests in parallel (one import, a user folder per test), about a minute for the whole suite; it needs the pinned Godot that `ci/build/build.sh --quick` downloads. `tools/platform_hashes.py run` is online-ready's first look across platforms (N2b, docs/milestones/online-ready.md): it exports Linux Test, Windows Test and Web Test into `build/`, plays the same recorded runs in each (`--replay-hashes`, tests/platforms/replay_hashes_runner.gd: Linux headless, Windows through WSL's interop, the web in headless Chromium through `smbot.websmoke`) and names the first tick, area and members where a platform parts from Linux; `play NAME --build DIR` plays one export already built (`linux`, `linux-gdscript`, `windows` or `web`; the daily run's `platforms` job plays each on its own runner, Windows on a Windows runner) and `compare LOG...` compares saved logs with the first, giving each parting area's two hashes. A run also says what its export was built with (`REPLAY BUILD`): an export whose WebRTC extension is missing or did not load is reported on its own, apart from the hashes (the one check of the Windows build's; `run` sets the extension up with `ci/build/webrtc.sh` before it exports). It writes only under `build/` (and a copy of the Windows export under %TEMP%), needs one `build.sh --quick` and, for Windows, WSL; its tests are `tools/test_platform_hashes.py`. `tools/online_pair.sh [ticks]` plays the real game twice on this machine (netcode spike S4): two headless processes go through Host and Join over WebRTC with no STUN server, their codes handed over as files under a `user://` of their own (`build/logs/online/`), play a sandbox with both seats scripted (`tests/net/online_runner.gd`), and it passes when every hash check agreed; about fifteen seconds for the default 600 ticks. `tools/online_signal.sh` runs the room server's own tests (`node --test` in `server/signal/`), then starts the server on this machine (`local.js`, Node alone) and plays the game's real handshake through it; `tools/online_room.sh [ticks]` plays the real game twice through a room on that server (online lobby L2: Play, the altar, the code, two players a machine, the stone, a run) and passes when every hash check agreed. `tools/online_party.sh [ticks]` does the same with four processes, a host and three guest machines of one player each (L3). All three need Node 22 or later.

**Editor scripts** (`@tool`, allowed here and in core/ only, by the owner's decision of 2026-11-11; AGENTS.md, hard rule 4): `prop_stand_in.gd` (`PropStandIn`) and `enemy_stand_in.gd` (`EnemyStandIn`) place a prop or an enemy in a room's scene and show it in the editor as the game will (content/rooms/README.md, props W8b). They never run in play: Flow takes them out of the room and reads only their `prop` or `enemy`.

**Not an area for content PRs.** Scripts here run on contributors' machines, so they change only through Claude's PRs or the owner's.

## Contract

- Tools only read the repository and report, or write the files they are asked for (`atlas.py` its out file, `pixel_grid.py` a grid's SVGs); they never change anything else, push or open PRs.
- They depend on git and Python 3.10 or newer, nothing else (`ptest.sh` also needs bash and the pinned Godot). Pipeline Python code lives in `ci/smbot/`, which is owner-only; `check.sh` is a thin wrapper around it. `atlas.py` is self-contained (standard library only) because it reads the game's content, not the pipeline.
- They work in any clone with an `origin` remote, and still run (on the local copy) when they can't fetch.

## Allowed files

`.sh` and `.py` scripts and the editor scripts (`.gd`, with their `.uid` files) (Claude's PRs only) and this README. No binaries, archives or downloaded tools.

## Steps

Run the check from the repository root before every PR:

```sh
tools/check.sh
```

It fetches `origin/main`, then checks everything you changed against it: committed, uncommitted and new files. It runs `python3 -m smbot.rules --base origin/main --worktree`, and any flags you add are passed on:

- `--author LOGIN`: the PR author's GitHub login, which decides the path rules. The default is an outside contributor. `--author 'spellmerge-bot[bot]'` applies Claude's wider rules (docs, plan files, `tools/` scripts).
- `--format text|github|json`: `text` (the default) for people, `github` for CI annotations, `json` for scripts and agents.

Every problem is printed as the rule, the file and line, what is wrong and how to fix it. The script exits with 1 when there is an error, and with 0 when there are only warnings or nothing. Empty placeholder files that an agent's sandbox leaves in the working directory (`.bashrc`, `.gitconfig`, `.idea/` and similar) are skipped.

## Example to copy

`tools/check.sh`: a short POSIX `sh` script that changes to the repository root, fetches `origin/main` and runs the Python module with `PYTHONPATH=ci`.

## Validate

```sh
tools/check.sh                              # your change, as an outside contributor
tools/check.sh --author 'spellmerge-bot[bot]'  # Claude's own PRs
PYTHONPATH=ci python3 -m unittest discover -s ci/tests -t ci   # the rules' own tests
```

## Rating questions

Besides the standard criteria (fit, quality, value, risk, scope):

- Does it only read and report, with no side effects on the checkout or GitHub?
- Does it run with just git and Python 3.10+, and keep working offline?
- Does it give the same answer as the `rules` check in CI?
