class_name RewardRoll
extends RefCounted
## How a reward's choices are rolled (connected biomes CB10, decisions 16 and 17): from a reward
## table (`RewardTable`), as many as the player's `reward_choices`, each a line picked by weight and,
## for a line of any card, a card picked evenly from those it allows; never one the offer already
## has (a few tries each, then it offers fewer). Its chance is the run's (`sim.chance`, purpose
## `PURPOSE`, keyed by the seat, its counter the seat's roll count times `TRIES_A_ROLL` plus the
## try), so every machine rolls the same, and one seat's roll never shifts another's. One small
## policy, apart from the area that keeps the offers, so it changes alone. It keeps nothing.

## The chance's purposes: which line, and which card of a line of any card.
const PURPOSE: StringName = &"reward"
const CARD_PURPOSE: StringName = &"reward_card"
## The tries a choice gets to find a reward the offer has not, and the most choices an offer has.
const TRIES: int = 8
const MOST: int = 8
## The counters one roll may use: every try of every choice.
const TRIES_A_ROLL: int = TRIES * MOST


## Fill `offer` with up to `count` choices from `table` for seat `seat`'s roll number `roll`,
## `cards` being the card ids a line of any card may give, each with its complexity
## (`complexities`, by the same index), in id order.
static func fill(offer: RewardOffer, table: RewardTable, count: int, sim: Sim, seat: int, roll: int, cards: Array[StringName], complexities: PackedInt32Array) -> void:
	if table == null or sim == null:
		return
	var total: float = table.total_weight()
	if total <= 0.0:
		return
	var allowed: Array[StringName] = []
	for choice in mini(count, MOST):
		for attempt in TRIES:
			var counter: int = roll * TRIES_A_ROLL + choice * TRIES + attempt
			var entry: RewardEntry = _line(table, total, sim.chance(PURPOSE, seat, counter))
			if entry == null:
				continue
			var id: StringName = entry.id
			if entry.kind == RewardEntry.CARD and id == &"":
				allowed.clear()
				for at in cards.size():
					if entry.max_complexity <= 0 or complexities[at] <= entry.max_complexity:
						allowed.append(cards[at])
				if allowed.is_empty():
					continue
				id = allowed[sim.chance_int(CARD_PURPOSE, seat, counter, allowed.size())]
			if not offer.offers(entry.kind, id, entry.count):
				offer.add(entry.kind, id, entry.count)
				break


## The line of `table` a roll of `at` (0 to 1) lands on, by weight (`total` their sum).
static func _line(table: RewardTable, total: float, at: float) -> RewardEntry:
	var point: float = at * total
	var last: RewardEntry = null
	for entry: RewardEntry in table.entries:
		if entry == null or entry.weight <= 0.0:
			continue
		last = entry
		if point < entry.weight:
			return entry
		point -= entry.weight
	return last
