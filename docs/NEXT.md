# Next

The ordered task queue for the current milestone, M1 (its design is the first task below; M0's [dry runs](milestones/M0-foundation.md#dry-runs) carry over). The first unchecked task under "Queue" is next. Bug reports go above features. Claude keeps this file up to date; only tasks in paths Claude may change belong here (docs/PLAN.md, "Path tiers").

## Queue

- [ ] **M1 design document.** Write `docs/milestones/M1-core-loop.md` from docs/PLAN.md and docs/DESIGN.md, in the same shape as `M0-foundation.md`: goal, done when, who builds what, parts in build order, out of scope. M1 is the core loop prototype: 1 spell, 1 enemy, 1 room, 4-player join, game feel and pools ("Roadmap"); the `core/` services and the `player`, `combat`, `feel` and `coop` sub-areas ("Gameplay sub-areas", "Co-op technology"); performance budgets and the 4-bot smoke test; the provisional Style Guide page and starter kit, and the weekly owner playtest ("Infrastructure first"); Art and Audio open for PRs; checkpoint C1 at the end. Done when: the 4-bot smoke test passes on web, plus M0's carried-over dry runs and 3 daily releases in a row (docs/ROADMAP.md). Then replace this task with M1's tasks in this queue, in build order, each sized to one session, with the first content example per area. No M1 code before the design has merged.

## Blocked

- [ ] **Reconcile the event lists (waits for the M1 event bus).** The "Events at a glance" table in `gameplay/README.md` and the per-area event lists are kept in sync by hand. Once `core/events` exists, make it the single source: delete the table or generate it, and fix the area READMEs to match.

## Done recently

- [x] **README for `tools/`.** Added by the owner's session (Claude sessions may not write to `tools/`): how to run `tools/check.sh`, its flags and output; listed in `llms.txt`.
- [x] **READMEs for `art/`, `audio/` and `tests/`.** Size limits, `.ogg`-only audio, the origin manifest format, how to validate; all three are in `llms.txt`. `tools/README.md` followed separately.
- [x] **llms.txt.** `llms.txt` at the repo root indexes every doc (guides, plan files, ops docs, all area READMEs, tools, manifests, maintainer prompts) with a one-line description each.
- [x] **Area READMEs for code areas.** `core/`, `hud/` and the 10 `gameplay/` sub-areas each have a README with the fixed sections, build and open milestones, entry script name and the dependency direction; `core/` states it is closed to outside PRs.
- [x] **Area READMEs for the content areas.** `content/spells/`, `relics/`, `wizard/`, `enemies/`, `bosses/`, `rooms/` and `story/` each have a README with the fixed sections. The four top-level `.gitkeep` files are gone; spells, wizard and story keep their sub-folder `.gitkeep`s.
