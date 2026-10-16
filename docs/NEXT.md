# Next

The ordered task queue for the current milestone, M0 ([design](milestones/M0-foundation.md)). The first unchecked task under "Queue" is next. Bug reports go above features. Claude keeps this file up to date; only tasks in paths Claude may change belong here (docs/PLAN.md, "Path tiers").

## Queue

- [ ] **Area READMEs for code areas.** The same for `core/`, `hud/` and each of the 10 `gameplay/` sub-areas, including each sub-area's job, when it is built and when it opens (docs/PLAN.md, "Gameplay sub-areas"), its public entry script name, and the dependency direction `core` ← `gameplay` ← `content`. `core/` states it is closed to outside PRs.
- [ ] **Area READMEs for shared assets and tests.** The same for `art/`, `audio/`, `tests/` and `tools/`, including the asset size limits, `.ogg`-only audio, the origin manifest (`art/manifest.json`, `audio/manifest.json`) and how to run `tools/check.sh`.
- [ ] **llms.txt.** An index of every doc in the repo with a one-line description each, following the llms.txt convention, for agents and LLM tools.

## Blocked

(none)

## Done recently

- [x] **Area READMEs for the content areas.** `content/spells/`, `relics/`, `wizard/`, `enemies/`, `bosses/`, `rooms/` and `story/` each have a README with the fixed sections. The four top-level `.gitkeep` files are gone; spells, wizard and story keep their sub-folder `.gitkeep`s.
