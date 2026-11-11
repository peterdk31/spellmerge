extends "res://tests/support/suite.gd"
## The hub (docs/milestones/online-lobby.md, L1): `hub_requested` (the main menu's Play) starts the
## hub room with three training dummies and no wave; players join and leave in any order; hits land
## and take nothing; the teleporter stone is lit only while every wizard stands on it (put out by
## one stepping off or by a new join at once), and then the command `run_requested` (a seat's A)
## starts a run of waves, every seat keeping its staffs, whose end brings everyone back to the hub.
## Uses the real autoloads; time moves through Flow.step(), and commands are applied as the frames
## service applies them at a tick's start (`Events.apply_command`), unless a test says otherwise.

const FlowScript := preload("res://gameplay/flow/flow.gd")

const DT: float = 1.0 / 60.0

var flow: FlowScript
var input: Node
var events: Node
var frames: Node
var combat: Node
## Every `start_stone_changed`, as (standing, wizards, lit).
var stone: Array[Vector3i] = []
var sandbox_flags: Array[bool] = []
var waves: Array[int] = []
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
	sandbox_flags.clear()
	waves.clear()
	hits = 0
	events.connect("start_stone_changed", _on_stone)
	events.connect("sandbox_changed", _on_sandbox_changed)
	events.connect("wave_started", _on_wave_started)
	events.connect("hit_landed", _on_hit_landed)


func after_each() -> void:
	events.disconnect("start_stone_changed", _on_stone)
	events.disconnect("sandbox_changed", _on_sandbox_changed)
	events.disconnect("wave_started", _on_wave_started)
	events.disconnect("hit_landed", _on_hit_landed)
	flow.stop_run()
	flow.world_parent = null
	for index in 4:
		input.leave(index)


func _on_stone(standing: int, wizards: int, lit: bool) -> void:
	stone.append(Vector3i(standing, wizards, 1 if lit else 0))


func _on_sandbox_changed(on: bool) -> void:
	sandbox_flags.append(on)


func _on_wave_started(number: int) -> void:
	waves.append(number)


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


## One tick of Flow.
func _tick() -> void:
	flow.step(DT)


## Seat `seat` presses A on the stone: the command as a tick's start applies it.
func _press_a(seat: int) -> void:
	events.call("apply_command", &"run_requested", [seat])


func _stop() -> void:
	flow.stop_run()
	for index in 4:
		input.leave(index)
	stone.clear()
	sandbox_flags.clear()
	waves.clear()


func test_play_starts_the_hub_with_three_dummies_and_no_wave() -> void:
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
		check_equal(waves, [] as Array[int], "%d players: no wave" % count)
		check_equal(sandbox_flags, [false] as Array[bool], "%d players: not the sandbox" % count)
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
			check(wizard.health.invincible, "order %s: a joiner takes nothing from hits" % [order])
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
		check_equal(flow.mode, FlowScript.MODE_WAVES, "seat %d: A starts the run" % presser)
		check_equal(flow.room_id, flow.room_id_to_play, "seat %d: in the run's room" % presser)
		check(flow.world != hub_world, "seat %d: a new world" % presser)
		check_equal(waves, [1] as Array[int], "seat %d: wave 1" % presser)
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
	check_equal(flow.mode, FlowScript.MODE_WAVES, "and starts the run there")


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


func test_a_wizard_hit_in_the_hub_loses_no_health() -> void:
	_start([0])
	var wizard: Actor = _wizards()[0]
	var full: float = wizard.health.health
	var counted: bool = combat.call("hit", -1, wizard, 40.0, Vector2.RIGHT, 200.0)
	check(counted, "the hit lands")
	check_equal(hits, 1, "it is heard (its flash)")
	check_equal(wizard.health.health, full, "and takes nothing")
	for i in 10:
		combat.call("hit", -1, wizard, wizard.health.max_health, Vector2.LEFT, 200.0)
	check(not wizard.is_down(), "nobody is downed in the hub")


func test_the_runs_end_brings_everyone_back_to_the_hub() -> void:
	_start([0, 1])
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(1)
	check_equal(flow.mode, FlowScript.MODE_WAVES, "the run started")
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	check(flow.is_restarting(), "everyone down ends the run")
	flow.step(FlowScript.RESTART_DELAY)
	# The hub is a run's start of its own: the frames service sends it as the next step starts.
	from_frames()
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub")
	check_equal(flow.room_id, FlowScript.HUB_ROOM_ID, "the hub's room")
	check_equal(_wizards().size(), 2, "both are there")
	check_equal(_last(), Vector3i(0, 2, 0), "the stone counts them")
	for wizard in _wizards():
		check(wizard.health.invincible and not wizard.is_down(), "standing, and hits take nothing again")


## Owner, 2026-11-10: the hub is the arsenal a run's tools are picked from. What a seat built in
## the hub is in its staffs in the run; a seat that joins mid-run starts with Play's cards; and
## back in the hub after the run (lost or won) nothing of the run comes with the party, its
## staffs neither: it is ready for a new run.
func test_staffs_built_in_the_hub_follow_into_the_run_and_nothing_comes_back() -> void:
	_start([0, 1])
	var built: Array[StringName] = [&"bolt", &"dash", &"bolt"]
	events.emit_signal("staff_cards_requested", 1, 2, built)
	await commands_applied()
	check_equal((flow.get_wizard(1) as Actor).caster.cards_of(2).slice(0, 3), built, "seat 1 built its Y staff in the hub")
	var fresh_y: Array[StringName] = (flow.get_wizard(0) as Actor).caster.cards_of(2)
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_WAVES, "the run started")
	check_equal((flow.get_wizard(1) as Actor).caster.cards_of(2).slice(0, 3), built, "seat 1's staff came into the run")
	check_equal((flow.get_wizard(0) as Actor).caster.cards_of(2), fresh_y, "seat 0's staff is as it was")
	input.add_virtual_device(2)
	check_equal((flow.get_wizard(2) as Actor).caster.cards_of(0).slice(0, 1), [&"dash"] as Array[StringName], "a seat joining mid-run starts with Play's cards")
	input.leave(2)
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	# The hub is a run's start of its own: the frames service sends it as the next step starts.
	from_frames()
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub")
	check_equal((flow.get_wizard(1) as Actor).caster.cards_of(2), fresh_y, "seat 1's staff did not come back: the hub's own again")
	check_equal((flow.get_wizard(0) as Actor).caster.cards_of(2), fresh_y, "seat 0's neither")


func test_a_run_of_play_requested_still_restarts() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)
	var first: Node = flow.world
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	check_equal(flow.mode, FlowScript.MODE_WAVES, "a run started without the hub restarts")
	check(flow.world != first, "a fresh world")


func test_the_hub_and_its_command_are_ignored_elsewhere() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)
	events.emit_signal("hub_requested", 0)
	check_equal(flow.mode, FlowScript.MODE_WAVES, "a hub request mid-run changes nothing")
	var world: Node = flow.world
	_press_a(0)
	check(flow.world == world, "run_requested out of the hub changes nothing")


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
	# Not from a run of waves: that run plays on.
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(0)
	_tick()
	check_equal(flow.mode, FlowScript.MODE_WAVES, "the run from the stone")
	events.emit_signal("hub_requested", 0)
	_tick()
	check_equal(flow.mode, FlowScript.MODE_WAVES, "the hub asked for during a run changes nothing")
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
	from_frames()
	_tick()
	check_equal(told, [true, false, true] as Array[bool], "back in the hub after the run")
	_stop()
	check_equal(told.back(), false, "the game stopped: not in it")
	events.disconnect("hub_changed", hear)



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
## staffs: what the hub's wizards hold is written into the recording's header, so a machine that
## plays the recording from its start builds the same staffs. A run's end, recorded anew, takes
## nothing along (owner, 2026-11-10).
func test_the_hub_begun_anew_keeps_every_wizards_staffs_in_its_recording() -> void:
	_start([0, 1])
	var built: Array[StringName] = [&"bolt", &"dash", &"bolt"]
	events.emit_signal("staff_cards_requested", 1, 2, built)
	await commands_applied()
	var fresh_y: Array[StringName] = _cards(0, 2)
	var first: Node = flow.get_wizard(1)
	events.emit_signal("hub_requested", 0)
	check(flow.get_wizard(1) != first, "the hub began anew")
	check_equal(_cards(1, 2).slice(0, 3), built, "seat 1 kept the staff it built")
	check_equal(_cards(0, 2), fresh_y, "seat 0's is as it was")
	# Recorded: the start is sent by the frames service, after the header is written.
	var replay: Replay = frames.call(&"record", &"hub_requested", 0) as Replay
	check_equal((replay.carry.staffs_of(1)[2] as Array).slice(0, 3), built, "the recording's header carries it")
	check_equal(replay.carry.seats(), 0b0011, "and every wizard's staffs")
	check_equal(_cards(1, 2).slice(0, 3), built, "the hub begun anew under the recording keeps it")
	frames.call(&"stop_recording")
	# A machine that plays the recording from its start, which never had that staff.
	flow.stop_run()
	for index in 4:
		input.leave(index)
	check(frames.call(&"play", replay), "the recording plays")
	check_equal(flow.mode, FlowScript.MODE_HUB, "in the hub")
	check(flow.get_wizard(1) != null and _cards(1, 2).slice(0, 3) == built, "seat 1's wizard holds the staff it built on the machine that recorded")
	check_equal(_cards(0, 2), fresh_y, "seat 0's as there")
	frames.call(&"stop_playing")
	_stop()
	# A run's end recorded anew: nothing comes back.
	_start([0, 1])
	events.emit_signal("staff_cards_requested", 1, 2, built)
	await commands_applied()
	var anew: Array[Replay] = []
	var hear: Callable = func(next: Replay) -> void: anew.append(next)
	frames.connect(&"recorded_anew", hear)
	frames.call(&"record", &"hub_requested", 0)
	_place(0, true)
	_place(1, true)
	_tick()
	_press_a(0)
	check_equal(flow.mode, FlowScript.MODE_WAVES, "the run from the stone")
	check_equal(_cards(1, 2).slice(0, 3), built, "with the staff")
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	from_frames()
	check_equal(anew.size(), 1, "back in the hub, recorded anew")
	if anew.size() == 1:
		check(anew[0].carry.is_empty(), "its header takes nothing along")
	check_equal(_cards(1, 2), fresh_y, "and seat 1's staff is the hub's own again")
	frames.disconnect(&"recorded_anew", hear)
	frames.call(&"stop_recording")
	_stop()
