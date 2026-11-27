# Items (`content/items`)

## Purpose

Premade items (items I6, [docs/milestones/items.md](../../docs/milestones/items.md)): things lying in a room for anyone to take, made as data. Staffs first: a premade staff is a staff with a build in it (the hub's rack). The registry finds them under `items` (`ItemKinds.premade_of`).

## Contract

- **One folder each:** `staffs/<id>/` with `<id>.tres` (a `StaffItem`, core/base/staff_item.gd) and its own test `test_<id>.gd`. Deleting one is deleting its folder.
- **`StaffItem`:** `id` (the folder name), `display_name` (shown near it on the ground; empty: its staff's), `staff` (a `StaffBase` of `content/wizard/staffs/`: its slots, numbers and head) and `cards` (card ids by slot, no more than the staff's slots; `problems()`). Taken, it is that staff with those cards like any other (its stack's id is its staff's), so nothing else knows it was premade.
- **Where it lies** is the room's: an `ItemStandIn` (tools/item_stand_in.gd) in the room's scene with the item picked in the Inspector (the hub's `Items`: the normal staffs `TwinBolt`, `FrostSeeker` and `Firebolt` in a row 64 px apart ending at the Wild star on `Rack`, and under it one row of the premade builds 64 px apart, `PatientSentry`, the five, `FrostfireCascade`; `tests/content/rooms/test_hub_data.gd` holds both rows on open floor).
- **The normal staffs** (the owner, 2026-11-20, on #891: real, balanced builds beside the crazy ones, so players and bots have real choices), each on a starter staff (6 slots, a starter's mana and cooldown) with its own test (sound, no card wasted, a fair staff): `firebolt` (fire on a bolt, the moon staff), `frost_seeker` (a homing frost bolt, the crystal staff) and `twin_bolt` (a bolt and +2: three bolts in a fan, the curl staff). The test bots take only these, never a dev staff or the Wild star (tests/bots/README.md): the mender takes the Firebolt. A card can lie there too, picked from `content/spells/`.
- **The premade builds** (2026-11-14): `glacier_engine`, `hammer_of_the_faithless`, `corpse_bloom`, `death_from_every_sky` and `the_mutiny`, five of the crazy builds, on the `dev` staff (20 slots, no cooldown, a million mana) because none of them fits in four slots. Taken into a run they keep the dev staff's numbers: they are for trying builds out, not for a fair run.
- **The showcase builds** (crypt rework CR-S, 2026-11-16: the owner's "Move the staffs to the hub", the sandbox's two start builds), on the `dev` staff too, at the ends of the rack's row, each with its own test (no card wasted):
  - `frostfire_cascade`, the Frostfire Cascade: the most shots. A fire nova of bolts with three +2 (56 shots) whose every shot, as it ends, fires a frost nova of bolts with three +2 (56 each, 3,136 in all): past the web's projectile cap, which it holds for a few seconds (until 2026-11-27 Split multiplied: 216 each, #972). The hub storm benchmark casts it (tests/benchmark/hub_storm.gd), and the replay tests' scripted player takes it (tests/support/replay_run.gd).
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

`staffs/wild_star/`: the Wild star, the star staff holding lightning, chain, +2 and bolt (no card wasted: its test).

## Validate

```sh
tools/check.sh
tools/ptest.sh 8 'test_wild_star|test_firebolt|test_frost_seeker|test_twin_bolt|test_hub_data|test_item_kinds|test_content_determinism'
```
