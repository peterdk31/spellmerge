extends SceneTree
## Tests for the `player_stats_changed` event of gameplay/player (what the HUD
## shows): sent when a wizard appears, on a health change (hit, revive), when
## mana is spent and when regenerating mana crosses a whole number, and not
## when nothing changed. Four wizards at once keep their own numbers. The seat
## (the wizard's PlayerController) sends it for the wizard it drives (actors G7).
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_stats.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")

const STEP: float = 0.0625

var _failures: Array[String] = []
var _world: Fixture = null
var _players: Array[Actor] = []
## Every event as [player, health, max_health, mana, max_mana].
var _stats: Array[Array] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_sent_when_the_wizard_appears()
	_test_hit_and_revive()
	_test_nothing_changed_sends_nothing()
	_test_mana_spent_and_regenerated()
	_test_four_wizards_keep_their_own_numbers()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: gameplay/player (player_stats_changed)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _teardown() -> void:
	if _world != null:
		_world.free_all()
	_world = null
	_players.clear()
	_stats.clear()


func _setup(count: int) -> void:
	_teardown()
	_world = Fixture.new(root, true)
	_world.bus.player_stats_changed.connect(func(p: int, h: int, mh: int, m: float, mm: float) -> void:
		_stats.append([p, h, mh, m, mm]))
	for index in count:
		_players.append(_world.wizard(index, Vector2(40.0 * index, 0.0)))


func _test_sent_when_the_wizard_appears() -> void:
	_setup(1)
	_check(_stats.size() == 1, "one event when the wizard appears, got %d" % _stats.size())
	if _stats.is_empty():
		return
	var wizard: Actor = _players[0]
	_check(_stats[0] == [0, wizard.health.max_health, wizard.health.max_health, wizard.caster.max_mana, wizard.caster.max_mana],
		"the first event carries full health and mana, got %s" % [_stats[0]])


func _test_hit_and_revive() -> void:
	_setup(1)
	_stats.clear()
	_world.combat.hit(-1, _players[0], 30)
	_check(_stats.size() == 1 and _stats[0][1] == 70, "a hit of 30 sends health 70, got %s" % [_stats])
	_world.combat.hit(-1, _players[0], 100)
	_check(_players[0].is_down() and _stats.back()[1] == 0, "being downed sends health 0")
	_stats.clear()
	Fixture.downed(_players[0]).revive(1)
	_check(_stats.size() == 1 and _stats[0][1] == Downed.REVIVE_HEALTH, "a revive sends the revive health, got %s" % [_stats])


func _test_nothing_changed_sends_nothing() -> void:
	_setup(1)
	_stats.clear()
	_players[0].step(0.01)  # full mana stays full
	_check(_stats.is_empty(), "no event when nothing changed, got %d" % _stats.size())
	_players[0].health.take(0)
	_check(_stats.is_empty(), "a hit of 0 sends nothing")


func _test_mana_spent_and_regenerated() -> void:
	_setup(1)
	_world.fake.cost = 25.0
	_players[0].caster.set_staff(0, [&"bolt"] as Array[StringName])
	_stats.clear()
	_check(_players[0].caster.cast(0), "the cast fires")
	_check(_stats.size() == 1 and _stats[0][3] == 75.0, "spending 25 mana sends mana 75, got %s" % [_stats])
	_stats.clear()
	# 0.0625 s * 10 mana/s = 0.625: two steps cross one whole number, not two events per step.
	# The seat looks at the mana when it thinks, before the Caster regenerates, so the crossing
	# is announced the step after it (actors G7: one step later than the old wizard).
	_players[0].step(STEP)
	_players[0].step(STEP)
	_check(_stats.is_empty(), "the crossing is not announced in the step it happens, got %s" % [_stats])
	_players[0].step(STEP)
	_check(_stats.size() == 1, "regenerating 1.25 mana crosses one whole number once, got %d events" % _stats.size())
	_check(_stats.size() == 1 and _stats[0][3] == 76.0, "regenerated mana is whole numbers, got %s" % [_stats])


func _test_four_wizards_keep_their_own_numbers() -> void:
	_setup(4)
	_stats.clear()
	_world.combat.hit(-1, _players[2], 40)
	_check(_stats.size() == 1 and _stats[0][0] == 2 and _stats[0][1] == 60, "only player 2 reports its hit, got %s" % [_stats])
	_stats.clear()
	_world.combat.hit(-1, _players[3], 10)
	_check(_stats.size() == 1 and _stats[0][0] == 3 and _stats[0][1] == 90, "only player 3 reports its hit, got %s" % [_stats])
	_check(_players[0].health.health == _players[0].health.max_health and _players[1].health.health == _players[1].health.max_health,
		"players 0 and 1 are untouched")
