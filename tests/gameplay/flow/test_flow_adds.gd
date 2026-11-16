extends "res://tests/support/suite.gd"
## A phase's adds and health by player count (boss plan OB13, docs/milestones/boss-old-broom.md,
## "Phase adds and player-count scaling"), on the real autoloads: a test boss made here (the imp's
## body, a boss of a biome of its own, pinned as the boss of a run of one room, tests/support/
## pinned_run.gd) whose phase calls imps. Flow stands its burst by the wizards in play, round the
## boss or at the room's spawns, clear of the walls; its waves under the cap of those alive; the adds
## crumble when the boss dies (nobody's kill) and the room is cleared after the last; its health
## follows the wizards joining and leaving, keeping its share. 1, 2 and 4 players.
##
## godot --headless --path . --script res://tests/gameplay/flow/test_flow_adds.gd

const FlowScript := preload("res://gameplay/flow/flow.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")
const BOSS_ID: StringName = &"test_adds_boss"
const LAIR: StringName = &"test_adds_lair"

var flow: FlowScript
var input: Node
var events: Node
var combat: Node
var projectiles: Node
var registry: Node
var was_run: StringName
var cleared: int = 0
var deaths: Array[int] = []
var boss_data: EnemyBase
var adds: EnemyAdds


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	events = root.get_node("Events")
	combat = root.get_node("Combat")
	projectiles = root.get_node("Projectiles")
	registry = root.get_node("Registry")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	cleared = 0
	deaths.clear()
	events.connect("room_cleared", _on_room_cleared)
	events.connect("enemy_died", _on_enemy_died)
	if registry.call("get_resource", &"bosses", BOSS_ID) == null:
		registry.call("add", &"bosses", _make_boss())
	boss_data = registry.call("get_resource", &"bosses", BOSS_ID) as EnemyBase
	adds = boss_data.phases[0].adds[0]
	adds.at = EnemyAdds.At.RING
	was_run = flow.run_id_to_play
	flow.run_id_to_play = PinnedRun.pin(registry, ARENA, LAIR, RoomKind.FILL_BOSS)


func after_each() -> void:
	events.disconnect("room_cleared", _on_room_cleared)
	events.disconnect("enemy_died", _on_enemy_died)
	flow.stop_run()
	flow.world_parent = null
	flow.run_id_to_play = was_run
	for index in 4:
		input.leave(index)


func _on_room_cleared(_room_id: StringName) -> void:
	cleared += 1


func _on_enemy_died(killer: int, _enemy: Node, _position: Vector2, _shot: int) -> void:
	deaths.append(killer)


## The imp as a boss, 100 health and half more for each player after the first; under half health
## (no transition) it calls 2 imps and 1 more a player, then waves of 1 every second, at most 3 and 1
## more a player alive.
func _make_boss() -> EnemyBase:
	var data: EnemyBase = (registry.call("get_resource", &"enemies", &"ember_imp") as EnemyBase).duplicate() as EnemyBase
	data.id = BOSS_ID
	data.boss = true
	data.biomes = [LAIR] as Array[StringName]
	data.max_health = 100.0
	data.health_per_player = 0.5
	var called := EnemyAdds.new()
	called.enemy = &"ember_imp"
	called.count = 2
	called.per_player = 1
	called.every = 1.0
	called.wave_count = 1
	called.cap = 3
	called.cap_per_player = 1
	var phase := EnemyPhase.new()
	phase.health_below = 0.5
	phase.transition = 0.0
	phase.adds = [called] as Array[EnemyAdds]
	data.phases = [phase] as Array[EnemyPhase]
	return data


func _start(count: int) -> void:
	for index in count:
		input.add_virtual_device(index)
	events.emit_signal("play_requested", 0)


func _boss() -> Actor:
	for enemy: Node in flow._enemies:
		if (enemy as Actor).data == boss_data:
			return enemy as Actor
	return null


func _imps() -> Array[Actor]:
	var found: Array[Actor] = []
	for enemy: Node in flow._enemies:
		if (enemy as Actor).data != boss_data:
			found.append(enemy as Actor)
	return found


func test_the_burst_stands_by_the_players_in_play_round_the_boss() -> void:
	for count: int in [1, 2, 4]:
		_start(count)
		var boss: Actor = _boss()
		check(boss != null, "%d players: the boss stands" % count)
		if boss == null:
			return
		check_equal(flow.enemies_left(), 1, "%d players: nothing else before its phase" % count)
		boss.phases.begin(0)
		var imps: Array[Actor] = _imps()
		check_equal(imps.size(), adds.burst_for(count), "%d players: 2 imps and 1 more a player" % count)
		var reach: float = boss.hurtbox.outer_radius() + RoomAdds.RING_GAP
		for imp: Actor in imps:
			check(not projectiles.call("circle_blocked", imp.position, imp.wall_radius()), "%d players: an imp clear of the walls at %s" % [count, imp.position])
			check(imp.position.distance_to(boss.position) <= reach + imp.wall_radius() * 2.0 + 0.5, "%d players: an imp round the boss" % count)
		check(imps.size() < 2 or not imps[0].position.is_equal_approx(imps[1].position), "%d players: each in a place of its own" % count)
		flow.stop_run()
		for index in 4:
			input.leave(index)


func test_waves_stand_under_the_cap_of_those_alive() -> void:
	_start(1)
	var boss: Actor = _boss()
	boss.phases.begin(0)
	check_equal(_imps().size(), 2, "the burst")
	boss.phases.step(1.0)
	check_equal(_imps().size(), 3, "a wave of one")
	boss.phases.step(1.0)
	check_equal(_imps().size(), 3, "never past the cap of 3 alive")
	combat.call("hit", -1, _imps()[0], 1000.0)
	check_equal(_imps().size(), 2, "one is killed")
	boss.phases.step(1.0)
	check_equal(_imps().size(), 3, "the next wave fills the cap again")


func test_the_adds_crumble_when_the_boss_dies_and_the_room_is_cleared_after() -> void:
	_start(2)
	var boss: Actor = _boss()
	boss.phases.begin(0)
	var imps: int = _imps().size()
	check(imps > 0, "its adds stand")
	combat.call("hit", -1, boss, 10000.0)
	check_equal(_imps().size(), imps, "they stand the moment the boss dies")
	check_equal(cleared, 0, "the room is not cleared while they stand")
	deaths.clear()
	flow.step(0.01)
	check_equal(flow.enemies_left(), 0, "they crumbled")
	check_equal(deaths.size(), imps, "each death told")
	check(deaths.all(func(killer: int) -> bool: return killer == -1), "nobody's kill")
	check_equal(cleared, 1, "the room is cleared once, after the last")


func test_the_adds_stand_at_the_rooms_spawns_when_asked() -> void:
	adds.at = EnemyAdds.At.SPAWNS
	_start(1)
	var boss: Actor = _boss()
	boss.phases.begin(0)
	var spawns: PackedVector2Array = flow._places.enemy_spawns
	var imps: Array[Actor] = _imps()
	check_equal(imps.size(), 2, "the burst")
	for n in imps.size():
		check(imps[n].position.is_equal_approx(FlowScript.stacked_position(spawns[n % spawns.size()], n / spawns.size())), "at the spawns in turn")


func test_only_a_body_flow_stood_calls_adds() -> void:
	_start(1)
	events.emit_signal("adds_requested", 999, adds, 0, false)
	events.emit_signal("adds_requested", -1, adds, 0, false)
	check_equal(flow.enemies_left(), 1, "an id no enemy of the room has calls nobody")


func test_health_follows_the_players_in_play_keeping_its_share() -> void:
	_start(2)
	var boss: Actor = _boss()
	check(is_equal_approx(boss.health.max_health, 150.0), "two players: half as much again, got %s" % boss.health.max_health)
	boss.health.take(75.0)
	input.add_virtual_device(2)
	await commands_applied()
	check(flow.get_wizard(2) != null, "a third wizard joins")
	check(is_equal_approx(boss.health.max_health, 200.0), "three players: twice, got %s" % boss.health.max_health)
	check(is_equal_approx(boss.health.health, 100.0), "its share kept: half, got %s" % boss.health.health)
	input.leave(2)
	input.leave(1)
	await commands_applied()
	check(is_equal_approx(boss.health.max_health, 100.0), "one player: its data's, got %s" % boss.health.max_health)
	check(is_equal_approx(boss.health.health, 50.0), "still half, got %s" % boss.health.health)
