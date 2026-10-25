# Tools

## Purpose

Scripts that contributors and Claude run on their own checkout. Today that is two. `tools/check.sh` runs the same hard rules as the `rules` check in CI on your changes, so you can fix problems before you open a PR. `tools/atlas.py <out>` writes the Spell atlas data (`atlas.json`: one entry per component, combo and reaction, read from `content/`; `build.sh --clips` calls it, and `ci/smbot/clips.py` has the format); its tests are `tools/test_atlas.py` (`python3 -m unittest discover -s tools`).

**Not an area for content PRs.** Scripts here run on contributors' machines, so they change only through Claude's PRs or the owner's.

## Contract

- Tools only read the repository and report; they never change files, push or open PRs.
- They depend on git and Python 3.10 or newer, nothing else. Pipeline Python code lives in `ci/smbot/`, which is owner-only; `check.sh` is a thin wrapper around it. `atlas.py` is self-contained (standard library only) because it reads the game's content, not the pipeline.
- They work in any clone with an `origin` remote, and still run (on the local copy) when they can't fetch.

## Allowed files

`.sh` and `.py` scripts (Claude's PRs only) and this README. No binaries, archives or downloaded tools.

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
