# Next

The ordered task queue for the current milestone, M0 ([design](milestones/M0-foundation.md)). The first unchecked task under "Queue" is next. Bug reports go above features. Claude keeps this file up to date; only tasks in paths Claude may change belong here (docs/PLAN.md, "Path tiers").

## Queue

- [ ] **Area READMEs for shared assets and tests.** The same for `art/`, `audio/`, `tests/` and `tools/`, including the asset size limits, `.ogg`-only audio, the origin manifest (`art/manifest.json`, `audio/manifest.json`) and how to run `tools/check.sh`. Add each new README to `llms.txt` in the same PR.

## Blocked

- [ ] **Reconcile the event lists (waits for the M1 event bus).** The "Events at a glance" table in `gameplay/README.md` and the per-area event lists are kept in sync by hand. Once `core/events` exists, make it the single source: delete the table or generate it, and fix the area READMEs to match.

## Done recently

- [x] **llms.txt.** `llms.txt` at the repo root indexes every doc (guides, plan files, ops docs, all area READMEs, tools, manifests, maintainer prompts) with a one-line description each.
- [x] **Area READMEs for code areas.** `core/`, `hud/` and the 10 `gameplay/` sub-areas each have a README with the fixed sections, build and open milestones, entry script name and the dependency direction; `core/` states it is closed to outside PRs.
- [x] **Area READMEs for the content areas.** `content/spells/`, `relics/`, `wizard/`, `enemies/`, `bosses/`, `rooms/` and `story/` each have a README with the fixed sections. The four top-level `.gitkeep` files are gone; spells, wizard and story keep their sub-folder `.gitkeep`s.
