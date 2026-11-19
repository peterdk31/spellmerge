class_name RewardRoll
extends RefCounted
## How a reward's choices are rolled (connected biomes CB10, decisions 16 and 17): from a reward
## table (`RewardTable`), as many as the player's `reward_choices`, each a line picked by weight and,
## for a line of any card, a card picked evenly from those it allows; never one the offer already
## has (a few tries each, then it offers fewer). Its chance is the run's (`sim.chance`, purpose
## `PURPOSE`, keyed by the seat, its counter the seat's roll count times `TRIES_A_ROLL` plus the
## try), so every machine rolls the same, and one seat's roll never shifts another's. One small
## policy, apart from the area that keeps the offers, so it changes alone. It keeps nothing.
##
## **A room's type** (`RewardType`, the owner's ask of 2026-11-19: a reward room's, decided as its
## biome is made): each choice is first rolled among the items of the type's narrowest level (its
## element's card, its card kind's cards, its item kind's lines) and, while that level has nothing
## left the offer has not (its tries all land on what it has), at the next wider level, down to the
## whole table. So a fire room offers Fire and then another infusion; a modifier room two modifiers;
## a coin room its coins and then anything of the table (it has one coin line). Each level rolls under purposes of its own
## (`LEVEL_PURPOSES`), so a roll of no type (every other room, a shop) rolls as it always did.

## The chance's purposes: which line, and which card of a line of any card.
const PURPOSE: StringName = &"reward"
const CARD_PURPOSE: StringName = &"reward_card"
## The purposes of a typed roll's levels (RewardType.ITEM, CARD_KIND, ELEMENT; ANY's are the
## caller's), the line's and the card's.
const LEVEL_PURPOSES: Array[StringName] = [&"", &"reward_item", &"reward_kind", &"reward_element"]
const LEVEL_CARD_PURPOSES: Array[StringName] = [&"", &"reward_item_card", &"reward_kind_card", &"reward_element_card"]
## The tries a choice gets to find a reward the offer has not, and the most choices an offer has.
const TRIES: int = 8
const MOST: int = 8
## The counters one roll may use: every try of every choice.
const TRIES_A_ROLL: int = TRIES * MOST


## Fill `offer` with up to `count` choices from `table` for seat `seat`'s roll number `roll`,
## `cards` being the cards a line of any card may give (`RewardCards`). `purpose` and
## `card_purpose`: the chance's (a shop's shelf rolls under its own, keyed by its room in place of a
## seat; connected biomes CB11). Each choice's line is in `lines`, when given, by the same index (a
## shelf's prices). `type`: the room's (null or any: the whole table).
static func fill(offer: RewardOffer, table: RewardTable, count: int, sim: Sim, seat: int, roll: int, cards: RewardCards, purpose: StringName = PURPOSE, card_purpose: StringName = CARD_PURPOSE, lines: Array[RewardEntry] = [], type: RewardType = null) -> void:
	if table == null or sim == null:
		return
	if cards == null:
		cards = RewardCards.new()
	var narrowest: int = type.narrowest() if type != null else RewardType.ANY
	var allowed: Array[StringName] = []
	var weights := PackedFloat64Array()
	for choice in mini(count, MOST):
		var base: int = roll * TRIES_A_ROLL + choice * TRIES
		for level in range(narrowest, RewardType.ANY - 1, -1):
			var line_purpose: StringName = purpose if level == RewardType.ANY else LEVEL_PURPOSES[level]
			var pick_purpose: StringName = card_purpose if level == RewardType.ANY else LEVEL_CARD_PURPOSES[level]
			if _choose(offer, table, sim, seat, base, cards, type, level, line_purpose, pick_purpose, allowed, weights, lines):
				break


## One choice at level `level` of `type`: up to TRIES lines rolled among the lines of that level
## (counters from `base`), the first giving what the offer has not added. False when none does. At
## a typed level only a line with something of the type the offer lacks weighs anything, and a card
## line's card is picked among those, so a typed level widens only once it has nothing left.
static func _choose(offer: RewardOffer, table: RewardTable, sim: Sim, seat: int, base: int, cards: RewardCards, type: RewardType, level: int, line_purpose: StringName, pick_purpose: StringName, allowed: Array[StringName], weights: PackedFloat64Array, lines: Array[RewardEntry]) -> bool:
	var total: float = 0.0
	weights.resize(table.entries.size())
	for at in table.entries.size():
		var entry: RewardEntry = table.entries[at]
		var weight: float = 0.0
		if entry != null and entry.weight > 0.0 and (level == RewardType.ANY or (type.line_fits(entry, level) and _left(offer, entry, cards, type, level, allowed))):
			weight = entry.weight
		weights[at] = weight
		total += weight
	if total <= 0.0:
		return false
	for attempt in TRIES:
		var counter: int = base + attempt
		var entry: RewardEntry = _line(table, weights, total, sim.chance(line_purpose, seat, counter))
		if entry == null:
			continue
		var id: StringName = entry.id
		if entry.kind == ItemKinds.CARD:
			if id == &"":
				allowed.clear()
				for at in cards.size():
					if not cards.line_gives(entry, at):
						continue
					if level == RewardType.ANY or (type.card_fits(cards.ids[at], cards.kinds[at], level) and not offer.offers(entry.kind, cards.ids[at], entry.count)):
						allowed.append(cards.ids[at])
				if allowed.is_empty():
					continue
				id = allowed[sim.chance_int(pick_purpose, seat, counter, allowed.size())]
			elif level >= RewardType.CARD_KIND and not type.card_fits(id, cards.kind_of(id), level):
				continue
		if not offer.offers(entry.kind, id, entry.count):
			offer.add(entry.kind, id, entry.count)
			lines.append(entry)
			return true
	return false


## True when the line `entry` can still give, at level `level` of `type`, an item the offer has not
## (`allowed`: scratch).
static func _left(offer: RewardOffer, entry: RewardEntry, cards: RewardCards, type: RewardType, level: int, allowed: Array[StringName]) -> bool:
	if entry.kind != ItemKinds.CARD:
		return not offer.offers(entry.kind, entry.id, entry.count)
	if entry.id != &"":
		return type.card_fits(entry.id, cards.kind_of(entry.id), level) and not offer.offers(entry.kind, entry.id, entry.count)
	for at in cards.size():
		if cards.line_gives(entry, at) and type.card_fits(cards.ids[at], cards.kinds[at], level) and not offer.offers(entry.kind, cards.ids[at], entry.count):
			return true
	return false


## The line of `table` a roll of `at` (0 to 1) lands on, by `weights` (by the same index; `total`
## their sum).
static func _line(table: RewardTable, weights: PackedFloat64Array, total: float, at: float) -> RewardEntry:
	var point: float = at * total
	var last: RewardEntry = null
	for index in table.entries.size():
		var weight: float = weights[index]
		if weight <= 0.0:
			continue
		last = table.entries[index]
		if point < weight:
			return last
		point -= weight
	return last
