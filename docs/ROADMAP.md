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

An eleventh, planned with the owner on 2026-11-13: **items**, things a body picks up, holds in bags (staffs, cards, relics, potions) and drops, with staff pickups first, counted cards, an inventory beside the builder and a rack in the hub ([items.md](milestones/items.md), phase I). It builds M3's bags and pickups early, for the staffs; what relics and potions do, and items as a run's rewards, stay M3.

A twelfth, planned with the owner on 2026-11-14 and 2026-11-15: **the first boss, the Old Broom**, after the crypt: a slow, sweeping charge that carries players into walls, two phases, pillars as shelter that gets used up, dust heaps that explode on fire, and mites the boss brings ([boss-old-broom.md](milestones/boss-old-broom.md), phase OB). It builds M3's first boss early, content first, on general pieces every actor gains (actor stats, the Lumber and Plow cards, moves with speed curves and a pass as wide as the body, `on wall` for moves, poses and layered bodies, phase adds and health by player count, the AI's run-up, held sounds and music with intensity, the boss bar); placing it in a run stays M3.

A thirteenth, planned with the owner on 2026-11-15: **run generation**, a run defined as data (its biome, map rules, room kinds and scaling) and its branching map generated from the run's seed and the content there is, filled with fights and the boss, scaled with depth and players, its rules open to meta progression on the host's save ([run-generation.md](milestones/run-generation.md), phase RG). It builds the core of M3's run structure early; waves are gone (boss OB2a). Reward and other rooms, unlocks and a difficulty setting stay M3 and later.

A fourteenth, planned with the owner on 2026-11-15: **ground cover**, grass and other cover on the floors that sways in the wind, bends as bodies walk through it, is trampled and burns: one layout worked out from each room (its biome's fill and fields placed by hand), the game's part a simulation grid, the look Feel's ([ground-cover.md](milestones/ground-cover.md), phase GC). It builds M3's "elements on the room" for fire on cover early, beside the boss plan; water, ice and breakable walls stay M3.

A fifteenth, planned with the owner on 2026-11-16 and approved the same day: **the hub rework**, the hub drawn again as the Landing, a magic island at the bottom of the shaft (a plaza round the stone, the landing at the top under a beam of light, the campfire, the rack, the training ring, the altar's dais, the junk yard; organic lines everywhere, a coast of light and motes, cracks into the void), with **holes**, a new kind of cell the whole game may use: walked round, dashed, teleported and portaled over, and fallen into ([hub-rework.md](milestones/hub-rework.md), phase HR).

A sixteenth, planned with the owner on 2026-11-16: **the boss intro**, a screen-wide overlay as a boss's fight starts: the boss a silhouette, then its name in a title type and the boss revealed looking mean, its lines if it has any, and the fight starting on any player's A ([boss-intro.md](milestones/boss-intro.md), phase BI). It replaces the boss plan's entrance banner for a boss with an intro, and is the one stop for everyone beside the pause menu and an unplugged pad (docs/DESIGN.md, no-waiting rule 7). Approved the same day.

A seventeenth, planned with the owner on 2026-11-16 and approved the same day: **the crypt rework**, the Vaults: every crypt room a floating slab of quiet cool flagstones in the dark, drawn from a shape as the hub is, with warm light against the dark, a landmark a room, pits (holes), gates for exits and pillars as props that crumble ([crypt-rework.md](milestones/crypt-rework.md), phase CR). The sandbox goes with it, its showcase staffs on the hub's rack. One session a step, each merged before the next. **Done 2026-11-17:** all five rooms are floating slabs (CR3 to CR7), the gate and the crypt pillar built (CR-G), the sandbox gone (CR-S).

An eighteenth, planned with the owner on 2026-11-18: **atmosphere**, more drawn layers in Feel: darker rooms with a coloured dark and wizards that carry their own light, lit dust in the air, shadows from walls and bodies, a room's sound, a world that notices the spells, and soft mist ([atmosphere.md](milestones/atmosphere.md), phase A to F). It changes no rule, damage or cap.

A nineteenth, planned with the owner on 2026-11-18: **sound**, a generator for every sound the game asks for: Python recipes in `tools/` baked into committed `.ogg` files in a modern synthesised style (effects with variants the game jitters, seamless held loops, music from a pattern sequencer with layers of one length), a view-only `core/audio` service for buses, volumes, ducking and UI sounds, loudness targets in docs/STYLE.md, a hash check that every sound matches its recipe, and a sound room to audition them ([sound.md](milestones/sound.md), phase AU). It fills every silent id the game named (49 when it was planned, 63 with the music and the menus'), the core combat set first. Approved; being built (AU2, the tool, done; AU3, the Audio service, done; AU4, the sound room, done; AU5, the core combat set, done; AU6, the rest of the effects and the ambience as recipes, done; AU7, the music, done; AU8, the UI sounds, done; AU9, the owner's playtest, next).

A twentieth, planned with the owner and approved on 2026-11-18: **connected biomes**, one walkable map a biome: 8 to 12 floating rooms of free shapes joined by bridges, anyone going anywhere with a Voronoi split camera, fights that seal one way, rewards per player, shared coins, special rooms and the boss's gather gate ([connected-biomes.md](milestones/connected-biomes.md), phase CB). It replaces run generation's row map and builds a large part of M3's run structure. Approved; being built (CB1, the camera spike, its stress fight drawn in 2 to 4 views and measured, kept as a stress test, `tests/benchmark/split_views.gd`, done: the owner sets the frame-time targets from its numbers; CB4, the ground drawn at layout from the mirrored shape, done). CB2, the biome world (sockets, the bridge, the mouth cell, the biome map as state, the grid's room layers out of the hash), built; CB3, room life (room state and events, seals one way, waking and sleeping, movement across mouths), built. CB5, the seeded biome generator (kinds fixed and by chance, the way to the boss, map styles as data, loops, mirroring, a template once a biome, the rule changes on the new numbers), built on stand-in content until the crypt has the templates; CB7, gather doors and the run's end (the boss's gate waiting for every seal and bringing everyone, the challenge room's gather door, a biome boss's intro, the portal home after the boss, everyone down back to the hub), built; the row run stays the default until CB8.

| # | Milestone | Status | Done when |
| --- | --- | --- | --- |
| M0 | [Foundation](milestones/M0-foundation.md) | **Closed early** on 2026-10-16 by the owner; its dry runs and release streak carry into M1 | 3 daily releases in a row work and every pipeline part passes its dry run |
| M1 | [Core loop prototype](milestones/M1-core-loop.md) | **Closed** on 2026-10-21 by the owner (C1: go, after two iterate rounds); its open owner items carry into M2 | 4-bot smoke test passes on web, plus M0's carried-over dry runs and 3 daily releases in a row |
| M2 | [Spell system: staffs](milestones/M2-staffs.md) (first design: [M2-spell-system.md](milestones/M2-spell-system.md)) | **In progress**: C2 (#264) answered with pivot on 2026-10-26; the staffs rework is being built | Every staffs part merged, every card in two combos, bots build staffs, the owner's playtest, then C2 again |
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
