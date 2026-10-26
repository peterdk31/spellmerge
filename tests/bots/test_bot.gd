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
	_test_names_exist(events)
	_test_join_and_leave()
	_test_idler_sends_nothing()
	_test_builder_walk()
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


## The bot calls these by name; a rename must fail here, not silently at runtime.
func _test_names_exist(events: Node) -> void:
	for method in ["add_virtual_device", "send_virtual", "leave"]:
		_check(_input.has_method(method), "PlayerInput has %s" % method)
	_check(_input.get("NO_DEVICE") != null, "PlayerInput has NO_DEVICE")
	for method in ["get_wizard", "stop_run"]:
		_check(_flow.has_method(method), "Flow has %s" % method)
	_check("world" in _flow, "Flow has a world property")
	for signal_name in ["play_requested", "room_entered", "room_cleared", "player_downed", "player_revived", "spell_cast"]:
		_check(events.has_signal(signal_name), "Events has %s" % signal_name)


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


## The way into the builder is the overlay tap, then one `move_down` and one `cast_a` press on
## later steps; without a wizard a bot cannot build and sends nothing.
func _test_builder_walk() -> void:
	var bot := BotScript.new()
	bot.join(1, BotScript.Mode.IDLER, _input, _flow)
	_check(not bot.build_random(1), "a bot without a wizard cannot build")
	_check(bot.requests_sent == 0, "a refused build sends no request")
	bot.open_builder()
	_check(int(_input.call("get_press_count", 1, &"overlay")) == 1, "the way into the builder starts with the overlay")
	var cast_before_down: bool = false
	for i in 6:
		bot.step(0.016)
		if int(_input.call("get_press_count", 1, &"cast_a")) > 0 and int(_input.call("get_press_count", 1, &"move_down")) == 0:
			cast_before_down = true
	_check(not cast_before_down, "move_down is pressed before cast on the way to Build")
	_check(int(_input.call("get_press_count", 1, &"move_down")) == 1, "one move_down press on the way")
	_check(int(_input.call("get_press_count", 1, &"cast_a")) == 1, "one cast_a press on the way, on Build")
	bot.leave()


## With a wizard, `build_random` sends one `staff_change_requested` per slot of staff Y, all for
## its own player, and the wizard's staff Y then holds the cards the bot chose.
func _test_build_random(events: Node, bot: BotScript, wizard: Node) -> void:
	var builds: Array = []
	var on_build := func(player: int, staff: int, slot: int, id: StringName) -> void: builds.append([player, staff, slot, id])
	events.connect("staff_change_requested", on_build)
	var before: int = bot.requests_sent
	_check(bot.build_random(5), "a bot with a wizard builds")
	events.disconnect("staff_change_requested", on_build)
	var slots: int = int(wizard.call("slot_count"))
	_check(bot.requests_sent - before == builds.size() and builds.size() == slots, "one counted request per slot")
	var own: bool = true
	for entry: Array in builds:
		own = own and entry[0] == 0 and entry[1] == BotScript.BUILD_STAFF
	_check(own, "all build calls are for the bot's own player and staff Y")
	_check(wizard.call("cards_of", BotScript.BUILD_STAFF) == bot.built_cards, "staff Y holds what the bot built")
	_check(bool(wizard.call("has_staff", BotScript.BUILD_STAFF)), "and it can cast")


func _test_idler_sends_nothing() -> void:
	var idler := BotScript.new()
	idler.join(2, BotScript.Mode.IDLER, _input, _flow)
	for i in 10:
		idler.step(0.016)
	_check(_input.call("get_move", 2) == Vector2.ZERO, "an idler does not move")
	_check(not _input.call("is_action_pressed", 2, &"cast_x"), "an idler does not cast")
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
		_test_build_random(events, bots[0], wizard)
	_flow.call("stop_run")
	for bot in bots:
		bot.step(0.016)
	_check(_input.call("get_move", 0) == Vector2.ZERO and not _input.call("is_action_pressed", 0, &"cast_x"), "with no world a fighter lets go of every input")
	for bot in bots:
		bot.leave()
