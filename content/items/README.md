# Items (`content/items`)

## Purpose

Premade items (items I6, [docs/milestones/items.md](../../docs/milestones/items.md)): things lying in a room for anyone to take, made as data. Staffs first: a premade staff is a staff with a build in it (the hub's rack). The registry finds them under `items` (`ItemKinds.premade_of`).

## Contract

- **One folder each:** `staffs/<id>/` with `<id>.tres` (a `StaffItem`, core/base/staff_item.gd) and its own test `test_<id>.gd`. Deleting one is deleting its folder.
- **`StaffItem`:** `id` (the folder name), `display_name` (shown near it on the ground; empty: its staff's), `staff` (a `StaffBase` of `content/wizard/staffs/`: its slots, numbers and head) and `cards` (card ids by slot, no more than the staff's slots; `problems()`). Taken, it is that staff with those cards like any other (its stack's id is its staff's), so nothing else knows it was premade.
- **Where it lies** is the room's: an `ItemStandIn` (tools/item_stand_in.gd) in the room's scene with the item picked in the Inspector (the hub's `Items`: the Wild star on `Rack`, and under it one row of the premade builds 64 px apart, `PatientSentry`, the five, `FrostfireCascade`, a second row of six under that and a third under that; `tests/content/rooms/test_hub_data.gd` holds the rows on open floor). A card can lie there too, picked from `content/spells/`.
- **The premade builds** (2026-11-14): `glacier_engine`, `hammer_of_the_faithless`, `corpse_bloom`, `death_from_every_sky` and `the_mutiny`, five of the crazy builds, on the `dev` staff (20 slots, no cooldown, a million mana) because none of them fits in four slots. Taken into a run they keep the dev staff's numbers: they are for trying builds out, not for a fair run.
- **The second row** (2026-11-20), six more crazy builds on the `dev` staff, under the first row, each with its own test (no card wasted, one cast):
  - `prism_crown`, the Prism Crown: a big slow lightning bolt circles its caster, and every 0.5 s five chaining lightning beams close in on it from a ring.
  - `choir_of_wisps`, the Choir of Wisps: three familiars at once, each casting at a foe that comes near: a homing fire bolt, a frost spray and a chaining lightning bolt.
  - `meteor_orchard`, the Meteor Orchard: a rune that calls a big blasting fire bolt down from the sky every 0.5 s while it waits, and a nova of frost bolts from the sky when it goes off.
  - `maelstrom_heart`, the Maelstrom Heart: a slow, growing water and storm bolt that drags foes toward its path and every 0.5 s throws a nova of weaving lightning atoms.
  - `hall_of_mirrors`, the Hall of Mirrors: three volleys of split frost bolts, fired forward and backward and echoed; each that hits closes a ring of five zapping lightning bolts in on where it hit.
  - `thunderclap_gauntlet`, the Thunderclap Gauntlet: a lightning swing and a storm slam together; the swing's hits throw a nova of chaining lightning atoms, the slam's call a big fire bolt down from the sky.
- **The third row** (2026-11-20), six even crazier builds on the `dev` staff, under the second row, each with its own test (no card wasted, one cast):
  - `starfall_engine`, the Starfall Engine: A big slow void bolt circles its caster and every 0.5 s drops a nova of fire bolts from the sky; each fire bolt, as it ends, closes five chaining lightning beams in on where it ended.
  - `gravity_well`, the Gravity Well: A huge, slow, growing void and storm bolt that drags foes toward its path and every 0.5 s throws a nova of weaving fire atoms and closes five zapping lightning bolts in on itself.
  - `cascade_of_cascades`, the Cascade of Cascades: A split frost, fire and lightning bolt at once, each of whose three shots throws a nova of atoms as it ends.
  - `rune_minefield`, the Rune Minefield: Three runes scattered at random, each throwing a nova of fire, frost or lightning atoms every 0.5 s while it waits.
  - `mirror_tempest`, the Mirror Tempest: A lightning and a frost beam eight ways at once, each fired backward too and echoed, three times over.
  - `meteor_monsoon`, the Meteor Monsoon: Three novas of blasting fire, frost and lightning bolts falling from the sky at once, three times over.
- **The showcase builds** (crypt rework CR-S, 2026-11-16: the owner's "Move the staffs to the hub", the sandbox's two start builds), on the `dev` staff too, at the ends of the rack's first row, each with its own test (no card wasted):
  - `frostfire_cascade`, the Frostfire Cascade: the most shots. A fire nova of bolts split three times (216 shots) whose every shot, as it ends, fires a frost nova of bolts split three times (216 each): far past the projectile cap, which it holds for a few seconds. The hub storm benchmark casts it (tests/benchmark/hub_storm.gd), and the replay tests' scripted player takes it (tests/support/replay_run.gd).
  - `patient_sentry`, the Patient Sentry: a decoy turret. Every 0.5 s it fires a homing fire, frost and lightning bolt (the lightning one sets off a chaining lightning atom on hit), and when it is hurt a void nova of bolts.
- The hub's rack is ordinary items (owner, 2026-11-13): not endless and with no rules of its own; it lies there again each time the hub starts.

## Allowed files

`.tres`, `.gd` (the tests), plus `.uid` and `.license` files. Images only if an item brings art of its own (with an `assets.json`). Limit: 1 MB per file. Typed GDScript only; no banned APIs.

## Steps

1. Copy `staffs/wild_star/` and rename the folder, the `.tres` and the test.
2. Set its `id`, name, staff and cards.
3. Place it in a room with an `ItemStandIn`.
4. Run the checks below.

## Example to copy

`staffs/wild_star/`: the Wild star, the star staff holding lightning, chain, split and bolt (no card wasted: its test).

## Validate

```sh
tools/check.sh
tools/ptest.sh 8 'test_wild_star|test_item_kinds|test_content_determinism'
```
