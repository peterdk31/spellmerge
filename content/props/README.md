# Props

## Purpose

Things in the world that stand, block, take hits, react by casting spell cards and give off motes: a barrel's fuse and blast, a crate's rubble, a brazier's embers ([docs/milestones/props.md](../../docs/milestones/props.md), phase W). A prop is an **actor with no controller** (owner, 2026-11-10): health, the hurt shape, statuses, possession and casting are the actor kit's, so nothing in Combat, Spells or possession needs to know it is a prop. If it acts on its own it is an enemy with a statue's look; if it only stands and reacts, it is a prop.

Built in W6 (reactions and states). The look (art layers, mote sources, a light spot) is W7's, the hub's prop yard W8's and the first props (barrel, crate, brazier, crystal, urn) W9's; until then this folder holds only the shared body.

## Contract

- **One folder each:** `content/props/<id>/` with `<id>.tres` (a `PropBase`, core/base/prop_base.gd), its art, `assets.json` and its own test `test_<id>.gd`. Deleting a prop is deleting its folder. The registry finds it under `props` by `id`.
- **One shared body:** `base/prop.tscn`, an actor of the world's team (`Actors.TEAM_WORLD`: every team's shots hit it, its shots hit every team) with `Health`, `Hurtbox`, `Footprint`, `Caster` and `Reactions`, and no controller and no Mover, so it is still (never stepped) and never moves. Every prop's `scene` is it; `PropBody.make(data)` (gameplay/actor) fills it from the data. **No `.gd` and no scene per prop:** a new prop is data and art.
- **`PropBase`:** `id`, `display_name`, `scene`, `max_health`, `invincible` (the hub's: hits land and show, health stays), the hurt shape (`radius`, or a box `size`, round `offset` from the feet), the ground (`footprint_radius` or `footprint_size`, `footprint_offset`; none: its hurt box's base, else the kit's circle), `staffs` (1–4 `StaffCards`, as an enemy's: what its reactions and a possessor cast; a staff's `wind_up` is a fuse, its `wind_cue` the fuse's look) and `states` (`PropState`, the first the one it starts in).
- **`PropState`:** `state_id`, `reactions` (in order), `blocks` (its footprint blocks the bodies that walk), `hittable` (its hurt shape can be hit), `gone` (entering it frees the prop).
- **`PropReaction`:** `when` and its numbers, then what it does: `cast` (a staff by number, 1–4; 0 none) and `then` (a state id; empty stays).

  | `when` | Fires when | Numbers |
  |---|---|---|
  | `element_hit` | a hit of that element lands on it (an invincible prop's too) | `element` (empty: a plain hit), `at_least` damage (0: any) |
  | `status` | a status is put on it | `status` |
  | `reaction` | one of Combat's reactions between statuses happens on it | `reaction` |
  | `health_below` | a hit takes its health below a share of its most (once: the hit that crosses it) | `share` |
  | `death` | its health runs out | |
  | `entered` | its state was just entered (not the one it starts in) | |
  | `cast` | its staff N's cast leaves (a reaction's or a possessor's, after any wind-up) | `staff` |

- **The rule:** on a moment every reaction of the current state that matches fires, in order; the first of them that names a `then` sets the next state, once, after they all fired. Reactions belong to states, so "only once" is a state change, never a flag. Leaving a state ends the wind-ups it cast (a lit barrel shot apart blows now, and its fuse no more). **Death doesn't free a prop:** its `death` reactions run and a possession of it ends; it is freed only by a `gone` state, and without a death row it stands with its health empty.
- **A prop's casts pay from its staffs' pools, which never refill** (a still body is never stepped): every cast a reaction makes must fit in a full pool (`tests/content/props/test_prop_data.gd`).
- `PropBase.problems()` must be empty: no scene or state, a state named twice, a staff it does not hold, a state, element, status or reaction nobody knows, a number out of range, `entered` reactions that go round for ever.
- Original names and art only.

## The barrel, written out

```
staffs   1: fire · blast, wind-up 1.0 s (the fuse)    2: fire · blast, no wind-up
idle     element_hit fire     → then fusing
         death                → cast 2, then broken          (shot apart: blows at once)
         cast 1, cast 2       → then broken                  (possessed: 1 lights the fuse the long way, 2 blows)
fusing   entered              → cast 1                       (the fuse burns, then it blows)
         death                → cast 2, then broken          (shot while lit: blows now)
         cast 1, cast 2       → then broken
broken   blocks off, hittable off (rubble)
```

As data: `tests/gameplay/actor/fixtures/barrel.tres` (its paths: `tests/gameplay/actor/test_reactions.gd`).

## Allowed files

`.tres`, `.tscn` (saved as text), sprites (`.png` or `.svg`), the prop's `test_<id>.gd`, plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs; load only with literal `res://` paths.

## Steps

1. Make `content/props/<id>/` and its `<id>.tres` (a `PropBase` with `scene` the shared `base/prop.tscn`); write its states and reactions (start from the barrel above).
2. Give it staffs of player cards for what it casts.
3. Add its art to an `assets.json` in its folder (W7 brings the look); commit the `.uid` files Godot creates.
4. Write `test_<id>.gd` for its paths (as `tests/gameplay/actor/test_reactions.gd` does the barrel's), run the checks below and open a PR.

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
