extends "res://tests/support/suite.gd"
## Two spawn styles in one room, played twice and through a snapshot (spawn styles AS2,
## docs/milestones/spawn-styles.md, "Tests"): the arena paced in groups (as test_snapshot_spawning.gd),
## with a style naming the room's biome and one enemy (the bone husk) naming a style of its own, each
## of another length, added to the registry of every fresh game (`ReplayRun.spawn_styles`). Flow picks
## each body's style as it stands it (`SpawnStyle.pick`), so the room spawns in both; the run recorded with a
## snapshot mid-spawn and resumed from it in a fresh game agrees tick for tick (`Actor.spawn_style` is
## state, saved in snapshots and hashed), and the game the snapshot restored had both styles in it.

const ReplayRun := preload("res://tests/support/replay_run.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")

const TICKS: int = 160
const SNAPSHOT_AT: int = 70
const BIOME_STYLE: StringName = &"fixture_biome_spawn"
const OWN_STYLE: StringName = &"fixture_own_spawn"
## The enemy given the style of its own: the seeded run's first group has it beside crypt mites.
const OWNER: StringName = &"bone_husk"

var _run: ReplayRun
## The enemies given a style of their own (to be given theirs back), and the styles each body spawned
## in that the snapshot caught.
var _given_own: Array[EnemyBase] = []
var _caught_styles: Dictionary[StringName, int] = {}
var _caught_spawning: int = 0


func before_each() -> void:
	var biome_style := SpawnStyle.from_default()
	biome_style.id = BIOME_STYLE
	biome_style.seconds = 1.2
	biome_style.biomes = [ARENA.biome] as Array[StringName]
	var own_style := SpawnStyle.from_default()
	own_style.id = OWN_STYLE
	own_style.seconds = 0.5
	own_style.mark_end = 0.2
	_given_own.clear()
	var owner := root.get_node("Registry").call("get_resource", &"enemies", OWNER) as EnemyBase
	check(owner != null and owner.biomes.has(ARENA.biome), "%s fights in the arena's biome" % OWNER)
	if owner != null:
		check_equal(owner.spawn_style, &"", "%s names no style of its own" % OWNER)
		owner.spawn_style = OWN_STYLE
		_given_own.append(owner)
	_run = ReplayRun.new(tree)
	_run.ticks = TICKS
	_run.run_seed = 0x5eed
	var pace := SpawnRules.new()
	pace.group_share = 0.5
	pace.refill_share = 0.0
	pace.stagger = 0.3
	_run.room = ARENA
	_run.spawning = pace
	_run.at_snapshot = _caught
	_run.spawn_styles = [biome_style, own_style] as Array[SpawnStyle]
	_caught_styles.clear()
	_caught_spawning = 0


func after_each() -> void:
	for enemy in _given_own:
		enemy.spawn_style = &""
	_given_own.clear()
	_run.spawn_styles = [] as Array[SpawnStyle]
	_run.room = null
	_run.spawning = null
	_run.at_snapshot = Callable()
	await _run.fresh()


func _caught() -> void:
	for enemy: Node in root.get_node("Flow").get(&"_enemies") as Array[Node]:
		if is_instance_valid(enemy):
			var style: StringName = (enemy as Actor).spawn_style
			_caught_styles[style] = int(_caught_styles.get(style, 0)) + 1
			if (enemy as Actor).is_spawning():
				_caught_spawning += 1


func test_a_room_of_two_styles_plays_the_same_through_a_snapshot() -> void:
	var recorded := Desync.new()
	_run.snapshot_at = SNAPSHOT_AT
	var replay: Replay = await _run.record(&"play_requested", 0, 1, recorded)
	check(replay != null and _run.snapshot != null, "recorded with its snapshot")
	if replay == null or _run.snapshot == null:
		return
	for problem in _run.snapshot.problems:
		check(false, "the snapshot: %s" % problem)
	check(_caught_styles.has(BIOME_STYLE) and _caught_styles.has(OWN_STYLE), "the snapshot caught bodies of both styles: %s" % _caught_styles)
	check(not _caught_styles.has(SpawnStyle.DEFAULT["id"]), "and none in rise: %s" % _caught_styles)
	check(_caught_spawning > 0, "with a body mid-spawn: %d" % _caught_spawning)
	recorded.hashes = recorded.hashes.slice(SNAPSHOT_AT + 1)
	var resumed := Desync.new()
	await _run.resume(replay, _run.snapshot, SNAPSHOT_AT, 0, resumed)
	for problem in _run.problems:
		check(false, problem)
	_run.problems.clear()
	check_equal(resumed.hashes.size(), TICKS - SNAPSHOT_AT - 1, "the resumed run played every tick after the snapshot")
	var tick: int = Desync.first_parting(recorded, resumed)
	check(tick < 0, "the resumed run parts from the recorded one %d ticks after the snapshot" % (tick + 1))
	var restored: Dictionary[StringName, int] = {}
	for enemy: Node in root.get_node("Flow").get(&"_enemies") as Array[Node]:
		if is_instance_valid(enemy):
			var style: StringName = (enemy as Actor).spawn_style
			restored[style] = int(restored.get(style, 0)) + 1
	check(restored.has(BIOME_STYLE) and restored.has(OWN_STYLE), "the resumed game's bodies are of both styles: %s" % restored)
