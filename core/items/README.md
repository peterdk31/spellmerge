# Items

## Purpose

What an item is ([docs/milestones/items.md](../../docs/milestones/items.md), "The model"): the kinds table and the stack. Who holds stacks is the actor kit's `Inventory` (`gameplay/actor/inventory.gd`); items on the ground are the Items area's (`gameplay/items/`).

## Contract

- **`item_kinds.gd` (`ItemKinds`):** one row a kind in `RULES` (staff, card, relic, potion, ...): its bag (`bag_of`, `kind_in`, `kinds_in`; the bags in order `BAGS`), whether it stacks (`stacks`), its registry folders and class (`content_of`, `is_content`), what can be done with one held (`can`: DROP, DROP_ONE, HAND), whether it is used (`usable(bag, id, registry)`, `use_of`), its content (`content(kind, id, registry)`), its premade folders (`premade_of`). `stack_of(resource)` is a resource as a stack (null for what is no kind's): what a room's item placement lays. **Nothing else names a kind to decide something:** a new kind is a row and its own code.
- **`item_stack.gd` (`ItemStack`):** a kind, an id and a count; a staff stack also its `number`, its `StaffBase` (never changed), its cards by slot (exactly its slots long: `fit`) and the mana it keeps off a hand. `card(id, count)`, `of_staff(base, cards)`, `copy()`. **The recharge travels with the item:** `recharge_left`, `recharge_whole`, `start_recharge`, `step_recharge` (at each of `RECHARGE_STEPS`), counted down by whoever holds it with the simulation's delta. A loadout carries no recharge.
- **`item_looks.gd` (`ItemLooks`):** how an item looks to people, one answer for every kind (`of(kind, id, registry, spells)`: `name`, `icon`, `description`): a card's from Spells, a staff's from its `StaffBase`, any other from its `ItemContent`. Rewards, shops and the inventory show items through it.
- **Currency bag:** coins (`CoinBase`), keys (`KeyBase`, content/keys) and rerolls (`RerollBase`, content/rerolls; `ItemKinds.REROLL`, id `RerollBase.REWARD`) are one stack each in the `currency` bag, dropped one copy at a time; a bag of several kinds tells them apart by id (`kind_in`). A reroll is spent by X in the reward picker; there is no room reroll.
- **An item is usable exactly when it has a use:** `ItemContent.use_of()`, an `ItemUse` (core/base), the one place that says what using it does, whether it is `consumed` (a potion, `ItemUse.drink`) or kept (**the default**), and its `cooldown` (a relic recharges, refused meanwhile). Binding, auto-bind, quick-use and the inventory's Use all go through `ItemKinds.usable` and `use_of`, never the kind.
- **Validation:** `ItemUse.problems` (does something; cooldown 0 or more, a kept use's above 0) and `RelicBase.problems` (a relic's use is never consumed), through `Registry.validate_items`.
- **`ground_sight.gd` (`GroundSight`):** the answer to `ground_looked`: up to `MOST` items, nearest first, each its number, place, in reach or not, and its stack (read only). Made once per asker, filled again each look; DERIVED to whoever holds it.
- **Simulation:** a simulation folder (`StateWalk.FOLDERS`): a held stack is state, walked and snapshotted member by member; no clock or dice here.

## Allowed files

Claude only, like all of `core/`. Typed GDScript.

## Steps

A new kind: a row in `ItemKinds.RULES` (and its bag in `BAGS` if new), then the code that makes it do something. A new question every kind answers: a key in every row and a function here.

## Example to copy

`ItemKinds.RULES`' card row.

## Validate

```sh
tools/ptest.sh 8 'test_item_kinds|test_inventory'
```

Tests: `tests/core/test_item_kinds.gd` (the table against every content folder it names, a use kept by default, the relic checks), `tests/gameplay/actor/test_inventory.gd`, `tests/gameplay/items/test_relic_recharge.gd`, `tests/gameplay/player/test_usable_items.gd` (every item usable exactly when it has a use).

History and reasons: [docs/history/core-items-README.md](../../docs/history/core-items-README.md).
