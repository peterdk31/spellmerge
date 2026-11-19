# Connected biomes: one walkable map a biome, free split and a Voronoi camera

**Status (2026-11-18): approved by the owner** ("Approve, open a PR"; the CB1 scene stays as a stress test); this document is the plan. **CB1 done** (2026-11-18): the camera spike's numbers are below ("CB1's numbers"); the owner sets the targets from them (decision 31). CB2 built (the biome world: "CB2 done", below). CB3 built (room life: "CB3 done", below). CB4 done (the ground drawn at layout; "Built (CB4)" below). CB6 built (the Voronoi camera; "Built (CB6)" below). Designed with the owner in one session ("Let's design a new room system"); every rule below is the owner's answer to a question of that session ("Owner decisions"). Reviewed against the code by a fresh-context agent the same day; its findings are written into the model and the steps, and the four that needed the owner were answered (decisions 2, 6, 25 and 1's count). It replaces run generation's branching row map ([run-generation.md](run-generation.md)) with a map of floating rooms joined by bridges, and keeps the rest of that plan (the run as data, kind rules, scaling, rule changes). It keeps the crypt rework's floating rooms ([crypt-rework.md](crypt-rework.md)). It builds a large part of M3's run structure ([docs/PLAN.md](../PLAN.md)).

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

1. **CB1 the camera spike** (done 2026-11-18; "CB1's numbers" below; `tests/benchmark/split_views.gd`). Draw 2, 3 and 4 Voronoi views (a viewport a cell, each masked to its cell) over the busiest stress fight, on Linux and the web build; measure frame time with shots, motes, light and cover. Report numbers and the fallbacks they need (fewer motes or lights a view). The owner sets the targets from it (decision 31). The measuring scene stays as a lasting stress test (owner, 2026-11-18), run again whenever the camera, motes or light change.
2. **CB2 the biome world.** Sockets on templates (a class in `core/`, its editor preview in `tools/`), the 32 px placement rule, the mouth cell (GDScript and native kernels together), one bridge template, the biome map as hashed state, the grid's room layers DERIVED. Two or three crypt rooms joined in a hand-made test map, walked through. The row run stays the default. Tests: shots stop at a mouth, a wizard crosses, a free enemy does not, the kernels match, the hash and snapshot cost of a 12-room biome.
3. **CB3 room life.** Room state and room events (each listener named above moved to them), body membership, waking and sleeping, fights that start past a mouth and seal one way, movement spells across mouths (never out of a seal), portals and possession across rooms, crawling while downed. Tests: determinism and snapshots with a split party and two sealed fights at once (the content-determinism test gains them), a room woken by a shot, sleep-and-wake against never slept, a swap across a seal fizzling.
4. **CB4 ground at layout.** The ground drawing of `tools/ground_shape.py` (and the wall art of `ground_walls.py`) run in the game when a room is laid out, from the mirrored shape: view only, no load stall (measured), its output for an unmirrored room the same as the baked art's (a test compares them). The baked ground scenes stay for the hub until it moves over too.
5. **CB5 the generator,** behind the test map: sockets and bridges, depth, kind rules (fixed and chance kinds, decision 1), map styles, once-a-biome templates, mirroring; `MapRules` and `RunRuleChange` on the new numbers. Tests: every style makes valid maps over many seeds, the boss deepest, at least 4 fights on its way, the fixed kinds always there, the validator names a run whose content makes no map.
6. **CB6 the Voronoi camera** for real, with the HUD's corner panels and the edge-marker rule (decision 28). Tests: 1–4 seats in any rooms, cells always cover the screen, a merge has no jump. (Built: "Built (CB6)" below.)
7. **CB7 gather doors and the run's end:** the boss gate (waits for seals; everyone comes), the challenge door, the portal back to the hub as the run's end.
8. **CB8 the switch.** The crypt run moves to the biome map, and in the same PR go: the row map and `RunMap.start_at`; `room_exit` and `crypt_gate` as exits, `RoomBase.EXIT_ROLE` and `exit_count`, `RunContent.templates_for`'s exit count, `MapRules.exit_problems`, `ExitRules`; the events `run_way_taken`, `room_exits_shown` and `run_map_changed`; the pause menu's row Map page (`hud/widgets/run_map_view.gd`); the lectern, `HubRules.start_depth`, `start_depth_changed` and the command `start_depth_picked` (out of `InputFrame.COMMAND_NAMES`, so the replay format moves on); `tests/support/pinned_run.gd` becomes a pinned one-room biome. Nothing is ever half switched.
9. **CB9 the map:** seen rooms as state, mouth kind symbols, the held Y map in a player's view.
10. **CB10 the rewards area and the economy:** the Rewards area itself (gameplay/rewards has only its README): a roll per player on a room's clear, the offer of `reward_choices` (2), the unspent icon, what a reward may be before relics exist; run stats; coins (shared income, own wallets).
11. **CB11 special rooms:** reward, shop (first buyer), fountain (shared pool), treasure and its key, secret rock (an element each), challenge, elites. Each a `RoomKind` (`content/room_kinds/<id>.tres`), its fill a behaviour in the engine (the shop's shelf and the fountain's pool are new), and its templates.
12. **CB12 sound and the look:** sound from this machine's rooms only, the mouth, seal and door looks, bridges' art, the dark of unvisited rooms, each kind's air.
13. **CB13 templates:** the crypt's set grown from the first small one (about 6 fights, 3 bridges, the start room, the boss and one of each special) toward 12–16 fights, in later PRs.

Every template is read by tests in all four mirrorings (sockets on the lip, every socket reaching every other, spawns clear, the 32 px rule) and played once in a generated biome; a screenshot of each template and each map style.

## CB1's numbers (2026-11-18)

The measuring scene is `tests/benchmark/split_views.gd` (tests/README.md, `benchmark/`): the stress fight (four bots with built spells, the crowd and the shots held at the cap, every hit's particles, light, motes and the crypt room's cover; `stress_runner.gd`) drawn as a Voronoi split. A view is a SubViewport the screen's size sharing the root's World2D, its own Camera2D at zoom 1 on its wizard, shown through a polygon the shape of its cell; the root then draws only the cells and the HUD (its canvas cull mask leaves the world's layer out). Each view past the first draws a light buffer of its own. Run it again whenever the camera, the motes or the light change.

**Where:** this session's container, 4 cores, no GPU: Linux under `xvfb-run` on Mesa's llvmpipe (software GL, on the same 4 cores as the game), and the Web Test export in headless Chrome on SwiftShader (software WebGL). Neither is a GPU: the times are far over any budget and only their **ratios** are worth reading. Each row is one scenario of the run, 10 s measured after 3 s of warm-up (`SPLIT VIEWS OK`, no errors).

Linux, the desktop's 200 enemies and 6,000 shots (frame time is the whole frame; GPU the views', the light buffers' and the root's, a frame):

| Views | Frame avg | Frame p95 | GPU total | GPU a view | Light buffers |
|---|---|---|---|---|---|
| no split | 138 ms | 165 ms | 64 ms | (root 51) | 13 ms (1) |
| 1 | 135 ms | 160 ms | 57 ms | 43 ms | 10 ms (1) |
| 2 | 207 ms | 240 ms | 124 ms | 51 ms | 19 ms (2) |
| 3 | 263 ms | 296 ms | 187 ms | 48 ms | 38 ms (3) |
| 4 | 297 ms | 347 ms | 214 ms | 41 ms | 44 ms (4) |
| 4, light off | 219 ms | 255 ms | 147 ms | 36 ms | none |
| 4, fewest motes (2,048) | 280 ms | 311 ms | 199 ms | 40 ms | 36 ms (4) |

Linux, the web's 100 enemies and 1,000 shots (the desktop's mote ring, 32,768):

| Views | Frame avg | Frame p95 | GPU total | GPU a view | Light buffers |
|---|---|---|---|---|---|
| no split | 80 ms | 90 ms | 42 ms | (root 31) | 11 ms (1) |
| 2 | 109 ms | 122 ms | 71 ms | 27 ms | 14 ms (2) |
| 3 | 139 ms | 161 ms | 99 ms | 25 ms | 19 ms (3) |
| 4 | 156 ms | 177 ms | 112 ms | 24 ms | 14 ms (4) |
| 4, light off | 118 ms | 138 ms | 78 ms | 19 ms | none |
| 4, fewest motes (2,048) | 145 ms | 163 ms | 101 ms | 21 ms | 12 ms (4) |

Web, the Web Test export (`--split-views`) in headless Chrome on SwiftShader, the web's load and mote ring (8,192). WebGL has no GPU timer queries, so only the frame time is a measure there (the run warns when it reads no GPU time):

| Views | Frame avg | Frame p95 | Against no split |
|---|---|---|---|
| no split | 273 ms | 330 ms | 1.0 |
| 2 | 452 ms | 597 ms | 1.66 |
| 3 | 666 ms | 828 ms | 2.44 |
| 4 | 788 ms | 974 ms | 2.89 |
| 4, light off | 614 ms | 807 ms | 2.25 (22% under 4 views) |
| 4, fewest motes (2,048) | 629 ms | 747 ms | 2.30 (20% under 4 views) |

The web's tick stays at 10.9 to 12.0 ms in every row.

**What they say:**

- **The split is drawing only.** A physics step's scripts take the same time in every row (about 20 ms desktop, 9 ms web on this machine), and the tick stays within its noise (17.0 to 18.5 ms desktop, 7.4 to 8.9 ms web): nothing in the simulation knows about the views, as the plan wants.
- **A view through a SubViewport costs nothing extra:** one view costs what the root drawing the world does (135 against 138 ms). The way CB6 draws views is settled: a SubViewport a view sharing the world, masked to its cell.
- **Each view draws the whole frame again,** about 40 to 50 ms of llvmpipe a view at the desktop's load and 20 to 27 ms at the web's: four views cost about 3.3 times one view's GPU time, close to linear. On a GPU the ratio is what to expect: four views of a busy fight cost about four frames' drawing.
- **Light is the largest share a fallback can take:** with it off, four views draw 26% faster (desktop on llvmpipe), 24% (the web's load on llvmpipe) and 22% (the browser); the light buffers are only part of it, most is the apply pass in each view (its screen copy and shader). **Motes depend on the renderer:** the fewest motes save 6 to 7% on llvmpipe but 20% in the browser, nearly what the light does; on the web they are the second fallback, not the last.
- **Every view draws every shot:** the projectile batches are never culled (`Batches.multimesh`, the world's box), so a view of an empty room still draws the fight in another. On one slab it does not matter (each view sees the fight); across the biome it will.

**The fallbacks, in the order to try them** (for the owner's targets, decision 31):

1. **Light a view at a lower price:** the light off past two views, or a light buffer at half its size a view past the first; light was a quarter of the frame at four views.
2. **Draw a view's own room's shots only:** cull the batches by the rooms a view shows (per-room batches, or a view's cull mask over room layers), so a split across rooms does not draw each fight in every view.
3. **Smaller views:** a SubViewport the size of its cell's box, not the screen's, so four views fill about one screen of pixels instead of four (the cell's camera offset moves with it).
4. **Fewer motes a view:** a step down the mote ring when split; little on the desktop, about a fifth of the frame in the browser, so on the web it comes second.

**For CB6, the light's look:** every view's apply rect is the world's one canvas item with one material, which reads the game's one light buffer at the screen's coordinates, so in a view the light is drawn where the root's camera would put it (the spike's extra buffers are drawn for their cost, not read). The fix that fits Godot: a light buffer and an apply rect a view, each apply rect on a visibility layer of its own (`CanvasItem.visibility_layer`) with its own material reading its own buffer, and each view's cull mask taking only its own layer; the lit-only motes and the mist read the buffer too and need the same (a MultiMeshInstance2D a view sharing the one MultiMesh, each with its view's material).

**What the spike does not measure:**

- **What each view frames:** every view's camera keeps to the room's limits, as the game's camera does today, so in the stress room (larger than a screen) the views show overlapping parts of the one fight (their screens are saved with `--shots`). That is the worst case, every view full of the fight; views onto void and quiet rooms cost less.
- **Cover:** the stress room's cover is the crypt's own (its cobwebs; the Cover step about 0.33 ms a tick), drawn in every view; a room thick with grass, and a "cover off" row, are left for when a biome has one.
- **What sits on the root's canvas layers but follows the world** (the teammate markers' layer, the HUD panels placed by the root camera) is drawn once by the root, over the cells, where the root's camera puts it; the mote sources and the bodies' on-screen checks still read the root's view. Cheap, and right in no split; CB6 moves each to its view.

**Targets:** not set here. These are software-rendered numbers; the owner's real measure is a GPU in a browser (the hub storm's harness, tests/README.md, `benchmark/`): the Web Test export with `--split-views` in Chrome without vsync, or `split_views.gd` on a desktop with a GPU.

## Built (CB4)

The ground drawn at layout (2026-11-18). `gameplay/feel/ground/` draws a room's ground in the game from its shape file, as the room is laid out: `GroundDrawing` is `tools/ground_shape.py`'s drawing line by line (with `ground_materials.py` and `ground_walls.py`), and the native module's `MoteKernel.draw_ground` (`native/src/ground_kernel.cpp`) its twin, to the byte. Feel's `Ground` part (`ground_layout.gd`) hears `room_built` and, for a room whose `.tres` names its shape (`RoomBase.ground_shape`: the five crypt rooms), puts the drawn floor, glow, rock face and wall art on the layout's `Floor` and makes its rims' and drips' mote lines again, before the room is shown. The hub names none and keeps its baked scene, as do the crypt rooms' scenes (the editor's view, the walls and holes, and what the drawing is held to).

- **Mirroring.** The layout's `GroundShape.MIRROR_META` (`Vector2i`, x or y 1) says how the room is placed; CB5's generator sets it. The ground's outline (land, cracks, pits, areas, slivers and ledges dropped: the floor a body stands on) is worked out in the template's frame exactly as the tool does, then mirrored; every look on it is drawn again (flagstones, lip, rubble, the rock face under the south edges, the walls' faces above the floor, rims, drips, glow), so the light still comes from the upper left. An area's middle (the broom's swept ring) is mirrored with it. What stands in the room is read from the template's scene as saved, so the drawing is a function of the template and its mirroring alone.
- **The same as the tool.** The tool reads a node's position and a zone's sides as single precision, as the game does (`single`), and only a line's own `position`; two test shapes that reach what no room uses yet (a wall's top, face and foot, an island's outline, a hole void, cracks from an outline, patches, strokes) are held to the tool by its hashes of them (`ground_fixtures.json`, `ground_shape.py --fixtures`, checked by `tools/test_ground_shape.py`).
- **The same as the baked art.** Unmirrored, every room's drawing is its baked PNGs to the pixel (the alpha of every pixel, the colour of every pixel that is not clear: the import fills clear pixels' colour) and its rims and drips are the baked scene's lines, the hub's too (`tests/gameplay/feel/test_ground_drawing.gd`, by the native module; by the GDScript for the antechamber). For it, the tool's lengths became `length_of` (a square root of the sum of the squares; `math.hypot` and `math.dist` round otherwise now and then): every PNG drawn again is byte for byte the same, and only each ground scene's hash changed.
- **No load stall, measured** (`test_ground_layout.gd`, `GROUND LAYOUT` lines; drawing and the textures, first and warm, this container's four cores): the antechamber (640×384) 23 to 30 ms, the nave (768×384) 31 to 37, arena_03 (640×448) 25 to 34, arena_04 (704×448) 37 to 42, the broom's hall (832×512) 36 to 53; the hub (1600×1088, not drawn at layout) 131. The frame's outline and the floor's materials run on the module's threads, eight rows a span; on one thread (as the web build, which has none, draws; measured on this desktop, the web's wasm slower still) the drawing alone takes 36 to 60 ms. Without the module the GDScript takes 4 to 6 s a crypt room (the Python 6 to 9 s), so without it an unmirrored room keeps its baked art (what would be drawn) and only a mirrored one is drawn; every exported build has the module. The test fails a room over 150 ms with the module.
- **For CB2 and CB5 (collision).** The mirrored floor is the exact mirror of the unmirrored one, pixel for pixel, so the mirrored room's walls and holes are the unmirrored cells mirrored (decision 6: whole cells). A cell's middle pixel (4, 4) mirrors to the mirrored cell's (3, 4), (4, 3) or (3, 3), by the axes mirrored (an 8 px cell has no middle pixel), where the art of every open cell is opaque: a test of a mirrored template's art reads an open cell there. The drawing changes no body: the baked scene's `Walls` and `Holes` stay until the biome's grid lays its own.

## CB2 done (2026-11-18)

What CB2 built, and where it settled what the plan left open:

- **Sockets** are `RoomSocket` nodes (core/base) in a template's scene, a point and a facing (north, east, south or west; a mouth is 64 px across), read by `RoomPlaces` and taken out before play; `SocketPreview` (tools/) draws them in the editor. A template is a `PieceShape` to a biome (core/base): its own extent, walls, holes and sockets, mirrored either way. **Its rules:** its size and sockets on the 32 px grid; open floor on a socket's landing (16 px inside it); the slab ending within 16 px past a room's socket (the lip wanders); a walkway's (`RoomBase.walkway`) two sockets on its own edge; every socket walkable to every other by a way at least 16 px wide (a wizard is 12 px across); in all four mirrorings (`tests/content/rooms/test_room_sockets.gd`). The antechamber has an east socket, the nave a west and an east one, the ossuary court a west one.
- **The bridge:** `content/rooms/crypt/bridge/crypt_bridge`, a walkway 128 px long, its floor a 64 px band of flagstones (drawn by `tools/ground_shape.py` from its shape: a stand-in until CB12), its sides void walls.
- **The mouth cell** is a bit of the wall grid (`RoomGrid.MOUTH_CELL`, 64; the solid shots' count now stops at 63 below it), one 8 px cell deep, laid just outside each joined room socket, on the bridge's floor. Shots see any byte but 0 as a wall, so the native hit pass (`ShotKernel`) needed no change and stops at a mouth as the GDScript does (compared in `test_native_kernel.gd`'s scene, which now has a mouth). A body's move reads the wall grid through a mask (`WallSlide.slide`'s `mask`, `BodyKernel` the same, compared to the bit in `test_wall_slide.gd`): a body a wizard drives (`Actor.passes_mouths`: its controller's seat, so a possessed enemy too) leaves the mouth's bit out. Sight sees through a mouth (`RoomGrid.sight_clear`, for CB3's looks across a doorway); **an AI's line of fire does not** (`line_clear` stays the shot's path: a shot ends at a mouth, so an enemy never fires into one, and its walk check stops there too), nor do standing, landing and an AI's run-up (`circle_blocked`, `clear_run`). The other movement spells' crossing and the seals are CB3's.
- **Laying a biome** (`BiomeWorld`, gameplay/flow): each piece's layout at its place, the grid over the whole biome, every piece's walls and holes, **the dark between pieces a wall** (`RoomGrid.wall_outside`: nothing stands or flies there; the crypt's void is a wall already), each joined socket's lip cut open to the template's edge (`cut`, from its landing), the bridges' walls, then the mouths. A mirrored piece's collision is mirrored in whole cells; its layout carries CB4's mirror meta (`PieceShape.GROUND_MIRROR_META`), and its ground is drawn mirrored once the pieces are announced to Feel with CB3's room events (`room_built` today makes Cover lay the whole room, so CB2 sends none); until then a mirrored piece shows its baked art.
- **The biome map** (`BiomeMap`, gameplay/run) is packed rows (rooms, bridges and their ends, depths), its rules checked by `problems`; the hand-made maps are `tests/support/biome_maps.gd` (the walk-through test map: the antechamber, the nave and the ossuary court joined by two bridges; a twelve-room row, the nave ten times, mirrored four ways).
- **The grid's room layers are DERIVED** (`RoomGrid.DERIVED`): the walls, mouths, holes, the walking grid and the footprints' counts; the footprints and the solid shots' cells stay state, and a restore sets the rest up again (`RoomGrid.rebuild_derived`, then the manager's `relay_solids`). A world that laid another biome lays the restored map's layers over the restored bounds and puts the stones back, touching no state (`BiomeWorld`; checked by hash with a live Wall card's stone in `test_snapshot.gd`). Flow's row run lays its room as before (the same room after a restore: its layers are the restored world's own).
- **Measured** (a 12-room row, 9728 × 512 px; `test_state_declared.gd`, `test_snapshot.gd`, `test_snapshot_game.gd` print it): the map is about 1.1 KB of state; the grid's layers, now left out of every hash and snapshot, are about 310 KB. The whole game's hash with it took about 10 ms, the snapshot about 90 ms to take and 25 ms to restore; a restore into a world with another biome lays it again in about 45 ms. **What still grows with a biome's area is the projectile manager's target grid** (`_cell_*`, `_shot_head`: 32 bytes a 64 px cell, state): about 6 KB here, about 190 KB for a 6000 × 4000 px biome. Left as it is for CB3 to make DERIVED or room-local (its cells are filled each step).

## CB3 done (2026-11-18)

What CB3 built, and where it settled what the plan left open:

- **Room state** is Flow's `RoomLife` (gameplay/flow): each room's flags (entered, started, sealed, cleared) and fight (`RoomFight`: its enemies, pace, scale and queue), and each place's wakefulness. A biome run starts by `Flow.start_biome(requester, map, fights)` (mode `MODE_BIOME`; only the tests start one until CB5 and CB8). Its bodies are stood from each room's places, mirrored and moved to the room's place (`RoomPlaces.placed_in`, read by `BiomeWorld.room_places`). Everyone down starts the same biome again.
- **Places:** the grid knows every piece as a place, the rooms then the bridges (`RoomGrid.add_place`, `place_at`; a 32 px lookup, DERIVED). **Membership** is each body's state (`Actor.room`), kept after every move and for every open body each tick (`RoomLife.wake`).
- **Fights and seals:** a room's fight starts as a wizard's own body stands in it for the first time (each fight's enemies at its own scale, `RoomFight.scale`, told before they stand); its mouths seal (`RoomGrid.set_sealed`, told again after a restore): a body in a sealed place passes no mouth (`Actor.passes_mouths`), so a teammate walks in and nobody walks out. A room's fight is what no seat drives standing in it: a possessed enemy is no one's fight, its room is cleared without it, and released elsewhere it fights for that room (a cleared room never seals again).
- **Waking:** a place is awake while a body that acts (not a world prop, not still, not dying) or a shot is in it, worked out after the bodies each tick (`RoomLife.wake`, `ProjectileManager.shot_places`); a sleeping place's bodies are skipped by the Tick and Combat (`Actors.asleep`) and its spawn queue waits. "Not at rest" for an enemy is read as alive and not still; an enemy's rest is for later.
- **Movement:** a teleport a wizard drives crosses an open mouth (`RoomGrid.clip_past_mouths`), never a seal; a body is never moved out of a sealed place by a swap or a portal (`RoomGrid.may_cross`, in `Mover`'s target move and the portal's shots); a swap between places goes only along a way a body could walk and fizzles across a seal (`CarrierSwap.may_trade`). A dash is the body's own move, which the seal already holds.
- **Crawling:** a downed wizard walks at `Mover.CRAWL_SHARE` (a quarter) of its speed in a biome (slowed as walking is), casting nothing, and starts no room's fight by crawling into it; a row run's stands where it fell until CB8.
- **Room events** carry the room's number (`Events.FIRST_ROOM` 0, `ALL_ROOMS`): `room_entered` (a room's first entry; FIRST_ROOM's is a new world), `room_cleared`, `room_built` (every piece, rooms then bridges, before its placements go), `room_items_placed` (every room's at the start; only FIRST_ROOM's clears the ground), `room_left` (a biome's only as its world goes, ALL_ROOMS). The listeners: Spells ends its carriers on `room_left`; Items keeps the ground past FIRST_ROOM; Entities, Coop's revives, Combat's fall cost, Feel's camera, music and room look, the room's ambience and the spectacle's mist reset on FIRST_ROOM only; the spectacle's light blockers take every piece's walls at its place; Feel's Ground draws every piece (a mirrored one mirrored); Cover and its look play FIRST_ROOM's cover only, and only where it stands at the world's origin unmirrored (one room at a time, never the biome at once; a cover a room, at its place and mirrored, is for later); the HUD and the input layer as before. Rewards has no code yet. The camera's limits are the biome's bounds, the projectile manager's bounds the biome's, and a growing shot grows to the biggest room's side (`set_room_size`).
- **The target grid** (`_cell_*`, `_shot_head`) is DERIVED, linked again from the targets' places after a restore (`_relink_targets`).
- **Tests:** `tests/gameplay/flow/test_room_life.gd` (the start room entered, every piece built, a mirrored one drawn mirrored; a fight seals one way and opens when cleared; a swap or a portal never takes a body out of a seal; a teleport crosses an open mouth but not a seal; a possessed enemy leaves its room cleared without it; a shot wakes a sleeping room; a sleeping room against one that never slept; a downed wizard crawls), and `test_content_determinism.gd`'s split party in two sealed fights at once, twice and through a snapshot (`tests/support/biome_fight.gd`).

## Built (CB6)

The Voronoi camera (2026-11-18; gameplay/feel/README.md, "The split screen"). `split_camera.gd` works the views out each drawn frame, `split_screen.gd` draws them, Feel steps both after the party camera; view only, nothing in the simulation reads it.

- **When it splits.** One picture (the party camera, unchanged) while the box round this machine's wizards fits at its widest zoom (0.5, its 48 px margin kept); past that a view a group; merged again once the box fits with 10% to spare (`MERGE_ROOM`), so a party at the edge does not flicker. Online each machine splits for its own seats only (`Frames.seats_here`); a teammate on another machine never splits this screen.
- **Groups, not only wizards.** Seats within 160 px of each other share a view (`JOIN_REACH`; once together, until 224 px apart, `LEAVE_REACH`), through any chain, so "wizards in the same place share one picture" holds with a third far away. With every seat in one group and no fit (a long line of four), each seat is its own.
- **Leaning.** The groups' middles are laid on the screen as they stand, one scale both ways (so the line between two cells is the bisector), the farthest 96 px from an edge (`SITE_MARGIN`, CB1's margin); each view looks where its group is drawn there, at `SPLIT_ZOOM` (1.0), kept to the world camera's limits; the cells are cut along the bisectors between where the groups are drawn now (`VoronoiCells.fill`, moved from the spike into Feel, nothing allocated). A group's cell holds its group.
- **No jump.** Each view eases on real time (the party camera's `FOLLOW_SPEED`). A new view starts as the picture drawn (read from the world camera's canvas transform, so Godot's own limit clamp is matched) or as the view that held its seats, so at first both sides of the line are one picture; a merging view eases onto its target (another view, or the world camera's picture) and goes only once they are the same to 0.05 px. Only the divider changes at once: 3 px (`DIVIDER_WIDTH`), a pixel a drawn frame, growing in with a new view and shrinking out with a merging one once their pictures are within a pixel. A view keeps its slot and its SubViewport while it lives; with four slots in use and a fifth view wanted (three changes inside a second), the merging view nearest done gives its slot up.
- **Drawn as CB1 settled:** a SubViewport a view sharing the root's World2D, its canvas transform set directly (no camera node: the transform is the view's), shown by a rect over the screen whose shader (`split_cell.gdshader`) keeps the pixels nearer its anchor than any other (ties to the lower view, so every pixel is one view's) and draws the divider in the void's dark, whole pixels. The root's cull mask drops the world's visibility layer while there is a view; every canvas item on a canvas layer of the root keeps a screen layer it still draws.
- **The light done right** (CB1's finding). A buffer a view: the game's light buffer follows the first view and each other view gets one sharing its world (`SpellLight.use_views`), so the lights are drawn once a view. What reads the light by the screen (the apply rect, the lit-only motes, the mist) finds the view it is drawn in by its canvas matrix in the shader (`light_views.gdshaderinc`, the nearest of the views' transforms SpellLight writes each frame) and reads that view's buffer: one material and one draw a view, no copies of the apply rect on visibility layers (CB1's suggestion), which would have needed a copy of every mote batch and the mist too.
- **The HUD** (decision 28). The corner panels are on the HUD's canvas layer, so they stay in the screen's corners, drawn once over the views. The edge markers are in screen pixels now: only for a teammate in no view's cell, on the line from the nearest view's anchor. Each player's item hint follows that player's own view and hides while the item is outside its cell.
- **What reads the picture by the screen** reads the views published on the root viewport while split (`ScreenViews`, core/display): the mouse's place in the world (through the view under the mouse), a body's looks on screen (in any cell), the mote sources and Feel's picture (the box round every view's). Sound still hears from the world camera's middle: sound from this machine's rooms is CB12's.
- **The fallbacks and the targets** (decision 31; the owner's answer of 2026-11-19: 16.7 ms a frame on the desktop and 33 ms on the web build with four views, to be tuned from a GPU run). A frame-time budget (`split_budget.gd`) climbs CB1's ladder while the screen is split and the frames' average runs over the target for a second: a cheaper light a view (the buffers past the first view's twice as small again each way), then half the motes, then a quarter; back down a rung after three seconds under three quarters of the target; nothing with one view. **How the targets should be met:** CB1 measured four views at about 3.3 times one view's GPU time, so on a GPU where the unsplit fight draws in about 5 ms (desktop) or 10 ms (web) four views fit as they are; above that the rungs take off up to about a quarter of the frame on the web (light and motes there save about 20% each) and less on the desktop (the light most of it). If a GPU run shows four views still over, the next rungs are CB1's others, kept for then: the light off past two views, a view's own room's shots only (per-room batches now that CB3 has rooms), and views the size of their cell.
- **The camera's limits** are still the room's (Flow's); CB3 moves them to the biome's bounds, and the views keep to whatever the world camera's limits are. Inside one room nothing splits unless the room is wider than the widest picture (the hub is: 1600 × 1088).
- **Tests:** `tests/gameplay/feel/test_split_camera.gd` (1 to 4 seats in the twelve-room biome's rooms, groups, the cells covering the screen and holding their wizards, a split starting as the picture drawn, a merge ending on it with the divider a pixel a frame, this machine's seats only, slots kept), `test_split_screen.gd` (the views drawing the world, the root its layers, published and put back; the light's buffers and readers; each item hint in its own view), `tests/core/test_screen_views.gd`, `test_teammate_markers.gd` (a teammate in another view, or in none).

## Answered by the owner (2026-11-18)

1. The plan: approved as written.
2. CB1's measuring scene: kept as a stress test.

## Not in this plan

- Chaining biomes into a run, and biomes past the crypt (decision 7).
- The relics and unlocks themselves (decision 26: only their hooks).
- Run themes (a flooded or burning crypt).
- A corner minimap (the Y map replaces it).
- The hub's move to the ground drawn at layout.
