extends "res://tests/support/suite.gd"
## The first cards' looks (staffs C0): every one of the first six modifiers gives off a
## particle style, and no two of them, and no infusion, share one, so a shot shows which
## cards are on it.
##
## godot --headless --path . --script res://tests/content/spells/test_original_looks.gd

const CARDS: Array[ModifierBase] = [
	preload("res://content/spells/modifiers/split/split.tres"),
	preload("res://content/spells/modifiers/pierce/pierce.tres"),
	preload("res://content/spells/modifiers/homing/homing.tres"),
	preload("res://content/spells/modifiers/chain/chain.tres"),
	preload("res://content/spells/modifiers/bigger/bigger.tres"),
	preload("res://content/spells/modifiers/faster/faster.tres"),
]

const INFUSIONS: Array[ElementBase] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
	preload("res://content/spells/elements/mend/mend.tres"),
]


func test_every_first_modifier_has_a_look() -> void:
	for card: ModifierBase in CARDS:
		check(card.look_layer > 0, "%s gives off a look" % card.id)


func test_no_first_modifier_shares_a_look() -> void:
	var seen: Dictionary = {}
	for card: ModifierBase in CARDS:
		check(not seen.has(card.look_layer), "%s has a look of its own among the first six (kind %d)" % [card.id, card.look_layer])
		seen[card.look_layer] = card.id
	for infusion: ElementBase in INFUSIONS:
		check(not seen.has(infusion.look_layer), "%s's look is not hidden by a first modifier (%s)" % [infusion.id, str(seen.get(infusion.look_layer, ""))])
