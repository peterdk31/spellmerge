# Roadmap

Eight strictly sequential milestones (docs/PLAN.md, "Roadmap"). One milestone at a time; nothing from a later milestone is built early. A milestone ends when its done-when criteria and the quality bar are met, never because time ran out.

One exception, by the owner on 2026-10-27: enemies casting spells from staffs moved from M3–M4 into M2 ([M2-staffs.md](milestones/M2-staffs.md), "Enemy staffs", phase F), so new enemy types are a sprite and a staff.

A second, by the owner on 2026-10-28: wizards and enemies become one kind of body, an actor made of components and driven by a controller, with no sides and a `possess` card ([M2-actors.md](milestones/M2-actors.md), phase G), before D3.

A third, by the owner on 2026-10-28: every character becomes a living staff, with a new story and an intro ([M2-living-staffs.md](milestones/M2-living-staffs.md), phase H), after phase G and before D3.

A fourth, by the owner on 2026-10-29: every card follows the general rules on every carrier, with no special cases and no silent no-ops, checked by a test that finds every card and carrier by itself ([M2-rules.md](milestones/M2-rules.md), phase R), before D3.

| # | Milestone | Status | Done when |
| --- | --- | --- | --- |
| M0 | [Foundation](milestones/M0-foundation.md) | **Closed early** on 2026-10-16 by the owner; its dry runs and release streak carry into M1 | 3 daily releases in a row work and every pipeline part passes its dry run |
| M1 | [Core loop prototype](milestones/M1-core-loop.md) | **Closed** on 2026-10-21 by the owner (C1: go, after two iterate rounds); its open owner items carry into M2 | 4-bot smoke test passes on web, plus M0's carried-over dry runs and 3 daily releases in a row |
| M2 | [Spell system: staffs](milestones/M2-staffs.md) (first design: [M2-spell-system.md](milestones/M2-spell-system.md)) | **In progress**: C2 (#264) answered with pivot on 2026-10-26; the staffs rework is being built | Every staffs part merged, every card in two combos, bots build staffs, the owner's sandbox playtest, then C2 again |
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
