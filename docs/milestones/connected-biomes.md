# Connected biomes: one walkable map a biome, free split and a Voronoi camera

**Status (2026-11-18): proposed, for the owner's approval.** Designed with the owner in one session ("Let's design a new room system"); every rule below is the owner's answer to a question of that session ("Owner decisions"). No code yet. It replaces run generation's branching row map ([run-generation.md](run-generation.md)) with a map of rooms joined wall to wall, and keeps the rest of that plan (the run as data, kind rules, scaling, rule changes). It builds a large part of M3's run structure ([docs/PLAN.md](../PLAN.md)).

The steps are **CB1 to CB11** (CB for connected biomes). Each is one PR with its tests, in order.

## What the owner asked (2026-11-18)

"Would it be feasible to have larger rooms AND have each room in a biome be connected 'physically'? Sort of like in Binding of Isaac? So we have a large map with different room types the player can choose to visit, to get all upgrades a biome has to offer - before having to fight a boss to reach the next level."

And on how the party moves: "Free split would really make the game awesome! Could it be done such that players in the same room share a camera, but everyone (also local players) could also split up?"

## What the players see

- The hub's stone takes the party by portal to the biome's **start room**, a small safe room. From there the biome is one walkable place: 8–12 rooms of free shapes, about 1 to 2 screens each, joined by doorways and short corridors.
- **Anyone goes anywhere.** Wizards in the same place share one picture; when they are too far apart for one view, in one room or in two, the screen splits along the line between them (a Voronoi split), each view leaning toward the others, and merges back as they meet.
- A fight starts when the first wizard is past a doorway. Its doors seal **one way**: teammates may come in, nobody inside leaves until it is cleared.
- Doors tell what lies behind them (a kind symbol). Holding **Y** shows the map over that player's own view; nobody else stops.
- A cleared room stays cleared; what was left on the floor stays there.
- Coins dropped by enemies are shared income: whoever picks one up, every wallet gains it. Spending is one's own.
- Rooms to find: reward, shop, fountain, treasure (needs a key), challenge (the whole party enters together for a bigger reward), 1–2 secret rooms behind cracked walls that only one element breaks, and the boss, whose door opens only with every standing wizard at it.
- A downed wizard can crawl; enemies ignore them; a teammate has to come for the revive.

## Owner decisions (2026-11-18)

**The map and rooms**

1. **One continuous world a biome:** every room stands at its place in one world; a doorway is an opening in the wall. 8–12 rooms a biome, boss and special rooms included. Mixed sizes, about 1 to 2 screens (640×384 to about 1280×768).
2. **Free shapes:** no grid. Templates mark **door sockets** (position, facing, a 64 px opening); a generator grows the biome from the start room by matching sockets, with **corridor** templates bridging gaps. Unused sockets become wall.
3. **Rooms remember:** cleared stays cleared, leftovers stay, a shop keeps its shelf.
4. **Depth** is the fewest doors from the start room; the boss stands deepest. At least about 4 fights lie on the way to the boss; the rest are optional branches.
5. **Map shape styles in data:** a biome rolls a style (long, branching, loop, hub and spokes), each a few generator weights.
6. **Variety:** a template at most once a biome (corridors and the start room excepted), **mirrored** either way when placed. Walls are **built when the room is laid out** from the mirrored layout (collision from the layout, in whole pixels; the art from wall pieces), not baked per variant.
7. **One biome (the crypt) for now;** chaining biomes into a run is decided later. After the boss a portal leads back to the hub.
8. **The lectern goes** (its depth pick has no meaning on this map).

**Moving and splitting**

9. **Free split** for every player, local ones too.
10. **Fight doors seal one way:** teammates come in; nobody inside leaves, downed or standing; no enemy leaves.
11. **Shots never cross a doorway.** **Movement spells** (dash, teleport, swap, portal, possess) **do**, through doorways only (never through a wall), and **never out of a sealed fight** (a swap across a seal fizzles).
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
22. **Secret rooms:** 1–2 a biome, each behind a cracked wall that opens to **one element, rolled for that room** (the crack's tint hints which), to reward varied builds.
23. **Challenge rooms:** 0–1 a biome, a **gather door** (every standing wizard at it), sealed, an elite fight, a bigger reward.
24. **Elites:** an enemy type with more health, one extra card from the biome's list in its staff and an outline; about 1 fight room in 4 from a set depth on; a challenge room's enemies are all elite.
25. **The boss gate** is a gather door counting standing wizards; when it opens **everyone comes**, downed or far away, onto the arena's spawns. After the boss: each player's boss reward, coins to every wallet, and a gather-door portal onward.
26. **Hooks, not content:** the map-touching effects (more choices, map reveal, secret sense, prices, more special rooms, fountain size, starting coins) are **run stats** that relics and rule changes add to; the relics themselves come with M3's relic work.

**Camera, HUD, sound and look**

27. **A Voronoi split for 1–4 local players:** one view while everyone fits; past that the screen divides along the bisector between the wizards (cells of up to four), each view leaning toward the others, and merges without a jump (only the divider grows in, over frames). Online each machine splits for its own seats only.
28. **HUD:** the panels stay in the screen's corners. Edge markers only for a teammate in none of this machine's views. The Y map draws inside its player's view.
29. **Sound only from rooms this machine's wizards are in;** music follows the most intense of them.
30. **The look:** an open doorway's shimmer (flares where a shot stops); a seal's bars drop in over frames with a rune; a gather door has a lamp for each standing wizard, lit in their hat colour as they arrive; a key door's padlock turns and falls; a secret crack's tint brightens near its element and breaks in stages. Unvisited rooms in a view are dark by a whole-pixel dither, lightening in stages. Each kind may bring its air, light and music layer.
31. **Performance:** the camera spike (CB1) sets the frame-time targets; nothing is promised before.

## The model

- **The biome map** (`gameplay/run`, replacing `RunMap`'s rows): rooms, each a template, a place, a mirroring and a kind; links, each two sockets; depth by doors. Pure and seeded: the same seed and content give the same map on every machine. A snapshot never saves the layout (it is made again from the seed); it saves what happened.
- **Room state** (each room, hashed): entered, fight started, sealed, cleared, its enemies (by actor), what lies on its floor, its shop's shelf, its fountain's pool, its seen flag (the party's map). An enemy belongs to the room it stands in.
- **A room is awake** while anything acts in it: a wizard, a live enemy that is not at rest, a shot, a growing effect. It wakes when anything enters and sleeps when nothing acts. Only game state decides it, so every machine agrees; a sleeping room's bodies hash at rest.
- **Doorways** are a wall to shots and to enemies, an opening to wizards and to movement spells; a seal makes a doorway one-way for wizards and closed to everything from inside. All in whole pixels, in the simulation.
- **Run stats** (core): named numbers (`reward_choices`, `price_scale`, `map_reveal`, `secret_sense`, `fountain_pool`, `start_coins`, each kind's limit, ...) worked out a player at a time as base, then the run's rule changes, then that player's relics (each a data list of stat changes). The systems read a stat by name and never know where it came from; a new stat is a row, a new relic a file.
- **The view** (Feel): the Voronoi camera, the dark of unvisited rooms, the doorway and door looks, the Y map. Drawing only; nothing in the simulation reads it.

## Fit with the design

- **Nobody waits** (pillar 2): anyone goes anywhere; menus stay per player; the map is held, not a menu. The only shared choices are made by walking (rule 5): the boss gate, the challenge door and the portal onward.
- **Rewards rolled per player** (rule 3), carried over when missed (rule 4); coins never raced for (shared income).
- **One game, the same everywhere:** the map, waking and sleeping, doorways and seals are state on the tick; the camera, the dark, sound and looks are view only. No machine ever simulates differently because of what it draws.
- **Smooth:** every door and room look changes by at least 3 frames in whole pixels; the split merges without a jump.
- **Short loops:** 8–12 rooms a biome keeps a biome to minutes; one biome for now.
- **Conflict to settle:** DESIGN.md's "every reward offers 3 options with trade-offs" (decision 17). The owner changes that line.

## Steps

1. **CB1 the camera spike.** Draw 2, 3 and 4 Voronoi views (a viewport a cell, each masked to its cell) over the busiest stress fight, on Linux and the web build; measure frame time with shots, motes, light and cover. Report numbers and the fallbacks they need (fewer motes or lights a view). The owner sets the targets from it (decision 31). Throwaway code, kept out of the game.
2. **CB2 the biome world.** Door sockets on templates (a class in `core/`, an editor preview of the mirrored layouts in `tools/`), doorways that stop shots and pass wizards, 2–3 crypt rooms joined in a hand-made test map, walked through. The current run stays the default. Tests: shots stop at a doorway, a wizard walks through, mirrored sockets land on walls.
3. **CB3 room life.** Room state, waking and sleeping, fights that start past a doorway and seal one way, enemies kept in their room, movement spells across doorways (never out of a seal), portals and possession across rooms (decision 12), crawling while downed. Tests: determinism and snapshots with a split party (the content-determinism test gains a split party), a room woken by a shot, a swap across a seal fizzling.
4. **CB4 the generator and the switch.** The socket generator with corridors, depth, kind rules, map styles, once-a-biome templates, mirroring with walls built at layout. The crypt run moves to it; the row map, the old exits (`room_exit`, `ExitRules`) and the lectern are removed in the same PR, so nothing is ever half switched. Tests: every map style makes valid maps over many seeds, the boss is deepest, at least 4 fights on its way, the validator names a run whose content makes no map.
5. **CB5 the Voronoi camera** for real, with the HUD's corner panels and the edge-marker rule (decision 28). Tests: 1–4 seats in any rooms, cells always cover the screen, a merge has no jump.
6. **CB6 the map:** seen rooms as state, door kind symbols, the held Y map in a player's view.
7. **CB7 gather doors:** the boss gate (everyone comes) and the challenge door; the portal onward.
8. **CB8 run stats and the economy:** the run stats; rewards as pick 1 of 2 by `reward_choices`; coins (shared income, own wallets); keys.
9. **CB9 special rooms:** reward, shop (first buyer), fountain (shared pool), treasure, secret walls (an element each), challenge, elites. Each a `room_kinds` folder and its templates.
10. **CB10 sound and the look:** sound from this machine's rooms only, the door and doorway looks, the dark of unvisited rooms, each kind's air.
11. **CB11 templates:** the crypt's set grown from the first small one (about 6 fights, 3 corridors, the start room, the boss and one of each special) toward 12–16 fights, in later PRs.

Every template is read by tests in all four mirrorings (sockets on walls, every socket reaching every other, spawns clear, unused sockets closed) and played once in a generated biome; a screenshot of each template and each map style.

## Questions for the owner

1. Approve this plan as written?
2. CB1 is a spike: keep its measuring scene as a lasting stress test, or throw it away once the numbers are in?

## Not in this plan

- Chaining biomes into a run, and biomes past the crypt (decision 7).
- The relics and unlocks themselves (decision 26: only their hooks).
- Run themes (a flooded or burning crypt).
- A corner minimap (the Y map replaces it).
