extends RefCounted
## Seeded random staffs for the bots and the spell fuzz test (staffs A6a): a row of card ids
## drawn from a bag. The same seed always gives the same staff, so a failure can be replayed
## from its seed. Every arrangement is legal (docs/milestones/M2-staffs.md, "Reading a staff"),
## so nothing is checked here; `random_cards` only makes sure there is at least one carrier,
## so a bot's staff fires something.
##
## Example:
##   var fuzzer := StaffFuzzerScript.new(bag, func(id: StringName) -> StringName: return Spells.component_kind(id))
##   var cards: Array[StringName] = fuzzer.random_cards(rng, 8)

## Chance (percent) that a slot stays empty.
const EMPTY_CHANCE: int = 15

var _bag: Array[StringName] = []
var _forms: Array[StringName] = []


## `bag` is the card ids to draw from; `kind_of` (Callable(id) -> StringName) tells the carriers
## (`&"form"`) apart.
func _init(bag: Array[StringName], kind_of: Callable) -> void:
	_bag = bag.duplicate()
	for id in _bag:
		if StringName(kind_of.call(id)) == &"form":
			_forms.append(id)


## True when the bag has a carrier to build with.
func can_build() -> bool:
	return not _forms.is_empty()


## A random row of at most `slots` cards (1 to `slots` long), with at least one carrier when the
## bag has one; `&""` is an empty slot.
func random_cards(rng: RandomNumberGenerator, slots: int) -> Array[StringName]:
	var cards: Array[StringName] = []
	if _bag.is_empty() or slots <= 0:
		return cards
	var length: int = rng.randi_range(1, slots)
	for _slot in length:
		if rng.randi_range(1, 100) <= EMPTY_CHANCE:
			cards.append(&"")
		else:
			cards.append(_bag[rng.randi_range(0, _bag.size() - 1)])
	var has_form: bool = false
	for id in cards:
		has_form = has_form or _forms.has(id)
	if not has_form and not _forms.is_empty():
		cards[rng.randi_range(0, cards.size() - 1)] = _forms[rng.randi_range(0, _forms.size() - 1)]
	return cards
