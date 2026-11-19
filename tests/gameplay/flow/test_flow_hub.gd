extends "res://tests/support/suite.gd"
## The hub (docs/milestones/online-lobby.md, L1): `hub_requested` (the main menu's Play) starts the
## hub room with three training dummies and no enemies; players join and leave in any order; hits hurt,
## but a wizard downed there stands up by itself at full health a moment later and nothing restarts
## (owner, 2026-11-13); the teleporter stone is lit only while every wizard stands on it (put out by
## one stepping off or by a new join at once), and then the command `run_requested` (a seat's A)
## starts a run, every seat keeping its staffs, whose end (won or lost) brings everyone back to the hub.
## Uses the real autoloads; time moves through Flow.step(), and commands are applied as the frames
## service applies them at a tick's start (`Events.apply_command`), unless a test says otherwise.

const FlowScript := preload("res://gameplay/flow/flow.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")

const DT: float = 1.0 / 60.0
## The items on the hub's rack: the Wild star and the seven premade builds (content/items/staffs/;
## the two showcase builds of crypt rework CR-S among them).
const HUB_RACK: int = 8

var flow: FlowScript
var input: Node
var events: Node
var frames: Node
var combat: Node
## Every `start_stone_changed`, as (standing, wizards, lit).
var stone: Array[Vector3i] = []
var hits: int = 0


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	events = root.get_node("Events")
	frames = root.get_node("Frames")
	combat = root.get_node("Combat")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	stone.clear()
	hits = 0
	events.connect("start_stone_changed", _on_stone)
	events.connect("hit_landed", _on_hit_landed)


func after_each() -> void:
	events.disconnect("start_stone_changed", _on_stone)
	events.disconnect("hit_landed", _on_hit_landed)
	flow.run_id_to_play = FlowScript.DEFAULT_RUN_ID
	flow.stop_run()
	flow.world_parent = null
	for index in 4:
		input.leave(index)
	# The joins and leaves this test asked for are commands waiting for a tick: apply them now, so
	# they never pile up across the file past what a frame holds.
	await commands_applied()


func _on_stone(standing: int, wizards: int, lit: bool) -> void:
	stone.append(Vector3i(standing, wizards, 1 if lit else 0))


func _on_hit_landed(_by: int, _target: Node, _amount: float, _at: Vector2, _kind: StringName, _shot: int) -> void:
	hits += 1


func _start(seats: Array) -> void:
	for seat: int in seats:
		input.add_virtual_device(seat)
	events.emit_signal("hub_requested", seats[0] if not seats.is_empty() else 0)


func _room() -> RoomBase:
	return root.get_node("Registry").call("get_resource", &"rooms", FlowScript.HUB_ROOM_ID) as RoomBase


func _wizards() -> Array[Actor]:
	var found: Array[Actor] = []
	for index in 4:
		var wizard := flow.get_wizard(index) as Actor
		if wizard != null:
			found.append(wizard)
	return found


## The last `start_stone_changed`, or (-1, -1, -1) for none.
func _last() -> Vector3i:
	return stone.back() if not stone.is_empty() else Vector3i(-1, -1, -1)


## Put seat `seat`'s wizard on the stone (spread round its centre) or off it, below.
func _place(seat: int, on: bool) -> void:
	var centre: Vector2 = HubRules.area_of(_room().places(), HubRules.ROLE_RUN_START).get_center()
	var wizard := flow.get_wizard(seat)
	wizard.position = centre + Vector2(-24.0 + 16.0 * seat, 8.0) if on else centre + Vector2(0.0, 160.0)


## The next physics step starts: the frames service sends a run's start the game asked for.
func from_frames() -> void:
	frames.call(&"begin_step", DT)


## The run is over: the ticks of the party's departure for the hub pass (Departure.TICKS), and the
## frames service sends the hub's start as the next step starts.
func _home() -> void:
	check(flow.departure.is_under_way(), "the party departs for the hub first")
	for i in Departure.TICKS:
		_tick()
	from_frames()


## One tick of Flow.
func _tick() -> void:
	flow.step(DT)


## Seat `seat` presses A on the stone: the command as a tick's start applies it, and the ticks of
## the party's departure pass (on a lit stone the run starts on the last; Departure.TICKS).
func _press_a(seat: int) -> void:
	_press_a_only(seat)
	for i in Departure.TICKS:
		_tick()


## Seat `seat` presses A on the stone, and no tick passes.
func _press_a_only(seat: int) -> void:
	events.call("apply_command", &"run_requested", [seat])


func _stop() -> void:
	flow.stop_run()
	for index in 4:
		input.leave(index)
	stone.clear()


func test_play_starts_the_hub_with_three_dummies_and_no_enemies() -> void:
	for count: int in [1, 2, 4]:
		_start(range(count))
		check_equal(flow.mode, FlowScript.MODE_HUB, "%d players: the hub" % count)
		check_equal(flow.room_id, FlowScript.HUB_ROOM_ID, "%d players: the hub's room" % count)
		check_equal(_wizards().size(), count, "%d players: a wizard each" % count)
		var ids: Array[StringName] = []
		for dummy: Node in flow.dummies():
			ids.append((dummy.get("data") as EnemyBase).id)
		check_equal(ids, [&"training_dummy", &"training_dummy", &"training_dummy"] as Array[StringName], "%d players: three training dummies" % count)
		check_equal(flow.enemies_left(), 0, "%d players: no enemies" % count)
		check_equal(_last(), Vector3i(0, count, 0), "%d players: the stone says nobody is on it" % count)
		check(not flow.is_stone_lit(), "%d players: the stone is dark" % count)
		flow.stop_run()
		check_equal(_last(), Vector3i(0, 0, 0), "%d players: leaving the hub says so" % count)
		_stop()


func test_players_join_and_leave_in_any_order() -> void:
	for order: Array in [[0, 1, 2, 3], [3, 1, 0, 2], [2, 3]]:
		_start([order[0]])
		for seat: int in order.slice(1):
			input.add_virtual_device(seat)
			check(flow.get_wizard(seat) != null, "order %s: seat %d's wizard appears" % [order, seat])
			var wizard := flow.get_wizard(seat) as Actor
			check(not wizard.health.invincible, "order %s: hits hurt a joiner" % [order])
			check(not wizard.health.is_protected(), "order %s: a joiner needs no protection there" % [order])
			check_equal(_last().y, _wizards().size(), "order %s: the stone counts the joiner at once" % [order])
		check_equal(_wizards().size(), order.size(), "order %s: everyone is in" % [order])
		var leaving: Array = order.duplicate()
		leaving.reverse()
		for seat: int in leaving.slice(0, leaving.size() - 1):
			input.leave(seat)
			check(flow.get_wizard(seat) == null, "order %s: seat %d's wizard is gone" % [order, seat])
		check_equal(_last(), Vector3i(0, 1, 0), "order %s: the stone counts the one left at once" % [order])
		check_equal(flow.mode, FlowScript.MODE_HUB, "order %s: still the hub" % [order])
		_stop()


func test_the_stone_lights_only_with_every_wizard_on_it() -> void:
	_start([0, 1, 2])
	_place(0, true)
	_place(1, true)
	_tick()
	check_equal(_last(), Vector3i(2, 3, 0), "two of three on it")
	check(not flow.is_stone_lit(), "not lit with one off")
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_HUB, "A on a dark stone starts nothing")
	_place(2, true)
	_tick()
	check_equal(_last(), Vector3i(3, 3, 1), "all three on it: lit")
	_place(1, false)
	_tick()
	check(not flow.is_stone_lit(), "one stepping off puts it out")
	_place(1, true)
	_tick()
	check(flow.is_stone_lit(), "lit again")
	input.add_virtual_device(3)
	check_equal(_last(), Vector3i(3, 4, 0), "a joiner puts it out at once")
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_HUB, "A in the tick a wizard joined starts nothing")


## The hub's stone and altar are props (props W8) standing where the room places them; the stone
## prop lights with the stone and goes out with it, playing its cue once as it lights.
func test_the_stone_prop_follows_the_stone() -> void:
	var cues: Array[StringName] = []
	var hear := func(_caster: int, cue: StringName, _at: Vector2, _dir: Vector2, _size: float, _tint: Color, _look: int) -> void: cues.append(cue)
	events.connect("cue_shown", hear)
	_start([0, 1])
	var ids: Array[StringName] = []
	var stone_prop: Actor = null
	for node: Node in flow.room_props():
		var prop := node as Actor
		ids.append(prop.prop.id)
		if prop.prop.id == &"hub_stone":
			stone_prop = prop
	check_equal(ids, [&"hub_stone", &"hub_altar"] as Array[StringName], "the stone and the altar stand")
	check(stone_prop != null and HubRules.area_of(_room().places(), HubRules.ROLE_RUN_START).has_point(stone_prop.position), "the stone prop on the stone")
	if stone_prop == null:
		events.disconnect("cue_shown", hear)
		return
	check_equal(stone_prop.state_triggers.state_id(), HubRules.UNLIT, "dark at the start")
	_place(0, true)
	_tick()
	check_equal(stone_prop.state_triggers.state_id(), HubRules.UNLIT, "dark with one of two on it")
	_place(1, true)
	_tick()
	check_equal(stone_prop.state_triggers.state_id(), HubRules.LIT, "lit with both")
	_tick()
	check_equal(cues.count(&"stone_lit"), 1, "its cue once as it lights")
	_place(1, false)
	_tick()
	check_equal(stone_prop.state_triggers.state_id(), HubRules.UNLIT, "out as one steps off")
	_place(1, true)
	_tick()
	input.add_virtual_device(2)
	check_equal(stone_prop.state_triggers.state_id(), HubRules.UNLIT, "out at once under a joiner")
	check_equal(cues.count(&"stone_lit"), 2, "its cue again as it lit again")
	events.disconnect("cue_shown", hear)
	flow.stop_run()
	check(flow.room_props().is_empty(), "the props go with the hub")


## The stone follows the rules whenever it is out of step (props W8c, review): knocked out of `lit`
## while everyone still stands on it, it is asked back at the next count.
func test_a_stone_out_of_step_is_asked_back() -> void:
	_start([0])
	_place(0, true)
	_tick()
	var stones: Array[Actor] = flow.contents.with_role(HubRules.ROLE_RUN_START)
	check_equal(stones.size(), 1, "one stone")
	if stones.is_empty():
		return
	check_equal(stones[0].state_triggers.state_id(), HubRules.LIT, "lit")
	events.emit_signal("prop_state_requested", stones[0].id, HubRules.UNLIT)
	check_equal(stones[0].state_triggers.state_id(), HubRules.UNLIT, "knocked out of step")
	_tick()
	check_equal(stones[0].state_triggers.state_id(), HubRules.LIT, "asked back at the next count")


func test_a_join_and_a_leave_in_one_tick_put_the_stone_out() -> void:
	_start([0, 1])
	_place(0, true)
	_place(1, true)
	_tick()
	check(flow.is_stone_lit(), "lit")
	input.leave(1)
	input.add_virtual_device(2)
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_HUB, "the count is the same, but the newcomer is off the stone: nothing starts")
	check_equal(_last(), Vector3i(1, 2, 0), "and the stone says so")


func test_a_by_any_seat_on_the_lit_stone_starts_the_run() -> void:
	for presser: int in [0, 2, 3]:
		_start([0, 1, 2, 3])
		for seat in 4:
			_place(seat, true)
		_tick()
		check(flow.is_stone_lit(), "seat %d: lit" % presser)
		var hub_world: Node = flow.world
		_press_a(presser)
		check_equal(flow.mode, FlowScript.MODE_RUN, "seat %d: A starts the run" % presser)
		var map: BiomeMap = root.get_node("Run").get(&"map") as BiomeMap
		check(map != null and flow.room_id == map.room_templates[0], "seat %d: in the start room of the run's biome" % presser)
		check(flow.world != hub_world, "seat %d: a new world" % presser)
		check(flow.life.rooms() > 1 and flow.enemies_left() == 0, "seat %d: a biome of rooms, no fight in the start room" % presser)
		check_equal(_wizards().size(), 4, "seat %d: everyone plays" % presser)
		check_equal(_last(), Vector3i(0, 0, 0), "seat %d: the stone's line goes" % presser)
		for wizard in _wizards():
			check(not wizard.health.invincible, "seat %d: hits hurt in the run" % presser)
		_stop()


func test_a_staff_button_on_the_lit_stone_starts_nothing() -> void:
	# The staffs are on RB, RT, LB, LT (Space and the mouse): they cast; A (`accept`) starts.
	_start([0])
	_place(0, true)
	_tick()
	check(flow.is_stone_lit(), "lit")
	for staff in 4:
		var frame: InputFrame = frames.call("frame_of", 0) as InputFrame
		frame.press(staff)
		_tick()
		frame.pressed_bits = 0
	check_equal(flow.mode, FlowScript.MODE_HUB, "no staff button starts the run")


func test_a_sent_by_the_hud_starts_the_run_at_the_next_tick() -> void:
	_start([0])
	_place(0, true)
	_tick()
	events.emit_signal("run_requested", 0)
	check_equal(flow.mode, FlowScript.MODE_HUB, "a command waits for the tick's start")
	await commands_applied()
	check(flow.departure.is_under_way(), "the party departs there")
	for i in Departure.TICKS:
		_tick()
	check_equal(flow.mode, FlowScript.MODE_RUN, "and the run starts when it is done")


## A on the lit stone starts the party's departure (the loading screen comes down over the hub), and
## the run starts Departure.TICKS ticks later, on that tick and no other: a second A, a
## wizard stepping off the stone and a joiner change nothing. `run_departure_changed` is told as it
## begins and as it ends.
func test_a_on_the_lit_stone_departs_and_the_run_starts_ticks_later() -> void:
	var told: Array[bool] = []
	var hear := func(departing: bool) -> void: told.append(departing)
	events.connect("run_departure_changed", hear)
	_start([0, 1])
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a_only(1)
	check(flow.departure.is_under_way(), "A on the lit stone: the party departs")
	check_equal(flow.departure.seat, 1, "for the seat that pressed")
	check_equal(told, [true] as Array[bool], "and the HUD is told at once")
	_press_a_only(0)
	check_equal(flow.departure.seat, 1, "a second A changes nothing")
	_place(0, false)
	input.add_virtual_device(2)
	for i in Departure.TICKS - 1:
		_tick()
		check_equal(flow.mode, FlowScript.MODE_HUB, "tick %d: still the hub" % (i + 1))
	check(not flow.is_stone_lit(), "the stone went out under the departure")
	check_equal(told, [true] as Array[bool], "the departure goes on")
	_tick()
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run starts on the last tick")
	check_equal(flow.get_wizard(2) != null, true, "the joiner goes along")
	check(not flow.departure.is_under_way(), "nothing departs in the run")
	check_equal(told, [true, false] as Array[bool], "and the HUD is told the departure is over")
	events.disconnect("run_departure_changed", hear)


## The seat that pressed A leaves during the departure: the run starts for a seat still there.
func test_the_presser_leaving_hands_the_run_to_a_seat_still_there() -> void:
	_start([0, 1])
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a_only(0)
	input.leave(0)
	await commands_applied()
	for i in Departure.TICKS:
		_tick()
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run starts")
	check(flow.get_wizard(1) != null and flow.get_wizard(0) == null, "with the seat left")
	check_equal(flow.get("_starter"), 1, "and for it")


## The run's end (everyone down) departs for the hub: the run steps on for Departure.TICKS, the
## loading screen is wanted from its first tick, and still while the hub is asked of the frames
## service, until the hub stands.
func test_the_runs_end_departs_for_the_hub_behind_the_loading_screen() -> void:
	var told: Array[bool] = []
	var hear := func(departing: bool) -> void: told.append(departing)
	_start([0])
	_place(0, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run started")
	events.connect("run_departure_changed", hear)
	(flow.get_wizard(0) as Actor).health.take(100000.0)
	flow.step(FlowScript.RESTART_DELAY)
	check(flow.departure.is_under_way() and flow.departure.to == Departure.To.HUB, "everyone down: the party departs for the hub")
	check_equal(told, [true] as Array[bool], "the screen is asked for at once")
	for i in Departure.TICKS - 1:
		_tick()
		check_equal(flow.mode, FlowScript.MODE_RUN, "tick %d: still the run" % (i + 1))
	_tick()
	check_equal(flow.state, FlowScript.State.IDLE, "the run went on the last tick")
	check_equal(told, [true] as Array[bool], "the screen stays while the hub is asked for")
	from_frames()
	check_equal(flow.mode, FlowScript.MODE_HUB, "the hub stands")
	check_equal(told, [true, false] as Array[bool], "and the screen goes")
	events.disconnect("run_departure_changed", hear)


## The portal home departs for the hub too, and the main menu under that departure ends it: no hub,
## and the screen goes.
func test_the_main_menu_under_a_return_starts_no_hub() -> void:
	var told: Array[bool] = []
	var hear := func(departing: bool) -> void: told.append(departing)
	_start([0])
	_place(0, true)
	_tick()
	_press_a(0)
	events.connect("run_departure_changed", hear)
	flow.call("_take_portal_home")
	check(flow.departure.is_under_way() and flow.departure.to == Departure.To.HUB, "the portal home: the party departs for the hub")
	_tick()
	events.emit_signal("main_menu_requested", 0)
	check_equal(told, [true, false] as Array[bool], "the main menu: the screen goes")
	for i in Departure.TICKS:
		_tick()
	from_frames()
	check_equal(flow.state, FlowScript.State.IDLE, "and no hub starts")
	events.disconnect("run_departure_changed", hear)


## The main menu under a departure (the pause menu's): no run starts, and the HUD is told it ended.
func test_the_main_menu_under_a_departure_starts_no_run() -> void:
	var told: Array[bool] = []
	var hear := func(departing: bool) -> void: told.append(departing)
	events.connect("run_departure_changed", hear)
	_start([0])
	_place(0, true)
	_tick()
	_press_a_only(0)
	_tick()
	events.emit_signal("main_menu_requested", 0)
	check(not flow.departure.is_under_way(), "the departure ends")
	check_equal(told, [true, false] as Array[bool], "and the HUD is told")
	for i in Departure.TICKS:
		_tick()
	check_equal(flow.state, FlowScript.State.IDLE, "and no run starts")
	events.disconnect("run_departure_changed", hear)


func test_the_stone_is_told_again_after_a_restore() -> void:
	# A snapshot puts the stone's count back under a game that sent another (online-ready N10): what
	# was sent is only drawn, so the next count is sent again.
	_start([0])
	_place(0, true)
	_tick()
	check_equal(_last(), Vector3i(1, 1, 1), "lit")
	var told: int = stone.size()
	flow.hub.set(&"_stone_sent", Vector2i(0, 1))
	_tick()
	check_equal(stone.size(), told + 1, "told again")
	check_equal(_last(), Vector3i(1, 1, 1), "the HUD and the lit look follow the restored state")


func test_a_wizard_hit_in_the_hub_loses_health() -> void:
	_start([0])
	var wizard: Actor = _wizards()[0]
	var full: float = wizard.health.health
	var counted: bool = combat.call("hit", -1, wizard, 40.0, Vector2.RIGHT, 200.0)
	check(counted, "the hit lands")
	check_equal(hits, 1, "it is heard (its flash)")
	check_equal(wizard.health.health, full - 40.0, "and hurts")


## Owner, 2026-11-13: no longer invincible in the hub; a downed wizard comes back to full life a
## moment after, so parties may fight each other there and builds be tried, with no consequence.
func test_a_wizard_downed_in_the_hub_stands_up_at_full_health() -> void:
	_start([0, 1])
	var wizard := flow.get_wizard(0) as Actor
	wizard.health.take(wizard.health.max_health)
	check(wizard.is_down(), "downed")
	var after: float = _room().stand_up_after
	check(after > 0.0, "the hub stands its wizards up")
	flow.step(after * 0.5)
	check(wizard.is_down(), "still down halfway")
	flow.step(after * 0.5 + DT)
	check(not wizard.is_down(), "it stands up by itself")
	check_equal(wizard.health.health, wizard.health.max_health, "at full health")
	check(wizard.health.is_protected(), "protected for a moment")
	check_equal(flow.mode, FlowScript.MODE_HUB, "still the hub")


func test_everyone_down_in_the_hub_restarts_nothing() -> void:
	_start([0, 1])
	var hub_world: Node = flow.world
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	check(not flow.is_restarting(), "no restart counts")
	flow.step(_room().stand_up_after + DT)
	from_frames()
	check(flow.world == hub_world, "the same hub")
	for wizard in _wizards():
		check(not wizard.is_down(), "everyone stands")
		check_equal(wizard.health.health, wizard.health.max_health, "at full health")


func test_a_wizard_who_leaves_while_down_stands_up_nowhere() -> void:
	_start([0, 1])
	var wizard := flow.get_wizard(1) as Actor
	wizard.health.take(wizard.health.max_health)
	input.leave(1)
	input.add_virtual_device(1)
	var back := flow.get_wizard(1) as Actor
	check(back != wizard and not back.is_down(), "a fresh wizard joins")
	back.health.take(10.0)
	flow.step(_room().stand_up_after + DT)
	check_equal(back.health.health, back.health.max_health - 10.0, "the old fall heals nothing")


func test_a_run_from_the_hub_still_downs_for_good() -> void:
	_start([0, 1])
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run started")
	var wizard := flow.get_wizard(0) as Actor
	wizard.health.take(wizard.health.max_health)
	flow.step(_room().stand_up_after + DT)
	check(wizard.is_down(), "in a run, nobody stands up by themselves")


## A run the content cannot make a map of is refused before anything goes (`Registry.run_problems`):
## the party stays in the hub as it was.
func test_a_run_that_cannot_be_made_leaves_the_hub_as_it_was() -> void:
	var rules := MapRules.new()
	rules.biome = &"test_hub_nowhere"
	rules.rooms_min = 0
	rules.rooms_max = 0
	rules.start_kind = &"fight"
	var nowhere := RunDefinition.new()
	nowhere.id = &"test_hub_nowhere"
	nowhere.biomes = [rules] as Array[MapRules]
	root.get_node("Registry").call("add", &"runs", nowhere)
	flow.run_id_to_play = nowhere.id
	_start([0])
	var hub_world: Node = flow.world
	_place(0, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_HUB, "still the hub")
	check(flow.world == hub_world and flow.state == FlowScript.State.RUNNING, "the same hub, going on")


## A map its rolls cornered (the templates' shapes leaving a room no place, after the hub went: the map is made
## from the run's seed, at its start; here the run's area does not answer at all) sends the party
## back to the hub, each wizard with everything it took to the stone, and the stone works again.
func test_a_run_with_no_map_from_the_stone_goes_back_to_the_hub_as_it_went() -> void:
	var run: Node = root.get_node("Run")
	var answer: Callable = Callable(run, &"_on_run_begun")
	_start([0, 1])
	# Seat 1 holds something of its own: a staff it built in the hub.
	var built: Array[StringName] = [&"bolt", &"dash", &"bolt"]
	events.emit_signal("staff_cards_requested", 1, 1, built, (flow.get_wizard(1) as Actor).key())
	await commands_applied()
	var went: Array[PlayerLoadout] = []
	for seat in 2:
		went.append(PlayerController.loadout_of(flow.get_wizard(seat) as Actor))
	for seat in 2:
		_place(seat, true)
	_tick()
	events.disconnect("run_begun", answer)
	_press_a(0)
	events.connect("run_begun", answer)
	check_equal(flow.state, FlowScript.State.IDLE, "no run: the hub went first")
	from_frames()
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub")
	check_equal(flow.room_id, FlowScript.HUB_ROOM_ID, "the hub's room")
	check_equal(_wizards().size(), 2, "both wizards are there")
	for seat in 2:
		var now: PlayerLoadout = PlayerController.loadout_of(flow.get_wizard(seat) as Actor)
		check(now != null and now.equals(went[seat]), "seat %d comes back as it went" % seat)
	check_equal(_cards(1, 1).slice(0, 3), built, "seat 1 kept the staff it built")
	for seat in 2:
		_place(seat, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "the stone starts the run again")


func test_the_runs_end_brings_everyone_back_to_the_hub() -> void:
	_start([0, 1])
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(1)
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run started")
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	check(flow.is_restarting(), "everyone down ends the run")
	flow.step(FlowScript.RESTART_DELAY)
	# The hub is a run's start of its own: the frames service sends it as the next step starts.
	_home()
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub")
	check_equal(flow.room_id, FlowScript.HUB_ROOM_ID, "the hub's room")
	check_equal(_wizards().size(), 2, "both are there")
	check_equal(_last(), Vector3i(0, 2, 0), "the stone counts them")
	for wizard in _wizards():
		check(not wizard.is_down(), "standing")
		check_equal(wizard.health.health, wizard.health.max_health, "at full health")


## A run from the stone won (its pinned room, of a kind that opens the portal home, cleared and every
## standing wizard in the portal: connected biomes CB7) brings the party back to the hub, as a lost
## one does.
func test_a_won_run_from_the_stone_goes_back_to_the_hub() -> void:
	var registry: Node = root.get_node("Registry")
	flow.run_id_to_play = PinnedRun.pin(registry, ARENA)
	(registry.call("get_resource", &"room_kinds", flow.run_id_to_play) as RoomKind).portal_home = true
	_start([0, 1])
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run started")
	for enemy: Node in flow.get("_enemies").duplicate():
		events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO, -1)
	_tick()
	check(flow.life.has(0, RoomLife.CLEARED), "cleared")
	check(flow.gates.portal_room == 0, "the portal home opens")
	for seat in 2:
		flow.get_wizard(seat).global_position = flow.gates.portal_area.get_center()
	_tick()
	_home()
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub")
	check_equal(_wizards().size(), 2, "everyone with it")
	(registry.call("get_resource", &"room_kinds", PinnedRun.room_id(ARENA)) as RoomKind).portal_home = false


## Owner, 2026-11-10: the hub is the arsenal a run's tools are picked from. What a seat built in
## the hub is in its staffs in the run; a seat that joins mid-run starts with Play's cards; and
## back in the hub after the run (lost or won) nothing of the run comes with the party, its
## staffs neither: it is ready for a new run.
func test_staffs_built_in_the_hub_follow_into_the_run_and_nothing_comes_back() -> void:
	_start([0, 1])
	var built: Array[StringName] = [&"bolt", &"dash", &"bolt"]
	events.emit_signal("staff_cards_requested", 1, 1, built, (flow.get_wizard(1) as Actor).key())
	await commands_applied()
	check_equal((flow.get_wizard(1) as Actor).caster.cards_of(1).slice(0, 3), built, "seat 1 built its RT staff in the hub")
	var fresh_rt: Array[StringName] = (flow.get_wizard(0) as Actor).caster.cards_of(1)
	var hub_bag: Array = _card_bag(1)
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run started")
	check_equal((flow.get_wizard(1) as Actor).caster.cards_of(1).slice(0, 3), built, "seat 1's staff came into the run")
	# The whole player goes into the run (owner, I1 decision 11; confirmed 2026-11-14): its card
	# bag is the one it held in the hub.
	check_equal(_card_bag(1), hub_bag, "the run's card bag is the one held in the hub")
	check_equal((flow.get_wizard(0) as Actor).caster.cards_of(1), fresh_rt, "seat 0's staff is as it was")
	input.add_virtual_device(2)
	check_equal((flow.get_wizard(2) as Actor).caster.cards_of(0).slice(0, 1), [&"dash"] as Array[StringName], "a seat joining mid-run starts with Play's cards")
	input.leave(2)
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	# The hub is a run's start of its own: the frames service sends it as the next step starts.
	_home()
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub")
	check_equal((flow.get_wizard(1) as Actor).caster.cards_of(1), fresh_rt, "seat 1's staff did not come back: the hub's own again")
	check_equal((flow.get_wizard(0) as Actor).caster.cards_of(1), fresh_rt, "seat 0's neither")


## The hands go into the run as they are (items I2): RB and RT hold Play's staffs in the hub, LB
## and LT are empty, and so they are in the run; a seat joining mid-run holds the same; back in the
## hub, the hub's own again. (The whole player is carried, its loadout: below.)
func test_the_hands_held_in_the_hub_go_into_the_run_as_they_are() -> void:
	_start([0, 1])
	for seat in [0, 1]:
		_check_two_hands(seat, "in the hub")
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run started")
	for seat in [0, 1]:
		_check_two_hands(seat, "in the run")
	input.add_virtual_device(2)
	_check_two_hands(2, "joining mid-run")
	input.leave(2)
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	_home()
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub")
	_check_two_hands(1, "back in the hub")


## Seat `seat`'s wizard holds Play's first two staffs on RB and RT and nothing on LB and LT.
func _check_two_hands(seat: int, where: String) -> void:
	var wizard := flow.get_wizard(seat) as Actor
	check(wizard != null, "seat %d has a wizard %s" % [seat, where])
	if wizard == null:
		return
	for at in 4:
		var held: bool = at < FlowScript.START_HANDS
		check_equal(wizard.caster.holds(at), held, "seat %d's hand %d %s %s" % [seat, at, "holds a staff" if held else "is empty", where])
		if held:
			check_equal(wizard.caster.staff_of(at).id, FlowScript.STARTER_HEADS[at], "seat %d's hand %d holds Play's staff %s" % [seat, at, where])


## Every run ends back in the hub (connected biomes CB7, decision 14), one started without it too.
func test_a_run_of_play_requested_ends_in_the_hub_too() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "a run")
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	_home()
	check_equal(flow.mode, FlowScript.MODE_HUB, "everyone down: back in the hub")


func test_the_hub_and_its_command_are_ignored_elsewhere() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)
	events.emit_signal("hub_requested", 0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "a hub request mid-run changes nothing")
	var world: Node = flow.world
	_press_a(0)
	check(flow.world == world, "run_requested out of the hub changes nothing")


## The hub hands out Play's bag (owner, 2026-11-19), and the cheat code's command
## `all_cards_requested` fills the card bag of the sending seat's wizard, and no other's (owner:
## only the typer's wizard), with Inventory.DEV_COPIES of every card, at the tick's start; the run
## from the stone takes them along, and the hub begun again after the run hands out Play's bag again.
func test_the_cheat_code_gives_the_typers_wizard_every_card() -> void:
	_start([0, 1])
	var plain: Array = [[&"dash", 1], [&"bolt", 1]]
	check_equal(_card_bag(0), plain, "the hub's bag is Play's: one dash, one bolt")
	check_equal(_card_bag(1), plain, "seat 1's too")
	events.emit_signal("all_cards_requested", 1)
	check_equal(_card_bag(1), plain, "a command waits for the tick's start")
	await commands_applied()
	var every: Array = []
	var dev: Dictionary = Inventory.dev_cards(root.get_node("Registry"))
	for id: Variant in dev:
		every.append([id, dev[id]])
	check(every.size() > 2, "the registry holds more cards than Play's two")
	check_equal(_card_bag(1), every, "seat 1, who typed it, holds every card, DEV_COPIES of each")
	check_equal(_card_bag(0), plain, "seat 0 keeps Play's bag")
	check_equal((flow.get_wizard(1) as Actor).caster.cards_of(0).slice(0, 1), [&"dash"] as Array[StringName], "the staffs keep their cards")
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run started")
	check_equal(_card_bag(1), every, "the run takes every card along with the whole player")
	check_equal(_card_bag(0), plain, "and seat 0's bag as it was")
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	_home()
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub")
	check_equal(_card_bag(1), plain, "the hub begun again hands out Play's bag again")


## The cheat code gives only the typer's wizard: a seat joining after it gets Play's bag, and a seat
## with no wizard changes nothing.
func test_a_seat_joining_after_the_cheat_code_gets_plays_bag() -> void:
	_start([0])
	events.call("apply_command", &"all_cards_requested", [0])
	check(_card_bag(0).size() > 2, "seat 0 holds every card")
	input.add_virtual_device(1)
	check_equal(_card_bag(1), [[&"dash", 1], [&"bolt", 1]], "the joiner holds Play's bag")
	events.call("apply_command", &"all_cards_requested", [3])
	check_equal(_card_bag(1), [[&"dash", 1], [&"bolt", 1]], "a seat with no wizard gives nobody anything")


## The cheat code's command does nothing outside the hub: a run's bag stays as it is.
func test_the_cheat_code_does_nothing_in_a_run() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "a run")
	var before: Array = _card_bag(0)
	events.call("apply_command", &"all_cards_requested", [0])
	check_equal(_card_bag(0), before, "the run's bag is as it was")


## Where the altar stands is told for the view (online-lobby L5c: the room's code over it): the top
## middle of its area once in the hub, and none once the hub is left.
func test_the_altars_place_is_told_in_the_hub_and_gone_out_of_it() -> void:
	var told: Array = []
	var hear: Callable = func(standing: bool, at: Vector2) -> void: told.append([standing, at])
	events.connect("altar_placed", hear)
	_start([0])
	_tick()
	_tick()
	var altar: Rect2 = HubRules.area_of(_room().places(), HubRules.ROLE_PARTY_ALTAR)
	check_equal(told, [[true, Vector2(altar.get_center().x, altar.position.y)]], "told once: over the altar's area, in its middle")
	_place(0, true)
	_tick()
	_press_a(0)
	_tick()
	check_equal(told.back(), [false, Vector2.ZERO], "out of the hub no altar stands")
	events.disconnect("altar_placed", hear)


## The altar (online-lobby L2): which seats' wizards stand on it is told as it changes.
func test_the_seats_on_the_altar_are_told_as_they_change() -> void:
	var told: Array[int] = []
	var hear: Callable = func(seats: int) -> void: told.append(seats)
	events.connect("altar_changed", hear)
	_start([0, 2])
	_tick()
	told.clear()
	var altar: Rect2 = HubRules.area_of(_room().places(), HubRules.ROLE_PARTY_ALTAR)
	flow.get_wizard(2).position = altar.get_center()
	_tick()
	_tick()
	check_equal(told, [0b0100] as Array[int], "seat 2's wizard steps on it: told once, by its seat")
	flow.get_wizard(0).position = altar.position + Vector2(4.0, 4.0)
	_tick()
	check_equal(told.back(), 0b0101, "both")
	flow.get_wizard(2).position = altar.end + Vector2(8.0, 8.0)
	_tick()
	check_equal(told.back(), 0b0001, "one steps off")
	_place(0, true)
	_tick()
	_press_a(0)
	_tick()
	check_equal(told.back(), 0, "out of the hub nobody is on it")
	events.disconnect("altar_changed", hear)
	_stop()


## Asked for in the hub, the hub starts anew (net/ begins a recording of it for a machine that
## joins): everyone back at their spawn, the same seats.
func test_the_hub_asked_for_in_the_hub_starts_anew() -> void:
	_start([0, 1])
	_tick()
	var before: Vector2 = flow.get_wizard(1).position
	flow.get_wizard(1).position = before + Vector2(64.0, 0.0)
	var first: Node = flow.get_wizard(1)
	events.emit_signal("hub_requested", 0)
	_tick()
	check_equal(flow.mode, FlowScript.MODE_HUB, "still the hub")
	check_equal(_wizards().size(), 2, "the same two seats")
	check(flow.get_wizard(1) != first, "with new wizards")
	check_equal(flow.get_wizard(1).position, before, "at their spawns")
	# Not from a run: that run plays on.
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(0)
	_tick()
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run from the stone")
	events.emit_signal("hub_requested", 0)
	_tick()
	check_equal(flow.mode, FlowScript.MODE_RUN, "the hub asked for during a run changes nothing")
	_stop()


## Where the party is, for whoever lets other machines join it: told as it changes, in plain words.
func test_the_bus_is_told_when_the_party_enters_and_leaves_the_hub() -> void:
	var told: Array[bool] = []
	var hear: Callable = func(in_hub: bool) -> void: told.append(in_hub)
	events.connect("hub_changed", hear)
	_start([0])
	_tick()
	check_equal(told, [true] as Array[bool], "in the hub")
	_place(0, true)
	_tick()
	_press_a(0)
	_tick()
	check_equal(told, [true, false] as Array[bool], "the run from the stone: out of it")
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	_home()
	_tick()
	check_equal(told, [true, false, true] as Array[bool], "back in the hub after the run")
	_stop()
	check_equal(told.back(), false, "the game stopped: not in it")
	events.disconnect("hub_changed", hear)



## Seat `seat`'s card bag as [id, copies] pairs, in order.
func _card_bag(seat: int) -> Array:
	var out: Array = []
	for stack: ItemStack in (flow.get_wizard(seat) as Actor).inventory.stacks_in(&"cards"):
		out.append([stack.id, stack.count])
	return out


func _cards(seat: int, staff: int) -> Array[StringName]:
	return (flow.get_wizard(seat) as Actor).caster.cards_of(staff)


## A machine joining the party (online lobby, decision 4): a seat that joins the hub under way
## appears beside the altar, at the hub's spawn for joiners of its seat, not at the room's player
## spawns, and not on the altar itself (where A opens the room).
func test_a_seat_that_joins_the_hub_appears_beside_the_altar() -> void:
	_start([0])
	var room: RoomBase = _room()
	check_equal(flow.get_wizard(0).position, room.places().player_spawns[0], "the seat the hub began with stands at its spawn")
	for seat: int in [2, 1, 3]:
		input.add_virtual_device(seat)
		var at: Vector2 = flow.get_wizard(seat).position
		check_equal(at, room.places().joiner_spawns[seat], "seat %d appears at its joiners' spawn" % seat)
		check(not HubRules.area_of(room.places(), HubRules.ROLE_PARTY_ALTAR).has_point(at), "seat %d is not on the altar" % seat)
		check(at.distance_to(HubRules.area_of(room.places(), HubRules.ROLE_PARTY_ALTAR).get_center()) < 128.0, "seat %d is beside it (%s)" % [seat, at])
	_tick()
	check_equal(flow.hub.get(&"_altar_sent"), 0, "nobody stands on the altar")
	_stop()


## The hub begun anew for a joining machine (net/ records it from its start) keeps every wizard's
## loadout (items I4): every bag, staff and hand the hub's wizards hold is written into the recording's header, so a machine that
## plays the recording from its start builds the same staffs. A run's end, recorded anew, takes
## nothing along (owner, 2026-11-10).
func test_the_hub_begun_anew_keeps_every_wizards_staffs_in_its_recording() -> void:
	_start([0, 1])
	var built: Array[StringName] = [&"bolt", &"dash", &"bolt"]
	events.emit_signal("staff_cards_requested", 1, 1, built, (flow.get_wizard(1) as Actor).key())
	await commands_applied()
	var fresh_rt: Array[StringName] = _cards(0, 1)
	var first: Node = flow.get_wizard(1)
	events.emit_signal("hub_requested", 0)
	check(flow.get_wizard(1) != first, "the hub began anew")
	check_equal(_cards(1, 1).slice(0, 3), built, "seat 1 kept the staff it built")
	check_equal(_cards(0, 1), fresh_rt, "seat 0's is as it was")
	# Recorded: the start is sent by the frames service, after the header is written.
	var replay: Replay = frames.call(&"record", &"hub_requested", 0) as Replay
	check_equal(replay.party.of(1).staff_cards(1).slice(0, 3), built, "the recording's header carries it")
	check_equal(replay.party.seats(), 0b0011, "and every wizard's loadout")
	check_equal(replay.party.of(1).staff_id(1), FlowScript.STARTER_HEADS[1], "the staffs themselves too")
	var bag_before: Array = _card_bag(1)
	check(replay.party.of(1).equals(PlayerController.loadout_of(flow.get_wizard(1) as Actor)), "the whole player: bags and hands too")
	check_equal(_cards(1, 1).slice(0, 3), built, "the hub begun anew under the recording keeps it")
	frames.call(&"stop_recording")
	# A machine that plays the recording from its start, which never had that staff.
	flow.stop_run()
	for index in 4:
		input.leave(index)
	check(frames.call(&"play", replay), "the recording plays")
	check_equal(flow.mode, FlowScript.MODE_HUB, "in the hub")
	check(flow.get_wizard(1) != null and _cards(1, 1).slice(0, 3) == built, "seat 1's wizard holds the staff it built on the machine that recorded")
	check_equal(_card_bag(1), bag_before, "and the same card bag, counted as there")
	check_equal(_cards(0, 1), fresh_rt, "seat 0's as there")
	frames.call(&"stop_playing")
	_stop()
	# A run's end recorded anew: nothing comes back.
	_start([0, 1])
	events.emit_signal("staff_cards_requested", 1, 1, built, (flow.get_wizard(1) as Actor).key())
	await commands_applied()
	var anew: Array[Replay] = []
	var hear: Callable = func(next: Replay) -> void: anew.append(next)
	frames.connect(&"recorded_anew", hear)
	frames.call(&"record", &"hub_requested", 0)
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run from the stone")
	check_equal(_cards(1, 1).slice(0, 3), built, "with the staff")
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	_home()
	check_equal(anew.size(), 1, "back in the hub, recorded anew")
	if anew.size() == 1:
		check(anew[0].party.is_empty(), "its header takes nothing along")
	check_equal(_cards(1, 1), fresh_rt, "and seat 1's staff is the hub's own again")
	frames.disconnect(&"recorded_anew", hear)
	frames.call(&"stop_recording")
	_stop()


## Items I6: the hub's rack is ordinary items lying where the hub's scene places them (the Wild
## star and the premade builds, HUB_RACK of them); a wizard by it takes it with A onto its first free hand (LB: players start with RB and
## RT), and a run from the stone takes it along with the rest of the player.
func test_the_rack_lies_in_the_hub_and_a_takes_it_along() -> void:
	var items: Node = root.get_node("Items")
	_start([0])
	check_equal((items.call("lying") as Array).size(), HUB_RACK, "the hub's rack lies there")
	var rack: GroundItem = _wild_star(items)
	check(rack != null, "the Wild star among it")
	check_equal([rack.stack.kind, rack.stack.id, rack.title], [ItemKinds.STAFF, &"star", "Wild star"], "the Wild star")
	var wizard := flow.get_wizard(0) as Actor
	wizard.position = rack.at + Vector2(6.0, 0.0)
	items.call("step", DT)
	check_equal(items.call("near_of", 0), rack.number, "in reach of the wizard by it")
	events.call("apply_command", &"item_take_requested", [0, rack.number])
	check(_wild_star(items) == null and (items.call("lying") as Array).size() == HUB_RACK - 1, "taken, the rest left")
	var hands: PackedInt32Array = wizard.inventory.hands()
	check(hands[2] != Inventory.NO_STAFF, "onto LB, the first free hand (%s)" % hands)
	check_equal(wizard.caster.cards_of(2), rack.stack.cards, "with its crazy build")
	for seat in 1:
		_place(seat, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run starts")
	var carried := flow.get_wizard(0) as Actor
	check_equal(carried.caster.cards_of(2), rack.stack.cards, "the run's wizard holds it on LB")
	check((items.call("lying") as Array).is_empty(), "and the run's room has nothing lying")
	_stop()


## Owner, 2026-11-14: the hub's rack is fresh only when a host starts the hub or a party comes back
## to it from a run. Begun anew in place (a machine joining: the hub recorded anew), what lies there
## stays as it was, also on a machine that only plays the recording; a run's end lays it fresh.
func test_the_hub_begun_anew_keeps_its_ground_and_a_runs_end_lays_the_rack_again() -> void:
	var items: Node = root.get_node("Items")
	_start([0, 1])
	var rack: GroundItem = _wild_star(items)
	var wizard := flow.get_wizard(0) as Actor
	wizard.position = rack.at
	events.call("apply_command", &"item_take_requested", [0, rack.number])
	check(_wild_star(items) == null, "the Wild star taken")
	# A machine joins: the hub is recorded anew, its start sent once the header is written.
	var replay: Replay = frames.call(&"record", &"hub_requested", 0) as Replay
	check_equal([replay.ground.room, replay.ground.count()], [FlowScript.HUB_ROOM_ID, HUB_RACK - 1], "the recording's header says what is left on the hub's ground")
	from_frames()
	check(_wild_star(items) == null and (items.call("lying") as Array).size() == HUB_RACK - 1, "the hub begun anew under the recording: the Wild star does not lie there again")
	check((flow.get_wizard(0) as Actor).caster.cards_of(2) == rack.stack.cards, "and the wizard still holds it")
	frames.call(&"stop_recording")
	# A machine that plays the recording from its start, whose hub had a rack.
	flow.stop_run()
	for index in 4:
		input.leave(index)
	check(frames.call(&"play", replay), "the recording plays")
	check(_wild_star(items) == null and (items.call("lying") as Array).size() == HUB_RACK - 1, "no Wild star there either")
	frames.call(&"stop_playing")
	_stop()
	# A run's end: the party back in the hub finds the rack again.
	_start([0])
	rack = _wild_star(items)
	(flow.get_wizard(0) as Actor).position = rack.at
	events.call("apply_command", &"item_take_requested", [0, rack.number])
	_place(0, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_RUN, "the run from the stone")
	for each in _wizards():
		each.health.take(each.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	_home()
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub")
	check_equal((items.call("lying") as Array).size(), HUB_RACK, "the whole rack lies there again")
	_stop()


## The Wild star lying on the hub's ground, or null.
func _wild_star(items: Node) -> GroundItem:
	for item: GroundItem in items.call("lying"):
		if item.title == "Wild star":
			return item
	return null
