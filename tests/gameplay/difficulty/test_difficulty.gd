extends "res://tests/support/suite.gd"
## The difficulty area (run generation RG5, docs/milestones/run-generation.md, "Scaling";
## gameplay/difficulty/difficulty.gd), on the real autoloads: the room's scale the run names
## (`run_room_scaled`) is the level (never `difficulty_changed`, the setting's, which the enemies'
## skill follows: enemy AI AI10); an enemy or a boss about to stand
## (`enemy_standing`) takes it (`Actor.stat_scale`), so its data's health is multiplied by it; the level
## is the run's state, 1 again at every run's start, so the hub scales nothing; and in
## play, a pinned room of the crypt arena (tests/support/pinned_run.gd) scaled by its players stands
## its enemies at the room's scale, also through a snapshot. (Deeper rooms of a biome, each fight at its
## own scale: tests/gameplay/flow/test_room_life.gd.)
const Spawning := preload("res://tests/support/spawning.gd")
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")
const IMP: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")
const DT: float = 1.0 / 60.0

var difficulty: Node
var flow: FlowScript
var run: Node
var events: Node
var tick: TickScript
var input: Node
var registry: Node
var told: Array[float] = []
## The pinned run's definition whose scaling a test set (put back to none after).
var scaled: RunDefinition = null
## What holds the bodies a test stood by hand (freed before the next run's start).
var holders: Array[Node] = []


func before_each() -> void:
	difficulty = root.get_node("Difficulty")
	flow = root.get_node("Flow") as FlowScript
	run = root.get_node("Run")
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	registry = root.get_node("Registry")
	told.clear()
	events.connect("difficulty_changed", _on_told)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	events.disconnect("difficulty_changed", _on_told)
	for holder: Node in holders:
		holder.free()
	holders.clear()
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	flow.run_id_to_play = FlowScript.DEFAULT_RUN_ID
	if scaled != null:
		scaled.scaling = null
		scaled = null
	for seat in 4:
		input.leave(seat)
	tick.begin_run()


func _on_told(level: float) -> void:
	told.append(level)


func _level() -> float:
	return float(difficulty.get(&"level"))


## A body of `data` scaled as Flow stands one: told to difficulty before it enters the tree.
func _stand(data: EnemyBase) -> Actor:
	var body := RoomContents.make_body(data) as Actor
	events.emit_signal("enemy_standing", body)
	var holder := Node2D.new()
	holder.add_child(body)
	root.add_child(holder)
	holders.append(holder)
	return body


## A pinned run of a copy of the arena (a one-room biome), grown twice as hard to its rules'
## `scale_depth` and 1.6 times with four players (each extra player a fifth more), played by `players`.
func _play_scaled(players: int) -> void:
	var id: StringName = PinnedRun.pin(registry, ARENA)
	scaled = registry.call("get_resource", &"runs", id) as RunDefinition
	scaled.scaling = RunScaling.new()
	scaled.scaling.per_depth = ScaleCurve.make(1.0, 2.0)
	scaled.scaling.per_player = ScaleCurve.make(1.0, 1.6)
	flow.run_id_to_play = id
	for seat in players:
		input.add_virtual_device(seat)
	events.emit_signal("play_requested", 0)


## Every enemy standing in the room has its data's health times `scale`, and all of it.
## The enemies are stepped past their spawn first (enemy spawning EA3): one spawning is not in Combat.
func _check_enemies_at(scale: float, label: String) -> void:
	Spawning.land(flow)
	var enemies: Array = flow.get(&"_enemies")
	check(not enemies.is_empty(), "%s: enemies stand" % label)
	for enemy: Actor in enemies:
		check(is_equal_approx(enemy.stat_scale, scale), "%s: %s is scaled %s, not %s" % [label, enemy.data.id, enemy.stat_scale, scale])
		check(is_equal_approx(enemy.health.max_health, enemy.data.max_health * scale), "%s: %s has %s health of %s" % [label, enemy.data.id, enemy.health.max_health, enemy.data.max_health])
		check_equal(enemy.health.health, enemy.health.max_health, "%s: %s at full health" % [label, enemy.data.id])
		check(is_equal_approx(float(root.get_node("Combat").call("health_of", enemy)), enemy.data.max_health * scale), "%s: registered in Combat at its scaled health" % label)


func test_the_room_s_scale_is_the_level() -> void:
	tick.begin_run()
	check_equal(_level(), 1.0, "a run's start: as the data says")
	events.emit_signal("run_room_scaled", 2.5)
	check_equal(_level(), 2.5, "the room's scale is the level")
	check_equal(told, [] as Array[float], "not told as the difficulty setting's level")
	events.emit_signal("run_room_scaled", 0.0)
	events.emit_signal("run_room_scaled", NAN)
	check_equal(_level(), 2.5, "a scale that is no factor changes nothing")


func test_an_enemy_standing_takes_the_level_on_its_health() -> void:
	tick.begin_run()
	var plain: Actor = _stand(IMP)
	check_equal(plain.stat_scale, 1.0, "out of a run's room: as the data says")
	check_equal(plain.health.max_health, IMP.max_health, "its data's health")
	events.emit_signal("run_room_scaled", 1.5)
	var harder: Actor = _stand(IMP)
	check_equal(harder.stat_scale, 1.5, "in a room 1.5 times harder: scaled so")
	check_equal(harder.room_level, 1.5, "and its room's level kept, which its aim sharpens by")
	check_equal(plain.room_level, 1.0, "out of a run's room, level 1")
	check(is_equal_approx(harder.health.max_health, IMP.max_health * 1.5), "its health 1.5 times its data's: %s" % harder.health.max_health)
	check_equal(harder.health.health, harder.health.max_health, "and full")
	check_equal(plain.health.max_health, IMP.max_health, "a body already standing keeps what it stood with")
	events.emit_signal("enemy_standing", own(Node.new()))
	check_equal(_level(), 1.5, "a node that is no actor is let be")


func test_the_level_is_state_and_a_run_s_start_renews_it() -> void:
	tick.begin_run()
	check(tick.state_areas().has("Difficulty"), "the Tick hashes the difficulty area")
	var before: int = SimHash.of(difficulty)
	events.emit_signal("run_room_scaled", 2.0)
	check(SimHash.of(difficulty) != before, "the level changes the hash")
	var walk := StateWalk.new()
	walk.values("Difficulty", difficulty, [])
	check_equal(walk.problems, PackedStringArray(), "the area's state walks without problems")
	tick.begin_run()
	check_equal(_level(), 1.0, "a run's start: 1 again")


## The hub is no run of rooms: whatever the last run's level, nothing is scaled there.
func test_the_hub_scales_nothing() -> void:
	events.emit_signal("run_room_scaled", 3.0)
	input.add_virtual_device(0)
	flow.mode = FlowScript.MODE_HUB
	check(flow.start_run(0), "the hub starts")
	check_equal(_level(), 1.0, "the hub's start too")


## A snapshot taken in a scaled room restores its enemies with their scaled health and the level
## into a machine whose run is unscaled: by the snapshot's map (its rooms' scales are state), though
## the definition there has no scaling.
func test_a_snapshot_of_a_scaled_room_restores_its_scale() -> void:
	_play_scaled(2)
	_check_enemies_at(1.2, "the room")
	var snapshot: Snapshot = Snapshot.take(tick.state_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	var taken_hash: Dictionary = SimHash.areas(tick.state_areas(), StateWalk.new())
	flow.stop_run()
	scaled.scaling = null
	events.emit_signal("play_requested", 0)
	_check_enemies_at(1.0, "a joining machine's unscaled run")
	check_equal(snapshot.restore(tick.state_areas(), root), PackedStringArray(), "restored without problems")
	check_equal(SimHash.areas(tick.state_areas(), StateWalk.new()), taken_hash, "the game is the snapshot's")
	check(is_equal_approx(_level(), 1.2), "the level is the snapshot's: %s" % _level())
	_check_enemies_at(1.2, "the restored room")


## Play: two players in a pinned room, the start room of its biome: scaled by the players alone (1.2),
## told to difficulty before its enemies stand (the room's fight's scale, `run_room_filled`).
func test_each_room_s_enemies_stand_at_its_scale() -> void:
	_play_scaled(2)
	check_equal(flow.state, FlowScript.State.RUNNING, "the run is under way")
	var map: BiomeMap = run.get(&"map") as BiomeMap
	check(map != null and is_equal_approx(map.room_scales[0], 1.2), "the room's scale: %s" % (map.room_scales[0] if map != null else -1.0))
	check(is_equal_approx(flow.life.fights[0].scale, 1.2), "its fight's scale")
	check(is_equal_approx(_level(), 1.2), "the level is the room's")
	_check_enemies_at(1.2, "the room")
	check(told.is_empty(), "the room's scale is never the setting's level")
