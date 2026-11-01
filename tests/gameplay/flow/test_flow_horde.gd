extends "res://tests/support/suite.gd"
## The horde run (docs/milestones/horde.md, H2): `horde_requested` starts the room `horde` with a
## wizard per joined player, no waves and no dummies, the plain starter staffs in every build
## channel and the start cards; `room_entered(&"horde")` then `horde_started(world)`. Everyone down
## starts it over after HORDE_RESTART_DELAY (fresh world, `horde_started` again, no `horde_ended`);
## `horde_ended` follows `stop_run` and a run of another mode replacing it. A joiner gets a wizard
## as in any run. The camera and the projectile bounds cover the whole 1280×720 arena. 1, 2 and 4
## players. Uses the real autoloads; time moves through Flow.step().

const FlowScript := preload("res://gameplay/flow/flow.gd")

var flow: FlowScript
var input: Node
var events: Node
## Every event of interest in order, as [name, argument].
var heard: Array = []


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	events = root.get_node("Events")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	heard.clear()
	events.connect("room_entered", _on_room_entered)
	events.connect("horde_started", _on_horde_started)
	events.connect("horde_ended", _on_horde_ended)
	events.connect("wave_started", _on_wave_started)
	events.connect("sandbox_changed", _on_sandbox_changed)


func after_each() -> void:
	events.disconnect("room_entered", _on_room_entered)
	events.disconnect("horde_started", _on_horde_started)
	events.disconnect("horde_ended", _on_horde_ended)
	events.disconnect("wave_started", _on_wave_started)
	events.disconnect("sandbox_changed", _on_sandbox_changed)
	flow.stop_run()
	flow.world_parent = null
	for index in 4:
		input.leave(index)


func _on_room_entered(id: StringName) -> void:
	heard.append(["room_entered", id])


func _on_horde_started(world: Node2D) -> void:
	heard.append(["horde_started", world])


func _on_horde_ended() -> void:
	heard.append(["horde_ended", null])


func _on_wave_started(number: int) -> void:
	heard.append(["wave_started", number])


func _on_sandbox_changed(on: bool) -> void:
	heard.append(["sandbox_changed", on])


## The names heard, in order (`sandbox_changed` left out unless `all`).
func _names(all: bool = false) -> Array[String]:
	var out: Array[String] = []
	for entry: Array in heard:
		if all or entry[0] != "sandbox_changed":
			out.append(entry[0])
	return out


func _count(name: String) -> int:
	return _names(true).count(name)


func _start(count: int) -> void:
	for index in count:
		input.add_virtual_device(index)
	events.emit_signal("horde_requested", 0)


func _wizards() -> Array[Actor]:
	var found: Array[Actor] = []
	for index in 4:
		var wizard := flow.get_wizard(index) as Actor
		if wizard != null:
			found.append(wizard)
	return found


func _down_everyone() -> void:
	for wizard in _wizards():
		wizard.health.take(wizard.health.max_health)


func _reset() -> void:
	flow.stop_run()
	for index in 4:
		input.leave(index)
	heard.clear()


func test_horde_starts_the_horde_room_with_a_wizard_each_and_no_enemies() -> void:
	for count: int in [1, 2, 4]:
		_start(count)
		check_equal(flow.mode, FlowScript.MODE_HORDE, "%d players: the mode is horde" % count)
		check(not flow.sandbox, "%d players: not a sandbox" % count)
		check_equal(flow.state, FlowScript.State.RUNNING, "%d players: the run is on" % count)
		check_equal(flow.room_id, FlowScript.HORDE_ROOM_ID, "%d players: the room" % count)
		check_equal(_wizards().size(), count, "%d players: a wizard each" % count)
		check_equal(flow.enemies_left(), 0, "%d players: no wave" % count)
		check_equal(flow.dummies().size(), 0, "%d players: no dummies" % count)
		check_equal(flow.wave, 0, "%d players: no wave number" % count)
		check_equal(_names(), ["room_entered", "horde_started"] as Array[String], "%d players: room_entered, then horde_started, and no wave_started" % count)
		check_equal(heard[0][1], &"horde", "%d players: room_entered names the horde room" % count)
		check(heard.back()[1] == flow.world and flow.world != null, "%d players: horde_started carries the world" % count)
		check(heard.has(["sandbox_changed", false]), "%d players: the HUD hears it is no sandbox" % count)
		var actors: int = 0
		for node: Node in flow.world.find_children("*", "Actor", true, false):
			actors += 1
		check_equal(actors, count, "%d players: the only actors are the wizards" % count)
		_reset()


func test_the_horde_gets_the_basic_staffs_and_the_horde_cards() -> void:
	var registry: Node = root.get_node("Registry")
	for name: String in ["one run", "another run"]:
		_start(1)
		var wizard: Actor = flow.get_wizard(0) as Actor
		check(wizard != null, "%s: a wizard" % name)
		if wizard == null:
			_reset()
			continue
		for at in 4:
			var head: StaffBase = registry.call("get_resource", &"wizard", FlowScript.STARTER_HEADS[at]) as StaffBase
			var staff: StaffBase = wizard.caster.staff_of(at)
			check(staff == head, "%s: button %d holds the %s staff itself, not a copy" % [name, at, FlowScript.STARTER_HEADS[at]])
		check_equal(wizard.caster.cards_of(0)[0], &"dash", "%s: RB starts with dash" % name)
		check_equal(wizard.caster.cards_of(1).slice(0, 1), [&"swing"] as Array[StringName], "%s: RT starts with swing" % name)
		for empty: int in [2, 3]:
			check(wizard.caster.cards_of(empty).all(func(id: StringName) -> bool: return id == &""), "%s: staff %d starts empty" % [name, empty])
		_reset()


func test_the_camera_and_the_shots_cover_the_whole_arena() -> void:
	_start(1)
	var camera: Camera2D = null
	for node: Node in flow.world.get_children():
		if node is Camera2D:
			camera = node as Camera2D
	check(camera != null, "the world has a camera")
	if camera != null:
		check_equal(Vector2(camera.limit_right, camera.limit_bottom), Vector2(1280, 720), "the camera's limits are the arena")
	var room: RoomBase = root.get_node("Registry").call("get_resource", &"rooms", FlowScript.HORDE_ROOM_ID) as RoomBase
	check_equal(FlowScript.room_size(room, own(room.scene.instantiate()) as Node), Vector2(1280.0, 720.0), "the room size comes from the floor")


func test_the_m1_rooms_keep_their_size() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in [&"arena_01", &"sandbox"]:
		var room: RoomBase = registry.call("get_resource", &"rooms", id) as RoomBase
		var layout: Node = own(room.scene.instantiate()) as Node
		check_equal(FlowScript.room_size(room, layout), FlowScript.room_size(room), "%s: the floor does not change its size" % id)


func test_everyone_down_starts_it_over_after_the_horde_delay() -> void:
	for count: int in [1, 4]:
		_start(count)
		var old_world: Node2D = flow.world
		_down_everyone()
		check(flow.is_restarting(), "%d players: all down starts the timer" % count)
		flow.step(FlowScript.RESTART_DELAY)
		check(flow.world == old_world, "%d players: not after the waves' short delay" % count)
		flow.step(FlowScript.HORDE_RESTART_DELAY - FlowScript.RESTART_DELAY - 0.25)
		check(flow.world == old_world, "%d players: still the old world just before the horde delay" % count)
		flow.step(0.5)
		check(flow.world != old_world and flow.world != null, "%d players: a fresh world after %f s" % [count, FlowScript.HORDE_RESTART_DELAY])
		check_equal(flow.mode, FlowScript.MODE_HORDE, "%d players: still a horde run" % count)
		check_equal(_wizards().size(), count, "%d players: a wizard each again" % count)
		for wizard in _wizards():
			check(not wizard.is_down(), "%d players: wizard %d stands" % [count, PlayerController.of(wizard).seat])
		check_equal(_names(), ["room_entered", "horde_started", "room_entered", "horde_started"] as Array[String], "%d players: horde_started again, no horde_ended" % count)
		check(heard.back()[1] == flow.world, "%d players: the new horde_started carries the new world" % count)
		_reset()


func test_horde_ended_on_stop_run_once() -> void:
	_start(2)
	flow.stop_run()
	check_equal(_count("horde_ended"), 1, "stopping sends horde_ended")
	check_equal(flow.mode, FlowScript.MODE_WAVES, "flow is back to the waves mode")
	flow.stop_run()
	check_equal(_count("horde_ended"), 1, "a second stop sends nothing more")


func test_play_after_the_horde_is_the_normal_game_and_ends_it_once() -> void:
	_start(1)
	flow.stop_run()
	events.emit_signal("play_requested", 0)
	check_equal(flow.mode, FlowScript.MODE_WAVES, "Play is the waves")
	check_equal(flow.room_id, FlowScript.DEFAULT_ROOM_ID, "Play starts the normal room")
	check(flow.enemies_left() > 0, "with a wave")
	check_equal(_count("horde_ended"), 1, "horde_ended once")
	check_equal(_count("horde_started"), 1, "Play sends no horde_started")


func test_another_mode_replacing_the_horde_ends_it() -> void:
	_start(1)
	flow.mode = FlowScript.MODE_WAVES
	check(flow.start_run(0), "a waves run starts over the horde")
	check_equal(_names(), ["room_entered", "horde_started", "horde_ended", "room_entered", "wave_started"] as Array[String], "horde_ended before the new run's events")


func test_no_horde_events_outside_the_horde() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)
	flow.stop_run()
	events.emit_signal("sandbox_requested", 0)
	flow.stop_run()
	check_equal(_count("horde_started") + _count("horde_ended"), 0, "Play and the sandbox send no horde event")


func test_horde_is_ignored_while_a_run_is_on() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)
	events.emit_signal("horde_requested", 0)
	check_equal(flow.mode, FlowScript.MODE_WAVES, "a horde request mid-run changes nothing")
	check_equal(flow.room_id, FlowScript.DEFAULT_ROOM_ID, "the normal room stays")
	check_equal(_count("horde_started"), 0, "no horde_started")


func test_a_joiner_gets_a_wizard_with_the_horde_staffs() -> void:
	_start(1)
	input.add_virtual_device(1)
	events.emit_signal("player_joined", 1)
	var joiner: Actor = flow.get_wizard(1) as Actor
	check(joiner != null, "the joiner has a wizard")
	if joiner != null:
		var head: StaffBase = root.get_node("Registry").call("get_resource", &"wizard", FlowScript.STARTER_HEADS[0]) as StaffBase
		check(joiner.caster.staff_of(0) == head, "the joiner holds the basic staffs too")
		check(joiner.get_parent() == flow.world, "in the horde world")
	check_equal(_count("horde_started"), 1, "a join starts nothing over")


func test_a_join_during_the_countdown_does_not_call_it_off() -> void:
	_start(1)
	var old_world: Node2D = flow.world
	_down_everyone()
	input.add_virtual_device(1)
	events.emit_signal("player_joined", 1)
	check(flow.is_restarting(), "the horde is over: the countdown goes on")
	flow.step(FlowScript.HORDE_RESTART_DELAY)
	check(flow.world != old_world, "the horde starts over")
	check_equal(_wizards().size(), 2, "with the joiner")
