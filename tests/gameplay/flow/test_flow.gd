extends "res://tests/support/suite.gd"
## gameplay/flow on the real autoloads (the real wiring is the point): Play starts the room in the
## same call with 1, 2 and 4 players, the enemies the run's map puts in it stand (no waves: boss
## OB2a; run generation RG3; the arena pinned as the run's one room, tests/support/pinned_run.gd, so
## its spawns are known), `room_entered` and `room_cleared` are sent once, a won room ends the run
## after RUN_WON_DELAY, every wizard holds the two start spells, the cooldowns are reset on a new
## run, the room restarts in under 3 seconds when every player is down (and not while one still
## stands), the walls reach the projectile manager, and the main menu only asks for the hub. Each
## test joins the players it needs by virtual devices and starts its own run; `after_each` stops it,
## frees the devices, puts the run to play back and drops the test's listeners. Time moves by fixed
## steps through Flow.step(); nothing waits.

const FlowScript := preload("res://gameplay/flow/flow.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")
## The arena's floor, wall border included.
const INNER := Rect2(Vector2.ZERO, Vector2(640.0, 384.0))

var events: Node
var flow: FlowScript
var input: InputManagerScript
var combat: Node
var spells: SpellsScript
var run: Node
var registry: Node
## The pinned arena's id (a copy of arena_01, the run's one room).
var arena: StringName = &""
var entered: Array[StringName] = []
var cleared: Array[StringName] = []
## The actors each `room_start` cue was played as (S6, item 13).
var room_cues: Array[int] = []
## [signal, callable] of every listener the test connected to the game's bus.
var _listening: Array[Array] = []


func before_each() -> void:
	events = root.get_node("Events")
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput") as InputManagerScript
	combat = root.get_node("Combat")
	spells = root.get_node("Spells") as SpellsScript
	run = root.get_node("Run")
	registry = root.get_node("Registry")
	flow.run_id_to_play = PinnedRun.pin(registry, ARENA)
	arena = PinnedRun.room_id(ARENA)
	entered.clear()
	cleared.clear()
	room_cues.clear()
	_listen("room_entered", func(id: StringName) -> void: entered.append(id))
	_listen("room_cleared", func(id: StringName) -> void: cleared.append(id))
	_listen("cue_shown", func(caster: int, cue: StringName, _at: Vector2, _d: Vector2, _s: float, _t: Color, _l: int) -> void:
		if cue == FlowScript.ROOM_START_CUE:
			room_cues.append(caster))


func after_each() -> void:
	flow.stop_run()
	flow.run_id_to_play = FlowScript.DEFAULT_RUN_ID
	for index in InputManagerScript.MAX_PLAYERS:
		input.leave(index)
	for row: Array in _listening:
		if events.is_connected(row[0], row[1]):
			events.disconnect(row[0], row[1])
	_listening.clear()


## Connects `callable` to the game's bus's `signal_name` for this test.
func _listen(signal_name: StringName, callable: Callable) -> void:
	events.connect(signal_name, callable)
	_listening.append([signal_name, callable])


## `count` players joined by virtual devices (slots 0..count-1).
func _join(count: int) -> void:
	for index in count:
		input.add_virtual_device(index)


func _play(requester: int = 0) -> void:
	events.emit_signal("play_requested", requester)


## `count` players joined, and Play pressed.
func _playing(count: int) -> void:
	_join(count)
	_play()


## Ends the run and frees every device, so a test can start again with other players.
func _stop() -> void:
	flow.stop_run()
	for index in InputManagerScript.MAX_PLAYERS:
		input.leave(index)
	entered.clear()
	cleared.clear()
	room_cues.clear()


func _wizards() -> Array[Actor]:
	var found: Array[Actor] = []
	for index in InputManagerScript.MAX_PLAYERS:
		var wizard := flow.get_wizard(index) as Actor
		if wizard != null:
			found.append(wizard)
	return found


## The wizard actor of player `index` (actors G7: a wizard is an Actor; its seat is its
## PlayerController's).
func _wizard(index: int) -> Actor:
	return flow.get_wizard(index) as Actor


func _seat(wizard: Actor) -> int:
	var seat: PlayerController = PlayerController.of(wizard)
	return seat.seat if seat != null else -1


## A hit that takes all of `wizard`'s health.
func _down(wizard: Actor) -> void:
	wizard.health.take(wizard.health.max_health)


func _down_everyone() -> void:
	for wizard in _wizards():
		_down(wizard)


## How many enemies the run's map puts in the room the party is in (each restart is a new run, and
## a new map).
func _room_count() -> int:
	var node: RunNode = run.call("room_now") as RunNode
	return node.enemies.size() if node != null else 0


## Kill every enemy of the room (as if shot down).
func _kill_room() -> void:
	for enemy: Node in flow._enemies.duplicate():
		events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO, -1)


## The arena's walls, as rectangles.
func _arena_walls() -> Array[Rect2]:
	var scene: Node = ARENA.scene.instantiate()
	var walls: Array[Rect2] = []
	for child in scene.get_node("Walls").get_children():
		var shape_node := child as CollisionShape2D
		if shape_node != null and shape_node.shape is RectangleShape2D:
			var size: Vector2 = (shape_node.shape as RectangleShape2D).size
			walls.append(Rect2(shape_node.position - size * 0.5, size))
	scene.free()
	return walls


# --- Play ------------------------------------------------------------------------------------

func test_the_restart_delay_is_under_three_seconds() -> void:
	check(FlowScript.RESTART_DELAY < 3.0, "the restart delay must be under 3 seconds, is %f" % FlowScript.RESTART_DELAY)


func test_play_starts_the_run_in_the_same_call() -> void:
	_playing(1)
	check_equal(flow.state, FlowScript.State.RUNNING, "flow is running after play_requested")
	check(flow.world != null and flow.world.is_inside_tree(), "the world is in the tree")


func test_play_enters_the_pinned_room_once() -> void:
	_playing(1)
	check_equal(entered, [arena] as Array[StringName], "room_entered(arena_01) was sent once")


func test_room_cleared_is_not_sent_at_the_start() -> void:
	_playing(4)
	check(cleared.is_empty(), "room_cleared is not sent at the start")


func test_play_spawns_a_wizard_for_each_joined_player() -> void:
	for count: int in [1, 2, 4]:
		_playing(count)
		check_equal(_wizards().size(), count, "%d players: one wizard each" % count)
		_stop()


func test_each_wizard_has_its_seat_and_its_ramp() -> void:
	_playing(4)
	for index in 4:
		var wizard: Actor = _wizard(index)
		check(wizard != null and _seat(wizard) == index and wizard.ramp == index, "wizard %d has its seat and its ramp" % index)


func test_each_wizard_starts_with_dash_on_a_and_bolt_on_x() -> void:
	_playing(4)
	for index in 4:
		var wizard: Actor = _wizard(index)
		check(wizard != null and wizard.caster.has_staff(0) and wizard.caster.has_staff(1), "wizard %d holds two staffs" % index)
		check(wizard != null and wizard.caster.cards_of(0)[0] == &"dash" and wizard.caster.cards_of(1)[0] == &"bolt", "wizard %d has the start cards" % index)


func test_each_wizard_stands_on_its_spawn() -> void:
	_playing(4)
	for index in 4:
		var wizard: Actor = _wizard(index)
		check(wizard != null and wizard.position == Vector2(224.0 + 64.0 * index, 320.0), "wizard %d stands on its spawn" % index)


func test_the_rooms_enemies_stand() -> void:
	for count: int in [1, 4]:
		_playing(count)
		check(_room_count() > 0, "%d players: the arena lists its enemies" % count)
		check_equal(flow.enemies_left(), _room_count(), "%d players: the room's enemies stand" % count)
		_stop()


func test_combat_knows_every_enemy_and_wizard() -> void:
	_playing(4)
	check_equal(combat.call("actor_count"), _room_count() + 4, "every enemy and wizard is registered with combat")


## Every enemy the room lists stands inside it and clear of the walls.
func test_the_rooms_enemies_stand_on_the_floor() -> void:
	_playing(1)
	var walls: Array[Rect2] = _arena_walls()
	check_equal(flow._enemies.size(), _room_count(), "the room's enemies are up")
	for enemy: Node2D in flow._enemies:
		var body := Rect2(enemy.position - Vector2(12.0, 12.0), Vector2(24.0, 24.0))
		check(INNER.encloses(body), "enemy at %s is inside the room" % enemy.position)
		for wall in walls:
			check(not wall.intersects(body), "enemy at %s is clear of the wall %s" % [enemy.position, wall])


## Even the most the sandbox's arena keeps up (SANDBOX_MAX), placed as a room's fight is, stand on
## the floor: the stacked spawns stay inside the room and clear of the walls. No run needed.
func test_a_full_sandbox_arena_stands_on_the_floor() -> void:
	var walls: Array[Rect2] = _arena_walls()
	var spawns: int = ARENA.places().enemy_spawns.size()
	for at: int in FlowScript.SANDBOX_MAX:
		var spawn: int = at % spawns
		var times: int = at / spawns
		var position: Vector2 = FlowScript.stacked_position(ARENA.places().enemy_spawns[spawn], times)
		var body := Rect2(position - Vector2(12.0, 12.0), Vector2(24.0, 24.0))
		check(INNER.encloses(body), "enemy %d of a full arena (%s) is inside the room" % [at, position])
		for wall in walls:
			check(not wall.intersects(body), "spawn %d (%s) is clear of the wall %s" % [at, position, wall])


## As a run's room starts, its cue plays on every wizard, as that wizard's actor.
func test_the_room_start_cue_plays_on_every_wizard_as_its_actor() -> void:
	for count: int in [1, 4]:
		_playing(count)
		var ids: Array[int] = []
		for index in count:
			ids.append(int(_wizard(index).id))
		check_equal(room_cues.size(), count, "%d players: room_start on every wizard" % count)
		check(room_cues.all(func(id: int) -> bool: return ids.has(id)), "%d players: as each wizard's actor" % count)
		_stop()


func test_play_with_nobody_joined_joins_the_keyboard_as_p1() -> void:
	_play(0)
	check(input.is_joined(0) and input.device_of(0) == InputManagerScript.KEYBOARD, "Play with the mouse joins the keyboard as P1")
	check_equal(_wizards().size(), 1, "one wizard for the keyboard player")


func test_a_second_play_while_running_is_ignored() -> void:
	_playing(2)
	var first: Node = flow.world
	_play()
	check(flow.world == first, "a second play_requested does not rebuild the room")
	check_equal(entered.size(), 1, "room_entered was sent once")


func test_play_from_an_unjoined_requester_other_than_p1_starts_nothing() -> void:
	_play(2)
	check(flow.state == FlowScript.State.IDLE and flow.world == null, "nobody joined and requester 3 is not the keyboard: no run starts")
	check(entered.is_empty(), "no room_entered without a run")


## A gamepad owner already joined in a later slot keeps it: the keyboard stays out.
func test_play_leaves_the_keyboard_out_when_a_pad_joined_a_later_slot() -> void:
	input.add_virtual_device(2)
	_play(0)
	check(not input.is_joined(0), "the keyboard does not take slot 0 when someone else joined")


func test_play_with_a_pad_in_a_later_slot_plays_only_that_player() -> void:
	input.add_virtual_device(2)
	_play(0)
	check(_wizards().size() == 1 and flow.get_wizard(2) != null, "only the joined player plays")


# --- Cooldowns -------------------------------------------------------------------------------

const AT := Vector2(100.0, 100.0)


func test_each_staff_waits_out_its_own_delay() -> void:
	_playing(2)
	# Spells keeps staffs by caster: the actor id the wizard of player 2 opened (actors G3b).
	var caster: int = _wizard(1).id
	check(spells.cast_staff(caster, 1, AT, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "staff X fires for player 2")
	check(spells.cast_staff(caster, 1, AT, Vector2.RIGHT, 100.0) == SpellsScript.REFUSED, "staff X waits out its delay for player 2")
	check(spells.cast_staff(caster, 0, AT, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "staff A has its own delay")


func test_a_new_run_forgets_the_delays() -> void:
	_playing(2)
	spells.cast_staff(_wizard(1).id, 1, AT, Vector2.RIGHT, 100.0)
	flow.stop_run()
	_play()
	check(spells.cast_staff(_wizard(1).id, 1, AT, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "a new run forgot the delays")


# --- Clearing the room -----------------------------------------------------------------------

## Four players playing, every enemy of the room but the last dead; the room's enemies.
func _all_but_one_dead() -> Array[Node]:
	_playing(4)
	var enemies: Array[Node] = flow._enemies.duplicate()
	check_equal(enemies.size(), _room_count(), "the test sees the room's enemies")
	for at in enemies.size() - 1:
		events.emit_signal("enemy_died", at % 4, enemies[at], Vector2.ZERO, -1)
	return enemies


func test_room_cleared_waits_for_the_last_enemy() -> void:
	_all_but_one_dead()
	check(cleared.is_empty(), "room_cleared waits for the last enemy")
	check_equal(flow.enemies_left(), 1, "one enemy is left")


func test_room_cleared_is_sent_once_as_the_last_enemy_dies() -> void:
	var enemies: Array[Node] = _all_but_one_dead()
	events.emit_signal("enemy_died", 3, enemies[enemies.size() - 1], Vector2.ZERO, -1)
	check_equal(cleared, [arena] as Array[StringName], "room_cleared(arena_01) was sent once")
	check_equal(flow.state, FlowScript.State.CLEARED, "flow is in the cleared state")


func test_a_repeated_death_does_not_send_room_cleared_again() -> void:
	var enemies: Array[Node] = _all_but_one_dead()
	events.emit_signal("enemy_died", 3, enemies[enemies.size() - 1], Vector2.ZERO, -1)
	events.emit_signal("enemy_died", 0, enemies[0], Vector2.ZERO, -1)
	check_equal(cleared.size(), 1, "a repeated death does not send room_cleared again")


## A player who possesses an enemy of the room still lets the room clear: the possessed body is on
## the wizards' team while it is driven, and its death must still count as an enemy's. Bots stopped
## building `possess` because the room stayed uncleared.
func _clear_with_a_possessed_enemy(possessed_first: bool) -> void:
	_playing(1)
	var wizard: Actor = _wizard(0)
	var enemies: Array[Node] = flow._enemies.duplicate()
	var held := enemies[0] as Actor
	var possession: Possession = Possession.begin(wizard, held, 3.0)
	check(possession != null and held.controller == wizard.home_controller, "the wizard possesses an enemy of the room")
	var order: Array[Node] = enemies.duplicate()
	if not possessed_first:
		order.reverse()
	for enemy: Node in order:
		combat.call("hit", 0, enemy, 100000)
	check_equal(flow.enemies_left(), 0, "no enemy is left")
	check_equal(cleared, [arena] as Array[StringName], "the room clears")


func test_a_room_clears_with_its_possessed_enemy_killed_first() -> void:
	_clear_with_a_possessed_enemy(true)


func test_a_room_clears_with_its_possessed_enemy_killed_last() -> void:
	_clear_with_a_possessed_enemy(false)


func test_killing_every_enemy_wins_the_room() -> void:
	_playing(1)
	_kill_room()
	check_equal(cleared, [arena] as Array[StringName], "the room is cleared")
	check_equal(flow.state, FlowScript.State.CLEARED, "won")


## A won room (every enemy down) with no room after it ends the run RUN_WON_DELAY later; a run from
## `play_requested` starts the room again (a run from the hub's stone goes back there:
## test_flow_hub.gd).
func test_a_won_run_ends_run_won_delay_later_and_begins_again() -> void:
	for count: int in [1, 4]:
		_playing(count)
		var world: Node = flow.world
		_kill_room()
		flow.step(FlowScript.RUN_WON_DELAY - 0.1)
		check(flow.world == world, "%d players: the kill is seen out first" % count)
		flow.step(0.2)
		check(flow.world != world and flow.state == FlowScript.State.RUNNING, "%d players: the run ended and began again" % count)
		check_equal(flow.enemies_left(), _room_count(), "%d players: with the room's enemies" % count)
		_stop()


## Won, the run ends RUN_WON_DELAY later whatever the players do.
func _won() -> void:
	_playing(1)
	_kill_room()
	check(is_equal_approx(float(flow.get("_restart_left")), FlowScript.RUN_WON_DELAY), "won: the run's end counts")


func test_going_down_after_the_win_starts_no_restart_of_its_own() -> void:
	_won()
	_down(_wizard(0))
	check(is_equal_approx(float(flow.get("_restart_left")), FlowScript.RUN_WON_DELAY), "going down after the win changes nothing")


func test_a_revive_after_the_win_stops_nothing() -> void:
	_won()
	_down(_wizard(0))
	Downed.of(_wizard(0)).revive(0)
	check(flow.is_restarting(), "a revive does not stop the won run's end")


## A run whose map cannot be made (no room of its biome hosts its kind) starts nothing: Flow says so
## and stays idle, so Play can start again. The unknown run's case is test_flow_content_choice.gd's.
func _try_a_run_with_no_map() -> bool:
	var rules := MapRules.new()
	rules.biome = &"test_flow_nowhere"
	rules.depth_min = 1
	rules.depth_max = 1
	rules.kinds = [KindRule.make(&"fight", 0, -1)] as Array[KindRule]
	var nowhere := RunDefinition.new()
	nowhere.id = &"test_flow_nowhere"
	nowhere.biomes = [rules] as Array[MapRules]
	registry.call("add", &"runs", nowhere)
	_join(1)
	flow.run_id_to_play = nowhere.id
	return flow.start_run(0)


func test_a_run_with_no_map_starts_nothing() -> void:
	check(not _try_a_run_with_no_map(), "a run with no map starts no run")
	check(flow.state == FlowScript.State.IDLE and flow.world == null, "flow is idle, with no world")
	check(entered.is_empty(), "no room was entered, got %s" % [entered])


func test_play_starts_again_after_a_run_with_no_map() -> void:
	_try_a_run_with_no_map()
	flow.run_id_to_play = PinnedRun.room_id(ARENA)
	_play()
	check_equal(flow.state, FlowScript.State.RUNNING, "Play starts again after")


## What the run names that the registry lacks (an enemy deleted after a map was made) stands nothing,
## with a warning, and a room the run puts nothing in is won as it starts. The run's area never names
## either: the answer is stood in for here, heard after the area's (Flow takes the last answer to its
## `run_begun`).
func _play_a_room_of(named: Array) -> void:
	var enemies: Array[StringName] = []
	enemies.assign(named)
	var answer := func(_run_id: StringName, _players: int, _start_depth: int) -> void:
		events.emit_signal("run_room_chosen", arena, enemies, [] as Array[StringName])
	_listen("run_begun", answer)
	_playing(1)


func test_an_enemy_the_registry_lacks_stands_nothing() -> void:
	_play_a_room_of([&"no_such_enemy", &"ember_imp", &"no_such_enemy"])
	check_equal(flow.enemies_left(), 1, "the imp stands, the unknown id stands nothing")


func test_a_room_with_nothing_in_it_is_won_as_it_starts() -> void:
	_play_a_room_of([])
	check_equal(cleared, [arena] as Array[StringName], "a room with nothing in it is won as it starts")


## A room of a kind filled by a boss (`RoomKind.FILL_BOSS`) stands the boss the map names, by id
## (`EnemyBase.FOLDERS`: the bosses' folder too). The boss added is of a biome of its own, so no
## other test's run meets it.
func test_a_boss_room_stands_the_boss_its_map_names() -> void:
	var boss: EnemyBase = (registry.call("get_resource", &"enemies", &"ember_imp") as EnemyBase).duplicate() as EnemyBase
	boss.id = &"test_flow_boss"
	boss.boss = true
	# A biome of its own: the boss pool is this boss alone, whatever bosses the crypt gets.
	boss.biomes = [&"test_flow_lair"] as Array[StringName]
	registry.call("add", &"bosses", boss)
	var room: RoomBase = ARENA.duplicate() as RoomBase
	room.id = &"test_flow_boss_room"
	flow.run_id_to_play = PinnedRun.pin(registry, room, &"test_flow_lair", RoomKind.FILL_BOSS)
	_playing(1)
	check_equal(flow.enemies_left(), 1, "the boss stands")
	var node: RunNode = run.call("room_now") as RunNode
	var named: Array[StringName] = node.enemies if node != null else [] as Array[StringName]
	check_equal(named, [boss.id] as Array[StringName], "the map names it")


# --- Restarting ------------------------------------------------------------------------------

func test_everyone_down_starts_the_restart_timer() -> void:
	for count: int in [1, 2, 4]:
		_playing(count)
		_down_everyone()
		check(flow.is_restarting(), "%d players: all down starts the restart timer" % count)
		_stop()


func test_no_restart_before_the_delay() -> void:
	_playing(2)
	var old_world: Node = flow.world
	_down_everyone()
	flow.step(FlowScript.RESTART_DELAY - 0.5)
	check(flow.world == old_world, "no restart before the delay")


func test_the_room_restarts_after_the_delay() -> void:
	for count: int in [1, 2, 4]:
		_playing(count)
		var old_world: Node = flow.world
		_down_everyone()
		flow.step(FlowScript.RESTART_DELAY - 0.5)
		flow.step(0.5)
		check(flow.world != old_world and flow.world != null, "%d players: the room restarted after %f s" % [count, FlowScript.RESTART_DELAY])
		check_equal(entered.size(), 2, "%d players: room_entered was sent again for the new room" % count)
		check(not flow.is_restarting(), "%d players: the timer is off after the restart" % count)
		_stop()


func test_after_a_restart_every_wizard_stands_at_full_health() -> void:
	_playing(4)
	_down_everyone()
	flow.step(FlowScript.RESTART_DELAY)
	check_equal(_wizards().size(), 4, "the wizards are back")
	for wizard in _wizards():
		check(wizard.health.health == wizard.health.max_health and not wizard.is_down(), "wizard %d is standing at full health" % _seat(wizard))


func test_after_a_restart_the_rooms_enemies_stand_again() -> void:
	_playing(2)
	_down_everyone()
	flow.step(FlowScript.RESTART_DELAY)
	check_equal(flow.enemies_left(), _room_count(), "the room's enemies stand again")


func test_a_restart_leaves_no_old_shot() -> void:
	_playing(1)
	var projectiles: Node = root.get_node("Projectiles")
	projectiles.call("spawn", 0, Vector2(100.0, 100.0), Vector2(10.0, 0.0), 5.0)
	check_equal(projectiles.call("get_count"), 1, "a shot is in the air")
	_down(_wizard(0))
	flow.step(FlowScript.RESTART_DELAY)
	check_equal(projectiles.call("get_count"), 0, "the restart cleared the shots")


func test_a_restart_leaves_no_old_enemy_in_combat() -> void:
	_playing(1)
	_down(_wizard(0))
	flow.step(FlowScript.RESTART_DELAY)
	check_equal(combat.call("actor_count"), _room_count() + 1, "combat knows only the room's new enemies and the wizard")


func test_no_restart_while_one_of_four_stands() -> void:
	_playing(4)
	for index in 3:
		_down(_wizard(index))
	check(not flow.is_restarting(), "three of four down: no restart")
	var world: Node = flow.world
	flow.step(10.0)
	check(flow.world == world, "three of four down: the room stays")


func test_a_revive_cancels_the_restart() -> void:
	_playing(2)
	_down_everyone()
	check(flow.is_restarting(), "two of two down: restarting")
	Downed.of(_wizard(0)).revive(1)
	check(not flow.is_restarting(), "a revive cancels the restart")


## The last enemy dies (a bolt still in flight) after every wizard is down: the room is cleared, but
## the restart timer keeps running and gives a new world.
func test_a_room_cleared_with_everyone_down_still_restarts() -> void:
	_playing(2)
	_down_everyone()
	_kill_room()
	check_equal(cleared, [arena] as Array[StringName], "the room still counts as cleared")
	check(flow.is_restarting(), "the last enemy dying does not cancel the restart")


func test_a_room_cleared_with_everyone_down_restarts_into_a_new_run() -> void:
	_playing(2)
	var old_world: Node = flow.world
	_down_everyone()
	_kill_room()
	flow.step(FlowScript.RESTART_DELAY)
	check(flow.world != old_world and flow.world != null, "the run restarted after the last enemy died with everyone down")
	check(flow.state == FlowScript.State.RUNNING and flow.enemies_left() == _room_count(), "the new run is running with the room's enemies")


## A failed restart (content gone) ends the run instead of leaving it stuck.
func _failed_restart() -> void:
	_playing(1)
	var kept: Node = flow.registry
	flow.registry = null
	_down(_wizard(0))
	flow.step(FlowScript.RESTART_DELAY)
	flow.registry = kept


func test_a_failed_restart_returns_flow_to_idle() -> void:
	_failed_restart()
	check(flow.state == FlowScript.State.IDLE and flow.world == null, "a failed restart returns flow to idle")


func test_play_starts_again_after_a_failed_restart() -> void:
	_failed_restart()
	_play()
	check_equal(flow.state, FlowScript.State.RUNNING, "Play starts again after a failed restart")


# --- Walls -----------------------------------------------------------------------------------

## Flow gives the arena's walls to the projectile manager: a path across the top border or a pillar
## ends there.
func _check_arena_walls(when: String) -> void:
	var projectiles: Node = root.get_node("Projectiles")
	var top: Vector2 = projectiles.call("clip_to_walls", Vector2(100.0, 100.0), Vector2(100.0, -10.0))
	check(top.is_equal_approx(Vector2(100.0, 32.0)), "%s: a path up ends on the top border at y 32, got %s" % [when, top])
	var pillar: Vector2 = projectiles.call("clip_to_walls", Vector2(100.0, 144.0), Vector2(300.0, 144.0))
	check(pillar.is_equal_approx(Vector2(160.0, 144.0)), "%s: a path right ends on the pillar at x 160, got %s" % [when, pillar])


func test_the_walls_reach_the_projectile_manager_at_the_start() -> void:
	_playing(2)
	_check_arena_walls("after start_run")


func test_the_walls_reach_the_projectile_manager_again_after_a_restart() -> void:
	_playing(2)
	_down_everyone()
	flow.step(FlowScript.RESTART_DELAY)
	check_equal(flow.state, FlowScript.State.RUNNING, "the run restarted")
	_check_arena_walls("after a restart")


func test_each_players_shot_stops_on_the_border() -> void:
	_playing(2)
	var projectiles: Node = root.get_node("Projectiles")
	# Shots are cast by actor id: each wizard's own (actors G3b).
	var casters: Array[int] = [_wizard(0).id, _wizard(1).id]
	for index in 2:
		projectiles.call("spawn", casters[index], Vector2(100.0 + 20.0 * index, 100.0), Vector2(0.0, -300.0), 5.0, 2.0, 0)
	check(projectiles.call("get_count_for", casters[0]) == 1 and projectiles.call("get_count_for", casters[1]) == 1, "each player has a shot in the air")
	projectiles.call("step", 0.25)
	check_equal(projectiles.call("get_count"), 0, "both players' shots ended on the border")


# --- The main menu ---------------------------------------------------------------------------

## The menu's Play button sends `hub_requested` and nothing else (online-lobby L1): it neither
## names flow nor changes the scene.
func test_the_main_menu_script_names_no_flow_and_no_scene_change() -> void:
	var source: String = FileAccess.get_file_as_string("res://hud/menus/main_menu/main_menu.gd")
	check(not source.is_empty(), "the menu script can be read")
	for banned: String in ["Flow", "change_scene", "current_scene", "gameplay/"]:
		check(not source.contains(banned), "main_menu.gd must not use '%s'" % banned)


## The main menu in the tree, its Play button pressed; the players hub_requested named.
func _press_play_on_the_menu() -> Array[int]:
	var menu := own((load("res://hud/menus/main_menu/main_menu.tscn") as PackedScene).instantiate()) as Control
	root.add_child(menu)
	var seen: Array[int] = []
	_listen("hub_requested", func(player: int) -> void: seen.append(player))
	(menu.get_node("%Play") as Button).pressed.emit()
	return seen


func test_pressing_play_on_the_menu_sends_hub_requested() -> void:
	check_equal(_press_play_on_the_menu(), [0] as Array[int], "pressing Play sent hub_requested(0)")


func test_flow_not_the_menu_starts_the_hub_on_play() -> void:
	_press_play_on_the_menu()
	check_equal(flow.state, FlowScript.State.RUNNING, "flow, not the menu, started the room")
	check_equal(flow.room_id, FlowScript.HUB_ROOM_ID, "Play's room is the hub")
