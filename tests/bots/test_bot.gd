extends SceneTree
## Tests for the bot (tests/bots/bot.gd): it takes a virtual device, an idler sends
## nothing, a fighter walks toward the enemies and lets go of every input when the
## run is over, the overlay tap goes through the input path to its own player only,
## and leaving frees the slot. Bots for different indices never disturb each other.
##
## godot --headless --path . --script res://tests/bots/test_bot.gd

const BotScript := preload("res://tests/bots/bot.gd")

var _failures: Array[String] = []
var _input: Node
var _flow: Node


func _initialize() -> void:
	await process_frame
	_input = root.get_node_or_null("PlayerInput")
	_flow = root.get_node_or_null("Flow")
	var events: Node = root.get_node_or_null("Events")
	if _input == null or _flow == null or events == null:
		printerr("TEST FAILED: the Events, PlayerInput and Flow autoloads must exist")
		quit(1)
		return
	_test_join_and_leave()
	_test_idler_sends_nothing()
	await _test_fighter(events)
	if _failures.is_empty():
		print("TEST OK: tests/bots")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_join_and_leave() -> void:
	var first := BotScript.new()
	var second := BotScript.new()
	var clash := BotScript.new()
	_check(first.join(0, BotScript.Mode.FIGHTER, _input, _flow), "bot 1 takes slot 0")
	_check(second.join(3, BotScript.Mode.IDLER, _input, _flow), "bot 4 takes slot 3")
	_check(not clash.join(0, BotScript.Mode.FIGHTER, _input, _flow), "a taken slot is refused")
	_check(_input.call("is_joined", 0) and _input.call("is_joined", 3), "both slots are joined")
	_check(not _input.call("is_joined", 1), "slot 1 stays free")
	second.tap_overlay()
	_check(int(_input.call("get_press_count", 3, &"overlay")) == 1, "the overlay tap counts as one press for player 4")
	_check(int(_input.call("get_press_count", 0, &"overlay")) == 0, "the overlay tap does not reach player 1")
	first.leave()
	second.leave()
	_check(not _input.call("is_joined", 0) and not _input.call("is_joined", 3), "leaving frees the slots")


func _test_idler_sends_nothing() -> void:
	var idler := BotScript.new()
	idler.join(2, BotScript.Mode.IDLER, _input, _flow)
	for i in 10:
		idler.step(0.016)
	_check(_input.call("get_move", 2) == Vector2.ZERO, "an idler does not move")
	_check(not _input.call("is_action_pressed", 2, &"cast"), "an idler does not cast")
	idler.leave()


func _test_fighter(events: Node) -> void:
	var bots: Array[BotScript] = []
	for index in 2:
		var bot := BotScript.new()
		bot.join(index, BotScript.Mode.FIGHTER, _input, _flow)
		bots.append(bot)
	events.emit_signal("play_requested", 0)
	await process_frame
	var wizard := _flow.call("get_wizard", 0) as Node2D
	_check(wizard != null, "the run started with a wizard for bot 1")
	if wizard != null:
		var before: Vector2 = wizard.global_position
		for i in 20:
			for bot in bots:
				bot.step(0.016)
			await physics_frame
		_check(wizard.global_position.distance_to(before) > 1.0, "a fighter walks toward the enemies")
		var other := _flow.call("get_wizard", 1) as Node2D
		_check(other != null and other.global_position != wizard.global_position, "each bot steers its own wizard")
	_flow.call("stop_run")
	for bot in bots:
		bot.step(0.016)
	_check(_input.call("get_move", 0) == Vector2.ZERO and not _input.call("is_action_pressed", 0, &"cast"), "with no world a fighter lets go of every input")
	for bot in bots:
		bot.leave()
