extends SceneTree
## Tests for gameplay/flow (the M1 arena glue), on the real autoloads: Play starts
## the room with 1, 2 and 4 players, the wave is fixed, `room_entered` and
## `room_cleared` are sent once, the bolt's shared cooldowns are reset on a new run,
## the room restarts in under 3 seconds when every player is down (and not while
## one still stands), and the first room is up in the same call. Time moves by
## fixed deltas through Flow.step(); nothing waits.
##
## godot --headless --path . --script res://tests/gameplay/flow/test_flow.gd

const FlowScript := preload("res://gameplay/flow/flow.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

var _failures: Array[String] = []
var _events: Node
var _flow: FlowScript
var _input: InputManagerScript
var _combat: Node
var _bolt: SpellBase
var _entered: Array[StringName] = []
var _cleared: Array[StringName] = []


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
	_bolt = registry.call("get_resource", &"spells", &"bolt") as SpellBase
	_events.connect("room_entered", func(id: StringName) -> void: _entered.append(id))
	_events.connect("room_cleared", func(id: StringName) -> void: _cleared.append(id))
	_test_restart_delay_is_under_three_seconds()
	for count: int in [1, 2, 4]:
		_test_play_starts_the_room(count)
	_test_keyboard_joins_when_nobody_has()
	_test_play_is_ignored_while_running()
	_test_unjoined_requester_other_than_p1_starts_nothing()
	_test_cooldowns_reset_on_a_new_run()
	_test_room_cleared_once_when_the_wave_is_dead()
	_test_restart_when_all_down()
	_test_no_restart_while_one_stands()
	_test_revive_cancels_the_restart()
	_test_no_restart_after_clear()
	_test_last_enemy_dies_after_all_down()
	_test_failed_restart_goes_idle()
	_test_play_keeps_joined_pad_without_keyboard()
	_test_wave_stands_on_floor()
	_test_restart_leaves_no_old_enemies_or_shots()
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


## End the run and free every device, so the next test starts clean.
func _stop() -> void:
	_flow.stop_run()
	for index in InputManagerScript.MAX_PLAYERS:
		_input.leave(index)


func _play(requester: int = 0) -> void:
	_events.emit_signal("play_requested", requester)


func _wizards() -> Array[PlayerScript]:
	var found: Array[PlayerScript] = []
	for index in InputManagerScript.MAX_PLAYERS:
		var wizard := _flow.get_wizard(index) as PlayerScript
		if wizard != null:
			found.append(wizard)
	return found


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
		var wizard := _flow.get_wizard(index) as PlayerScript
		_check(wizard != null and wizard.index == index and wizard.spell == _bolt, "%d players: wizard %d has its index and the bolt" % [count, index])
		_check(wizard != null and wizard.position == Vector2(224.0 + 64.0 * index, 320.0), "%d players: wizard %d stands on its spawn" % [count, index])
	_check(_flow.enemies_left() == FlowScript.WAVE.size(), "%d players: the wave has %d enemies, got %d" % [count, FlowScript.WAVE.size(), _flow.enemies_left()])
	_check(_combat.call("get_enemy_count") == FlowScript.WAVE.size(), "%d players: every enemy is registered with combat" % count)
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
	var wizard := _flow.get_wizard(1) as PlayerScript
	_check(_bolt.cast(1, Vector2(100.0, 100.0), Vector2.RIGHT, 100.0) != SpellBase.REFUSED, "the bolt fires for player 2")
	_check(_bolt.cast(1, Vector2(100.0, 100.0), Vector2.RIGHT, 100.0) == SpellBase.REFUSED, "the bolt cools down for player 2")
	_flow.stop_run()
	_play()
	_check(_bolt.cast(1, Vector2(100.0, 100.0), Vector2.RIGHT, 100.0) != SpellBase.REFUSED, "a new run forgot the bolt cooldown (the shared resource)")
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


func _test_restart_when_all_down() -> void:
	for count: int in [1, 2, 4]:
		_setup(count)
		_play()
		var old_world: Node = _flow.world
		for wizard in _wizards():
			wizard.take_damage(PlayerScript.MAX_HEALTH)
		_check(_flow.is_restarting(), "%d players: all down starts the restart timer" % count)
		_flow.step(FlowScript.RESTART_DELAY - 0.5)
		_check(_flow.world == old_world, "%d players: no restart before the delay" % count)
		_flow.step(0.5)
		_check(_flow.world != old_world and _flow.world != null, "%d players: the room restarted after %f s" % [count, FlowScript.RESTART_DELAY])
		_check(_entered.size() == 2, "%d players: room_entered was sent again for the new room, got %d" % [count, _entered.size()])
		_check(_wizards().size() == count, "%d players: the wizards are back" % count)
		for wizard in _wizards():
			_check(wizard.health == PlayerScript.MAX_HEALTH and not wizard.is_downed(), "%d players: wizard %d is standing at full health" % [count, wizard.index])
		_check(_flow.enemies_left() == FlowScript.WAVE.size(), "%d players: a new wave stands" % count)
		_check(not _flow.is_restarting(), "%d players: the timer is off after the restart" % count)
		_stop()


func _test_no_restart_while_one_stands() -> void:
	_setup(4)
	_play()
	for index in 3:
		(_flow.get_wizard(index) as PlayerScript).take_damage(PlayerScript.MAX_HEALTH)
	_check(not _flow.is_restarting(), "three of four down: no restart")
	var world: Node = _flow.world
	_flow.step(10.0)
	_check(_flow.world == world, "three of four down: the room stays")
	_stop()


func _test_revive_cancels_the_restart() -> void:
	_setup(2)
	_play()
	(_flow.get_wizard(0) as PlayerScript).take_damage(PlayerScript.MAX_HEALTH)
	(_flow.get_wizard(1) as PlayerScript).take_damage(PlayerScript.MAX_HEALTH)
	_check(_flow.is_restarting(), "two of two down: restarting")
	(_flow.get_wizard(0) as PlayerScript).revive(1)
	_check(not _flow.is_restarting(), "a revive cancels the restart")
	_stop()


func _test_no_restart_after_clear() -> void:
	_setup(1)
	_play()
	for enemy: Node in _flow._enemies.duplicate():
		_events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO)
	(_flow.get_wizard(0) as PlayerScript).take_damage(PlayerScript.MAX_HEALTH)
	_check(not _flow.is_restarting(), "a cleared room does not restart when the players go down")
	_stop()


## The last enemy dies (a bolt still in flight) after every wizard is down: the
## room is cleared, but the restart timer keeps running and gives a new world.
func _test_last_enemy_dies_after_all_down() -> void:
	_setup(2)
	_play()
	var old_world: Node = _flow.world
	for wizard in _wizards():
		wizard.take_damage(PlayerScript.MAX_HEALTH)
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
	(_flow.get_wizard(0) as PlayerScript).take_damage(PlayerScript.MAX_HEALTH)
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


func _test_restart_leaves_no_old_enemies_or_shots() -> void:
	_setup(1)
	_play()
	var projectiles: Node = root.get_node("Projectiles")
	projectiles.call("spawn", 0, Vector2(100.0, 100.0), Vector2(10.0, 0.0), 5.0)
	_check(projectiles.call("get_count") == 1, "a shot is in the air")
	(_flow.get_wizard(0) as PlayerScript).take_damage(PlayerScript.MAX_HEALTH)
	_flow.step(FlowScript.RESTART_DELAY)
	_check(projectiles.call("get_count") == 0, "the restart cleared the shots")
	_check(_combat.call("get_enemy_count") == FlowScript.WAVE.size(), "combat knows only the new wave, got %d" % _combat.call("get_enemy_count"))
	_stop()


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
