# Roadmap

Eight strictly sequential milestones (docs/PLAN.md, "Roadmap"). One milestone at a time; nothing from a later milestone is built early. A milestone ends when its done-when criteria and the quality bar are met, never because time ran out.

One exception, by the owner on 2026-10-27: enemies casting spells from staffs moved from M3–M4 into M2 ([M2-staffs.md](milestones/M2-staffs.md), "Enemy staffs", phase F), so new enemy types are a sprite and a staff.

A second, by the owner on 2026-10-28: wizards and enemies become one kind of body, an actor made of components and driven by a controller, with no sides and a `possess` card ([M2-actors.md](milestones/M2-actors.md), phase G), before D3.

A third, by the owner on 2026-10-28: every character becomes a living staff, with a new story and an intro ([M2-living-staffs.md](milestones/M2-living-staffs.md), phase H), after phase G and before D3.

A fourth, by the owner on 2026-10-29: every card follows the general rules on every carrier, with no special cases and no silent no-ops, checked by a test that finds every card and carrier by itself ([M2-rules.md](milestones/M2-rules.md), phase R), before D3.

A fifth, by the owner on 2026-10-30: **Horde**, a separate game mode against a growing horde of 500+ enemies, to test the mechanics at scale. Removed by the owner on 2026-11-09, with all its code (docs/DECISIONS.md); its enemies, the Crypt Mite and the Bone Husk, stay as ordinary enemies.

A sixth, by the owner on 2026-11-01: **an enemy AI that plays whatever staffs it holds** (it reads what each staff casts next), with profiles, phases for bosses, dodging, channelled casts, teamwork, bots on the same AI and an enemy arena ([M2-enemy-ai.md](milestones/M2-enemy-ai.md), phase AI). It is the baseline; designing new enemies and bosses on it stays M3 and later.

A seventh, by the owner on 2026-11-03: **spell spectacle**, three drawn-only layers built ahead of M4's polish: motes (tens of thousands of single-pixel particles with no game logic), floor marks that stay for the room, and spell light ([spell-spectacle.md](milestones/spell-spectacle.md), phase P). It changes no rule, damage or cap.

An eighth, by the owner on 2026-11-04: **online-ready**, a deterministic simulation (the same inputs give the same game on every platform), input frames and replays, one tick clock, and snapshots, so online co-op can be added later ([online-ready.md](milestones/online-ready.md), phase N). It builds no netcode; networking stays banned until its own owner exception. Approved the same day: after the owner lane's current work, beside D3 and C2 (it does not hold them up), and done before M3 starts. It runs in one order with **shot scale** (threads in the shot kernel, toward 100,000 shots; [shot-scale.md](milestones/shot-scale.md)), approved the same day on five shared rules.

A ninth, by the owner on 2026-11-10: **the online lobby**, room codes through a small signalling server on Cloudflare's free plan, and the hub as the lobby: an island in the void where local and online players take up to four seats from any machines and start a run from the teleporter stone ([online-lobby.md](milestones/online-lobby.md)). It follows the netcode spike ([netcode-spike.md](milestones/netcode-spike.md)) and does not wait for its S5: L1 (the hub, offline) and L2 (the server and room codes) first, for a working lobby as soon as possible. The hub is the one M5 grows.

A tenth, planned with the owner on 2026-11-10 and approved on 2026-11-11: **props**, things in the world that stand, block, take hits, react by casting spell cards and give off motes (an exploding barrel's fuse and blast, a crate's rubble, a brazier's embers), each an actor with no controller and one content folder ([props.md](milestones/props.md), phase W). It runs beside the online lobby (owner, 2026-11-10).

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
