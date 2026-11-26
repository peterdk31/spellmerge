# Items

## Purpose

What lies on the ground, and picking it up ([docs/milestones/items.md](../../docs/milestones/items.md), "The ground" and "Picking up"): staffs, cards, potions, coins, keys, relics. What an item is (kinds, stacks) is `core/items/`; who holds stacks is the actor kit's `Inventory` (`gameplay/actor/`).

## Contract

- **Public entry script:** `gameplay/items/items.gd` (autoload `Items`). Other code uses only this script and its events; `PickupRule` and `GroundItem` are its own.
- **The ground** (`items.gd`): a row an item (`GroundItem`: its number, handed out once a run; where it lies; its stack, one copy, no piles), simulation state, snapshotted with the rest (`rebuild_derived` says everything again after a restore). A relic dropped mid-recharge keeps recharging on the ground (`ItemStack.step_recharge`). An item is no body: nothing hits, pushes or is blocked by it. A run's start clears the ground (`begin_run`, `Tick.RUN_ORDER`).
  - **Kept when the room is begun anew:** the ground is the frames service's ground source (`ground_now`, a `GroundLoadout`), written into a recording's header; a run in the same room lays exactly that (`lay_ground`), any other start the room's placements.
  - **Laid** by the room (`room_items_placed`: each `ItemStandIn`, `ItemKinds.stack_of` its data) and by a drop (`item_drop_requested`), which lands `DROP_STEPS` from the body at the first free way of `DIRECTIONS` (no item, wall or standing body there), at the feet when every way is blocked. The same on every machine.
  - **In reach:** its step (`Tick.STEPS` "Items", after the bodies) finds, for each seat's driven body, the item in reach (`PickupRule.nearest`; none for a body with no Inventory, or down) and says it as it changes (`item_near_changed`); a coin is never that item.
  - **Walked over:** first, in the same step, each seat's driven body (seats in order) takes every coin within `PickupRule.WALK_REACH` into its own currency bag, no A. A dropped coin waits for its dropper's feet to leave it (`GroundItem.waits_for`). Keys and every other item need A.
  - **Taken:** `take(actor, item)` by actor id: the item must still lie in reach and the pickup rule must find room (`Take`: TAKEN, GONE, NO_HOLDER, OUT_OF_REACH, NO_ROOM). A seat's A is the command `item_take_requested`, applied at the tick's start seat by seat (the first seat wins a tie); no room is `item_refused` for that seat, anything else is silent.
- **Looked at by an actor:** `ground_looked(actor, feet, reach, sight)` fills the asker's `GroundSight` (core/items) at once, nearest first, each marked in reach; `actor_take_requested(actor, item)` is an actor's take during the tick, silently. The AI never calls this area.
- **The pickup rule** (`pickup_rule.gd`, `PickupRule`): reach (`REACH`, from the feet), which item is in reach (the nearest; the lower number on a tie), which coin a body walks over (`walks_over`, `walked_over`), what a take does (a staff onto a free hand, `Inventory.free_hand`/`put_on_hand`, else into its bag; anything else into its bag; no room, nothing). A new way to pick up is a change there only.
- **Views** (`view_of`): an item's name and icon as `ItemLooks` says them, a staff's numbers; plain values in `ground_item_changed`. Feel draws the items (`gameplay/feel/ground_items.gd`), the HUD the hint (`hud/panels/item_hints.gd`).
- **Dependency direction:** `core` ← `gameplay` ← `content`. Uses `core/` (the bus, the actor table, the projectile manager's walls, Spells for cards' names and icons) and the actor kit's Inventory; knows nothing of the HUD, the AI or `net/`.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `ground_item_changed`, `item_near_changed`, `item_refused`.
  - Listens to: `room_items_placed` (flow), `item_drop_requested` (an Inventory), `ground_looked` and `actor_take_requested` (ai), and the command `item_take_requested` (HUD, through `Events.listen`).

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

History and reasons: [docs/history/gameplay-items-README.md](../../docs/history/gameplay-items-README.md).
