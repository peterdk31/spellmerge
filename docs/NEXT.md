# Next

The ordered task queue for the current milestone, M0 ([design](milestones/M0-foundation.md)). The first unchecked task under "Queue" is next. Bug reports go above features. Claude keeps this file up to date; only tasks in paths Claude may change belong here (docs/PLAN.md, "Path tiers").

## Queue

## Blocked

- [ ] **README for `tools/` (blocked: the session may not write to `tools/`).** Left over from "Area READMEs for shared assets and tests": write `tools/README.md` (purpose, how to run `tools/check.sh` with `--author` and `--format`, contract, allowed files) and add it to `llms.txt`. Writes to `tools/` were denied by the session's permission settings three times (the third on 2026-10-16, even for a plain `Write` of `tools/README.md`). `ci/smbot/session.py` keeps `tools/` read-only for Claude's sandbox, yet `ci/smbot/rules.py` allows the bot to change `.sh` and `.py` files there. **The owner would need to** either allow writes to `tools/` in the development session's permissions (`.github/` or `.claude/` settings), or add `tools/README.md` by hand. Facts for the README: `tools/check.sh` runs `python3 -m smbot.rules --base origin/main --worktree`; extra flags pass through: `--author LOGIN` (the PR author's GitHub login; default is an outside contributor, `'spellmerge-bot[bot]'` applies the bot's wider path rules) and `--format text|github|json` (default `text`); it needs git and Python 3.10+, fetches `origin/main` first, and prints rule, file, line and fix for each problem.

- [ ] **Reconcile the event lists (waits for the M1 event bus).** The "Events at a glance" table in `gameplay/README.md` and the per-area event lists are kept in sync by hand. Once `core/events` exists, make it the single source: delete the table or generate it, and fix the area READMEs to match.

## Done recently

- [x] **READMEs for `art/`, `audio/` and `tests/`.** Size limits, `.ogg`-only audio, the origin manifest format, how to validate; all three are in `llms.txt`. `tools/README.md` is still open (see Queue).
- [x] **llms.txt.** `llms.txt` at the repo root indexes every doc (guides, plan files, ops docs, all area READMEs, tools, manifests, maintainer prompts) with a one-line description each.
- [x] **Area READMEs for code areas.** `core/`, `hud/` and the 10 `gameplay/` sub-areas each have a README with the fixed sections, build and open milestones, entry script name and the dependency direction; `core/` states it is closed to outside PRs.
- [x] **Area READMEs for the content areas.** `content/spells/`, `relics/`, `wizard/`, `enemies/`, `bosses/`, `rooms/` and `story/` each have a README with the fixed sections. The four top-level `.gitkeep` files are gone; spells, wizard and story keep their sub-folder `.gitkeep`s.
