class_name RewardEntry
extends Resource
## One line of a reward table (connected biomes CB10, `RewardTable`): what a reward choice may be
## and how likely, against the table's other lines. Before relics exist a reward is a card, coins,
## healing or a little more health (`KINDS`; the owner, 2026-11-19; a card upgrade waits for card
## levels); a new kind is a row there and its code in the Rewards area (gameplay/rewards).

## A copy of a card into the player's card bag: `id`'s, or with no id any card of the registry's
## `spells` of at most `max_complexity` (0: any), the same for each roll as the run's chance says.
const CARD: StringName = &"card"
## Coins into the player's own wallet (`count` of them).
const COINS: StringName = &"coins"
## A heal of the player's wizard, `count` health (not while it is down).
const HEAL: StringName = &"heal"
## `count` more most health for the player's wizard, and as much health.
const MAX_HEALTH: StringName = &"max_health"
## The kinds a line may be.
const KINDS: Array[StringName] = [CARD, COINS, HEAL, MAX_HEALTH]
## What a choice of each kind does, one short line for the reward menu's card (`describe`;
## `{count}` is its count). A card says its own (`SpellComponent.description`), so it has none here;
## a new kind brings its line with its row of `KINDS`.
const DESCRIPTIONS: Dictionary = {
	COINS: "{count} coins into your own purse, to spend in a shop.",
	HEAL: "Heals your wizard {count} health at once. Not while down.",
	MAX_HEALTH: "Your wizard's most health grows by {count}, healed too.",
}

## What it gives (one of `KINDS`).
@export var kind: StringName = CARD
## The card it gives (a card line); empty: any card, as `max_complexity` allows.
@export var id: StringName = &""
## How many: a card's copies, the coins, the health healed or added.
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


## What a choice of `of_kind`, `of_count` of it, does (`DESCRIPTIONS`); empty for a card (its own
## description is the card's) or a kind with no line.
static func describe(of_kind: StringName, of_count: int) -> String:
	return String(DESCRIPTIONS.get(of_kind, "")).format({"count": of_count})


## What is wrong with it, one line each, named by `what`: a kind not of `KINDS`, a weight not above
## 0, a count under 1, a line other than a card's that names an id.
func problems(what: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not KINDS.has(kind):
		found.append("%s: a line of the kind '%s', which is none of %s." % [what, kind, KINDS])
	if not is_finite(weight) or weight <= 0.0:
		found.append("%s: a line weighs %s; it must weigh more than 0." % [what, weight])
	if count < 1:
		found.append("%s: a line gives %d; it must give at least 1." % [what, count])
	if price < 1:
		found.append("%s: a line costs %d; at least 1." % [what, price])
	if kind != CARD and id != &"":
		found.append("%s: a %s line names the id '%s'; only a card has one." % [what, kind, id])
	return found
