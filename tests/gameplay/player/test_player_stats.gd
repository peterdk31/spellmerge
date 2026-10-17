extends SceneTree
## Tests for the `player_stats_changed` event of gameplay/player (what the HUD
## shows): sent when a wizard appears, on a health change (hit, revive), when
## mana is spent and when regenerating mana crosses a whole number, and not
## when nothing changed. Four wizards at once keep their own numbers.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_stats.gd

const PlayerScript := preload("res://gameplay/player/player.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const CountingSpell := preload("res://tests/gameplay/player/fixtures/counting_spell.gd")

const STEP: float = 0.0625

var _failures: Array[String] = []
var _bus: Node
var _input: Node
var _registry: Node
var _players: Array[PlayerScript] = []
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
	for player in _players:
		player.free()
	_players.clear()
	for node: Node in [_input, _registry, _bus]:
		if node != null:
			node.free()
	_input = null
	_registry = null
	_bus = null
	_stats.clear()


func _setup(count: int) -> void:
	_teardown()
	_bus = EventsScript.new()
	_input = InputManagerScript.new()
	_input.events = _bus
	_registry = RegistryScript.new()
	_bus.player_stats_changed.connect(func(p: int, h: int, mh: int, m: float, mm: float) -> void:
		_stats.append([p, h, mh, m, mm]))
	for index in count:
		_input.add_virtual_device(index)
		var player := PlayerScript.new()
		player.index = index
		player.input = _input
		player.events = _bus
		player.registry = _registry
		player._ready()
		_players.append(player)


func _test_sent_when_the_wizard_appears() -> void:
	_setup(1)
	_check(_stats.size() == 1, "one event when the wizard appears, got %d" % _stats.size())
	if _stats.is_empty():
		return
	_check(_stats[0] == [0, PlayerScript.MAX_HEALTH, PlayerScript.MAX_HEALTH, PlayerScript.MAX_MANA, PlayerScript.MAX_MANA],
		"the first event carries full health and mana, got %s" % [_stats[0]])


func _test_hit_and_revive() -> void:
	_setup(1)
	_stats.clear()
	_bus.damage_dealt.emit(-1, _players[0], 30, Vector2.ZERO)
	_check(_stats.size() == 1 and _stats[0][1] == 70, "a hit of 30 sends health 70, got %s" % [_stats])
	_bus.damage_dealt.emit(-1, _players[0], 100, Vector2.ZERO)
	_check(_players[0].is_downed() and _stats.back()[1] == 0, "being downed sends health 0")
	_stats.clear()
	_players[0].revive(1)
	_check(_stats.size() == 1 and _stats[0][1] == PlayerScript.REVIVE_HEALTH, "a revive sends the revive health, got %s" % [_stats])


func _test_nothing_changed_sends_nothing() -> void:
	_setup(1)
	_stats.clear()
	_players[0].step(0.01)  # full mana stays full
	_check(_stats.is_empty(), "no event when nothing changed, got %d" % _stats.size())
	_players[0].take_damage(0)
	_check(_stats.is_empty(), "a hit of 0 sends nothing")


func _test_mana_spent_and_regenerated() -> void:
	_setup(1)
	var spell: CountingSpell = CountingSpell.new()
	spell.id = &"test_spell"
	spell.mana_cost = 25.0
	spell.cooldown = 0.0
	_players[0].spell = spell
	_stats.clear()
	_check(_players[0].cast(), "the cast fires")
	_check(_stats.size() == 1 and _stats[0][3] == 75.0, "spending 25 mana sends mana 75, got %s" % [_stats])
	_stats.clear()
	# 0.0625 s * 10 mana/s = 0.625: two steps cross one whole number, not two events per step.
	_players[0].step(STEP)
	_players[0].step(STEP)
	_check(_stats.size() == 1, "regenerating 1.25 mana crosses one whole number once, got %d events" % _stats.size())
	_check(_stats.size() == 1 and _stats[0][3] == 76.0, "regenerated mana is whole numbers, got %s" % [_stats])


func _test_four_wizards_keep_their_own_numbers() -> void:
	_setup(4)
	_stats.clear()
	_bus.damage_dealt.emit(-1, _players[2], 40, Vector2.ZERO)
	_check(_stats.size() == 1 and _stats[0][0] == 2 and _stats[0][1] == 60, "only player 2 reports its hit, got %s" % [_stats])
	_stats.clear()
	_bus.damage_dealt.emit(-1, _players[3], 10, Vector2.ZERO)
	_check(_stats.size() == 1 and _stats[0][0] == 3 and _stats[0][1] == 90, "only player 3 reports its hit, got %s" % [_stats])
	_check(_players[0].health == PlayerScript.MAX_HEALTH and _players[1].health == PlayerScript.MAX_HEALTH, "players 0 and 1 are untouched")
