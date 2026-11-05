extends SceneTree
## Tests for the bot (tests/bots/bot.gd): it takes a virtual device and fills its seat's input
## frames (the Frames autoload), an idler wants nothing, a fighter's brain (the enemies' AI, with
## the bot's profile) drives its own wizard and walks toward the enemies, casting with no windup
## (it is on the players' team), and lets go of everything when the run is over; what the brain
## wants becomes the frame (the walk, the aim, a press per press, a held button per hold); the B
## tap goes through the input path to its own player only, and leaving frees the slot and the
## seat's frames. Bots for different indices never disturb each other.
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
	_test_fills_its_seats_frames()
	_test_idler_sends_nothing()
	_test_builder_walk()
	_test_intent_becomes_buttons()
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


## A bot fills its seat's frames while it is in, and the seat's device does again once it left.
func _test_fills_its_seats_frames() -> void:
	var frames: Node = root.get_node_or_null("Frames")
	_check(frames != null, "the Frames autoload exists")
	if frames == null:
		return
	var bot := BotScript.new()
	bot.join(2, BotScript.Mode.FIGHTER, _input, _flow)
	_check(frames.call("source_of", 2) == bot, "a bot is its seat's frame source")
	_check(frames.call("source_of", 1) == null, "and no other seat's")
	bot.leave()
	_check(frames.call("source_of", 2) == null, "leaving hands the seat back")


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
## its own player, and the wizard's staff 3 holds the cards the bot chose from the next tick on
## (a command applies at the tick's start).
func _test_build_random(events: Node, bot: BotScript, wizard: Node) -> void:
	var builds: Array = []
	var on_build := func(player: int, staff: int, slot: int, id: StringName) -> void: builds.append([player, staff, slot, id])
	events.connect("staff_change_requested", on_build)
	var before: int = bot.requests_sent
	_check(bot.build_random(5), "a bot with a wizard builds")
	events.disconnect("staff_change_requested", on_build)
	await physics_frame
	await physics_frame
	var caster: Caster = (wizard as Actor).caster
	var slots: int = caster.slot_count()
	_check(bot.requests_sent - before == builds.size() and builds.size() == slots, "one counted request per slot")
	var own: bool = true
	for entry: Array in builds:
		own = own and entry[0] == 0 and entry[1] == BotScript.BUILD_STAFF
	_check(own, "all build calls are for the bot's own player and staff 3")
	_check(caster.cards_of(BotScript.BUILD_STAFF) == bot.built_cards, "staff 3 holds what the bot built")
	_check(caster.has_staff(BotScript.BUILD_STAFF), "and it can cast")


## What the brain wants, as the frame a person's buttons would make: the walk each axis full on
## or off, the aim, a press, a hold, a press and hold; a press lasts one frame.
func _test_intent_becomes_buttons() -> void:
	var bot := BotScript.new()
	bot.join(1, BotScript.Mode.FIGHTER, _input, _flow)
	var wanted := ActorIntent.new()
	wanted.move = Vector2(1.0, 0.1)
	wanted.aim = Vector2(0.0, 3.0)
	wanted.press(0)
	wanted.hold(2, true)
	bot.send(wanted)
	var frame := InputFrame.new()
	frame.seat = 1
	_fill(bot, frame)
	_check(frame.move_vector() == Vector2.RIGHT, "it walks the way wanted: %s" % frame.move_vector())
	_check(frame.aim_vector().is_equal_approx(Vector2.DOWN), "and aims: %s" % frame.aim_vector())
	_check(frame.is_pressed(0) and not frame.is_held(0), "a press is one press")
	_check(frame.is_held(2) and not frame.is_pressed(2), "a hold keeps the button down")
	wanted.begin_step()
	wanted.hold(2, false)
	wanted.press(1)
	wanted.hold(1, true)
	bot.send(wanted)
	_fill(bot, frame)
	_check(not frame.is_held(2), "let go, it is up")
	_check(not frame.is_pressed(0), "a press lasts one frame")
	_check(frame.is_pressed(1) and frame.is_held(1), "a press and hold presses and stays down")
	bot.leave()
	_check(bot.wanted_frame().move == Vector2i.ZERO and bot.wanted_frame().held_bits == 0, "leaving lets go of everything")


## The frame as the frames service asks for it, without the brain thinking (no world: `step`
## lets go, so the frame is taken from what `send` wanted, read before the step).
func _fill(bot: BotScript, frame: InputFrame) -> void:
	var wanted: InputFrame = bot.wanted_frame()
	frame.move = wanted.move
	frame.aim = wanted.aim
	frame.held_bits = wanted.held_bits
	frame.pressed_bits = wanted.pressed_bits
	wanted.pressed_bits = 0


func _test_idler_sends_nothing() -> void:
	var idler := BotScript.new()
	idler.join(2, BotScript.Mode.IDLER, _input, _flow)
	var frame := InputFrame.new()
	frame.seat = 2
	for i in 10:
		idler.fill_frame(frame, 0.016)
	_check(frame.move == Vector2i.ZERO, "an idler does not move")
	_check(frame.held_bits == 0 and frame.pressed_bits == 0, "an idler does not cast")
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
		# The bots think at each tick's start (the Frames autoload asks them for their frames).
		for i in 20:
			await physics_frame
		_check(wizard.global_position.distance_to(before) > 1.0, "a fighter walks toward the enemies")
		_check(bots[0].brain.actor == wizard and bots[0].brain.profile == BotScript.PROFILE, "its brain drives its own wizard by the bot's profile")
		_check(not bots[0].brain.warns() and bots[0].brain.windup_for(1) == 0.0, "on the players' team: no windup")
		var other := _flow.call("get_wizard", 1) as Node2D
		_check(other != null and other.global_position != wizard.global_position, "each bot steers its own wizard")
		await _test_build_random(events, bots[0], wizard)
	_flow.call("stop_run")
	await physics_frame
	var frames: Node = root.get_node_or_null("Frames")
	var frame: InputFrame = frames.call("frame_of", 0) if frames != null else null
	_check(frame != null and frame.move == Vector2i.ZERO and frame.aim == InputFrame.AIM_KEEP and frame.held_bits == 0 and frame.pressed_bits == 0, "with no world a fighter lets go of everything")
	for bot in bots:
		bot.leave()
