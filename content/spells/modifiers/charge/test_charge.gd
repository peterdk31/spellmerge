extends "res://tests/support/suite.gd"
## The Charge card (content/spells/modifiers/charge/, cast timing T7; docs/milestones/
## cast-timing.md): the next carrier winds up two seconds longer, then hits four times as hard.
## Its wind-up is a cost, never an effect, so on a carrier that hits nothing it is wasted.
##
## godot --headless --path . --script res://content/spells/modifiers/charge/test_charge.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/charge/charge.tres") as ModifierBase


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "charge.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"charge", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.NONE, "numbers only")
	check(card.look_layer > 0, "its shots give off a look")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_winds_up_longer_and_hits_four_times_as_hard() -> void:
	var arena := ArenaScript.new(root)
	var plain: CompiledCast = arena.install_cards(0, 0, ["bolt"]).casts[0]
	var charged: CompiledCast = arena.install_cards(0, 1, ["charge", "bolt"]).casts[0]
	check(is_equal_approx(charged.wind_up, plain.wind_up + 2.0), "two seconds more wind-up (%s)" % charged.wind_up)
	check(is_equal_approx(charged.group.spells[0].damage, plain.group.spells[0].damage * 4.0), "four times the damage")
	check(not charged.wasted.has(0), "it counts on a bolt")
	arena.free_all()


func test_a_charged_bolt_leaves_after_its_wind_up_and_hits_harder() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	arena.install_cards(0, 0, ["charge", "bolt"])
	check(arena.cast(0, 0), "the press is taken")
	arena.run(1.5)
	check_equal(arena.projectiles.get_count(), 0, "nothing has left while it winds up")
	arena.run(1.5)
	var charged: int = arena.lost(imp)
	arena.free_all()
	arena = ArenaScript.new(root)
	imp = arena.add_imp(Vector2(100.0, 0.0))
	arena.install_cards(0, 0, ["bolt"])
	arena.cast(0, 0)
	arena.run(1.5)
	var plain: int = arena.lost(imp)
	arena.free_all()
	check(plain > 0 and charged >= plain * 3, "the charged bolt hurts far more: %d against %d" % [charged, plain])


func test_on_a_carrier_that_hits_nothing_it_is_wasted() -> void:
	var arena := ArenaScript.new(root)
	var cast: CompiledCast = arena.install_cards(0, 0, ["charge", "familiar"]).casts[0]
	check(cast.wasted.has(0), "a familiar hits nothing itself: the charge is wasted")
	arena.free_all()
