class_name RewardEntry
extends Resource
## One line of a reward table (connected biomes CB10, `RewardTable`): the item a reward choice may
## be and how likely, against the table's other lines. Every reward is an inventory item (the owner,
## 2026-11-19: "reward cards do not need a special design or data type. They are simply wrapping
## an existing item"): a line names an item by its kind (a row of `ItemKinds.RULES`: a card, a
## potion, coins, ...) and its content's id, and the reward puts `count` of it into the player's
## inventory. Nothing here says what an item does or how it looks: that is the item's own
## (`ItemLooks`).

## The kind of item it gives (a row of `ItemKinds.RULES`).
@export var kind: StringName = ItemKinds.CARD
## The item's id (its content's: `healing` under the potions, `coin` under the coins); for a card
## line, empty: any card, as `max_complexity` allows.
@export var id: StringName = &""
## How many: a card's copies, the potions, the coins.
@export_range(1, 999) var count: int = 1
## How likely, against the table's other lines (above 0).
@export var weight: float = 1.0
## For a card line with no id: the most complex card it may give (`SpellComponent.complexity`);
## 0 for any.
@export_range(0, 10) var max_complexity: int = 0
## What it costs on a shop's shelf (connected biomes CB11, decision 19), in coins, before the buyer's
## `price_scale` run stat; read only by a shelf's table (`RoomKind.shelf`).
@export_range(1, 999) var price: int = 10


## A line of `of_kind` (`of_id`, `of_count` of it) at `of_weight`.
static func make(of_kind: StringName, of_id: StringName = &"", of_count: int = 1, of_weight: float = 1.0) -> RewardEntry:
	var made := RewardEntry.new()
	made.kind = of_kind
	made.id = of_id
	made.count = of_count
	made.weight = of_weight
	return made


## What is wrong with it, one line each, named by `what`: a kind that is no item kind, a weight not
## above 0, a count under 1, a price under 1, a line other than a card's with no id, coins of
## another id than the coin's.
func problems(what: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not ItemKinds.has(kind):
		found.append("%s: a line of the kind '%s', which is none of the item kinds %s." % [what, kind, ItemKinds.kinds()])
	if not is_finite(weight) or weight <= 0.0:
		found.append("%s: a line weighs %s; it must weigh more than 0." % [what, weight])
	if count < 1:
		found.append("%s: a line gives %d; it must give at least 1." % [what, count])
	if price < 1:
		found.append("%s: a line costs %d; at least 1." % [what, price])
	if kind != ItemKinds.CARD and id == &"":
		found.append("%s: a %s line names no item; only a card line may leave its id empty (any card)." % [what, kind])
	if kind == ItemKinds.COIN and id != &"" and id != CoinBase.ID:
		found.append("%s: a coin line names '%s'; the coin is '%s'." % [what, id, CoinBase.ID])
	return found
