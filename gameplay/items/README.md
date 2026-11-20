# Items

## Purpose

What lies on the ground, and picking it up (items I6, [docs/milestones/items.md](../../docs/milestones/items.md), "The ground" and "Picking up"). Staffs first, cards and potions too (a potion or the coin dropped lies as any item); relics later. What an item is (the kinds table, the stack) is `core/items/`; who holds stacks is the actor kit's `Inventory` (`gameplay/actor/`).

## Contract

- **Public entry script:** `gameplay/items/items.gd` (autoload `Items`). Other code uses only this script and its events; `PickupRule` and `GroundItem` are its own.
- **The ground** (`items.gd`): a row an item (`GroundItem`: its number, handed out once a run; where it lies; its stack, one copy: no piles), state like any simulation area's; an active relic dropped mid-recharge keeps recharging where it lies (its step counts each stack's recharge down with the tick's delta, `ItemStack.step_recharge`; the owner, 2026-11-20) and is taken as recharged as it is (a ground loadout, a recording's header, carries no recharge: the room begun anew lays it ready); saved and restored with the rest (after a restore it says everything again, `rebuild_derived`, for that machine's looks). An item is no body: nothing hits, pushes or is blocked by it. It belongs to the room it lies in: a run's start (one room a run) clears the ground (`begin_run`, in `Tick.RUN_ORDER`).
  - **Kept when the room is begun anew** (owner, 2026-11-14): what lies there is the frames service's ground source (`ground_now`, a `GroundLoadout`, core/sim), written into a recording's header; a run in the same room (the hub begun anew for a joining machine) lays exactly that (`lay_ground`), any other start (a host starting the hub, a party back from a run) the room's placements, so the rack is fresh then.
  - **Laid** by the room (`room_items_placed`, from flow: each `ItemStandIn` of the room's scene, `ItemKinds.stack_of` its data; a premade staff is shown by its own name) and by a drop (`item_drop_requested`, from an actor's Inventory: a card given back to a full bag), which lands `DROP_STEPS` from the body at the first free way of `DIRECTIONS` (no item lying within twice its radius, no wall, no standing body's ground round it, no wall between: the projectile manager's grid), tried from the side away from the item the body would take next; at the feet when every way is blocked. The same on every machine.
  - **In reach:** its step (`Tick.STEPS` "Items", after the bodies) finds, for the body each seat drives now, the item in reach (`PickupRule.nearest`; none for a body with no Inventory, or down) and says it as it changes (`item_near_changed`); a coin is never that item.
  - **Walked over** (the owner, 2026-11-19): first, in the same step, each seat's driven body (seats in order, standing, with room) takes every coin its feet come within `PickupRule.WALK_REACH` (10 px) of, no A, into its own currency bag: one's own, never shared (the shared floor coins are the Rewards area's). A dropped coin waits for its dropper's feet to leave it before that body walks it up again (`GroundItem.waits_for`), so a drop at the feet stays down. Keys and every other item keep A. A dying foe's coins taken later (Rewards, `Inventory.drop_taken`) lie here as plain coins.
  - **Taken:** `take(actor, item)` by actor id (a seat's request is one caller; the AI, I9, another): the item must still lie there in reach of the actor's feet, and the pickup rule must find room (`Take`: TAKEN, GONE, NO_HOLDER, OUT_OF_REACH, NO_ROOM). A seat's A is the command `item_take_requested`, applied at the tick's start seat by seat, so of two seats asking for one item in one tick the first takes it; no room is `item_refused` for that seat, anything else is silent.
- **Looked at by an actor** (items I9): `ground_looked(actor, feet, reach, sight)` asks what lies within `reach` of `feet`; `look` fills the asker's `GroundSight` (core/items) at once, the nearest first, each marked in reach as the pickup rule says. `actor_take_requested(actor, item)` is an actor's take during the tick (the AI's), as `take` says, silently. So the AI sees and takes without calling this area.
- **The pickup rule** (`pickup_rule.gd`, `PickupRule`): reach (`REACH`, 24 px from the feet), which item is the one in reach (the nearest; the lower number on a tie) which coin a body walks over (`walks_over`, `walked_over`: a coin, within `WALK_REACH`, not waiting for that body), and what a take does (a staff onto a free hand, `Inventory.free_hand`/`put_on_hand`, else into its bag; anything else into its bag; no room, nothing). One small policy apart from the bags and the ground (owner, 2026-11-13: "the way to pickup items could be tweaked"): walking over an item or another button is a change there only.
- **Views** (`view_of`): an item's name and icon as `ItemLooks` says them (core/items), a staff's numbers; plain values for the looks (`ground_item_changed` lists them): Feel draws the items (`gameplay/feel/ground_items.gd`), the HUD the hint (`hud/panels/item_hints.gd`).
- **Dependency direction:** `core` ← `gameplay` ← `content`. It uses `core/` (the bus, the actor table, the projectile manager's walls, Spells for cards' names and icons) and the actor kit's Inventory; it knows nothing of the HUD, the AI or `net/`.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `ground_item_changed`, `item_near_changed`, `item_refused`.
  - Listens to: `room_items_placed` (flow), `item_drop_requested` (an Inventory: a card given back to a full bag, or what the inventory menu dropped, items I7), `ground_looked` and `actor_take_requested` (ai, items I9), and the command `item_take_requested` (HUD, through `Events.listen`).

## Allowed files

`.gd`, plus `.uid` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

- **A new way to pick up:** change `PickupRule` only.
- **A new item to lie in a room:** an `ItemStandIn` in the room's scene (tools/), its `item` picked in the Inspector; a premade staff is a folder under `content/items/staffs/` (content/items/README.md).

## Example to copy

`content/items/staffs/wild_star/` (the hub's rack) and the hub's scene's `Items/Rack`.

## Validate

```sh
tools/ptest.sh 8 'test_items|test_relic_recharge|test_ai_pick_up|test_inventory|test_item_kinds|test_wild_star|test_flow_hub|test_content_determinism'
```
