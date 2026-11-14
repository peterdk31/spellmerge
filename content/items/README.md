# Items (`content/items`)

## Purpose

Premade items (items I6, [docs/milestones/items.md](../../docs/milestones/items.md)): things lying in a room for anyone to take, made as data. Staffs first: a premade staff is a staff with a build in it (the hub's rack). The registry finds them under `items` (`ItemKinds.premade_of`).

## Contract

- **One folder each:** `staffs/<id>/` with `<id>.tres` (a `StaffItem`, core/base/staff_item.gd) and its own test `test_<id>.gd`. Deleting one is deleting its folder.
- **`StaffItem`:** `id` (the folder name), `display_name` (shown near it on the ground; empty: its staff's), `staff` (a `StaffBase` of `content/wizard/staffs/`: its slots, numbers and head) and `cards` (card ids by slot, no more than the staff's slots; `problems()`). Taken, it is that staff with those cards like any other (its stack's id is its staff's), so nothing else knows it was premade.
- **Where it lies** is the room's: an `ItemStandIn` (tools/item_stand_in.gd) in the room's scene with the item picked in the Inspector (the hub's `Items/Rack`). A card can lie there too, picked from `content/spells/`.
- **The premade builds** (2026-11-14): `glacier_engine`, `hammer_of_the_faithless`, `corpse_bloom`, `death_from_every_sky` and `the_mutiny`, five of the crazy builds, on the `dev` staff (20 slots, no cooldown, a million mana) because none of them fits in four slots. Each one's test also checks that its build reads in one cast and that its triggers fire at the payload depths the build is made of. Taken into a run they keep the sandbox staff's numbers: they are for trying builds out, not for a fair run.
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
