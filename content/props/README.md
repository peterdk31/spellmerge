# Props

## Purpose

Things in the world that stand, block, take hits, react by casting spell cards and give off motes: an exploding barrel's fuse and blast, a crate's rubble, a fire pit's embers ([docs/milestones/props.md](../../docs/milestones/props.md), phase W). A prop is an **actor with no controller** (owner, 2026-11-10): health, the hurt shape, statuses, possession and casting are the actor kit's, so nothing in Combat, Spells or possession needs to know it is a prop. If it acts on its own it is an enemy with a statue's look; if it only stands and reacts, it is a prop.

**Placing a prop in a room** (W8a/W8b/W8c): add a `PropStandIn` (tools/prop_stand_in.gd, a `RoomPlacement`) anywhere in the room's scene, pick the prop in the Inspector and move it; the editor draws the prop as the game will (any state, with its hurt shape, ground and area outlined), and the game stands the real prop there. Nothing to add to the prop's folder. **A prop is self-contained** (owner, 2026-11-11): what it means to the game comes with it, never with a room: its `role` (empty for most; `run_start`, `party_altar`: the hub's rules read them, `HubRules`) and where it is stood on (`area_size`, `area_offset`, apart from the ground that blocks). **The hub's prop yard** (W8, the hub scene's `RoomZone` `prop_yard`) stands every prop here with no `role` (most), in rows by id, each fresh again 10 s after it is lit, broken or gone: a new prop appears there with no edit anywhere else. The hub's own teleporter stone and altar (`hub_stone`, `hub_altar`) are props too, of the roles `run_start` and `party_altar`, each stood on where its 96×96 `area` is: the hub's rules count a wizard on them there and light the stone by asking it (`prop_state_requested`) to enter `lit` or `unlit`, the states a `run_start` has (`tests/content/props/test_prop_data.gd` holds every role to what its rules need).

Built in W6 (states and their triggers; the component and rows were named `Reactions` and `PropReaction` until the owner renamed them, 2026-11-11: Combat has reactions of its own). The look (art layers, mote sources, a light, a cue) is W7's, the hub's prop yard W8's (with the hub's stone and altar) and the first five props W9c's: the **exploding barrel** (`exploding_barrel`, the example below), the **crate** (`crate`), the **fire pit** (`fire_pit`), the **arc lodestone** (`arc_lodestone`) and the **burial jar** (`burial_jar`).

## Contract

- **One folder each:** `content/props/<id>/` with `<id>.tres` (a `PropBase`, core/base/prop_base.gd), `<id>_states.tres` (its `PropStates`, below; a prop may name another's instead, a big exploding barrel the small one's), its art, `assets.json` and its own test `test_<id>.gd`. Deleting a prop is deleting its folder. The registry finds it under `props` by `id`.
- **One shared body:** `base/prop.tscn`, an actor of the world's team (`Actors.TEAM_WORLD`: every team's shots hit it, its shots hit every team) with `Health`, `Hurtbox`, `Footprint`, `Caster`, `PropStateTriggers`, a `Sprite` and a `PropLook`, and no controller and no Mover, so it is still (never stepped) and never moves. Every prop's `scene` is it; `PropBody.make(data)` (gameplay/actor) fills it from the data. **No `.gd` and no scene per prop:** a new prop is data and art.
- **`PropBase`:** `id`, `display_name`, `scene`, `max_health`, `invincible` (the hub's: hits land and show, health stays), `role` (what it is to the game's rules; empty: nothing, and it stands in the hub's prop yard), `area_size`/`area_offset` (where standing on it counts), the hurt shape (`radius`, or a box `size`, round `offset` from the feet), the ground (`footprint_radius` or `footprint_size`, `footprint_offset`; none: its hurt box's base, else the kit's circle), `staffs` (1–4 `StaffCards`, as an enemy's: what its triggers and a possessor cast; a staff's `wind_up` is a fuse, its `wind_cue` the fuse's look) and `states` (a `PropStates` file).
- **Its looks (W7):** `PropBase.looks`, one `PropStateLook` a state (`state_id`; an empty one is the look of every state with none of its own; every state needs one). On the prop, not its states, so props sharing a states file look as each wants. A look is:
  - `layers` (`PropLayer`, drawn in order): a picture (`texture`, its `frames` side by side played `fps` a second), its bottom middle on the feet moved by `offset` (whole pixels), `drawn` among the bodies (`AMONG_BODIES`, the default), `OVER_BODIES` (a tall prop's top, which hides a wizard behind it), `ON_FLOOR` (a slab walked on, under every body and the floor's marks: the hub's stone) or `HIDDEN` (a mask only), and the `motes` it gives off (`MoteSource`: a point, a line, a box, an oval's rim from the feet, or a mask of this layer's lit pixels; a mask may `stand`, a twinkling mote on every lit pixel; colours by palette name, `colours = [&"fire"]`; every field and its default: content/motes/README.md, "How to make something in the world give off motes"). **The first layer is the body:** the shared scene's `Sprite`, which a hit flashes, so it is neither hidden nor over the bodies (it may lie on the floor). A mask is read once, so it is a still layer of its own (never the body's, nor one of several frames).
  - a light (`light_reach` above 0: spell light's, as a torch's), from `light_at`, its strength and flicker, in `light_tint` or its `light_layer`'s art colour.
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
  | `refused` | a trigger's cast of its staff N did not go: the staff busy (winding up, or in the delay after its last cast) or, `dry`, its mana paying none of its casts | `staff`, `dry` (only when dry) |

- **The rule:** on a moment every trigger of the current state that matches fires, in order; the first of them that names a `then` sets the next state, once, after they all fired. Triggers belong to states, so "only once" is a state change, never a flag. Leaving a state ends the wind-ups it cast (a lit barrel shot apart blows now, and its fuse no more). **Death doesn't free a prop:** its `death` triggers run and a possession of it ends; it is freed only by a `gone` state, and without a death row it stands with its health empty.
- **A prop's casts pay from its staffs' pools, which never refill** (a still body is never stepped): the first cast of every staff a trigger casts must fit in a full pool (`tests/content/props/test_prop_data.gd`); a staff cast more than once over a prop's life needs a pool for each.
- **A trigger's cast is the prop's own:** never a press (it sets off no `on recast`), its wind-up outlasts a possession (a lit barrel possessed still blows; a possessor's own presses end with it), and a `cast` trigger never casts the staff whose cast it hears while that cast leaves.
- `PropBase.problems()` must be empty: no scene or state, a state named twice, a staff it does not hold, a state, element, status or reaction nobody knows, a number out of range, `entered` triggers that go round for ever.
- Original names and art only.

## The exploding barrel, written out

```
staffs   1: fire · blast · pulse, wind-up 1.0 s (the fuse)    2: fire · blast · pulse, no wind-up
idle     element_hit fire     → then fusing
         death                → cast 2, then broken          (shot apart: blows at once)
         cast 1, cast 2       → then broken                  (possessed: 1 lights the fuse the long way, 2 blows)
fusing   entered              → cast 1                       (the fuse burns, then it blows)
         death                → cast 2, then broken          (shot while lit: blows now)
         cast 1, cast 2       → then broken
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
