# Next

The ordered task queue for the current milestone, M0 ([design](milestones/M0-foundation.md)). The first unchecked task under "Queue" is next. Bug reports go above features. Claude keeps this file up to date; only tasks in paths Claude may change belong here (docs/PLAN.md, "Path tiers").

## Queue

- [ ] **Area READMEs for the content areas.** Write `README.md` for `content/spells/`, `content/relics/`, `content/wizard/`, `content/enemies/`, `content/bosses/`, `content/rooms/` and `content/story/`, with the fixed sections from docs/PLAN.md ("AI-friendly onboarding"): Purpose · Contract · Allowed files · Steps · Example to copy · Validate · Rating questions. Each states that the area opens for PRs in its milestone (see "Opens for PRs" in docs/ROADMAP.md), and that the example to copy arrives with Claude's first content in that milestone. Remove the `.gitkeep` files in folders that now have a README. Done when every content area has a README that an outside contributor (or their AI agent) can follow, and nothing in them contradicts docs/PLAN.md.
- [ ] **Area READMEs for code areas.** The same for `core/`, `hud/` and each of the 10 `gameplay/` sub-areas, including each sub-area's job, when it is built and when it opens (docs/PLAN.md, "Gameplay sub-areas"), its public entry script name, and the dependency direction `core` ← `gameplay` ← `content`. `core/` states it is closed to outside PRs.
- [ ] **Area READMEs for shared assets and tests.** The same for `art/`, `audio/`, `tests/` and `tools/`, including the asset size limits, `.ogg`-only audio, the origin manifest (`art/manifest.json`, `audio/manifest.json`) and how to run `tools/check.sh`.
- [ ] **llms.txt.** An index of every doc in the repo with a one-line description each, following the llms.txt convention, for agents and LLM tools.

## Blocked

(none)

## Done recently

(none yet)
