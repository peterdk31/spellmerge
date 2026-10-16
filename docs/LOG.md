# Log

What each run did, newest first. Claude appends a short entry after each development session; the detailed record of every bot action is in the pinned Daily log issue.

## 2026-10-16

- Wrote the M1 design document (`docs/milestones/M1-core-loop.md`): 25 parts in build order (after review, four big parts were split), decisions on events (including the `play_requested` intent from the menu to `flow`), scenes, registry (sounds by id, `null` when missing), the one spell, arena glue and placeholder art, and the owner-only steps. Replaced the task in `docs/NEXT.md` with M1's 25 tasks. `tools/check.sh` reports the same 3 errors and 3 warnings on `main` and here: they are untracked local files (`.idea`, `.vscode`, `scripts`) that are not part of the change.
- Owner's decision: M0 closed early and M1 started. M0's dry runs and the 3-release streak carry into M1's done-when. First M1 task in `docs/NEXT.md`: the M1 design document.
- Owner's session: wrote `tools/README.md` (sessions may not write to `tools/`), unblocking the last README task. `develop` now also starts `daily` and `weekly` when GitHub misses their schedule.
- Tried again to write `tools/README.md`; writes to `tools/` were denied a third time. Moved the task to "Blocked" in `docs/NEXT.md` with what the owner needs to change and the facts for the README.
- Wrote READMEs for `art/`, `audio/` and `tests/` (size limits, `.ogg`-only audio, manifest format, how to validate). `tools/README.md` could not be written: writes to `tools/` were denied by the session, so it stays in the queue.
- Wrote `llms.txt`: an index of every doc with a one-line description, in the llms.txt format (H1, summary, link sections, "Optional" for the maintainer prompts).
- Wrote READMEs for `core/`, `hud/`, a shared `gameplay/README.md` and the 10 gameplay sub-areas (job, built and open milestones, entry script, dependency direction `core` ← `gameplay` ← `content`; `core/` closed to outside PRs). Revised after review: HUD events match the player-intent decision, Feel's hit-stop is named as its only timing effect, gameplay allows `.gd` and `.tres` only.
- Wrote READMEs for the seven content areas (spells, relics, wizard, enemies, bosses, rooms, story), each stating the milestone it opens in and that the example to copy arrives with Claude's first content.
- Repository created with `setup.sh`; all settings verified with `./setup.sh --check`. Spellmerge Bot app installed; secrets stored in the `automation` environment.
- Control panel (#4) and Daily log (#5) issues created by the owner, pinned and locked.
- M0 parts 1 and 2 built in interactive sessions: hard rules check and `checks.yml` (#2); Godot 4.7.2 project, build pipeline with smoke tests (editor, Linux, web in headless Chrome) and daily release (#3).
- M0 parts 3 and 4 in progress: control gate, Control panel verification, owner commands, pacing, alarms, plan files.
