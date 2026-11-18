# Connected biomes: one walkable map a biome, free split and a Voronoi camera

**Status (2026-11-18): approved by the owner** ("Approve, open a PR"; the CB1 scene stays as a stress test); this document is the plan. **CB2 built** (the biome world: "CB2 done", below). Designed with the owner in one session ("Let's design a new room system"); every rule below is the owner's answer to a question of that session ("Owner decisions"). Reviewed against the code by a fresh-context agent the same day; its findings are written into the model and the steps, and the four that needed the owner were answered (decisions 2, 6, 25 and 1's count). It replaces run generation's branching row map ([run-generation.md](run-generation.md)) with a map of floating rooms joined by bridges, and keeps the rest of that plan (the run as data, kind rules, scaling, rule changes). It keeps the crypt rework's floating rooms ([crypt-rework.md](crypt-rework.md)). It builds a large part of M3's run structure ([docs/PLAN.md](../PLAN.md)).

The steps are **CB1 to CB13** (CB for connected biomes). Each is one PR with its tests, in order.

## What the owner asked (2026-11-18)

"Would it be feasible to have larger rooms AND have each room in a biome be connected 'physically'? Sort of like in Binding of Isaac? So we have a large map with different room types the player can choose to visit, to get all upgrades a biome has to offer - before having to fight a boss to reach the next level."

And on how the party moves: "Free split would really make the game awesome! Could it be done such that players in the same room share a camera, but everyone (also local players) could also split up?"

## What the players see

- The hub's stone takes the party by portal to the biome's **start room**, a small safe slab. From there the biome is one walkable place: 8–12 floating rooms of free shapes, about 1 to 2 screens each, joined by stone **bridges** across the dark.
- **Anyone goes anywhere.** Wizards in the same place share one picture; when they are too far apart for one view, on one slab or on two, the screen splits along the line between them (a Voronoi split), each view leaning toward the others, and merges back as they meet.
- A fight starts when the first wizard steps off a bridge onto its slab. Its bridge mouths seal **one way**: teammates may come in, nobody inside leaves until it is cleared.
- A bridge mouth tells what lies behind it (a kind symbol). Holding **Y** shows the map over that player's own view; nobody else stops.
- A cleared room stays cleared; what was left on the floor stays there.
- Coins dropped by enemies are shared income: whoever picks one up, every wallet gains it. Spending is one's own.
- Rooms to find: reward, shop, fountain, treasure (needs a key), challenge (the whole party enters together for a bigger reward), 1–2 secret rooms behind cracked rock that only one element breaks, and the boss, whose gate opens only with every standing wizard at it.
- A downed wizard can crawl; enemies ignore them; a teammate has to come for the revive.

## Owner decisions (2026-11-18)

**The map and rooms**

1. **One continuous world a biome:** every room stands at its place in one world. 8–12 rooms a biome, **not counting the start room and the bridges**. Every biome has the boss, a reward room, a shop, a secret room and at least 4 fights; by chance a fountain, a treasure room, a second secret, a challenge room and more fights. Mixed sizes, about 1 to 2 screens (a screen is 640×360).
2. **Floating rooms joined by bridges:** the crypt's rooms stay slabs in the void (crypt rework). A template marks **sockets** on its slab's lip (position, facing, a 64 px mouth); **bridges** (and other walkways) are templates of their own that span the dark between two sockets. The bridge's mouth is the doorway: where a seal stands and where shots stop. Unused sockets stay lip. Free shapes: no room-sized grid, but room origins, sockets and template sizes sit on the 32 px grid (the 8 px wall cells and the tiles never shift by part of a cell).
3. **Rooms remember:** cleared stays cleared, leftovers stay, a shop keeps its shelf.
4. **Depth** is the fewest bridges from the start room; the boss stands deepest. At least 4 fights lie on the way to the boss; the rest are optional branches.
5. **Map shape styles in data:** a biome rolls a style (long, branching, loop, hub and spokes), each a few generator weights.
6. **Variety:** a template at most once a biome (bridges and the start room excepted), **mirrored** either way when placed. The ground is **drawn when the room is laid out** from the mirrored shape, still lit from the upper left (the art never flips; it is drawn again). Collision comes from the mirrored layout, in whole cells; the drawing is view only.
7. **One biome (the crypt) for now;** chaining biomes into a run is decided later. After the boss a portal leads back to the hub.
8. **The lectern goes** (its depth pick has no meaning on this map).

**Moving and splitting**

9. **Free split** for every player, local ones too.
10. **Fight mouths seal one way:** teammates come in; nobody inside leaves, downed or standing; no enemy leaves.
11. **Shots never cross a doorway** (a bridge's mouth). **Movement spells** (dash, teleport, swap, portal, possess) **do**, along a way a body could walk (a move's segment from start to end crosses no wall or void cell; across a mouth only from outside a seal), and **never out of a sealed fight** (a swap across a seal fizzles).
12. **Portals and possession carry everything:** shots ride a portal into another room; a possessed enemy may leave its room and **joins the room it ends in** (its home room is cleared without it). A portal opened into a sealed fight from outside carries shots in, never out.
13. **A downed wizard can crawl** (slowly, no casting), is **ignored by enemies** (already the AI's rule: `gameplay/ai/brain.gd`, a target that is down is no target), and is revived only by a teammate.
14. **Everyone down: the run is lost,** back to the hub.

**Fights, rewards and the economy**

15. **A fight is scaled for the whole party,** as today, whoever is in the room.
16. **Rewards per player** (rule 3): each wizard's own roll on a clear; one who was not there gets it as an unspent icon (rule 4).
17. **Every reward is "pick 1 of 2"**, fight clears, reward rooms, treasure, challenge and boss alike (kinds differ by rarity); the number of choices is a player's own number, raised by relics and meta progression. *This changes DESIGN.md's "every reward offers 3 options": the owner edits that line.*
18. **Coins: shared income, own wallet.** A coin on the floor is one coin anyone may take; taking it adds one to every player's wallet; buying spends only the buyer's.
19. **Shop:** one copy of each item; the first buyer takes it.
20. **Fountain:** a shared pool of healing; a hurt wizard in it draws on it.
21. **Keys:** one a treasure room, dropped on the way to it; a key door opens for all.
22. **Secret rooms:** 1–2 a biome, each behind cracked rock that opens to **one element, rolled for that room** (the crack's tint hints which), to reward varied builds.
23. **Challenge rooms:** 0–1 a biome, a **gather door** (every standing wizard at it), sealed, an elite fight, a bigger reward.
24. **Elites:** an enemy type with more health, one extra card from the biome's list in its staff and an outline; about 1 fight room in 4 from a set depth on; a challenge room's enemies are all elite.
25. **The boss gate** is a gather door counting standing wizards, and it **stays shut while any seal holds a wizard**, downed or standing. When it opens **everyone comes**, downed or far away, onto the arena's spawns. After the boss: each player's boss reward, coins to every wallet, and a gather-door portal onward.
26. **Hooks, not content:** the map-touching effects (more choices, map reveal, secret sense, prices, more special rooms, fountain size, starting coins) are **run stats** that relics and rule changes add to; the relics themselves come with M3's relic work.

**Camera, HUD, sound and look**

27. **A Voronoi split for 1–4 local players:** one view while everyone fits; past that the screen divides along the bisector between the wizards (cells of up to four), each view leaning toward the others, and merges without a jump (only the divider grows in, over frames). Online each machine splits for its own seats only.
28. **HUD:** the panels stay in the screen's corners. Edge markers only for a teammate in none of this machine's views. The Y map draws inside its player's view.
29. **Sound only from rooms this machine's wizards are in;** music follows the most intense of them.
30. **The look:** an open mouth's shimmer (flares where a shot stops); a seal's bars drop in over frames with a rune; a gather door has a lamp for each standing wizard, lit in their hat colour as they arrive; a key door's padlock turns and falls; a secret crack's tint brightens near its element and breaks in stages. Unvisited rooms in a view are dark by a whole-pixel dither, lightening in stages. Each kind may bring its air, light and music layer.
31. **Performance:** the camera spike (CB1) sets the frame-time targets; nothing is promised before.

## The model

- **The biome map** (`gameplay/run`, replacing `RunMap`'s rows): rooms (each a template id, a place, a mirroring and a kind), bridges (each a template and the two sockets it joins), depth by bridges. Made once by the seeded generator, a pure function of the seed, the content and the unlocks, and then **kept as small hashed state, as `RunMap` is today**, so a joining machine and a restored snapshot never make their own. Only the nodes and the drawn art are laid out again (`rebuild_derived`).
- **The wall grid:** `RoomGrid` today is state, laid as rooms are entered. A biome-wide 8 px grid (about 6000×4000 px) would put megabytes into every hash and snapshot. So the grid's room layers become **DERIVED**, laid again from the map, and only what changes in play (broken pillars, opened secret rock, a seal's state) stays state, a room at a time. CB2 measures the hash and snapshot cost and names it in `test_state_declared`, `test_snapshot` and `test_snapshot_game`.
- **Cells:** a new cell kind, the **mouth**: a wall to shots and to bodies not driven by a wizard, open to wizards' bodies and to movement spells; a sealed mouth is one-way for wizards (in only) and closed to everything from inside. It changes what `ShotKernel` and `BodyKernel`/`WallSlide` read, so the C++ kernels change with their GDScript, byte for byte (`test_native_kernel.gd`, `test_wall_slide.gd`); sight and `line_clear` treat a mouth as open.
- **Who passes a mouth** is by who drives the body, not its team: a wizard's own body, or a body a wizard possesses, passes; a free enemy never does. An enemy carried into another room belongs there; one that ends up in a cleared room fights there, and that room does not seal again.
- **Room state** (each room, hashed): entered, fight started, sealed, cleared, its spawn queue, its adds and its scale (today one of each: `RoomSpawning`, `RoomAdds`, Difficulty's level), what lies on its floor (Items no longer forgets the ground on entering a room), its shop's shelf, its fountain's pool, seen (the party's map). **Which room a body is in** is kept with the body as state, updated as it crosses a mouth (a body never crosses anywhere else).
- **Room events:** `room_entered`, `room_left` and `room_cleared` carry meaning today for Spells (a room left ends every carrier cast), Items, Rewards, the HUD, Cover (`room_built`) and the camera's limits and the projectile manager's bounds (`room_size`, `set_bounds`). They become events **of a room** (its id), heard by each listener for that room; the world's bounds become the biome's. CB3 lists each listener and its new rule.
- **A room is awake** while anything acts in it: a wizard, a live enemy not at rest, a shot, a growing effect. It wakes when anything enters and sleeps when nothing acts; only state decides it. Each area joined to the tick skips a sleeping room's bodies the same way on every machine (their brains, timers, statuses and spawn queue do not step), and a test plays a room that sleeps and wakes against one that never slept.
- **Run stats** (core): named numbers (`reward_choices`, `price_scale`, `map_reveal`, `secret_sense`, `fountain_pool`, `start_coins`, each kind's limit, ...) worked out a player at a time as base, then the run's rule changes, then that player's relics (each a data list of stat changes). The systems read a stat by name and never know where it came from; a new stat is a row, a new relic a file. `RunRuleChange` gets the biome map's numbers as its targets (room counts, kind limits, styles' weights, the deepest depth for `RunScaling`'s per-depth curve) in place of the row map's depth, width and branches.
- **The view** (Feel): the Voronoi camera, the ground drawn at layout from the mirrored shape, the dark of unvisited rooms, the mouth and door looks, the Y map. Drawing only; nothing in the simulation reads it.

## Fit with the design

- **Nobody waits** (pillar 2): anyone goes anywhere; menus stay per player; the map is held, not a menu. The only shared choices are made by walking (rule 5): the boss gate, the challenge door and the portal onward. Two places ask the party to come back together, by the owner's choice: the boss gate waits for any sealed fight (decision 25), and a downed wizard left outside a challenge room's seal waits for its clear.
- **Rewards rolled per player** (rule 3), carried over when missed (rule 4); coins are shared income, so nobody races for them. The shop is first come, first served (decision 19), the one place a teammate's choice takes something from another.
- **One game, the same everywhere:** the map, room membership, waking and sleeping, mouths and seals are state on the tick; the camera, the ground's art, the dark, sound and looks are view only.
- **Smooth:** every door and room look changes by at least 3 frames in whole pixels; the split merges without a jump.
- **Short loops:** 8–12 rooms a biome keeps a biome to minutes; one biome for now.
- **The crypt rework stays:** floating slabs, their broken lips, the void and the light from the upper left; bridges are new art in its style.
- **Conflict to settle:** DESIGN.md's "every reward offers 3 options with trade-offs" (decision 17). The owner changes that line.

## Steps

1. **CB1 the camera spike.** Draw 2, 3 and 4 Voronoi views (a viewport a cell, each masked to its cell) over the busiest stress fight, on Linux and the web build; measure frame time with shots, motes, light and cover. Report numbers and the fallbacks they need (fewer motes or lights a view). The owner sets the targets from it (decision 31). The measuring scene stays as a lasting stress test (owner, 2026-11-18), run again whenever the camera, motes or light change.
2. **CB2 the biome world.** Sockets on templates (a class in `core/`, its editor preview in `tools/`), the 32 px placement rule, the mouth cell (GDScript and native kernels together), one bridge template, the biome map as hashed state, the grid's room layers DERIVED. Two or three crypt rooms joined in a hand-made test map, walked through. The row run stays the default. Tests: shots stop at a mouth, a wizard crosses, a free enemy does not, the kernels match, the hash and snapshot cost of a 12-room biome.
3. **CB3 room life.** Room state and room events (each listener named above moved to them), body membership, waking and sleeping, fights that start past a mouth and seal one way, movement spells across mouths (never out of a seal), portals and possession across rooms, crawling while downed. Tests: determinism and snapshots with a split party and two sealed fights at once (the content-determinism test gains them), a room woken by a shot, sleep-and-wake against never slept, a swap across a seal fizzling.
4. **CB4 ground at layout.** The ground drawing of `tools/ground_shape.py` (and the wall art of `ground_walls.py`) run in the game when a room is laid out, from the mirrored shape: view only, no load stall (measured), its output for an unmirrored room the same as the baked art's (a test compares them). The baked ground scenes stay for the hub until it moves over too.
5. **CB5 the generator,** behind the test map: sockets and bridges, depth, kind rules (fixed and chance kinds, decision 1), map styles, once-a-biome templates, mirroring; `MapRules` and `RunRuleChange` on the new numbers. Tests: every style makes valid maps over many seeds, the boss deepest, at least 4 fights on its way, the fixed kinds always there, the validator names a run whose content makes no map.
6. **CB6 the Voronoi camera** for real, with the HUD's corner panels and the edge-marker rule (decision 28). Tests: 1–4 seats in any rooms, cells always cover the screen, a merge has no jump.
7. **CB7 gather doors and the run's end:** the boss gate (waits for seals; everyone comes), the challenge door, the portal back to the hub as the run's end.
8. **CB8 the switch.** The crypt run moves to the biome map, and in the same PR go: the row map and `RunMap.start_at`; `room_exit` and `crypt_gate` as exits, `RoomBase.EXIT_ROLE` and `exit_count`, `RunContent.templates_for`'s exit count, `MapRules.exit_problems`, `ExitRules`; the events `run_way_taken`, `room_exits_shown` and `run_map_changed`; the pause menu's row Map page (`hud/widgets/run_map_view.gd`); the lectern, `HubRules.start_depth`, `start_depth_changed` and the command `start_depth_picked` (out of `InputFrame.COMMAND_NAMES`, so the replay format moves on); `tests/support/pinned_run.gd` becomes a pinned one-room biome. Nothing is ever half switched.
9. **CB9 the map:** seen rooms as state, mouth kind symbols, the held Y map in a player's view.
10. **CB10 the rewards area and the economy:** the Rewards area itself (gameplay/rewards has only its README): a roll per player on a room's clear, the offer of `reward_choices` (2), the unspent icon, what a reward may be before relics exist; run stats; coins (shared income, own wallets).
11. **CB11 special rooms:** reward, shop (first buyer), fountain (shared pool), treasure and its key, secret rock (an element each), challenge, elites. Each a `RoomKind` (`content/room_kinds/<id>.tres`), its fill a behaviour in the engine (the shop's shelf and the fountain's pool are new), and its templates.
12. **CB12 sound and the look:** sound from this machine's rooms only, the mouth, seal and door looks, bridges' art, the dark of unvisited rooms, each kind's air.
13. **CB13 templates:** the crypt's set grown from the first small one (about 6 fights, 3 bridges, the start room, the boss and one of each special) toward 12–16 fights, in later PRs.

Every template is read by tests in all four mirrorings (sockets on the lip, every socket reaching every other, spawns clear, the 32 px rule) and played once in a generated biome; a screenshot of each template and each map style.

## CB2 done (2026-11-18)

What CB2 built, and where it settled what the plan left open:

- **Sockets** are `RoomSocket` nodes (core/base) in a template's scene, a point and a facing (north, east, south or west; a mouth is 64 px across), read by `RoomPlaces` and taken out before play; `SocketPreview` (tools/) draws them in the editor. A template is a `PieceShape` to a biome (core/base): its own extent, walls, holes and sockets, mirrored either way. **Its rules:** its size and sockets on the 32 px grid; open floor on a socket's landing (16 px inside it); the slab ending within 16 px past a room's socket (the lip wanders); a walkway's (`RoomBase.walkway`) two sockets on its own edge; every socket walkable to every other by a way at least 16 px wide (a wizard is 12 px across); in all four mirrorings (`tests/content/rooms/test_room_sockets.gd`). The antechamber has an east socket, the nave a west and an east one, the ossuary court a west one.
- **The bridge:** `content/rooms/crypt/bridge/crypt_bridge`, a walkway 128 px long, its floor a 64 px band of flagstones (drawn by `tools/ground_shape.py` from its shape: a stand-in until CB12), its sides void walls.
- **The mouth cell** is a bit of the wall grid (`RoomGrid.MOUTH_CELL`, 64; the solid shots' count now stops at 63 below it), one 8 px cell deep, laid just outside each joined room socket, on the bridge's floor. Shots see any byte but 0 as a wall, so the native hit pass (`ShotKernel`) needed no change and stops at a mouth as the GDScript does (compared in `test_native_kernel.gd`'s scene, which now has a mouth). A body's move reads the wall grid through a mask (`WallSlide.slide`'s `mask`, `BodyKernel` the same, compared to the bit in `test_wall_slide.gd`): a body a wizard drives (`Actor.passes_mouths`: its controller's seat, so a possessed enemy too) leaves the mouth's bit out. Sight sees through a mouth (`RoomGrid.sight_clear`, for CB3's looks across a doorway); **an AI's line of fire does not** (`line_clear` stays the shot's path: a shot ends at a mouth, so an enemy never fires into one, and its walk check stops there too), nor do standing, landing and an AI's run-up (`circle_blocked`, `clear_run`). The other movement spells' crossing and the seals are CB3's.
- **Laying a biome** (`BiomeWorld`, gameplay/flow): each piece's layout at its place, the grid over the whole biome, every piece's walls and holes, **the dark between pieces a wall** (`RoomGrid.wall_outside`: nothing stands or flies there; the crypt's void is a wall already), each joined socket's lip cut open to the template's edge (`cut`, from its landing), the bridges' walls, then the mouths. A mirrored piece's collision is mirrored in whole cells; its art is shown flipped as a stand-in until CB4 draws the ground from the mirrored shape.
- **The biome map** (`BiomeMap`, gameplay/run) is packed rows (rooms, bridges and their ends, depths), its rules checked by `problems`; the hand-made maps are `tests/support/biome_maps.gd` (the walk-through test map: the antechamber, the nave and the ossuary court joined by two bridges; a twelve-room row, the nave ten times, mirrored four ways).
- **The grid's room layers are DERIVED** (`RoomGrid.DERIVED`): the walls, mouths, holes, the walking grid and the footprints' counts; the footprints and the solid shots' cells stay state, and a restore sets the rest up again (`RoomGrid.rebuild_derived`, then the manager's `relay_solids`). A world that laid another biome lays the restored map's layers over the restored bounds and puts the stones back, touching no state (`BiomeWorld`; checked by hash with a live Wall card's stone in `test_snapshot.gd`). Flow's row run lays its room as before (the same room after a restore: its layers are the restored world's own).
- **Measured** (a 12-room row, 9728 × 512 px; `test_state_declared.gd`, `test_snapshot.gd`, `test_snapshot_game.gd` print it): the map is about 1.1 KB of state; the grid's layers, now left out of every hash and snapshot, are about 310 KB. The whole game's hash with it took about 10 ms, the snapshot about 90 ms to take and 25 ms to restore; a restore into a world with another biome lays it again in about 45 ms. **What still grows with a biome's area is the projectile manager's target grid** (`_cell_*`, `_shot_head`: 32 bytes a 64 px cell, state): about 6 KB here, about 190 KB for a 6000 × 4000 px biome. Left as it is for CB3 to make DERIVED or room-local (its cells are filled each step).

## Answered by the owner (2026-11-18)

1. The plan: approved as written.
2. CB1's measuring scene: kept as a stress test.

## Not in this plan

- Chaining biomes into a run, and biomes past the crypt (decision 7).
- The relics and unlocks themselves (decision 26: only their hooks).
- Run themes (a flooded or burning crypt).
- A corner minimap (the Y map replaces it).
- The hub's move to the ground drawn at layout.
