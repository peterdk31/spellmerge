extends SceneTree
## Tests for SpellBase.cast, tick and reset_cooldowns: REFUSED for a cooldown and
## for too little mana, cooldowns that are independent for players 0-3 on one
## shared resource, tick stopping at 0, and reset_cooldowns.
##
## godot --headless --path . --script res://tests/core/test_spell_base.gd

const CountingSpell := preload("res://tests/gameplay/player/fixtures/counting_spell.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_cast_returns_cost()
	_test_refused_for_mana()
	_test_refused_for_cooldown()
	_test_players_are_independent()
	_test_tick_stops_at_zero()
	_test_reset_cooldowns()
	if _failures.is_empty():
		print("TEST OK: core/base (spell cast)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _make(cost: float, cooldown: float) -> CountingSpell:
	var spell := CountingSpell.new()
	spell.id = &"test_spell"
	spell.mana_cost = cost
	spell.cooldown = cooldown
	return spell


func _cast(spell: SpellBase, player: int, mana: float) -> float:
	return spell.cast(player, Vector2.ZERO, Vector2.RIGHT, mana)


func _test_cast_returns_cost() -> void:
	var spell := _make(10.0, 0.0)
	_check(_cast(spell, 0, 10.0) == 10.0, "a cast with exactly enough mana returns the cost")
	_check(spell.fired_players == [0], "and fires")
	_check(spell.spell_id() == &"test_spell", "spell_id gives the id")


func _test_refused_for_mana() -> void:
	var spell := _make(10.0, 0.0)
	_check(_cast(spell, 0, 9.0) == SpellBase.REFUSED, "too little mana is REFUSED")
	_check(spell.fired_players.is_empty(), "and does not fire")
	_check(_cast(spell, 0, 10.0) == 10.0, "a refusal does not start a cooldown")


func _test_refused_for_cooldown() -> void:
	var spell := _make(1.0, 0.5)
	_check(_cast(spell, 0, 50.0) == 1.0, "the first cast fires")
	_check(_cast(spell, 0, 50.0) == SpellBase.REFUSED, "a cast during the cooldown is REFUSED")
	spell.tick(0, 0.25)
	_check(_cast(spell, 0, 50.0) == SpellBase.REFUSED, "still cooling down after half of it")
	spell.tick(0, 0.25)
	_check(_cast(spell, 0, 50.0) == 1.0, "it fires again once the cooldown is over")
	_check(spell.fired_players.size() == 2, "fired twice in all")


func _test_players_are_independent() -> void:
	var spell := _make(1.0, 0.5)
	for player in 4:
		_check(_cast(spell, player, 5.0) == 1.0, "player %d can cast on the shared spell" % player)
	spell.tick(2, 0.5)
	for player in 4:
		var result: float = _cast(spell, player, 5.0)
		if player == 2:
			_check(result == 1.0, "only player 2's cooldown ran")
		else:
			_check(result == SpellBase.REFUSED, "player %d is still cooling down" % player)


func _test_tick_stops_at_zero() -> void:
	var spell := _make(1.0, 0.5)
	_cast(spell, 1, 5.0)
	spell.tick(1, 100.0)
	_check(spell._cooldown_left[1] == 0.0, "tick never goes below 0")


func _test_reset_cooldowns() -> void:
	var spell := _make(1.0, 10.0)
	for player in 4:
		_cast(spell, player, 5.0)
	spell.reset_cooldowns()
	for player in 4:
		_check(_cast(spell, player, 5.0) == 1.0, "player %d can cast after reset_cooldowns" % player)
