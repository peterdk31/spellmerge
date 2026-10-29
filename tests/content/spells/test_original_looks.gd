extends "res://tests/support/suite.gd"
## The first cards' looks (staffs C0): every one of the first six modifiers gives off a
## particle style, as the infusions do.
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


func test_every_first_modifier_has_a_look() -> void:
	for card: ModifierBase in CARDS:
		check(card.look_layer > 0, "%s gives off a look" % card.id)
		check(card.range_problems().is_empty(), "%s is inside every range" % card.id)
