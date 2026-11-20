# Items

## Purpose

What an item is (items I3, [docs/milestones/items.md](../../docs/milestones/items.md), "The model"): the kinds table and the stack. Who holds stacks is the actor kit's `Inventory` (`gameplay/actor/inventory.gd`); items on the ground are the Items area's (`gameplay/items/`, I6).

## Contract

- **`item_kinds.gd` (`ItemKinds`):** one row a kind in `RULES` (staff, card, relic, potion): its bag (`bag_of`, `kind_in`; the bags in order are `BAGS`), whether it stacks (`stacks`), the registry folders its ids are in and the class a resource there must be (`content_of`, `is_content`), what can be done with one held (`can`: DROP, DROP_ONE, HAND, USE) and the folders its premade items are in (`premade_of`: the staff's `items`, content/items/). `stack_of(resource)` is one of what a resource is as a stack (a premade staff `StaffItem.stack()`, a staff empty, a card one copy; null for what is no kind's, a kind with no class of its own included): what a room's item placement lays. Nothing else names a kind to decide something: a new kind is a row and its own code.
- **`item_stack.gd` (`ItemStack`):** a kind, an id and a count; a staff stack also has its `number` in its inventory, the `StaffBase` it is (content, never changed), its cards by slot (exactly its slots long: `fit`) and the mana it keeps while on no hand. `card(id, count)`, `of_staff(base, cards)` (pool full), `copy()`.
- **`item_looks.gd` (`ItemLooks`):** how an item looks to people, one answer for every kind (`of(kind, id, registry, spells)`: `name`, `icon`, `description`): a card's are Spells', a staff's its `StaffBase`'s, any other kind's its content's (an `ItemContent`: a potion, the coin; or a `RelicBase`), found by `content_of(kind, id, registry)` in its row's folders. What a reward's card, a shop's shelf and the inventory show of an item (the owner, 2026-11-19: every reward is an item).
- **Rerolls** (the owner, 2026-11-19): a reroll is a `RerollBase` (content/rerolls; `ItemKinds.REROLL`), one stack in the currency bag beside the coins and the keys (id `RerollBase.REWARD`, the row's `ids`), droppable one at a time as they are; X spends one in the reward picker (gameplay/rewards). The room reroll is gone (the owner, 2026-11-19: "I only want the player to be able to reroll rewards, not rooms").
- **Potions and coins** (the owner, 2026-11-19): a potion is a `PotionBase` (content/potions; USE: drunk from the inventory, the player controller's `bag_use_requested`), coins one stack of the `CoinBase` and keys one of the `KeyBase` (content/keys), together in the currency bag (`currency`, after the owner's four; the owner, 2026-11-19: "a currency bag (along with coins)"; DROP: one copy at a time, as a potion, since the owner's "Everything is droppable" of 2026-11-19: it lies as any item and A takes it into the taker's own bag, never shared). A bag of two kinds tells them apart by id (the rows' `ids`, `ItemKinds.kind_in(bag, id)`, `kinds_in`). Both are `ItemContent` (core/base: id, name, description, icon). `ItemStack.of(kind, id, count)` makes a stack of any kind but a staff.
- **`ground_sight.gd` (`GroundSight`, items I9):** what a body sees lying round it, the answer to `ground_looked` (the Items area fills it at once): up to `MOST` items, nearest first, each its number, where it lies, whether it is in reach and its stack (the ground's own: read only). Made once per asker and filled again at each look; scratch (DERIVED) to whoever holds it.
- **Simulation:** a simulation folder (`StateWalk.FOLDERS`): a stack held by an inventory is state, walked and snapshotted member by member; nothing here has a clock or dice.

## Allowed files

Claude only, like all of `core/`. Typed GDScript. Tests: `tests/core/test_item_kinds.gd` (the table against every content folder it names, the potions and the coin sound), and the inventory's in `tests/gameplay/actor/test_inventory.gd`.

## Steps

A new kind: a row in `ItemKinds.RULES` (and its bag in `BAGS` if it has a new one), then the code that makes it do something. A new question every kind answers: a key in every row and a function here.

## Example to copy

`ItemKinds.RULES`' card row.

## Validate

```sh
tools/ptest.sh 8 'test_item_kinds|test_inventory'
```
