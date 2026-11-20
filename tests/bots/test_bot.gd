extends "res://tests/support/suite.gd"
## Tests for the bot (tests/bots/bot.gd), one behaviour per test: it takes a virtual device and
## fills its seat's input frames (the Frames autoload), an idler wants nothing, a fighter's brain
## (the enemies' AI, with the bot's profile) drives its own wizard and walks toward the enemies,
## casting with no windup (it is on the players' team), builds a random staff with a person's
## requests, and lets go of everything when the run is over; what the brain wants becomes the frame
## (the walk, the aim, a press per press, a held button per hold); the B tap goes through the input
## path to its own player only, and leaving frees the slot and the seat's frames. Bots for
## different indices never disturb each other.
##
## On the real autoloads (Events, PlayerInput, Flow, Frames), as the bots play. Only the fighter
## tests start a run (two fighters, `play_requested`); after each test every bot leaves, any run is
## stopped and the seats' leaves are applied.

const BotScript := preload("res://tests/bots/bot.gd")
const ReviveScript := preload("res://gameplay/ai/behaviours/revive.gd")

## Physics frames a fighter is given to walk (the bots think at each tick's start).
const WALK_FRAMES: int = 20
## The physics frames past the room's enemies' spawn (enemy spawning EA3: a bot walks toward the
## enemies there are, and one still spawning is not there yet: the longest `Actor.spawn_seconds` of
## the room's enemies, each its style's), and two more.
const SPAWN_EXTRA_FRAMES: int = 2

var _input: Node
var _flow: Node
var _events: Node
var _frames: Node
var _bots: Array[BotScript] = []


func before_each() -> void:
	_input = root.get_node("PlayerInput")
	_flow = root.get_node("Flow")
	_events = root.get_node("Events")
	_frames = root.get_node("Frames")
	_bots.clear()


func after_each() -> void:
	for bot in _bots:
		bot.leave()
	_bots.clear()
	_flow.call("stop_run")
	for index in 4:
		_input.call("leave", index)
	# The seats' leaves are commands: applied here, so the next test starts clean.
	await commands_applied()


## A bot of `mode` joined at `index` (it leaves after the test). Returns it, joined or not.
func _bot(index: int, mode: BotScript.Mode = BotScript.Mode.FIGHTER) -> BotScript:
	var bot := BotScript.new()
	if bot.join(index, mode, _input, _flow):
		_bots.append(bot)
	return bot


func _presses(index: int, action: StringName) -> int:
	return int(_input.call("get_press_count", index, action))


# --- The names the bot calls -------------------------------------------------------------------
# The bot calls these by name; a rename must fail here, not silently at runtime.


func test_player_input_has_what_the_bot_calls() -> void:
	for method: String in ["add_virtual_device", "send_virtual", "send_virtual_aim", "leave"]:
		check(_input.has_method(method), "PlayerInput has %s" % method)
	check(_input.get("NO_DEVICE") != null, "PlayerInput has NO_DEVICE")


func test_flow_has_what_the_bot_calls() -> void:
	for method: String in ["get_wizard", "stop_run"]:
		check(_flow.has_method(method), "Flow has %s" % method)
	check("world" in _flow, "Flow has a world property")


func test_events_has_the_signals_a_bot_run_uses() -> void:
	for signal_name: String in ["play_requested", "room_entered", "room_cleared", "player_downed", "player_revived", "spell_cast", "rewards_waiting_changed", "reward_pick_requested"]:
		check(_events.has_signal(signal_name), "Events has %s" % signal_name)


# --- Joining and leaving -----------------------------------------------------------------------


func test_a_bot_takes_a_free_slot() -> void:
	var bot := BotScript.new()
	var joined: bool = bot.join(3, BotScript.Mode.IDLER, _input, _flow)
	if joined:
		_bots.append(bot)
	check(joined, "bot 4 takes slot 3")
	check(_input.call("is_joined", 3), "slot 3 is joined")


func test_a_taken_slot_is_refused() -> void:
	_bot(0)
	check(not BotScript.new().join(0, BotScript.Mode.FIGHTER, _input, _flow), "a taken slot is refused")


func test_bots_leave_the_other_slots_free() -> void:
	_bot(0)
	_bot(3, BotScript.Mode.IDLER)
	check(not _input.call("is_joined", 1), "slot 1 stays free")


func test_leaving_frees_the_slot() -> void:
	var first: BotScript = _bot(0)
	var second: BotScript = _bot(3, BotScript.Mode.IDLER)
	first.leave()
	second.leave()
	check(not _input.call("is_joined", 0) and not _input.call("is_joined", 3), "leaving frees the slots")


func test_the_b_tap_counts_as_one_press_for_its_own_player() -> void:
	_bot(0)
	_bot(3, BotScript.Mode.IDLER).tap_back()
	check_equal(_presses(3, &"back"), 1, "the B tap counts as one press for player 4")


func test_the_b_tap_does_not_reach_another_player() -> void:
	_bot(0)
	_bot(3, BotScript.Mode.IDLER).tap_back()
	check_equal(_presses(0, &"back"), 0, "the B tap does not reach player 1")


func test_a_bot_is_its_own_seats_frame_source() -> void:
	var bot: BotScript = _bot(2)
	check(_frames.call("source_of", 2) == bot, "a bot is its seat's frame source")
	check(_frames.call("source_of", 1) == null, "and no other seat's")


func test_leaving_hands_the_seat_back() -> void:
	_bot(2).leave()
	check(_frames.call("source_of", 2) == null, "leaving hands the seat back")


# --- The idler and the builder -----------------------------------------------------------------


## The frame an idler at seat 2 fills over 10 asks.
func _idler_frame() -> InputFrame:
	var idler: BotScript = _bot(2, BotScript.Mode.IDLER)
	var frame := InputFrame.new()
	frame.seat = 2
	for i in 10:
		idler.fill_frame(frame, 0.016)
	return frame


func test_an_idler_does_not_move() -> void:
	check_equal(_idler_frame().move, Vector2i.ZERO, "an idler does not move")


func test_an_idler_does_not_cast() -> void:
	var frame: InputFrame = _idler_frame()
	check(frame.held_bits == 0 and frame.pressed_bits == 0, "an idler does not cast")


func test_a_bot_without_a_wizard_cannot_build() -> void:
	check(not _bot(1, BotScript.Mode.IDLER).build_random(1), "a bot without a wizard cannot build")


func test_a_refused_build_sends_no_request() -> void:
	var bot: BotScript = _bot(1, BotScript.Mode.IDLER)
	bot.build_random(1)
	check_equal(bot.requests_sent, 0, "a refused build sends no request")


## The way into the builder is one press of B (`back`) and nothing else.
func _opened_builder() -> void:
	var bot: BotScript = _bot(1, BotScript.Mode.IDLER)
	bot.open_builder()
	for i in 6:
		bot.step(0.016)


func test_one_b_press_opens_the_builder() -> void:
	_opened_builder()
	check_equal(_presses(1, &"back"), 1, "one B press opens the builder")


func test_opening_the_builder_presses_nothing_else() -> void:
	_opened_builder()
	check(_presses(1, &"accept") == 0 and _presses(1, &"move_down") == 0, "no other press")


# --- What the brain wants becomes the frame ----------------------------------------------------
# As the frame a person's buttons would make: the walk each axis full on or off, the aim, a press,
# a hold, a press and hold; a press lasts one frame.


## The frame as the frames service asks for it, without the brain thinking (no world: `step`
## lets go, so the frame is taken from what `send` wanted, read before the step).
func _fill(bot: BotScript, frame: InputFrame) -> void:
	var wanted: InputFrame = bot.wanted_frame()
	frame.move = wanted.move
	frame.aim = wanted.aim
	frame.held_bits = wanted.held_bits
	frame.pressed_bits = wanted.pressed_bits
	wanted.pressed_bits = 0


## A fighter at seat 1 that wanted a walk mostly right, an aim down, a press of staff 0 and a hold
## of staff 2; its frame, filled once. With `again` it then wanted staff 2 let go and staff 1
## pressed and held, and the frame is filled a second time.
func _wanted_frame(again: bool = false) -> InputFrame:
	var bot: BotScript = _bot(1)
	var wanted := ActorIntent.new()
	wanted.move = Vector2(1.0, 0.1)
	wanted.aim = Vector2(0.0, 3.0)
	wanted.press(0)
	wanted.hold(2, true)
	bot.send(wanted)
	var frame := InputFrame.new()
	frame.seat = 1
	_fill(bot, frame)
	if again:
		wanted.begin_step()
		wanted.hold(2, false)
		wanted.press(1)
		wanted.hold(1, true)
		bot.send(wanted)
		_fill(bot, frame)
	return frame


func test_the_frame_walks_each_axis_full_on_or_off() -> void:
	var frame: InputFrame = _wanted_frame()
	check_equal(frame.move_vector(), Vector2.RIGHT, "it walks the way wanted")


func test_the_frame_aims_where_wanted() -> void:
	var frame: InputFrame = _wanted_frame()
	check(frame.aim_vector().is_equal_approx(Vector2.DOWN), "it aims: %s" % frame.aim_vector())


func test_a_wanted_press_is_one_press() -> void:
	var frame: InputFrame = _wanted_frame()
	check(frame.is_pressed(0) and not frame.is_held(0), "a press is one press")


func test_a_wanted_hold_keeps_the_button_down() -> void:
	var frame: InputFrame = _wanted_frame()
	check(frame.is_held(2) and not frame.is_pressed(2), "a hold keeps the button down")


func test_a_button_let_go_is_up() -> void:
	check(not _wanted_frame(true).is_held(2), "let go, it is up")


func test_a_press_lasts_one_frame() -> void:
	check(not _wanted_frame(true).is_pressed(0), "a press lasts one frame")


func test_a_press_and_hold_presses_and_stays_down() -> void:
	var frame: InputFrame = _wanted_frame(true)
	check(frame.is_pressed(1) and frame.is_held(1), "a press and hold presses and stays down")


func test_leaving_lets_go_of_everything() -> void:
	_wanted_frame()
	var bot: BotScript = _bots[0]
	bot.leave()
	check(bot.wanted_frame().move == Vector2i.ZERO and bot.wanted_frame().held_bits == 0, "leaving lets go of everything")


# --- Fighters in a run -------------------------------------------------------------------------


## Two fighters (seats 0 and 1) in a run started by `play_requested`; bot 1's wizard, or null.
func _fighters_in_a_run() -> Node2D:
	_bot(0)
	_bot(1)
	_events.emit_signal("play_requested", 0)
	await process_frame
	var wizard := _flow.call("get_wizard", 0) as Node2D
	check(wizard != null, "the run started with a wizard for bot 1")
	return wizard


## Two fighters in a run that played WALK_FRAMES physics frames once its enemies spawned in; bot 1's wizard and where it
## started, or an empty array when the run had none.
func _fighters_who_walked() -> Array:
	var wizard: Node2D = await _fighters_in_a_run()
	if wizard == null:
		return []
	for i in ceili(_longest_spawn() * 60.0) + SPAWN_EXTRA_FRAMES:
		await physics_frame
	var before: Vector2 = wizard.global_position
	for i in WALK_FRAMES:
		await physics_frame
	return [wizard, before]


## The longest spawn of the room's enemies, in seconds (each spawns in in its own style), and never
## less than the style a body of no enemy's own picks (a body still to stand of the first group).
func _longest_spawn() -> float:
	var longest: float = (_flow.call("spawn_style_for", null) as SpawnStyle).seconds
	for enemy: Node in _flow.get("_enemies") as Array[Node]:
		if is_instance_valid(enemy):
			longest = maxf(longest, (enemy as Actor).spawn_seconds)
	return longest


func test_the_run_starts_with_a_wizard_for_the_bot() -> void:
	await _fighters_in_a_run()


func test_a_fighter_walks_toward_the_enemies() -> void:
	var walked: Array = await _fighters_who_walked()
	check(walked.size() == 2 and (walked[0] as Node2D).global_position.distance_to(walked[1]) > 1.0, "a fighter walks toward the enemies")


func test_a_fighters_brain_drives_its_own_wizard_by_the_bots_profile() -> void:
	var walked: Array = await _fighters_who_walked()
	check(walked.size() == 2 and _bots[0].brain.actor == walked[0] and _bots[0].brain.profile == BotScript.PROFILE, "its brain drives its own wizard by the bot's profile")


func test_a_fighter_on_the_players_team_winds_up_nothing() -> void:
	await _fighters_who_walked()
	check(not _bots[0].brain.warns() and _bots[0].brain.windup_for(1) == 0.0, "on the players' team: no windup")


func test_each_bot_steers_its_own_wizard() -> void:
	var walked: Array = await _fighters_who_walked()
	var other := _flow.call("get_wizard", 1) as Node2D
	check(walked.size() == 2 and other != null and other.global_position != (walked[0] as Node2D).global_position, "each bot steers its own wizard")


func test_with_no_world_a_fighter_lets_go_of_everything() -> void:
	await _fighters_who_walked()
	_flow.call("stop_run")
	await physics_frame
	var frame: InputFrame = _frames.call("frame_of", 0)
	check(frame != null and frame.move == Vector2i.ZERO and frame.aim == InputFrame.AIM_KEEP and frame.held_bits == 0 and frame.pressed_bits == 0, "with no world a fighter lets go of everything")


# --- A random build ----------------------------------------------------------------------------
# With a wizard, `build_random` sends one `staff_change_requested` per slot of staff 1, all for its
# own player, and the wizard's staff 1 holds the cards the bot chose from the next tick on (a
# command applies at the tick's start).


## Bot 1's random build in a run, applied: [the wizard's Caster, the requests the build sent as
## [player, staff, slot, card], how many requests the bot counted], or an empty array.
func _built() -> Array:
	var walked: Array = await _fighters_who_walked()
	if walked.is_empty():
		return []
	var bot: BotScript = _bots[0]
	var builds: Array = []
	var on_build := func(player: int, staff: int, slot: int, id: StringName, _body: int) -> void: builds.append([player, staff, slot, id])
	_events.connect("staff_change_requested", on_build)
	var before: int = bot.requests_sent
	check(bot.build_random(5), "a bot with a wizard builds")
	_events.disconnect("staff_change_requested", on_build)
	await commands_applied()
	return [(walked[0] as Actor).caster, builds, bot.requests_sent - before]


func test_a_random_build_sends_one_counted_request_per_slot() -> void:
	var built: Array = await _built()
	if built.is_empty():
		return
	var slots: int = (built[0] as Caster).slot_count()
	check_equal((built[1] as Array).size(), slots, "one request per slot")
	check_equal(built[2], slots, "every request counted")


func test_a_random_build_asks_only_for_its_own_player_and_staff() -> void:
	var built: Array = await _built()
	for entry: Array in (built[1] as Array if not built.is_empty() else []):
		check(entry[0] == 0 and entry[1] == BotScript.BUILD_STAFF, "a build call is for the bot's own player and staff 1: %s" % [entry])


func test_the_built_staff_holds_what_the_bot_built() -> void:
	var built: Array = await _built()
	check(not built.is_empty() and (built[0] as Caster).cards_of(BotScript.BUILD_STAFF) == _bots[0].built_cards, "staff 1 holds what the bot built")


func test_the_built_staff_can_cast() -> void:
	var built: Array = await _built()
	check(not built.is_empty() and (built[0] as Caster).has_staff(BotScript.BUILD_STAFF), "the built staff can cast")


func test_a_fighter_revives_a_downed_teammate_before_it_travels() -> void:
	# Regression (bots revive, 2026-11-19): out of a fight a fighter travels to the next one
	# (CB8), which walked it off a teammate it was reviving. In the start room, no fight on: bot 2's
	# wizard is downed (as its Downed component downs it), and bot 1 goes to it and stays.
	var wizard: Node2D = await _fighters_in_a_run()
	var mate := _flow.call("get_wizard", 1) as Actor
	if wizard == null or mate == null:
		return
	mate.set_down(true)
	for i in 60:
		await physics_frame
	check(_bots[0].brain.behaviour is ReviveScript, "bot 1 is reviving")
	check(wizard.global_position.distance_to(mate.global_position) <= ReviveScript.NEAR + 4.0, "bot 1 stands by its downed teammate (%.0f px off)" % wizard.global_position.distance_to(mate.global_position))


## Connected biomes CB3's crawl (the owner, 2026-11-19): a downed bot crawls toward the nearest
## standing teammate, never into an enemy, and stops beside it; with nobody standing it lies still.
func test_a_downed_bot_crawls_toward_its_nearest_standing_teammate() -> void:
	var wizard := await _fighters_in_a_run() as Actor
	var mate := _flow.call("get_wizard", 1) as Actor
	if wizard == null or mate == null:
		return
	mate.global_position = wizard.global_position + Vector2(96.0, 0.0)
	wizard.set_down(true)
	var way: Vector2 = _bots[0].crawl_way(wizard)
	check(way.x > 0.9, "toward the standing teammate: %s" % way)
	# An enemy just above the way: it leans away from it, down.
	var table: Node = _flow.get_node(^"/root/Actors")
	var foe := own(Node2D.new()) as Node2D
	_flow.get_parent().add_child(foe)
	foe.global_position = wizard.global_position + Vector2(20.0, -12.0)
	var id: int = table.call("open", 1, 4)
	table.call("set_node", id, foe)
	var shy: Vector2 = _bots[0].crawl_way(wizard)
	check(shy.y > 0.2 and shy.x > 0.0, "leaning away from the enemy near it, still on its way: %s" % shy)
	table.call("close", id)
	mate.global_position = wizard.global_position + Vector2(BotScript.CRAWL_BESIDE - 2.0, 0.0)
	check_equal(_bots[0].crawl_way(wizard), Vector2.ZERO, "beside the teammate it stops")
	mate.global_position = wizard.global_position + Vector2(96.0, 0.0)
	mate.set_down(true)
	check_equal(_bots[0].crawl_way(wizard), Vector2.ZERO, "nobody standing: it lies still")
	mate.set_down(false)
	# In play: the teammate stands still (an idler, so it does not come to revive), and the downed bot's
	# own frames crawl it nearer.
	_bots[1].mode = BotScript.Mode.IDLER
	_bots[1].wanted_frame().clear()
	var grid: RoomGrid = _flow.get_node(^"/root/Projectiles").call(&"grid") as RoomGrid
	var room: Rect2 = (_flow.get(&"biome") as BiomeWorld).room_rect(0)
	mate.global_position = grid.nearest_ground(room.get_center() + Vector2(48.0, 0.0), 6.0)
	wizard.global_position = grid.nearest_ground(room.get_center() - Vector2(48.0, 0.0), 6.0)
	var from: Vector2 = wizard.global_position
	var gap: float = from.distance_to(mate.global_position)
	for i in 60:
		await physics_frame
	check(wizard.global_position.x > from.x + 2.0 and wizard.global_position.distance_to(mate.global_position) < gap - 2.0, "in play its seat's frames crawl it nearer (%.0f px to %.0f)" % [gap, wizard.global_position.distance_to(mate.global_position)])


# --- Rewards (a bot never stands waiting in a reward room) -------------------------------------

## The offers `rewards_waiting_changed` would tell seat 1: one offer of number `number` with
## `choices` choices.
func _offer(number: int, choices: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var row: Array[Dictionary] = []
	for i in choices:
		row.append({"kind": ItemKinds.CARD, "id": &"bolt", "count": 1})
	list.append({"offer": number, "here": true, "choices": row})
	return list


## A fighter answers an offer waiting for its seat with the reward menu's command, on the bus (the
## frames service puts it in its seat's frame): the first choice; the next one while the same offer
## still waits (refused: a full bag); past its last choice the next offer waiting; nothing for another
## seat's offer, nor with none waiting.
func test_a_fighter_picks_the_first_choice_of_an_offer_waiting_for_it() -> void:
	var bot: BotScript = _bot(1)
	var asked: Array = []
	var hear := func(player: int, offer: int, choice: int) -> void: asked.append([player, offer, choice])
	_events.connect("reward_pick_requested", hear)
	bot.pick_reward()
	check(asked.is_empty(), "nothing waiting: nothing asked")
	_events.emit_signal("rewards_waiting_changed", 0, _offer(3, 2))
	bot.pick_reward()
	check(asked.is_empty(), "another seat's offer is not its own")
	var two: Array[Dictionary] = _offer(7, 2)
	two.append_array(_offer(8, 1))
	_events.emit_signal("rewards_waiting_changed", 1, two)
	bot.pick_reward()
	check_equal(asked, [[1, 7, 0]], "its oldest offer's first choice, as the menu's A")
	bot.pick_reward()
	check_equal(asked.back(), [1, 7, 1], "still waiting (refused): the next choice")
	bot.pick_reward()
	check_equal(asked.back(), [1, 8, 0], "every choice refused: the next offer waiting")
	asked.clear()
	bot.pick_reward()
	check(asked.is_empty(), "every choice of every offer asked: it asks no more")
	_events.emit_signal("rewards_waiting_changed", 1, _offer(7, 2))
	bot.pick_reward()
	check_equal(asked, [[1, 7, 0]], "the offers changed (one taken): it asks again from the first")
	asked.clear()
	_events.emit_signal("rewards_waiting_changed", 1, [] as Array[Dictionary])
	bot.pick_reward()
	check(asked.is_empty(), "taken: nothing waits")
	_events.disconnect("reward_pick_requested", hear)


func test_an_idler_picks_nothing() -> void:
	var bot: BotScript = _bot(1, BotScript.Mode.IDLER)
	var asked: Array = []
	var hear := func(player: int, _offer: int, _choice: int) -> void: asked.append(player)
	_events.connect("reward_pick_requested", hear)
	_events.emit_signal("rewards_waiting_changed", 1, _offer(7, 2))
	var frame := InputFrame.new()
	frame.seat = 1
	bot.fill_frame(frame, 1.0 / 60.0)
	check(asked.is_empty(), "an idler stands, as it does in a fight")
	_events.disconnect("reward_pick_requested", hear)


## In a run, through the real Rewards area and the frames service: an offer rolled for the fighters'
## room is picked within a few ticks, and its choice goes into the wizard's inventory.
func test_fighters_in_a_run_take_their_rewards() -> void:
	var wizard := await _fighters_in_a_run() as Actor
	if wizard == null:
		return
	var rewards: Node = root.get_node("Rewards")
	var taken: Array = []
	var hear := func(player: int, _offer: int, _choice: int, _reward: Dictionary) -> void: taken.append(player)
	_events.connect("reward_taken", hear)
	_events.emit_signal("room_rewards_due", wizard.room, &"clear", PackedStringArray(), PackedVector2Array())
	for i in 6:
		await physics_frame
	_events.disconnect("reward_taken", hear)
	check(taken.has(0) and taken.has(1), "each fighter took its own reward: %s" % [taken])
	check((rewards.call("waiting_of", 0) as Array).is_empty() and (rewards.call("waiting_of", 1) as Array).is_empty(), "nothing waits")
