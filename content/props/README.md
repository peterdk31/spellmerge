# Props

## Purpose

Things in the world that stand, block, take hits, react by casting spell cards and give off motes ([docs/milestones/props.md](../../docs/milestones/props.md)). A prop is an **actor with no controller**: health, hurt shape, statuses, possession and casting are the actor kit's. If it acts on its own it is an enemy; if it only stands and reacts, it is a prop.

- **Placing one in a room:** add a `PropStandIn` (tools/prop_stand_in.gd, a `RoomPlacement`) to the room's scene and pick the prop in the Inspector.
- **A prop is self-contained:** what it means to the game comes with it, never with a room: its `role` (empty for most; `run_start`, `party_altar`, read by `HubRules`) and its `area_size` / `area_offset`.
- **The hub's prop yard** (`RoomZone` `prop_yard`) stands every prop with no `role`, by id; a new prop appears there with no other edit.

## Contract

- **One folder each:** `content/props/<id>/` with `<id>.tres` (a `PropBase`, core/base/prop_base.gd), `<id>_states.tres` (a `PropStates`; may name another prop's instead), its art, `assets.json` and `test_<id>.gd`. Deleting a prop is deleting its folder. Registry folder `props`, by `id`.
- **One shared body:** `base/prop.tscn` (team `Actors.TEAM_WORLD`; `Health`, `Hurtbox`, `Footprint`, `Caster`, `PropStateTriggers`, `Sprite`, `PropLook`; no controller, no Mover), filled by `PropBody.make(data)`. **No `.gd` and no scene per prop:** a new prop is data and art.
- **`PropBase`:** `id`, `display_name`, `scene`, `max_health`, `invincible`, `role`, `area_size`/`area_offset`, hurt shape (`radius` or `size`, `offset`), ground (`footprint_*`), `blocks_light` (view only), `staffs` (1–4 `StaffCards`; `wind_up` is a fuse), `stats`, `states`, `looks`.
- **Looks:** `PropBase.looks`, one `PropStateLook` per state (`state_id`; empty: every state without its own; every state needs one). A look has:
  - `layers` (`PropLayer`, in order): `texture`, `frames`, `fps`, `loop_from` (0 loops all; a later frame plays the change once then loops; the last frame plays once and holds), `offset` (whole pixels), `drawn` (`AMONG_BODIES`, `OVER_BODIES`, `ON_FLOOR`, `HIDDEN`), `motes` (`MoteSource`; content/motes/README.md). A look only shown (set up, snapshot restore) starts at rest, with no change played.
  - **The first layer is the body** (the scene's `Sprite`, flashed by hits): never `HIDDEN` nor `OVER_BODIES`. A mote mask is a still layer of its own, never the body's nor a multi-frame one.
  - a light (`light_reach` above 0, `light_*`).
  - `cue`: played as the state is entered (not the start state).
- **Changes of state play their frames** (docs/STYLE.md, "Smooth").
- **Art at 2x detail, from parts:** a prop's looks are drawn by `tools/prop_art.py` (on `tools/sprite_rules.py`: each prop its own shapes and light rules) as `<name>@2x.svg` (a strip: `<name>@2x.png`), 64 art pixels a 32-unit cell, drawn at half size (`ArtDetail`; `PropLayer.frame_size` is in world units, `frame_px` in the picture's pixels). Change a prop's art in its rules and run the tool; `tools/test_prop_art.py` fails when a file differs. A mote mask (`<name>_motes.svg`) stays at 1x, a lit pixel a world pixel, written by the same tool from the prop's glowing points. The hub's stone and altar are drawn the same way by `tools/room_art.py` with the room's set pieces; the stone's lit runes give off their glimmers from a hidden 1x mask (`stone_lit_motes.svg`), the same carving drawn at 1x.
- **`PropStates`:** `list` of `PropState`, the first the start state. **`PropState`:** `state_id`, `triggers` (in order), `blocks`, `hittable`, `gone` (entering it frees the prop).
- **`PropTrigger`:** `when` and its numbers, then `cast` (staff 1–4; 0 none) and `then` (a state id; empty stays).

| `when` | Fires when | Numbers |
|---|---|---|
| `element_hit` | a hit of that element lands on it (an invincible prop's too) | `element` (empty: plain), `at_least` (0: any) |
| `status` | a status is put on it | `status` |
| `reaction` | a Combat reaction happens on it | `reaction` |
| `health_below` | a hit takes its health below a share of its most (once) | `share` |
| `death` | its health runs out | |
| `entered` | its state was just entered (not the start state) | |
| `cast` | its staff N's cast leaves | `staff` |
| `refused` | a trigger's cast of staff N did not go (busy, nothing to cast, or `dry`: no mana) | `staff`, `dry` |
| `timer` | every `seconds` in its state, on the sim clock (makes the prop **stepped**; chill slows, freeze holds; pools refill) | `seconds` |
| `touched` | a walking body (a Mover, not down) overlaps its area, every tick | |

- **The rule:** every matching trigger of the current state fires, in order; the first that names a `then` sets the next state, once, after all fired. "Only once" is a state change, never a flag. Leaving a state ends the wind-ups it cast.
- **Death doesn't free a prop:** `death` triggers run and possession ends; only a `gone` state frees it.
- **Pools never refill** on a still prop (only a `timer` prop is stepped): the first cast of every staff a trigger casts must fit in a full pool; a staff cast repeatedly needs a pool for each, or a `refused ... dry` row.
- **A trigger's cast is the prop's own:** never a press (no `on recast`); its wind-up outlasts a possession; a `cast` trigger never casts the staff whose cast it hears.
- A blocking prop with `touched` needs an area a little past its ground.
- `PropBase.problems()` must be empty (unknown scene/state/staff/element/status/reaction, duplicates, numbers out of range, `entered` loops, `touched` with no area, a `touched` state that casts and never leaves).
- Original names and art only.

## The exploding barrel, written out

```
staffs   1: fire · blast · pulse, wind-up 1.0 s (the fuse)    2: fire · blast · pulse, no wind-up
idle     status burn          → then fusing
         death                → cast 2, then broken
         cast 1, cast 2       → then broken
fusing   entered              → cast 1
         death                → cast 2, then broken
         cast 1, cast 2       → then broken
         element_hit water    → then idle
broken   blocks off, hittable off (rubble)
```

Other worked props to copy: `arc_lodestone` (runs dry: `refused 1, dry`), `fountain` (`timer`), `dust_heap` (`touched`), `crypt_pillar` (staged crumble by `health_below`, strips with `loop_from`), `cracked_pillar`, `crate`, `fire_pit`, `burial_jar`, `hub_stone`, `hub_altar`.

## Allowed files

`.tres`, `.tscn` (text), sprites (`.png` or `.svg`) and, for 1x art, their `.grid.json` grids, `assets.json`, the prop's `test_<id>.gd`, plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB otherwise. Typed GDScript only; no banned APIs; load only with literal `res://` paths.

## Steps

1. Make `content/props/<id>/`, its `<id>.tres` (`scene` = `base/prop.tscn`) and `<id>_states.tres` (start from the barrel).
2. Give it staffs of player cards for what it casts.
3. Draw its looks in `tools/prop_art.py` (copy the crate), run it, give each state a look, list the art in `assets.json`, commit the `.uid` files.
4. Write `test_<id>.gd` for its paths; run the checks; open a PR.

## Tests

`content/props/<id>/test_<id>.gd`, `tests/content/props/test_prop_data.gd` (roles, pools), `tests/gameplay/actor/test_prop_state_triggers.gd`, `tools/test_prop_art.py`, `tools/test_pixel_grid.py`.

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

- Does every path end where it should (a barrel blows once, whichever way it is set off)?
- Can each cast be paid from a full pool?
- Is it a prop, or an enemy in disguise?

History and reasons: [docs/history/content-props-README.md](../../docs/history/content-props-README.md).
