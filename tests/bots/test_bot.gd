extends SceneTree
## Tests for the bot (tests/bots/bot.gd): it takes a virtual device, an idler sends
## nothing, a fighter walks toward the enemies and lets go of every input when the
## run is over, the B tap goes through the input path to its own player only,
## and leaving frees the slot. Bots for different indices never disturb each other. Enemies
## are found in the world and one level down under its `Horde` node (a horde run's).
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
	_test_enemies_under_the_horde_node_are_found()
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
	for method in ["add_virtual_device", "send_virtual", "send_virtual_aim", "leave"]:
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
	second.tap_back()
	_check(int(_input.call("get_press_count", 3, &"back")) == 1, "the B tap counts as one press for player 4")
	_check(int(_input.call("get_press_count", 0, &"back")) == 0, "the B tap does not reach player 1")
	first.leave()
	second.leave()
	_check(not _input.call("is_joined", 0) and not _input.call("is_joined", 3), "leaving frees the slots")


## The way into the builder is one press of B (`back`) and nothing else; without a wizard a bot
## cannot build and sends nothing.
func _test_builder_walk() -> void:
	var bot := BotScript.new()
	bot.join(1, BotScript.Mode.IDLER, _input, _flow)
	_check(not bot.build_random(1), "a bot without a wizard cannot build")
	_check(bot.requests_sent == 0, "a refused build sends no request")
	bot.open_builder()
	for i in 6:
		bot.step(0.016)
	_check(int(_input.call("get_press_count", 1, &"back")) == 1, "one B press opens the builder")
	_check(int(_input.call("get_press_count", 1, &"accept")) == 0 and int(_input.call("get_press_count", 1, &"move_down")) == 0, "and no other press")
	bot.leave()


## With a wizard, `build_random` sends one `staff_change_requested` per slot of staff 3, all for
## its own player, and the wizard's staff 3 then holds the cards the bot chose.
func _test_build_random(events: Node, bot: BotScript, wizard: Node) -> void:
	var builds: Array = []
	var on_build := func(player: int, staff: int, slot: int, id: StringName) -> void: builds.append([player, staff, slot, id])
	events.connect("staff_change_requested", on_build)
	var before: int = bot.requests_sent
	_check(bot.build_random(5), "a bot with a wizard builds")
	events.disconnect("staff_change_requested", on_build)
	var caster: Caster = (wizard as Actor).caster
	var slots: int = caster.slot_count()
	_check(bot.requests_sent - before == builds.size() and builds.size() == slots, "one counted request per slot")
	var own: bool = true
	for entry: Array in builds:
		own = own and entry[0] == 0 and entry[1] == BotScript.BUILD_STAFF
	_check(own, "all build calls are for the bot's own player and staff 3")
	_check(caster.cards_of(BotScript.BUILD_STAFF) == bot.built_cards, "staff 3 holds what the bot built")
	_check(caster.has_staff(BotScript.BUILD_STAFF), "and it can cast")


## A staff whose next cast puts up a wall (owner, 2026-11-01) is a guard staff: never held with the
## attack (its wall would stand in front of the bot's own bolts), tapped toward a threat instead.
func _test_a_wall_staff_is_cover(bot: BotScript, wizard: Actor) -> void:
	wizard.caster.set_staff(BotScript.BUILD_STAFF, [&"wall"] as Array[StringName])
	wizard.caster.set_staff(1, [&"bolt"] as Array[StringName])
	_check(bool(bot.call("_is_guard", wizard, BotScript.BUILD_STAFF)), "a wall staff is a guard staff")
	_check(not bool(bot.call("_is_guard", wizard, 1)), "a bolt staff is not")
	bot.call("_hold_attack", wizard, true)
	_check(_input.call("is_action_pressed", 0, &"staff_2"), "the attack holds the bolt staff")
	_check(not _input.call("is_action_pressed", 0, &"staff_3"), "but never the wall staff")
	var threat := Node2D.new()
	threat.position = wizard.global_position + Vector2(60.0, 0.0)
	root.add_child(threat)
	var presses: int = int(_input.call("get_press_count", 0, &"staff_3"))
	bot.call("_cover_or_dash", wizard, threat)
	_check(int(_input.call("get_press_count", 0, &"staff_3")) == presses + 1, "a threat taps the wall staff")
	_check((_input.call("get_aim", 0) as Vector2).is_equal_approx(Vector2.RIGHT), "aimed at the threat")
	bot.call("_release")
	_check((_input.call("get_aim", 0) as Vector2) == Vector2.ZERO and not _input.call("is_action_pressed", 0, &"staff_2"), "letting go frees the aim and the staffs")
	threat.free()


## An enemy actor at `at` under `parent`; an AI drives it (set once it is ready, which takes
## the home controller it has none of).
func _enemy(parent: Node, at: Vector2) -> Actor:
	var enemy := Actor.new()
	enemy.position = at
	parent.add_child(enemy)
	enemy.controller = AIController.new()
	return enemy


func _test_enemies_under_the_horde_node_are_found() -> void:
	var bot := BotScript.new()
	var world := Node2D.new()
	root.add_child(world)
	var outside: Actor = _enemy(world, Vector2(100.0, 0.0))
	_check(bot.call("_nearest_enemy", world, Vector2.ZERO) == outside, "without a horde, the world's own enemy")
	var horde := Node2D.new()
	horde.name = "Horde"
	world.add_child(horde)
	var inside: Actor = _enemy(horde, Vector2(20.0, 0.0))
	_check(bot.call("_nearest_enemy", world, Vector2.ZERO) == inside, "a nearer enemy under the Horde node is found")
	inside.position = Vector2(300.0, 0.0)
	_check(bot.call("_nearest_enemy", world, Vector2.ZERO) == outside, "the world's nearer one still wins")
	world.remove_child(outside)
	_check(bot.call("_nearest_enemy", world, Vector2.ZERO) == inside, "a horde alone is found")
	for enemy: Actor in [outside, inside]:
		enemy.controller.free()
	outside.free()
	root.remove_child(world)
	world.free()


func _test_idler_sends_nothing() -> void:
	var idler := BotScript.new()
	idler.join(2, BotScript.Mode.IDLER, _input, _flow)
	for i in 10:
		idler.step(0.016)
	_check(_input.call("get_move", 2) == Vector2.ZERO, "an idler does not move")
	_check(not _input.call("is_action_pressed", 2, &"staff_2"), "an idler does not cast")
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
		_test_a_wall_staff_is_cover(bots[0], wizard as Actor)
	_flow.call("stop_run")
	for bot in bots:
		bot.step(0.016)
	_check(_input.call("get_move", 0) == Vector2.ZERO and not _input.call("is_action_pressed", 0, &"staff_2"), "with no world a fighter lets go of every input")
	for bot in bots:
		bot.leave()
