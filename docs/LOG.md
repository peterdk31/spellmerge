# Log

What each run did, newest first. Claude appends a short entry after each development session; the detailed record of every bot action is in the pinned Daily log issue.

## 2026-10-16

- Wrote `llms.txt`: an index of every doc with a one-line description, in the llms.txt format (H1, summary, link sections, "Optional" for the maintainer prompts).
- Wrote READMEs for `core/`, `hud/`, a shared `gameplay/README.md` and the 10 gameplay sub-areas (job, built and open milestones, entry script, dependency direction `core` ← `gameplay` ← `content`; `core/` closed to outside PRs). Revised after review: HUD events match the player-intent decision, Feel's hit-stop is named as its only timing effect, gameplay allows `.gd` and `.tres` only.
- Wrote READMEs for the seven content areas (spells, relics, wizard, enemies, bosses, rooms, story), each stating the milestone it opens in and that the example to copy arrives with Claude's first content.
- Repository created with `setup.sh`; all settings verified with `./setup.sh --check`. Spellmerge Bot app installed; secrets stored in the `automation` environment.
- Control panel (#4) and Daily log (#5) issues created by the owner, pinned and locked.
- M0 parts 1 and 2 built in interactive sessions: hard rules check and `checks.yml` (#2); Godot 4.7.2 project, build pipeline with smoke tests (editor, Linux, web in headless Chrome) and daily release (#3).
- M0 parts 3 and 4 in progress: control gate, Control panel verification, owner commands, pacing, alarms, plan files.
