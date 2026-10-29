extends SceneTree
## Tests for gameplay/flow (the M1 arena glue), on the real autoloads: Play starts
## the room with 1, 2 and 4 players, the wave is fixed, `room_entered` and
## `room_cleared` are sent once, every wizard builds the two start spells, the cooldowns are reset on a new run,
## the room restarts in under 3 seconds when every player is down (and not while
## one still stands), and the first room is up in the same call. Time moves by
## fixed deltas through Flow.step(); nothing waits.
##
## godot --headless --path . --script res://tests/gameplay/flow/test_flow.gd

const FlowScript := preload("res://gameplay/flow/flow.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

var _failures: Array[String] = []
var _events: Node
var _flow: FlowScript
var _input: InputManagerScript
var _combat: Node
var _spells: SpellsScript
var _entered: Array[StringName] = []
var _cleared: Array[StringName] = []
var _waves: Array[int] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_events = root.get_node_or_null("Events")
	_flow = root.get_node_or_null("Flow") as FlowScript
	_input = root.get_node_or_null("PlayerInput") as InputManagerScript
	_combat = root.get_node_or_null("Combat")
	var registry: Node = root.get_node_or_null("Registry")
	if _events == null or _flow == null or _input == null or _combat == null or registry == null:
		printerr("TEST FAILED: the Events, Registry, PlayerInput, Combat and Flow autoloads must exist")
		quit(1)
		return
	_spells = root.get_node_or_null("Spells") as SpellsScript
	_events.connect("room_entered", func(id: StringName) -> void: _entered.append(id))
	_events.connect("room_cleared", func(id: StringName) -> void: _cleared.append(id))
	_events.connect("wave_started", func(number: int) -> void: _waves.append(number))
	_test_restart_delay_is_under_three_seconds()
	for count: int in [1, 2, 4]:
		_test_play_starts_the_room(count)
	_test_keyboard_joins_when_nobody_has()
	_test_play_is_ignored_while_running()
	_test_unjoined_requester_other_than_p1_starts_nothing()
	_test_cooldowns_reset_on_a_new_run()
	_test_room_cleared_once_when_the_wave_is_dead()
	_test_possessed_enemy_does_not_strand_the_room()
	_test_restart_when_all_down()
	_test_no_restart_while_one_stands()
	_test_revive_cancels_the_restart()
	_test_no_restart_after_clear()
	_test_last_enemy_dies_after_all_down()
	_test_failed_restart_goes_idle()
	_test_play_keeps_joined_pad_without_keyboard()
	_test_wave_stands_on_floor()
	_test_biggest_wave_stands_on_floor()
	_test_restart_leaves_no_old_enemies_or_shots()
	_test_walls_reach_the_projectile_manager()
	_test_waves_grow_in_the_same_room()
	_test_wave_size_is_capped()
	_test_next_wave_stands_up_downed_wizards()
	_test_restart_goes_back_to_wave_one()
	_test_build_break_is_fixed()
	_test_build_break_ignores_builders()
	_test_main_menu_only_sends_play_requested()
	_stop()
	if _failures.is_empty():
		print("TEST OK: gameplay/flow (play, wave, room_entered, room_cleared, restart)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## Fresh state with `count` players joined by virtual devices (slots 0..count-1).
func _setup(count: int) -> void:
	_stop()
	for index in count:
		_input.add_virtual_device(index)
	_entered.clear()
	_cleared.clear()
	_waves.clear()


## End the run and free every device, so the next test starts clean.
func _stop() -> void:
	_flow.stop_run()
	for index in InputManagerScript.MAX_PLAYERS:
		_input.leave(index)


func _play(requester: int = 0) -> void:
	_events.emit_signal("play_requested", requester)


func _wizards() -> Array[Actor]:
	var found: Array[Actor] = []
	for index in InputManagerScript.MAX_PLAYERS:
		var wizard := _flow.get_wizard(index) as Actor
		if wizard != null:
			found.append(wizard)
	return found


## The wizard actor of player `index` (actors G7: a wizard is an Actor; its seat is its
## PlayerController's).
func _wizard(index: int) -> Actor:
	return _flow.get_wizard(index) as Actor


func _seat(wizard: Actor) -> int:
	var seat: PlayerController = PlayerController.of(wizard)
	return seat.seat if seat != null else -1


## A hit that takes all of `wizard`'s health.
func _down(wizard: Actor) -> void:
	wizard.health.take(wizard.health.max_health)


func _test_restart_delay_is_under_three_seconds() -> void:
	_check(FlowScript.RESTART_DELAY < 3.0, "the restart delay must be under 3 seconds, is %f" % FlowScript.RESTART_DELAY)


func _test_play_starts_the_room(count: int) -> void:
	_setup(count)
	var started: int = Time.get_ticks_msec()
	_play()
	var took: int = Time.get_ticks_msec() - started
	_check(took < 10000, "%d players: the first room took %d ms, must be under 10 s" % [count, took])
	_check(_flow.state == FlowScript.State.RUNNING, "%d players: flow is running after play_requested" % count)
	_check(_flow.world != null and _flow.world.is_inside_tree(), "%d players: the world is in the tree" % count)
	_check(_entered == [&"arena_01"], "%d players: room_entered(arena_01) was sent once, got %s" % [count, _entered])
	_check(_wizards().size() == count, "%d players: %d wizards spawned" % [count, _wizards().size()])
	for index in count:
		var wizard: Actor = _wizard(index)
		_check(wizard != null and _seat(wizard) == index and wizard.ramp == index and wizard.caster.has_staff(0) and wizard.caster.has_staff(1), "%d players: wizard %d has its seat, its ramp and its dash and bolt staffs" % [count, index])
		_check(wizard != null and wizard.caster.cards_of(0)[0] == &"dash" and wizard.caster.cards_of(1).slice(0, 2) == ([&"fire", &"bolt"] as Array[StringName]), "%d players: wizard %d has the start cards" % [count, index])
		_check(wizard != null and wizard.position == Vector2(224.0 + 64.0 * index, 320.0), "%d players: wizard %d stands on its spawn" % [count, index])
	_check(_flow.enemies_left() == FlowScript.WAVE.size(), "%d players: the wave has %d enemies, got %d" % [count, FlowScript.WAVE.size(), _flow.enemies_left()])
	_check(_combat.call("actor_count") == FlowScript.WAVE.size() + count, "%d players: every enemy and wizard is registered with combat" % count)
	_check(_cleared.is_empty(), "%d players: room_cleared is not sent at the start" % count)
	_stop()


func _test_keyboard_joins_when_nobody_has() -> void:
	_setup(0)
	_play(0)
	_check(_input.is_joined(0) and _input.device_of(0) == InputManagerScript.KEYBOARD, "Play with the mouse joins the keyboard as P1")
	_check(_wizards().size() == 1, "one wizard for the keyboard player")
	_stop()


func _test_play_is_ignored_while_running() -> void:
	_setup(2)
	_play()
	var first: Node = _flow.world
	_play()
	_check(_flow.world == first, "a second play_requested does not rebuild the room")
	_check(_entered.size() == 1, "room_entered was sent once, got %d" % _entered.size())
	_stop()


func _test_unjoined_requester_other_than_p1_starts_nothing() -> void:
	_setup(0)
	_play(2)
	_check(_flow.state == FlowScript.State.IDLE and _flow.world == null, "nobody joined and requester 3 is not the keyboard: no run starts")
	_check(_entered.is_empty(), "no room_entered without a run")
	_stop()


func _test_cooldowns_reset_on_a_new_run() -> void:
	_setup(2)
	_play()
	var wizard: Actor = _wizard(1)
	var at := Vector2(100.0, 100.0)
	# Spells keeps staffs by caster: the actor id the wizard of player 2 opened (actors G3b).
	var caster: int = wizard.id
	_check(_spells.cast_staff(caster, 1, at, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "staff X fires for player 2")
	_check(_spells.cast_staff(caster, 1, at, Vector2.RIGHT, 100.0) == SpellsScript.REFUSED, "staff X waits out its delay for player 2")
	_check(_spells.cast_staff(caster, 0, at, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "staff A has its own delay")
	_flow.stop_run()
	_play()
	caster = _wizard(1).id
	_check(_spells.cast_staff(caster, 1, at, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "a new run forgot the delays")
	_check(wizard != null, "the wizard of player 2 existed")
	_stop()


func _test_room_cleared_once_when_the_wave_is_dead() -> void:
	_setup(4)
	_play()
	var enemies: Array[Node] = _flow._enemies.duplicate()
	_check(enemies.size() == FlowScript.WAVE.size(), "four players: the test sees the wave")
	for at in enemies.size() - 1:
		_events.emit_signal("enemy_died", at % 4, enemies[at], Vector2.ZERO)
	_check(_cleared.is_empty(), "room_cleared waits for the last enemy")
	_check(_flow.enemies_left() == 1, "one enemy is left")
	_events.emit_signal("enemy_died", 3, enemies[enemies.size() - 1], Vector2.ZERO)
	_check(_cleared == [&"arena_01"], "room_cleared(arena_01) was sent once, got %s" % _cleared)
	_check(_flow.state == FlowScript.State.CLEARED, "flow is in the cleared state")
	_events.emit_signal("enemy_died", 0, enemies[0], Vector2.ZERO)
	_check(_cleared.size() == 1, "a repeated death does not send room_cleared again")
	_stop()


## A player who possesses an enemy of the wave still lets the room clear: the possessed body is on
## the wizards' team while it is driven, and its death must still count as an enemy's. Bots stopped
## building `possess` because the room stayed uncleared.
func _test_possessed_enemy_does_not_strand_the_room() -> void:
	for possessed_first: bool in [true, false]:
		_setup(1)
		_play()
		var wizard: Actor = _wizard(0)
		var enemies: Array[Node] = _flow._enemies.duplicate()
		var held := enemies[0] as Actor
		var possession: Possession = Possession.begin(wizard, held, 3.0)
		_check(possession != null and held.controller == wizard.home_controller, "the wizard possesses an enemy of the wave")
		var order: Array[Node] = enemies.duplicate()
		if not possessed_first:
			order.reverse()
		for enemy: Node in order:
			_combat.call("hit", 0, enemy, 100000)
		_check(_flow.enemies_left() == 0, "possessed killed first %s: no enemy is left, %d are" % [possessed_first, _flow.enemies_left()])
		_check(_cleared == [&"arena_01"], "possessed killed first %s: the room clears, got %s" % [possessed_first, _cleared])
		_stop()


func _test_restart_when_all_down() -> void:
	for count: int in [1, 2, 4]:
		_setup(count)
		_play()
		var old_world: Node = _flow.world
		for wizard in _wizards():
			_down(wizard)
		_check(_flow.is_restarting(), "%d players: all down starts the restart timer" % count)
		_flow.step(FlowScript.RESTART_DELAY - 0.5)
		_check(_flow.world == old_world, "%d players: no restart before the delay" % count)
		_flow.step(0.5)
		_check(_flow.world != old_world and _flow.world != null, "%d players: the room restarted after %f s" % [count, FlowScript.RESTART_DELAY])
		_check(_entered.size() == 2, "%d players: room_entered was sent again for the new room, got %d" % [count, _entered.size()])
		_check(_wizards().size() == count, "%d players: the wizards are back" % count)
		for wizard in _wizards():
			_check(wizard.health.health == wizard.health.max_health and not wizard.is_down(), "%d players: wizard %d is standing at full health" % [count, _seat(wizard)])
		_check(_flow.enemies_left() == FlowScript.WAVE.size(), "%d players: a new wave stands" % count)
		_check(not _flow.is_restarting(), "%d players: the timer is off after the restart" % count)
		_stop()


func _test_no_restart_while_one_stands() -> void:
	_setup(4)
	_play()
	for index in 3:
		_down(_wizard(index))
	_check(not _flow.is_restarting(), "three of four down: no restart")
	var world: Node = _flow.world
	_flow.step(10.0)
	_check(_flow.world == world, "three of four down: the room stays")
	_stop()


func _test_revive_cancels_the_restart() -> void:
	_setup(2)
	_play()
	_down(_wizard(0))
	_down(_wizard(1))
	_check(_flow.is_restarting(), "two of two down: restarting")
	Downed.of(_wizard(0)).revive(1)
	_check(not _flow.is_restarting(), "a revive cancels the restart")
	_stop()


func _test_no_restart_after_clear() -> void:
	_setup(1)
	_play()
	for enemy: Node in _flow._enemies.duplicate():
		_events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO)
	_down(_wizard(0))
	_check(not _flow.is_restarting(), "a cleared room does not restart when the players go down")
	_stop()


## The last enemy dies (a bolt still in flight) after every wizard is down: the
## room is cleared, but the restart timer keeps running and gives a new world.
func _test_last_enemy_dies_after_all_down() -> void:
	_setup(2)
	_play()
	var old_world: Node = _flow.world
	for wizard in _wizards():
		_down(wizard)
	_check(_flow.is_restarting(), "all down: restarting")
	for enemy: Node in _flow._enemies.duplicate():
		_events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO)
	_check(_cleared == [&"arena_01"], "the room still counts as cleared, got %s" % [_cleared])
	_check(_flow.is_restarting(), "the last enemy dying does not cancel the restart")
	_flow.step(FlowScript.RESTART_DELAY)
	_check(_flow.world != old_world and _flow.world != null, "the run restarted after the last enemy died with everyone down")
	_check(_flow.state == FlowScript.State.RUNNING and _flow.enemies_left() == FlowScript.WAVE.size(), "the new run is running with a full wave")
	_stop()


## A failed restart (content gone) ends the run instead of leaving it stuck.
func _test_failed_restart_goes_idle() -> void:
	_setup(1)
	_play()
	var registry: Node = _flow.registry
	_flow.registry = null
	_down(_wizard(0))
	_flow.step(FlowScript.RESTART_DELAY)
	_flow.registry = registry
	_check(_flow.state == FlowScript.State.IDLE and _flow.world == null, "a failed restart returns flow to idle")
	_play()
	_check(_flow.state == FlowScript.State.RUNNING, "Play starts again after a failed restart")
	_stop()


## A gamepad owner already joined in a later slot keeps it: the keyboard stays out.
func _test_play_keeps_joined_pad_without_keyboard() -> void:
	_setup(0)
	_input.add_virtual_device(2)
	_play(0)
	_check(not _input.is_joined(0), "the keyboard does not take slot 0 when someone else joined")
	_check(_wizards().size() == 1 and _flow.get_wizard(2) != null, "only the joined player plays")
	_stop()


## Every wave enemy stands inside the room and clear of the walls.
func _test_wave_stands_on_floor() -> void:
	_setup(1)
	_play()
	var room: RoomBase = load("res://content/rooms/crypt/arena_01.tres") as RoomBase
	var scene: Node = room.scene.instantiate()
	var walls: Array[Rect2] = []
	for child in scene.get_node("Walls").get_children():
		var shape_node := child as CollisionShape2D
		if shape_node != null and shape_node.shape is RectangleShape2D:
			var size: Vector2 = (shape_node.shape as RectangleShape2D).size
			walls.append(Rect2(shape_node.position - size * 0.5, size))
	scene.free()
	var inner := Rect2(Vector2.ZERO, Vector2(640.0, 384.0))
	_check(_flow._enemies.size() == FlowScript.WAVE.size(), "the wave is up")
	for enemy: Node2D in _flow._enemies:
		var body := Rect2(enemy.position - Vector2(12.0, 12.0), Vector2(24.0, 24.0))
		_check(inner.encloses(body), "enemy at %s is inside the room" % enemy.position)
		for wall in walls:
			_check(not wall.intersects(body), "enemy at %s is clear of the wall %s" % [enemy.position, wall])
	_stop()


## Even the biggest wave stands on the floor: the stacked spawns stay inside the
## room and clear of the walls.
func _test_biggest_wave_stands_on_floor() -> void:
	_setup(1)
	_play()
	var room: RoomBase = load("res://content/rooms/crypt/arena_01.tres") as RoomBase
	var scene: Node = room.scene.instantiate()
	var walls: Array[Rect2] = []
	for child in scene.get_node("Walls").get_children():
		var shape_node := child as CollisionShape2D
		if shape_node != null and shape_node.shape is RectangleShape2D:
			var size: Vector2 = (shape_node.shape as RectangleShape2D).size
			walls.append(Rect2(shape_node.position - size * 0.5, size))
	scene.free()
	var inner := Rect2(Vector2.ZERO, Vector2(640.0, 384.0))
	var uses: Dictionary = {}
	for at: int in FlowScript.wave_size(FlowScript.WAVE_MAX):
		var entry: int = FlowScript.WAVE[at] if at < FlowScript.WAVE.size() else at
		var spawn: int = entry % room.enemy_spawns.size()
		var times: int = uses.get(spawn, 0)
		uses[spawn] = times + 1
		var position: Vector2 = FlowScript.stacked_position(room.enemy_spawns[spawn], times)
		var body := Rect2(position - Vector2(12.0, 12.0), Vector2(24.0, 24.0))
		_check(inner.encloses(body), "spawn %d of the biggest wave (%s) is inside the room" % [at, position])
		for wall in walls:
			_check(not wall.intersects(body), "spawn %d (%s) is clear of the wall %s" % [at, position, wall])
	_stop()


func _test_restart_leaves_no_old_enemies_or_shots() -> void:
	_setup(1)
	_play()
	var projectiles: Node = root.get_node("Projectiles")
	projectiles.call("spawn", 0, Vector2(100.0, 100.0), Vector2(10.0, 0.0), 5.0)
	_check(projectiles.call("get_count") == 1, "a shot is in the air")
	_down(_wizard(0))
	_flow.step(FlowScript.RESTART_DELAY)
	_check(projectiles.call("get_count") == 0, "the restart cleared the shots")
	_check(_combat.call("actor_count") == FlowScript.WAVE.size() + 1, "combat knows only the new wave and the wizard, got %d" % _combat.call("actor_count"))
	_stop()


## Kill every enemy of the current wave (as if shot down).
func _kill_wave() -> void:
	for enemy: Node in _flow._enemies.duplicate():
		_events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO)


## After a clear and BUILD_BREAK the next, bigger wave stands in the same world.
func _test_waves_grow_in_the_same_room() -> void:
	for count: int in [1, 4]:
		_setup(count)
		_play()
		var world: Node = _flow.world
		_check(_waves == [1] and _flow.wave == 1, "%d players: wave 1 is announced once, got %s" % [count, _waves])
		_check(_flow.enemies_left() == FlowScript.wave_size(1), "%d players: wave 1 has %d enemies" % [count, FlowScript.wave_size(1)])
		_kill_wave()
		_check(_flow.state == FlowScript.State.CLEARED and _waves == [1], "%d players: a cleared wave waits before the next" % count)
		_flow.step(FlowScript.BUILD_BREAK - 0.5)
		_check(_flow.enemies_left() == 0 and _waves == [1], "%d players: no next wave before the delay" % count)
		_flow.step(0.5)
		_check(_flow.world == world, "%d players: wave 2 stands in the same world" % count)
		_check(_waves == [1, 2] and _flow.wave == 2, "%d players: wave_started(2) was sent, got %s" % [count, _waves])
		_check(_flow.state == FlowScript.State.RUNNING, "%d players: running again" % count)
		_check(_flow.enemies_left() == FlowScript.wave_size(2), "%d players: wave 2 has %d enemies" % [count, FlowScript.wave_size(2)])
		_check(FlowScript.wave_size(2) > FlowScript.wave_size(1), "wave 2 is bigger than wave 1")
		_check(_entered.size() == 1, "%d players: room_entered is not sent again for a new wave" % count)
		_kill_wave()
		_check(_cleared.size() == 2, "%d players: room_cleared is sent for every wave, got %d" % [count, _cleared.size()])
		_flow.step(FlowScript.BUILD_BREAK)
		_check(_flow.wave == 3 and _flow.enemies_left() == FlowScript.wave_size(3), "%d players: wave 3 follows" % count)
		_stop()


## The break is BUILD_BREAK seconds, announced once with its length, and counted by `build_break_left`.
func _test_build_break_is_fixed() -> void:
	_check(FlowScript.BUILD_BREAK > 3.0, "the build break is longer than M1's 3 s delay")
	_setup(1)
	var announced: Array[float] = []
	var listener := func(seconds: float) -> void: announced.append(seconds)
	_events.connect("build_break_started", listener)
	_play()
	_check(announced.is_empty() and _flow.build_break_left() == 0.0, "no break during a wave")
	_kill_wave()
	_check(announced == [FlowScript.BUILD_BREAK], "build_break_started is sent once with BUILD_BREAK, got %s" % [announced])
	_check(is_equal_approx(_flow.build_break_left(), FlowScript.BUILD_BREAK), "the whole break is left at its start")
	_flow.step(4.0)
	_check(is_equal_approx(_flow.build_break_left(), FlowScript.BUILD_BREAK - 4.0), "the break counts down")
	_flow.step(FlowScript.BUILD_BREAK)
	_check(_flow.wave == 2 and _flow.build_break_left() == 0.0, "the wave started and no break is left")
	_events.disconnect("build_break_started", listener)
	_stop()


## Whoever is building, the next wave starts after BUILD_BREAK, for 1, 2 and 4 players: no builder
## (open overlay focus, build requests in flight) holds it back or speeds it up.
func _test_build_break_ignores_builders() -> void:
	var focus: Node = root.get_node_or_null("UIFocus")
	_check(focus != null, "the UIFocus autoload exists")
	if focus == null:
		return
	for count: int in [1, 2, 4]:
		_setup(count)
		_play()
		_kill_wave()
		var builder: Control = Control.new()
		root.add_child(builder)
		# The last player sits in a menu for the whole break.
		_check(focus.call("open", count - 1, [builder] as Array[Control]) == true, "%d players: the last player opened a menu" % count)
		_events.emit_signal("staff_change_requested", count - 1, 2, 0, &"fire")
		_flow.step(FlowScript.BUILD_BREAK - 0.1)
		_check(focus.call("is_open", count - 1) == true, "%d players: the menu is still open late in the break" % count)
		_check(_flow.wave == 1 and _flow.state == FlowScript.State.CLEARED, "%d players: the wave is not early while someone builds" % count)
		_flow.step(0.1)
		_check(_flow.wave == 2 and _flow.state == FlowScript.State.RUNNING, "%d players: the wave starts on time while someone builds" % count)
		_check(_flow.enemies_left() == FlowScript.wave_size(2), "%d players: the next wave is whole" % count)
		for wizard: Actor in _wizards():
			_check(not wizard.is_down(), "%d players: every wizard stands for the wave" % count)
		focus.call("close", count - 1)
		builder.free()
		_stop()


func _test_wave_size_is_capped() -> void:
	_check(FlowScript.wave_size(1) == FlowScript.WAVE.size(), "wave 1 is the WAVE list")
	var last: int = 0
	for number in range(1, 200):
		var size: int = FlowScript.wave_size(number)
		_check(size >= last and size <= FlowScript.WAVE_MAX, "wave %d size %d never shrinks or passes WAVE_MAX" % [number, size])
		last = size
	_check(FlowScript.wave_size(200) == FlowScript.WAVE_MAX, "a very late wave holds WAVE_MAX enemies")


## A wizard who was down when the wave ended stands up for the next one, and nobody is hurt at once.
func _test_next_wave_stands_up_downed_wizards() -> void:
	_setup(2)
	_play()
	_down(_wizard(1))
	_check(_wizard(1).is_down(), "wizard 2 is down")
	_check(not _flow.is_restarting(), "one of two down: no restart")
	_kill_wave()
	_flow.step(FlowScript.BUILD_BREAK)
	var wizard: Actor = _wizard(1)
	_check(not wizard.is_down() and wizard.health.health > 0, "the downed wizard is up for wave 2")
	_check(wizard.health.health == Downed.REVIVE_HEALTH, "it stands with the revive health")
	_check(wizard.health.is_protected(), "the wizard is protected for a moment at the start of wave 2")
	_check(not _flow.is_restarting(), "no restart is pending in wave 2")
	_stop()


## Losing the room starts again from wave 1.
func _test_restart_goes_back_to_wave_one() -> void:
	_setup(1)
	_play()
	_kill_wave()
	_flow.step(FlowScript.BUILD_BREAK)
	_check(_flow.wave == 2, "the test reached wave 2")
	var wizard: Actor = _wizard(0)
	wizard.health.step(Downed.JOIN_PROTECTION) # the wave-start protection would absorb the hit
	_down(wizard)
	_flow.step(FlowScript.RESTART_DELAY)
	_check(_flow.wave == 1 and _waves.back() == 1, "the restart begins at wave 1, got %d" % _flow.wave)
	_check(_flow.enemies_left() == FlowScript.wave_size(1), "the restart has the wave 1 size")
	# A pending next wave of the old run must not fire in the new one.
	_flow.step(FlowScript.BUILD_BREAK)
	_check(_flow.wave == 1, "no stray wave timer survives the restart")
	_stop()


## Flow gives the arena's walls to the projectile manager: after `start_run` and
## after a restart, a path across the top border or a pillar ends there, and each
## of two players' shots is stopped.
func _test_walls_reach_the_projectile_manager() -> void:
	_setup(2)
	_play()
	var projectiles: Node = root.get_node("Projectiles")
	_check_arena_walls(projectiles, "after start_run")
	# Shots are cast by actor id: each wizard's own (actors G3b).
	var casters: Array[int] = [_wizard(0).id, _wizard(1).id]
	for index in 2:
		projectiles.call("spawn", casters[index], Vector2(100.0 + 20.0 * index, 100.0), Vector2(0.0, -300.0), 5.0, 2.0, 0)
	_check(projectiles.call("get_count_for", casters[0]) == 1 and projectiles.call("get_count_for", casters[1]) == 1, "each player has a shot in the air")
	projectiles.call("step", 0.25)
	_check(projectiles.call("get_count") == 0, "both players' shots ended on the border, %d left" % projectiles.call("get_count"))
	# A restart builds a new world and must give the walls again.
	_down(_wizard(0))
	_down(_wizard(1))
	_flow.step(FlowScript.RESTART_DELAY)
	_check(_flow.state == FlowScript.State.RUNNING, "the run restarted")
	_check_arena_walls(projectiles, "after a restart")
	_stop()


func _check_arena_walls(projectiles: Node, when: String) -> void:
	var top: Vector2 = projectiles.call("clip_to_walls", Vector2(100.0, 100.0), Vector2(100.0, -10.0))
	_check(top.is_equal_approx(Vector2(100.0, 32.0)), "%s: a path up ends on the top border at y 32, got %s" % [when, top])
	var pillar: Vector2 = projectiles.call("clip_to_walls", Vector2(100.0, 144.0), Vector2(300.0, 144.0))
	_check(pillar.is_equal_approx(Vector2(160.0, 144.0)), "%s: a path right ends on the pillar at x 160, got %s" % [when, pillar])


## The menu's Play button sends `play_requested` and nothing else: it neither
## names flow nor changes the scene (text scan of the script and a button press).
func _test_main_menu_only_sends_play_requested() -> void:
	var source: String = FileAccess.get_file_as_string("res://hud/menus/main_menu/main_menu.gd")
	_check(not source.is_empty(), "the menu script can be read")
	for banned: String in ["Flow", "change_scene", "current_scene", "gameplay/"]:
		_check(not source.contains(banned), "main_menu.gd must not use '%s'" % banned)
	_setup(0)
	var menu := (load("res://hud/menus/main_menu/main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(menu)
	var seen: Array[int] = []
	_events.connect("play_requested", func(player: int) -> void: seen.append(player))
	var button := menu.get_node("%Play") as Button
	button.pressed.emit()
	_check(seen == [0], "pressing Play sent play_requested(0), got %s" % [seen])
	_check(_flow.state == FlowScript.State.RUNNING, "flow, not the menu, started the room")
	_stop()
	if is_instance_valid(menu):
		menu.free()
