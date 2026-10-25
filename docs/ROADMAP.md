# Roadmap

Eight strictly sequential milestones (docs/PLAN.md, "Roadmap"). One milestone at a time; nothing from a later milestone is built early. A milestone ends when its done-when criteria and the quality bar are met, never because time ran out.

| # | Milestone | Status | Done when |
| --- | --- | --- | --- |
| M0 | [Foundation](milestones/M0-foundation.md) | **Closed early** on 2026-10-16 by the owner; its dry runs and release streak carry into M1 | 3 daily releases in a row work and every pipeline part passes its dry run |
| M1 | [Core loop prototype](milestones/M1-core-loop.md) | **Closed** on 2026-10-21 by the owner (C1: go, after two iterate rounds); its open owner items carry into M2 | 4-bot smoke test passes on web, plus M0's carried-over dry runs and 3 daily releases in a row |
| M2 | [Spell system](milestones/M2-spell-system.md) | **In progress again** since 2026-10-25: the owner answered C2 (#235) with iterate: the clip recorder and Spell atlas (#245), spell visuals (#244), Lightning (#243), in that order; its next end is a new C2 checkpoint; done-when item 3 is open on the real-GPU frame rate (for the owner to judge) | Validators pass, 20+ combos work, plus M1's carried-over items |
| M3 | Run structure | Not started | A full run can be completed |
| M4 | Polish and variety | Not started | Polished enough to show off |
| M5 | Meta-progression | Not started | Runs give lasting progression |
| M6 | Content expansion | Not started | 3 biomes, 3 bosses, Steam page |
| M7 | Early Access ready | Not started | Ready to launch on Steam |

## Checkpoints

| Checkpoint | Question | Decided by |
| --- | --- | --- |
| C1: end of M1 | Do moving, dodging and casting feel good, alone and with 4 players? | Owner, with Claude's assessment |
| C2: end of M2 | Is building spells fun and deep, with surprising combos? | Owner, with bot data and player feedback |
| C3: end of M3 | After one full run, do you want to play another? | Owner, with player feedback |
| C4: before the Steam page | Is the art, sound and polish good enough to show the world? | Owner |

Every milestone ends with a checkpoint issue, the named ones above and the rest alike. Development waits for the owner's `/go`, `/iterate <what>` or `/pivot <how>` before the next milestone starts; scheduled bug fixes keep going meanwhile.

Each milestone's design document is written in `docs/milestones/` before any code, and passes an independent self-critique review against `docs/DESIGN.md` before it merges.
