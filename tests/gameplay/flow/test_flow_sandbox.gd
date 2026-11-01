extends "res://tests/support/suite.gd"
## The sandbox run (staffs B7): `sandbox_requested` starts the sandbox room with both dummies and
## no wave, `sandbox_changed` tells the HUD, the sandbox actions add imps and put fresh dummies
## back, a cleared imp wave starts no build break, and everyone down stands up again with their
## staffs kept. 1, 2 and 4 players. Uses the real autoloads; time moves through Flow.step().

const FlowScript := preload("res://gameplay/flow/flow.gd")

var flow: FlowScript
var input: Node
var events: Node
var sandbox_flags: Array[bool] = []
var waves: Array[int] = []
var cleared: int = 0


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	events = root.get_node("Events")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	sandbox_flags.clear()
	waves.clear()
	cleared = 0
	events.connect("sandbox_changed", _on_sandbox_changed)
	events.connect("wave_started", _on_wave_started)
	events.connect("room_cleared", _on_room_cleared)


func after_each() -> void:
	events.disconnect("sandbox_changed", _on_sandbox_changed)
	events.disconnect("wave_started", _on_wave_started)
	events.disconnect("room_cleared", _on_room_cleared)
	flow.stop_run()
	flow.world_parent = null
	for index in 4:
		input.leave(index)


func _on_sandbox_changed(on: bool) -> void:
	sandbox_flags.append(on)


func _on_wave_started(number: int) -> void:
	waves.append(number)


func _on_room_cleared(_room_id: StringName) -> void:
	cleared += 1


func _start(count: int) -> void:
	for index in count:
		input.add_virtual_device(index)
	events.emit_signal("sandbox_requested", 0)


func _wizards() -> Array[Actor]:
	var found: Array[Actor] = []
	for index in 4:
		var wizard := flow.get_wizard(index) as Actor
		if wizard != null:
			found.append(wizard)
	return found


## The dummies the sandbox room should stand: `Flow.dummy_id` for each of its spawns.
func _wanted_ids() -> Array[StringName]:
	var room: RoomBase = root.get_node("Registry").call("get_resource", &"rooms", FlowScript.SANDBOX_ROOM_ID) as RoomBase
	var ids: Array[StringName] = []
	for i in room.dummy_spawns.size():
		ids.append(FlowScript.dummy_id(i))
	return ids


func _dummy_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for dummy: Node in flow.dummies():
		ids.append((dummy.get("data") as EnemyBase).id)
	return ids


func test_sandbox_starts_the_sandbox_room_with_both_dummies() -> void:
	for count: int in [1, 2, 4]:
		_start(count)
		check(flow.sandbox, "%d players: the run is a sandbox" % count)
		check_equal(flow.room_id, FlowScript.SANDBOX_ROOM_ID, "%d players: the room" % count)
		check_equal(_wizards().size(), count, "%d players: a wizard each" % count)
		check_equal(_dummy_ids(), _wanted_ids(), "%d players: the training and the shooting dummy stand, and the group" % count)
		check_equal(flow.enemies_left(), 0, "%d players: no wave" % count)
		check_equal(waves, [] as Array[int], "%d players: no wave_started" % count)
		check_equal(sandbox_flags, [true] as Array[bool], "%d players: sandbox_changed(true) once" % count)
		flow.stop_run()
		for index in 4:
			input.leave(index)
		sandbox_flags.clear()


func test_spawns_past_the_named_dummies_stand_training_dummies() -> void:
	check_equal(FlowScript.dummy_id(0), &"training_dummy", "the first")
	check_equal(FlowScript.dummy_id(1), &"shooting_dummy", "the second")
	check_equal(FlowScript.dummy_id(2), &"training_dummy", "every one after is a training dummy")
	check_equal(FlowScript.dummy_id(5), &"training_dummy", "every one after is a training dummy")


func test_the_dummies_stand_at_the_rooms_dummy_spawns() -> void:
	_start(1)
	var room: RoomBase = root.get_node("Registry").call("get_resource", &"rooms", FlowScript.SANDBOX_ROOM_ID) as RoomBase
	var dummies: Array[Node] = flow.dummies()
	for i in dummies.size():
		check_equal((dummies[i] as Node2D).position, room.dummy_spawns[i], "dummy %d stands at its spawn" % i)


func test_play_after_the_sandbox_is_the_normal_game() -> void:
	_start(1)
	flow.stop_run()
	check_equal(sandbox_flags, [true, false] as Array[bool], "stopping the sandbox sends sandbox_changed(false)")
	events.emit_signal("play_requested", 0)
	check(not flow.sandbox, "Play is not a sandbox")
	check_equal(flow.room_id, FlowScript.DEFAULT_ROOM_ID, "Play starts the normal room")
	check_equal(flow.dummies().size(), 0, "no dummies in the normal game")
	check_equal(sandbox_flags.back(), false, "the normal game says it is no sandbox")


func test_sandbox_is_ignored_while_a_run_is_on() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)
	events.emit_signal("sandbox_requested", 0)
	check(not flow.sandbox, "a sandbox request mid-run changes nothing")
	check_equal(flow.room_id, FlowScript.DEFAULT_ROOM_ID, "the normal room stays")


func test_the_enemy_arena_spawns_any_enemy_and_clears_them() -> void:
	_start(1)
	events.emit_signal("sandbox_spawn_requested", 0, &"storm_fork", 3)
	check_equal(flow.enemies_left(), 3, "three Storm Forks")
	check_equal(flow.spawn_in_sandbox(&"splinter", 2), 2, "and two Splinters, from code too")
	check_equal(flow.spawn_in_sandbox(&"no_such_enemy", 2), 0, "an unknown id spawns nothing")
	check_equal(flow.spawn_in_sandbox(&"splinter", 100), FlowScript.WAVE_MAX - 5, "never past WAVE_MAX")
	events.emit_signal("sandbox_action_requested", 0, FlowScript.ACTION_CLEAR_ENEMIES)
	check_equal(flow.enemies_left(), 0, "clear takes them all")
	check_equal(flow.dummies().size(), _wanted_ids().size(), "the dummies stay")
	check_equal(cleared, 0, "and clearing starts no break")


func test_the_enemy_arena_is_only_in_the_sandbox() -> void:
	for index in 1:
		input.add_virtual_device(index)
	events.emit_signal("play_requested", 0)
	check_equal(flow.spawn_in_sandbox(&"storm_fork", 3), 0, "Play has no arena")


func test_killing_the_arenas_enemies_starts_no_break() -> void:
	_start(1)
	flow.spawn_in_sandbox(&"ember_imp", 5)
	for enemy: Node in flow._enemies.duplicate():
		events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO, -1)
	check_equal(flow.enemies_left(), 0, "the enemies are gone")
	check_equal(cleared, 0, "no room_cleared in the sandbox")
	check_equal(flow.build_break_left(), 0.0, "no build break")
	check_equal(flow.state, FlowScript.State.RUNNING, "the sandbox keeps running")


func test_reset_dummies_puts_fresh_ones_back() -> void:
	_start(1)
	var old: Array[Node] = flow.dummies()
	# The shooting dummy can be killed; reset brings it back.
	events.emit_signal("enemy_died", 0, old[1], Vector2.ZERO, -1)
	check_equal(flow.dummies().size(), _wanted_ids().size() - 1, "a killed dummy is gone")
	events.emit_signal("sandbox_action_requested", 0, FlowScript.ACTION_RESET_DUMMIES)
	var fresh: Array[Node] = flow.dummies()
	check_equal(_dummy_ids(), _wanted_ids(), "every dummy stands again")
	check(not fresh.has(old[0]), "the training dummy is a new one")
	check(not is_instance_valid(old[0]) or not old[0].is_inside_tree(), "the old training dummy left the room")


func test_actions_out_of_the_sandbox_do_nothing() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)
	var imps: int = flow.enemies_left()
	events.emit_signal("sandbox_spawn_requested", 0, &"ember_imp", 5)
	events.emit_signal("sandbox_action_requested", 0, FlowScript.ACTION_RESET_DUMMIES)
	check_equal(flow.enemies_left(), imps, "no imps added to the normal game")
	check_equal(flow.dummies().size(), 0, "no dummies in the normal game")


func test_everyone_down_stands_up_with_their_staffs() -> void:
	for count: int in [1, 4]:
		_start(count)
		var world: Node = flow.world
		var first := _wizards()[0]
		events.emit_signal("staff_change_requested", PlayerController.of(first).seat, 2, 0, &"nova")
		for wizard in _wizards():
			wizard.health.take(wizard.health.max_health)
		check(flow.is_restarting(), "%d players: all down starts the timer" % count)
		flow.step(FlowScript.RESTART_DELAY)
		check(flow.world == world, "%d players: the same room, no restart" % count)
		for wizard in _wizards():
			check(not wizard.is_down(), "%d players: wizard %d stands again" % [count, PlayerController.of(wizard).seat])
		var cards: Array[StringName] = first.caster.cards_of(2)
		check_equal(cards[0], &"nova", "%d players: the staffs are kept" % count)
		check(not flow.is_restarting(), "%d players: the timer is off" % count)
		flow.stop_run()
		for index in 4:
			input.leave(index)


## The sandbox's own start cards (owner, 2026-11-01): Play's A and X, and the two showcase builds
## on Y and B, every card of them used (none wasted) on the sandbox's staffs.
func test_the_sandbox_starts_with_its_showcase_staffs() -> void:
	for count: int in [1, 2, 4]:
		_start(count)
		check_equal(flow.start_cards_for_mode(), FlowScript.SANDBOX_START_CARDS, "%d players: the sandbox's cards" % count)
		for wizard in _wizards():
			var seat: int = PlayerController.of(wizard).seat
			for at in 4:
				var wanted: Array[StringName] = []
				for id: Variant in FlowScript.SANDBOX_START_CARDS[at]:
					wanted.append(StringName(str(id)))
				check_equal(wizard.caster.cards_of(at).filter(func(id: StringName) -> bool: return id != &""), wanted, "%d players: seat %d staff %d holds its cards" % [count, seat, at])
		flow.stop_run()
		for index in 4:
			input.leave(index)


func test_the_showcase_builds_waste_no_card() -> void:
	var spells: Node = root.get_node("Spells")
	var dev: StaffBase = root.get_node("Registry").call("get_resource", &"wizard", FlowScript.DEV_STAFF) as StaffBase
	for at: int in [2, 3]:
		var ids: Array[StringName] = []
		for id: Variant in FlowScript.SANDBOX_START_CARDS[at]:
			ids.append(StringName(str(id)))
		check(ids.size() <= dev.slots, "staff %d fits the sandbox staff" % at)
		var view: Dictionary = spells.call("staff_view", ids, dev)
		check(not bool(view["empty"]), "staff %d casts something" % at)
		check_equal((view["wasted"] as Dictionary).size(), 0, "staff %d wastes no card" % at)
		check_equal((view["casts"] as Array).size(), 1, "staff %d is one cast" % at)
		check(float((view["casts"] as Array)[0]["mana"]) <= 100.0, "staff %d can be cast from a full pool" % at)


func test_play_keeps_its_own_start_cards() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)
	check_equal(flow.start_cards_for_mode(), flow.start_cards, "Play starts with start_cards")


## One staff per setup (owner, 2026-11-01): the sandbox's wizards hold the `dev` staff itself on
## every button, whatever the build channel, with its practically infinite mana in every pool.
func test_the_sandbox_holds_four_dev_staffs() -> void:
	var dev: StaffBase = root.get_node("Registry").call("get_resource", &"wizard", FlowScript.DEV_STAFF) as StaffBase
	check(dev.max_mana >= 1000000.0 and dev.mana_regen >= 1000000.0, "the dev staff's pool and regen are practically infinite")
	_start(2)
	for wizard in _wizards():
		for at in 4:
			check(wizard.caster.staff_of(at) == dev, "staff %d is the dev staff itself" % at)
			check_equal(wizard.caster.mana_of(at), dev.max_mana, "staff %d starts full" % at)
