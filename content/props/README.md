# Props

## Purpose

Things in the world that stand, block, take hits, react by casting spell cards and give off motes: an exploding barrel's fuse and blast, a crate's rubble, a fire pit's embers ([docs/milestones/props.md](../../docs/milestones/props.md), phase W). A prop is an **actor with no controller** (owner, 2026-11-10): health, the hurt shape, statuses, possession and casting are the actor kit's, so nothing in Combat, Spells or possession needs to know it is a prop. If it acts on its own it is an enemy with a statue's look; if it only stands and reacts, it is a prop.

**Placing a prop in a room** (W8a/W8b/W8c): add a `PropStandIn` (tools/prop_stand_in.gd, a `RoomPlacement`) anywhere in the room's scene, pick the prop in the Inspector and move it; the editor draws the prop as the game will (any state, with its hurt shape, ground and area outlined), and the game stands the real prop there. Nothing to add to the prop's folder. **A prop is self-contained** (owner, 2026-11-11): what it means to the game comes with it, never with a room: its `role` (empty for most; `run_start`, `party_altar`: the hub's rules read them, `HubRules`; `room_exit`: a run's room's exits, `ExitRules`, run generation RG4) and where it is stood on (`area_size`, `area_offset`, apart from the ground that blocks). **The hub's prop yard** (W8, the hub scene's `RoomZone` `prop_yard`) stands every prop here with no `role` (most), in rows by id, each fresh again once it has been out of its first state (lit, broken) or gone for 10 s on end: a new prop appears there with no edit anywhere else. The hub's own teleporter stone and altar (`hub_stone`, `hub_altar`) are props too, of the roles `run_start` and `party_altar`, each stood on where its 96×96 `area` is: the hub's rules count a wizard on them there and light the stone by asking it (`prop_state_requested`) to enter `lit` or `unlit`, the states a `run_start` has (`tests/content/props/test_prop_data.gd` holds every role to what its rules need). A run's room leads on by its **exits** (`room_exit`, run generation RG4): floor plates stood on where their 48×48 `area` is, `dark` until the room is cleared, then the exits' rules (`ExitRules`) light one a way on (`lit`) and take the party on when every standing wizard stands in a lit one.

Built in W6 (states and their triggers; the component and rows were named `Reactions` and `PropReaction` until the owner renamed them, 2026-11-11: Combat has reactions of its own). The look (art layers, mote sources, a light, a cue) is W7's, the hub's prop yard W8's (with the hub's stone and altar) and the first five props W9c's: the **exploding barrel** (`exploding_barrel`, the example below), the **crate** (`crate`), the **fire pit** (`fire_pit`), the **arc lodestone** (`arc_lodestone`) and the **burial jar** (`burial_jar`). The **fountain** (`fountain`, below) bursts water on a timer. The boss plan's OB5 added the **cracked pillar** (`cracked_pillar`: cover that cracks at half health and falls to rubble) and the **dust heap** (`dust_heap`, below) with the `touched` trigger. The crypt rework's CR-G (docs/milestones/crypt-rework.md) added the **crypt pillar** and the **crypt gate** (below), the first props whose every change of state plays its frames.

## Contract

- **One folder each:** `content/props/<id>/` with `<id>.tres` (a `PropBase`, core/base/prop_base.gd), `<id>_states.tres` (its `PropStates`, below; a prop may name another's instead, a big exploding barrel the small one's), its art, `assets.json` and its own test `test_<id>.gd`. Deleting a prop is deleting its folder. The registry finds it under `props` by `id`.
- **One shared body:** `base/prop.tscn`, an actor of the world's team (`Actors.TEAM_WORLD`: every team's shots hit it, its shots hit every team) with `Health`, `Hurtbox`, `Footprint`, `Caster`, `PropStateTriggers`, a `Sprite` and a `PropLook`, and no controller and no Mover, so it is still (never stepped) and never moves. Every prop's `scene` is it; `PropBody.make(data)` (gameplay/actor) fills it from the data. **No `.gd` and no scene per prop:** a new prop is data and art.
- **`PropBase`:** `id`, `display_name`, `scene`, `max_health`, `invincible` (the hub's: hits land and show, health stays), `role` (what it is to the game's rules; empty: nothing, and it stands in the hub's prop yard; `run_start` the hub's teleporter stone, `party_altar` its multiplayer altar, `start_lectern` its lectern, run generation RG7, `room_exit` a room's exit), `area_size`/`area_offset` (where standing on it counts), the hurt shape (`radius`, or a box `size`, round `offset` from the feet), the ground (`footprint_radius` or `footprint_size`, `footprint_offset`; none: its hurt box's base, else the kit's circle), `blocks_light` (docs/milestones/atmosphere.md, C: it stops spell light by its ground while that blocks, its hurt box the shaft drawn over it, Feel's `light_blockers.gd`; view only; the crypt's two pillars, false for every other prop, low enough to see over), `staffs` (1–4 `StaffCards`, as an enemy's: what its triggers and a possessor cast; a staff's `wind_up` is a fuse, its `wind_cue` the fuse's look), `stats` (an `ActorStats`, boss plan OB7: the power of its casts, its mass, its spells' size, its resists; null: the defaults, which change nothing; the body's `Stats` copies it) and `states` (a `PropStates` file).
- **Its looks (W7):** `PropBase.looks`, one `PropStateLook` a state (`state_id`; an empty one is the look of every state with none of its own; every state needs one). On the prop, not its states, so props sharing a states file look as each wants. A look is:
  - `layers` (`PropLayer`, drawn in order): a picture (`texture`, its `frames` side by side played `fps` a second, from the first as its state is entered and round again from `loop_from`: 0 loops them all; a later frame plays the frames before it once, the change from the last look (docs/STYLE.md "Smooth"), and loops the rest; the last frame plays the strip once and holds it, a crumble ending in rubble. A look only shown, as the prop is set up or a snapshot gives its state back, starts where it rests, with no change played), its bottom middle on the feet moved by `offset` (whole pixels), `drawn` among the bodies (`AMONG_BODIES`, the default), `OVER_BODIES` (a tall prop's top, which hides a wizard behind it), `ON_FLOOR` (a slab walked on, under every body and the floor's marks: the hub's stone) or `HIDDEN` (a mask only), and the `motes` it gives off (`MoteSource`: a point, a line, a box, an oval's rim from the feet, or a mask of this layer's lit pixels; a mask may `stand`, a twinkling mote on every lit pixel; colours by palette name, `colours = [&"fire"]`; every field and its default: content/motes/README.md, "How to make something in the world give off motes"). **The first layer is the body:** the shared scene's `Sprite`, which a hit flashes, so it is neither hidden nor over the bodies (it may lie on the floor). A mask is read once, so it is a still layer of its own (never the body's, nor one of several frames).
  - a light (`light_reach` above 0: spell light's, as a torch's), from `light_at`, its strength and flicker, in `light_tint` or its `light_layer`'s art colour, shining from `light_after` seconds after its state is entered until `light_until` (0: as long as the look shows), so it comes and goes with the art; a look only shown is past its start.
  - `cue`: played where it stands as the state is entered (not the one it starts in).
- **Art from a grid:** draw each picture as a grid of characters in `<name>.grid.json` beside it and write its SVGs with `tools/pixel_grid.py` (`<name>.svg`, and `<name>_motes.svg` when the grid marks mote points with `*`: a hidden layer whose mask gives off the motes). Commit the grid and both SVGs; `tools/test_pixel_grid.py` fails when an SVG differs from its grid.
- **`PropStates`:** `list`, its `PropState`s, the first the one it starts in. A file of its own, so props can share one, and the one thing the `PropStateTriggers` component reads: any actor's data could name one.
- **`PropState`:** `state_id`, `triggers` (in order), `blocks` (its footprint blocks the bodies that walk), `hittable` (its hurt shape can be hit), `gone` (entering it frees the prop).
- **`PropTrigger`:** `when` and its numbers, then what it does: `cast` (a staff by number, 1–4; 0 none) and `then` (a state id; empty stays).

  | `when` | Fires when | Numbers |
  |---|---|---|
  | `element_hit` | a hit of that element (its first) lands on it (an invincible prop's too) | `element` (empty: a plain hit), `at_least` damage (0: any) |
  | `status` | a status is put on it | `status` |
  | `reaction` | one of Combat's reactions between statuses happens on it | `reaction` |
  | `health_below` | a hit takes its health below a share of its most (once: the hit that crosses it) | `share` |
  | `death` | its health runs out | |
  | `entered` | its state was just entered (not the one it starts in) | |
  | `cast` | its staff N's cast leaves (a trigger's or a possessor's, after any wind-up) | `staff` |
  | `refused` | a trigger's cast of its staff N did not go: the staff busy (winding up, or in the delay after its last cast), nothing to cast, or, `dry`, its mana paying none of its casts (told only of a free staff); while it runs, its rows' casts of that staff do nothing | `staff`, `dry` (only when dry) |
| `timer` | every `seconds` it stays in its state, on the simulation's clock, from when the state was entered (or from the start, in the state it starts in). A prop with a timer row in any state is **stepped** (it is not still): its clock runs, slowed by a chill and held by a freeze as a wind-up is, and its pools refill as any staff's. Leaving and entering a state starts its clock again | `seconds` |
| `touched` | a body that walks (a Mover; not down) overlaps its area (`area_size`, `area_offset`): the body's circle against the walls at its feet, where its move left it, every tick it does (so a prop that hears it once goes to a state without the row). A prop that blocks needs an area a little past its ground, or a body stopped at its edge never reaches it | |

- **The rule:** on a moment every trigger of the current state that matches fires, in order; the first of them that names a `then` sets the next state, once, after they all fired. Triggers belong to states, so "only once" is a state change, never a flag. Leaving a state ends the wind-ups it cast (a lit barrel shot apart blows now, and its fuse no more). **Death doesn't free a prop:** its `death` triggers run and a possession of it ends; it is freed only by a `gone` state, and without a death row it stands with its health empty.
- **A prop's casts pay from its staffs' pools, which never refill** (a still body is never stepped), but for a prop with a `timer` row, which is stepped and refills as a staff does (the fountain): the first cast of every staff a trigger casts must fit in a full pool (`tests/content/props/test_prop_data.gd`); a staff cast more than once over a prop's life needs a pool for each.
- **A trigger's cast is the prop's own:** never a press (it sets off no `on recast`), its wind-up outlasts a possession (a lit barrel possessed still blows; a possessor's own presses end with it), and a `cast` trigger never casts the staff whose cast it hears while that cast leaves.
- `PropBase.problems()` must be empty: no scene or state, a state named twice, a staff it does not hold, a state, element, status or reaction nobody knows, a number out of range, `entered` triggers that go round for ever, a `touched` trigger with no area, a state whose `touched` rows cast and none leaves it (it would cast every tick).
- Original names and art only.

## The exploding barrel, written out

```
staffs   1: fire · blast · pulse, wind-up 1.0 s (the fuse)    2: fire · blast · pulse, no wind-up
idle     status burn          → then fusing                  (a burn lights it: a fire hit, burning grass; a soaked barrel takes none)
         death                → cast 2, then broken          (shot apart: blows at once)
         cast 1, cast 2       → then broken                  (possessed: 1 lights the fuse the long way, 2 blows)
fusing   entered              → cast 1                       (the fuse burns, then it blows)
         death                → cast 2, then broken          (shot while lit: blows now)
         cast 1, cast 2       → then broken
         element_hit water    → then idle                    (doused: its fuse goes out, and it can be lit again)
broken   blocks off, hittable off (rubble)
```

As data: `exploding_barrel/exploding_barrel.tres` and its `exploding_barrel_states.tres` (its paths: `tests/gameplay/actor/test_prop_state_triggers.gd`; its own test `exploding_barrel/test_exploding_barrel.gd`). Its fuse's `wind_cue` is `wind_area` (a ring closing in for the fuse's second); its sparks are its `fusing` look's.

## A prop that runs dry, written out

A prop's pool never refills, so a prop that casts again and again runs dry; a `refused` row says what then. The arc lodestone (`arc_lodestone`, a staff of `lightning · pulse` that winds up 0.5 s, a pool of 60 at 3 a zap):

```
idle      element_hit lightning  → then charged
charged   entered                → cast 1                (the charge, then the zap)
          cast 1                 → then idle
          refused 1, dry         → then spent            (its pool pays no more: dark for good)
          refused 1              → then idle             (charged while still in the delay after a zap)
spent     (no triggers)
```

## A prop on a timer, written out

The fountain (`fountain`): invincible, a staff of `water · nova · spray` that winds up 0.6 s (its `wind_cue` `wind_area`: the closing ring is the telegraph, with its `welling` look, the water bulging out of its bowl) and a staff of `water · pulse` with none; both refill (a stepped prop), and its stats cast at a quarter of their power, so its water soaks and shoves far more than it hurts.

```
still     timer 2.4 s         → cast 1, then welling     (the burst winds up)
          refused 1           → then still              (should it be refused: wait again)
welling   cast 1              → cast 2, then still      (eight jets of water, and a ring that wets the floor)
          timer 3 s           → then still              (never stuck, should its burst not go)
```

A burst every 3 s: what its water hits is soaked and a burn on it put out (Combat's soak), a lit barrel by it doused, the grass round it wet (`content/cover`). It has no role, so it stands in the hub's prop yard.

## A prop walked into, written out

The dust heap (`dust_heap`, boss plan OB5): invincible (only its triggers change it), a staff of `fire · blast · pulse` with no wind-up, its ground 24×8 and its area 36×20 round it, so a body that walks into it touches it before its ground stops it.

```
heap        element_hit fire  → cast 1, then burnt      (blown up)
            status burn       → cast 1, then burnt      (a burning patch under it)
            touched           → then scattered          (walked or swept into)
scattered   element_hit fire  → cast 1, then burnt      (blocks off: dust on the floor, still hit by fire)
            status burn       → cast 1, then burnt
burnt       blocks off, hittable off (a scorch mark)
```

The scattered dust stays hittable, so fire finds it, and so it still catches a shot that crosses it (a hit that does nothing: it is invincible); a hurt shape that hears hits without stopping shots would be engine work of its own. Its blast hurts everything near (a prop's shots hit every team), the heaps beside it too, which blow in turn.

**The crypt pillar** (`crypt_pillar/`, crypt rework CR-G): the crypt's cover, a round fluted column of 60 health on a 26×12 ground and a 22×52 hurt box, casting nothing. It blocks spell light (`blocks_light`), and as it comes down into rubble its shadow eases away with it. Its ground stops walking and its hurt box catches the shots that hit it, but, unlike a pillar wall, sight, rays and piercing shots pass it (gameplay/actor/footprint.gd), and the fight wears it down: a room that swaps its pillar walls for it plays differently, which that room's step weighs. The fight breaks it in stages, each a strip played once from the look the stage before rests on (`loop_from` its last frame; `test_crypt_pillar.gd` holds every hand-over pixel for pixel):

```
intact    death              → then rubble
          health_below 0.34  → then split        (a heavy hit goes as far as it reaches)
          health_below 0.67  → then cracked      (a crack runs down, a chip of the capital falls: 6 frames)
cracked   death → then rubble;  health_below 0.34 → then split
split     death              → then rubble       (half the capital breaks off and falls: 7 frames)
rubble    blocks off, hittable off               (it comes down drum by drum into a heap: 9 frames)
```

A hit past two stages at once plays only the last one's strip (from the stage it skipped). A room places it as a `PropStandIn`, as any prop.

**The crypt gate** (`crypt_gate/`, crypt rework CR-G): the crypt's room exit (`room_exit`, as the plate is): an arch of stone players walk into, drawn among the bodies, so a wizard in its mouth stands behind its arch, in its light. Nobody bumps into it and no hit lands on it, so a room stands it against its north edge, walked into from the front (its posts are not solid). It is stood on where its area is: as wide as its mouth (24 px), from just in front of its threshold up to the arch's top, so the exits' sign stands over the gate. Dark, its arch is sealed; lit (`ExitRules.LIT`), its runes light from the bottom and a veil of Void light rises from the threshold to fill the arch (6 frames), then its motes rise round in it (`loop_from` 5); dark again, the light drains down (6 frames). Its glimmers start and its light shines as the veil is full, and its light goes as the veil is mostly drained (its looks' `light_after`, `light_until`).

**The lectern** (`start_lectern/`, run generation RG7): a 32×32 stone stand with an open book on a wooden desk, invincible, blocking and never hit, its area (56×44) mostly in front of it, where a wizard walking up to it stands; at it a seat's A opens the menu of depths the stone's run may start at (gameplay/flow, hud). No room's scene names it: the hub has a zone named for its role (`start_lectern`), where the hub stands the registry's prop of that role (`RoomContents.stand_in_role_zones`), so deleting this folder leaves the hub whole and the run starting in its first room.

## Allowed files

`.tres`, `.tscn` (saved as text), sprites (`.png` or `.svg`) and their `.grid.json` grids, `assets.json`, the prop's `test_<id>.gd`, plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs; load only with literal `res://` paths.

## Steps

1. Make `content/props/<id>/` and its `<id>.tres` (a `PropBase` with `scene` the shared `base/prop.tscn`); write its states and triggers in `<id>_states.tres` (start from the exploding barrel above) and name it as its `states`.
2. Give it staffs of player cards for what it casts.
3. Draw its art as grids and write the SVGs (`tools/pixel_grid.py`), give each state a look in `looks` (its layers, motes, light, cue), list the art in an `assets.json` in its folder, and commit the `.uid` files Godot creates.
4. Write `test_<id>.gd` for its paths (as `tests/gameplay/actor/test_prop_state_triggers.gd` does the exploding barrel's), run the checks below and open a PR.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

Besides the general review:

- Does every path end where it should (a barrel blows once, whichever way it is set off)?
- Can each cast be paid from a full pool?
- Is it a prop (it only stands and reacts), or an enemy in disguise?
