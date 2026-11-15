extends "res://tests/support/suite.gd"
## The hub's trial gate (boss OB2, docs/milestones/boss-old-broom.md, decision 27): each wizard's
## pick of a room is its own (the command `trial_picked`, a room the lectern offers or nothing); the
## gate is lit only while every wizard stands in it and all of them picked the same room (put out
## by one stepping off, a joiner or a changed pick); then a seat's A (`run_requested`) sends the
## party there through a run's start of its own (`trial_requested`, recorded with its room), every
## wizard as the player it is; the room cleared or everyone down, the party is back in the hub as it
## left it. The sandbox's enemy arena spawns bosses too.
## Uses the real autoloads; time moves through Flow.step(), and commands are applied as the frames
## service applies them at a tick's start (`Events.apply_command`).

const FlowScript := preload("res://gameplay/flow/flow.gd")
const StandInScript := preload("res://tools/enemy_stand_in.gd")

const DT: float = 1.0 / 60.0
const ARENA: StringName = &"arena_01"

var flow: FlowScript
var input: Node
var events: Node
var frames: Node
var registry: Node
## Every `trial_gate_changed`, as (standing, wizards, lit); every `lectern_changed`; the last picks.
var gate: Array[Vector3i] = []
var lectern: Array[int] = []
var picks: PackedStringArray = PackedStringArray()
var picks_place: Vector2 = Vector2.ZERO
var cleared: Array[StringName] = []


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	events = root.get_node("Events")
	frames = root.get_node("Frames")
	registry = root.get_node("Registry")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	gate.clear()
	lectern.clear()
	picks = PackedStringArray()
	cleared.clear()
	events.connect("trial_gate_changed", _on_gate)
	events.connect("lectern_changed", _on_lectern)
	events.connect("trial_picks_changed", _on_picks)
	events.connect("room_cleared", _on_cleared)


func after_each() -> void:
	events.disconnect("trial_gate_changed", _on_gate)
	events.disconnect("lectern_changed", _on_lectern)
	events.disconnect("trial_picks_changed", _on_picks)
	events.disconnect("room_cleared", _on_cleared)
	frames.call(&"stop_recording")
	frames.call(&"stop_playing")
	flow.stop_run()
	flow.world_parent = null
	for index in 4:
		input.leave(index)
	await commands_applied()


func _on_gate(standing: int, wizards: int, lit: bool) -> void:
	gate.append(Vector3i(standing, wizards, 1 if lit else 0))


func _on_lectern(seats: int) -> void:
	lectern.append(seats)


func _on_picks(names: PackedStringArray, _standing: bool, at: Vector2) -> void:
	picks = names
	picks_place = at


func _on_cleared(room_id: StringName) -> void:
	cleared.append(room_id)


func _start(seats: Array) -> void:
	for seat: int in seats:
		input.add_virtual_device(seat)
	events.emit_signal("hub_requested", seats[0])


func _hub() -> RoomBase:
	return registry.call("get_resource", &"rooms", FlowScript.HUB_ROOM_ID) as RoomBase


## Put seat `seat`'s wizard in the gate (spread round its centre), at the lectern, or away from both.
func _place(seat: int, where: StringName) -> void:
	var wizard := flow.get_wizard(seat)
	match where:
		&"gate":
			var centre: Vector2 = HubRules.area_of(_hub().places(), HubRules.ROLE_TRIAL_GATE).get_center()
			wizard.position = centre + Vector2(-24.0 + 16.0 * seat, 8.0)
		&"lectern":
			wizard.position = HubRules.area_of(_hub().places(), HubRules.ROLE_TRIAL_LECTERN).get_center()
		_:
			wizard.position = _hub().places().player_spawns[seat]


func _pick(seat: int, room_id: StringName) -> void:
	events.call("apply_command", &"trial_picked", [seat, room_id])


func _press_a(seat: int) -> void:
	events.call("apply_command", &"run_requested", [seat])


func _last() -> Vector3i:
	return gate.back() if not gate.is_empty() else Vector3i(-1, -1, -1)


## The next physics step starts: the frames service sends a run's start the game asked for.
func _from_frames() -> void:
	frames.call(&"begin_step", DT)


## Every enemy of the trial dies (as Combat says it).
func _kill_all() -> void:
	for enemy: Node in flow.get("_enemies").duplicate():
		events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO, -1)


func _cards(seat: int, staff: int) -> Array[StringName]:
	return (flow.get_wizard(seat) as Actor).caster.cards_of(staff)


## Seats 0 and 1 in the hub, both in the gate, both picking the arena: the gate is lit.
func _lit_gate() -> void:
	_start([0, 1])
	_place(0, &"gate")
	_place(1, &"gate")
	_pick(0, ARENA)
	_pick(1, ARENA)
	flow.step(DT)


func test_the_lectern_offers_every_fighting_room_and_never_the_hub_or_sandbox() -> void:
	var offered: Array[RoomBase] = RoomBase.offered_for_trial(registry.call("get_all", &"rooms"))
	var ids: Array[StringName] = []
	for room in offered:
		ids.append(room.id)
	check(ids.has(ARENA), "the crypt arena is offered")
	check(not ids.has(FlowScript.HUB_ROOM_ID) and not ids.has(FlowScript.SANDBOX_ROOM_ID), "never the hub or the sandbox")
	var sorted: Array[StringName] = ids.duplicate()
	sorted.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	check_equal(ids, sorted, "by id")
	check(flow.is_trial_room(ARENA) and not flow.is_trial_room(FlowScript.HUB_ROOM_ID) and not flow.is_trial_room(&"no_such_room"), "Flow's check is the same rule")


func test_each_wizards_pick_is_its_own_and_only_a_room_offered() -> void:
	_start([0, 1])
	_pick(0, ARENA)
	check_equal(flow.hub.picks, [ARENA, &"", &"", &""] as Array[StringName], "seat 0 picked the arena, seat 1 nothing")
	check_equal(picks.slice(0, 2), PackedStringArray(["Crypt arena", ""]), "told by the rooms' shown names, by seat")
	check(picks_place != Vector2.ZERO, "over the gate")
	_pick(1, FlowScript.SANDBOX_ROOM_ID)
	_pick(1, &"no_such_room")
	check_equal(flow.hub.picks[1], &"", "a room the lectern does not offer is no pick")
	_pick(3, ARENA)
	check_equal(flow.hub.picks[3], &"", "a seat with no wizard picks nothing")
	_pick(0, &"")
	check_equal(flow.hub.picks[0], &"", "a pick taken back (no room)")
	_pick(0, ARENA)
	input.leave(0)
	check_equal(flow.hub.picks[0], &"", "a seat leaving forgets its pick")
	flow.stop_run()
	check_equal(picks, PackedStringArray(["", "", "", ""]), "leaving the hub clears what is drawn")


func test_the_lectern_says_who_stands_at_it() -> void:
	_start([0, 1])
	flow.step(DT)
	check(lectern.is_empty() or lectern.back() == 0, "nobody at first")
	_place(1, &"lectern")
	flow.step(DT)
	check_equal(lectern.back(), 0b10, "seat 1 stands at it")
	_place(1, &"away")
	flow.step(DT)
	check_equal(lectern.back(), 0, "and left")


func test_the_gate_lights_only_with_everyone_in_it_and_one_pick() -> void:
	_start([0, 1])
	_place(0, &"gate")
	_place(1, &"gate")
	flow.step(DT)
	check_equal(_last(), Vector3i(2, 2, 0), "both in it, no pick: dark")
	_pick(0, ARENA)
	check(not flow.is_gate_lit(), "one pick: dark")
	_pick(1, ARENA)
	check_equal(_last(), Vector3i(2, 2, 1), "both picked the arena: lit")
	check(flow.is_gate_lit(), "lit")
	var gate_prop: Actor = null
	for prop: Node in flow.room_props():
		if (prop as Actor).prop.role == HubRules.ROLE_TRIAL_GATE:
			gate_prop = prop as Actor
	await commands_applied()
	check(gate_prop != null and gate_prop.state_triggers.state_id() == HubRules.LIT, "the gate prop is lit")
	_place(1, &"away")
	flow.step(DT)
	check_equal(_last(), Vector3i(1, 2, 0), "one stepping off puts it out")
	_place(1, &"gate")
	flow.step(DT)
	check(flow.is_gate_lit(), "lit again")
	input.add_virtual_device(2)
	check_equal(_last(), Vector3i(2, 3, 0), "a joiner puts it out at once (in no gate, no pick)")
	_press_a(0)
	_from_frames()
	check_equal(flow.mode, FlowScript.MODE_HUB, "A on the dark gate starts nothing")
	input.leave(2)
	check(flow.is_gate_lit(), "lit with the joiner gone")
	await commands_applied()
	_pick(1, &"")
	check(not flow.is_gate_lit(), "a pick taken back puts it out")
	check_equal(flow.mode, FlowScript.MODE_HUB, "still the hub")


## Through the lit gate the party goes into the room every wizard picked, by a start of its own
## that names the room; every wizard goes in as the player it is, and the hub stands until the
## start comes.
func test_a_on_the_lit_gate_sends_the_party_to_the_room() -> void:
	_lit_gate()
	var built: Array[StringName] = [&"bolt", &"dash", &"bolt"]
	events.emit_signal("staff_cards_requested", 1, 1, built, (flow.get_wizard(1) as Actor).key())
	await commands_applied()
	var starts: Array[Array] = []
	var hear: Callable = func(player: int, room_id: StringName) -> void: starts.append([player, room_id])
	events.connect("trial_requested", hear)
	_press_a(1)
	check_equal(flow.mode, FlowScript.MODE_HUB, "the hub stands until the start comes")
	_from_frames()
	events.disconnect("trial_requested", hear)
	check_equal(starts, [[1, ARENA]], "the trial's start, for seat 1, in the arena")
	check_equal(flow.mode, FlowScript.MODE_TRIAL, "the trial")
	check_equal(flow.room_id, ARENA, "in the room picked")
	check_equal(flow.trial_room, ARENA, "its room kept")
	check_equal(_cards(1, 1).slice(0, 3), built, "seat 1 went in with the staff it built")
	check_equal(_last(), Vector3i(0, 0, 0), "the hub left: the gate says so")
	check_equal(flow.wave, 0, "no waves")
	check(flow.enemies_left() > 0, "a room that stands no enemies of its own: one wave of the run's enemy")


## Cleared, the party is back in the hub as it left it: what it built in the hub comes back, what
## it changed in the trial does not.
func test_the_trial_cleared_brings_the_party_back_as_it_left() -> void:
	_lit_gate()
	var built: Array[StringName] = [&"bolt", &"dash", &"bolt"]
	events.emit_signal("staff_cards_requested", 1, 1, built, (flow.get_wizard(1) as Actor).key())
	await commands_applied()
	_press_a(0)
	_from_frames()
	check_equal(flow.mode, FlowScript.MODE_TRIAL, "in the trial")
	var changed: Array[StringName] = [&"dash"]
	events.emit_signal("staff_cards_requested", 1, 1, changed, (flow.get_wizard(1) as Actor).key())
	await commands_applied()
	check_equal(_cards(1, 1).slice(0, 1), changed, "seat 1 rebuilt its staff in the trial")
	_kill_all()
	check_equal(cleared, [ARENA] as Array[StringName], "the room is cleared")
	check_equal(flow.mode, FlowScript.MODE_TRIAL, "the kill is seen out first")
	flow.step(FlowScript.TRIAL_CLEARED_DELAY)
	_from_frames()
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub")
	check_equal(_cards(1, 1).slice(0, 3), built, "with the staff seat 1 built in the hub, not the trial's")
	check_equal(flow.hub.picks, [&"", &"", &"", &""] as Array[StringName], "no picks left over")


func test_everyone_down_in_the_trial_brings_the_party_back() -> void:
	_lit_gate()
	_press_a(0)
	_from_frames()
	check_equal(flow.mode, FlowScript.MODE_TRIAL, "in the trial")
	for seat in [0, 1]:
		var wizard := flow.get_wizard(seat) as Actor
		wizard.health.take(wizard.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	_from_frames()
	check_equal(flow.mode, FlowScript.MODE_HUB, "back in the hub")
	check(flow.get_wizard(0) != null and flow.get_wizard(1) != null, "everyone with it")
	check(not (flow.get_wizard(0) as Actor).is_down(), "standing")


## A trial recorded is a recording of its own whose header names the room and carries the party; a
## machine playing it from its start stands in the same room with the same players, and the way
## back is a recording of its own that carries the party back.
func test_the_trial_is_recorded_with_its_room_and_party() -> void:
	_lit_gate()
	var built: Array[StringName] = [&"bolt", &"dash", &"bolt"]
	events.emit_signal("staff_cards_requested", 1, 1, built, (flow.get_wizard(1) as Actor).key())
	await commands_applied()
	var anew: Array[Replay] = []
	var hear: Callable = func(next: Replay) -> void: anew.append(next)
	frames.connect(&"recorded_anew", hear)
	frames.call(&"record", &"hub_requested", 0)
	_place(0, &"gate")
	_place(1, &"gate")
	_pick(0, ARENA)
	_pick(1, ARENA)
	flow.step(DT)
	_press_a(0)
	_from_frames()
	check_equal(anew.size(), 1, "the trial is recorded anew")
	var trial: Replay = anew[0] if anew.size() == 1 else null
	if trial != null:
		check_equal(trial.start, &"trial_requested", "by the trial's start")
		check_equal(trial.start_room, ARENA, "naming its room")
		check(trial.party.of(1) != null and trial.party.of(1).staff_cards(1).slice(0, 3) == built, "carrying the hub's party")
		var back: Replay = Replay.from_bytes(trial.to_bytes())
		check(back != null and back.start_room == ARENA, "through its bytes")
	check_equal(flow.mode, FlowScript.MODE_TRIAL, "in the trial")
	for seat in [0, 1]:
		var wizard := flow.get_wizard(seat) as Actor
		wizard.health.take(wizard.health.max_health)
	flow.step(FlowScript.RESTART_DELAY)
	_from_frames()
	check_equal(anew.size(), 2, "the way back recorded anew")
	if anew.size() == 2:
		check_equal(anew[1].start, &"hub_requested", "by the hub's start")
		check(anew[1].party.of(1) != null and anew[1].party.of(1).staff_cards(1).slice(0, 3) == built, "carrying the party back as it left")
	frames.disconnect(&"recorded_anew", hear)
	frames.call(&"stop_recording")
	if trial == null:
		return
	# A machine that never had the hub plays the trial from its start.
	flow.stop_run()
	for index in 4:
		input.leave(index)
	check(frames.call(&"play", trial), "the trial's recording plays")
	check_equal(flow.mode, FlowScript.MODE_TRIAL, "in the trial")
	check_equal(flow.room_id, ARENA, "in its room")
	check(flow.get_wizard(1) != null and _cards(1, 1).slice(0, 3) == built, "seat 1 holds the staff it built in the hub there")


## A room that stands its own enemies (a boss's arena stands its boss) is fought against those, no
## wave; the trial is won when they are down.
func test_a_room_that_stands_its_enemies_is_fought_against_them() -> void:
	var arena: RoomBase = registry.call("get_resource", &"rooms", ARENA) as RoomBase
	var enemy: EnemyBase = registry.call("get_resource", &"enemies", FlowScript.DEFAULT_ENEMY_ID) as EnemyBase
	var layout: Node = arena.scene.instantiate()
	var stand_in := StandInScript.new() as Node2D
	stand_in.name = "Boss"
	stand_in.set("enemy", enemy)
	stand_in.position = arena.places().enemy_spawns[0]
	layout.add_child(stand_in)
	stand_in.owner = layout
	var scene := PackedScene.new()
	check_equal(scene.pack(layout), OK, "the test room packs")
	layout.free()
	var room := RoomBase.new()
	room.id = &"test_trial_room"
	room.scene = scene
	registry.call("add", &"rooms", room)
	_start([0])
	_place(0, &"gate")
	_pick(0, room.id)
	flow.step(DT)
	check(flow.is_gate_lit(), "a new room is offered by itself")
	_press_a(0)
	_from_frames()
	check_equal(flow.room_id, room.id, "in the test room")
	check_equal(flow.enemies_left(), 1, "its one enemy, no wave")
	_kill_all()
	check_equal(cleared, [room.id] as Array[StringName], "won when it is down")


## A room offered that stands no enemies and has no enemy spawns is won as it starts: no trial is
## ever stuck there.
func test_a_room_with_no_enemies_at_all_is_won_at_once() -> void:
	var layout := Node2D.new()
	layout.name = "Empty"
	var spawns := Node2D.new()
	spawns.name = "PlayerSpawns"
	layout.add_child(spawns)
	spawns.owner = layout
	for seat in 4:
		var marker := Marker2D.new()
		marker.name = "P%d" % (seat + 1)
		marker.position = Vector2(100.0 + 40.0 * seat, 200.0)
		spawns.add_child(marker)
		marker.owner = layout
	var scene := PackedScene.new()
	check_equal(scene.pack(layout), OK, "the test room packs")
	layout.free()
	var room := RoomBase.new()
	room.id = &"test_empty_room"
	room.scene = scene
	registry.call("add", &"rooms", room)
	_start([0])
	_place(0, &"gate")
	_pick(0, room.id)
	flow.step(DT)
	_press_a(0)
	_from_frames()
	check_equal(flow.room_id, room.id, "in the empty room")
	check_equal(cleared, [room.id] as Array[StringName], "won as it starts")
	flow.step(FlowScript.TRIAL_CLEARED_DELAY)
	_from_frames()
	check_equal(flow.mode, FlowScript.MODE_HUB, "and back in the hub")


## A hub's start while the trial is still fought changes nothing: only its end goes back.
func test_a_hub_start_mid_trial_leaves_the_fight_alone() -> void:
	_lit_gate()
	_press_a(0)
	_from_frames()
	check_equal(flow.mode, FlowScript.MODE_TRIAL, "in the trial")
	events.emit_signal("hub_requested", 0)
	check_equal(flow.mode, FlowScript.MODE_TRIAL, "still in the trial")
	check_equal(flow.room_id, ARENA, "in its room")


## The frames service records no trial that names no room (its own decoder would refuse it).
func test_a_trial_with_no_room_is_never_recorded() -> void:
	check(frames.call(&"record", &"trial_requested", 0) == null, "nothing recorded")
	check(not frames.call(&"is_recording"), "and nothing is being recorded")


## The sandbox's enemy arena lists and spawns bosses too (content/bosses).
func test_the_sandbox_spawns_a_boss() -> void:
	var boss: EnemyBase = (registry.call("get_resource", &"enemies", FlowScript.DEFAULT_ENEMY_ID) as EnemyBase).duplicate() as EnemyBase
	boss.id = &"test_boss"
	registry.call("add", &"bosses", boss)
	input.add_virtual_device(0)
	events.emit_signal("sandbox_requested", 0)
	check_equal(flow.spawn_in_sandbox(&"test_boss", 1), 1, "a boss spawns in the sandbox")
