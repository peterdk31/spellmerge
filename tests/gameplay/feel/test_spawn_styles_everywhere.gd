extends "res://tests/support/suite.gd"
## Every spawn style on every enemy (spawn styles AS3, docs/milestones/spawn-styles.md, "Tests"), as
## tests/core/test_card_rules.gd plays every card on every carrier: it keeps no list. It asks the
## registry for every style and every enemy that spawns in (every non-boss enemy, and every enemy a
## boss's phase calls as an add: bosses themselves stand at once), makes each enemy's real body
## (`RoomContents.make_body`) and spawns it in each style, stepped as the tick steps it, with the look
## Feel draws it by. Each cell must: land on the tick its style's seconds run out; draw each of its
## motion's stages in at least `SpawnStyle.MIN_FRAMES` looks (docs/STYLE.md, "Smooth"; the mark's
## width and every number of the motion's look whole pixels); be drawn the same by a fresh look at
## any frame (from its state alone, as after a snapshot); and be put back once it stands. Each failing
## cell is named, and the test fails. A new style or enemy is checked the day it lands.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const Motion := preload("res://gameplay/feel/spawn_motions/spawn_motion.gd")

const STEP: float = 1.0 / SpawnStyle.CHECK_FPS
## Every how many frames a fresh look is asked to draw the same.
const FRESH_EVERY: int = 7

var _world: Fixture
var _look: SpawnLook
var _fresh: SpawnLook
var _registry: Node


func before_each() -> void:
	_world = Fixture.new(root)
	_registry = root.get_node("Registry")
	var registry: Node = _registry
	var lookup: Callable = func(id: StringName) -> SpawnStyle: return registry.call("get_resource", SpawnStyle.FOLDER, id) as SpawnStyle
	_look = SpawnLook.new()
	root.add_child(_look)
	_look.style_of = lookup
	_fresh = SpawnLook.new()
	root.add_child(_fresh)
	_fresh.style_of = lookup


func after_each() -> void:
	_look.free()
	_fresh.free()
	_world.free_all()


## Every enemy that spawns in, by id: the enemies (none a boss), and the adds the bosses call.
func _spawners() -> Dictionary[StringName, EnemyBase]:
	var found: Dictionary[StringName, EnemyBase] = {}
	for item: Resource in _registry.call("get_all", EnemyBase.FOLDERS[0]):
		var enemy := item as EnemyBase
		if enemy != null and enemy.phases.is_empty():
			found[enemy.id] = enemy
	for item: Resource in _registry.call("get_all", EnemyBase.FOLDERS[1]):
		var boss := item as EnemyBase
		if boss == null:
			continue
		for phase: EnemyPhase in boss.phases:
			for adds: EnemyAdds in phase.adds:
				var add := _registry.call("get_resource", EnemyBase.FOLDERS[0], adds.enemy) as EnemyBase
				check(add != null, "%s's add %s is an enemy" % [boss.id, adds.enemy])
				if add != null:
					found[add.id] = add
	return found


func _styles() -> Array[SpawnStyle]:
	var found: Array[SpawnStyle] = []
	for item: Resource in _registry.call("get_all", SpawnStyle.FOLDER):
		if item is SpawnStyle:
			found.append(item as SpawnStyle)
	return found


func test_every_style_on_every_enemy() -> void:
	var styles: Array[SpawnStyle] = _styles()
	var enemies: Dictionary[StringName, EnemyBase] = _spawners()
	check(styles.size() >= 2, "rise and materialize at least: %d" % styles.size())
	check(enemies.size() >= 5, "the enemies that spawn in: %s" % [enemies.keys()])
	var failed: PackedStringArray = PackedStringArray()
	var cells: int = 0
	for style in styles:
		for id: StringName in enemies:
			var problems: PackedStringArray = _play(enemies[id], style)
			cells += 1
			for problem in problems:
				failed.append("%s in %s: %s" % [id, style.id, problem])
	print("%d styles on %d enemies: %d cells, %d failed" % [styles.size(), enemies.size(), cells, failed.size()])
	for line in failed:
		print("  ✗ ", line)
	check_equal(failed, PackedStringArray(), "%d cells: every style draws every enemy smoothly and lands on time" % cells)


## What is wrong with `data`'s body spawning in `style`, one line each.
func _play(data: EnemyBase, style: SpawnStyle) -> PackedStringArray:
	var found := PackedStringArray()
	var body := RoomContents.make_body(data) as Actor
	if body == null:
		found.append("no body")
		return found
	body.spawn(style.seconds, style.id)
	_world.add(body, Vector2(160.0, 120.0))
	var motion: Motion = _look.motion_named(style.motion)
	var stages: PackedFloat32Array = motion.stages(style)
	var looks: Array = []
	looks.resize(stages.size() - 1)
	for s in looks.size():
		looks[s] = []
	var ticks: int = 0
	var due: int = ceili(style.seconds * SpawnStyle.CHECK_FPS - 0.001)
	while body.is_spawning() and ticks <= due + 2:
		var share: float = body.spawn_share()
		_look.step(_world.table, STEP)
		_look.cut()
		var radius: float = _mark_radius(_look)
		var seen: Array = [radius, motion.look_of(body)]
		if motion.look_of(body).is_empty():
			found.append("not drawn at %.2f" % share)
			break
		for s in looks.size():
			if share >= stages[s] and share < stages[s + 1] and not looks[s].has(seen):
				looks[s].append(seen)
		if ticks % FRESH_EVERY == 3:
			_fresh.step(_world.table, 0.0)
			_fresh.cut()
			var fresh_motion: Motion = _fresh.motion_named(style.motion)
			if fresh_motion.look_of(body) != motion.look_of(body) or _mark_radius(_fresh) != radius:
				found.append("a fresh look draws it otherwise at %.2f: %s, not %s" % [share, fresh_motion.look_of(body), motion.look_of(body)])
			_fresh_put_back(fresh_motion, body)
		body.tick_step(STEP)
		ticks += 1
	if absi(ticks - due) > 1:
		found.append("it landed after %d ticks, not %d (%s s)" % [ticks, due, style.seconds])
	for s in looks.size():
		if looks[s].size() < SpawnStyle.MIN_FRAMES:
			found.append("stage %d (%.2f to %.2f) is drawn in %d looks, %d at least" % [s, stages[s], stages[s + 1], looks[s].size(), SpawnStyle.MIN_FRAMES])
	_look.step(_world.table, STEP)
	_look.cut()
	if body.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED or not motion.look_of(body).is_empty():
		found.append("not put back once it stands")
	_world.actors.erase(body)
	body.free()
	_look.cut()
	return found


## The width of the one mark `look` lays this frame (0 for none).
static func _mark_radius(look: SpawnLook) -> float:
	return look.mark(0).z if look.marks() > 0 else 0.0


## The fresh look's motion puts `body` back (the game's look draws it again before the next frame), and
## a new fresh look is made, so each check is a first sight.
func _fresh_put_back(fresh_motion: Motion, body: Actor) -> void:
	fresh_motion.put_back(body.get_instance_id(), body)
	_fresh.free()
	_fresh = SpawnLook.new()
	root.add_child(_fresh)
	_fresh.style_of = _look.style_of
