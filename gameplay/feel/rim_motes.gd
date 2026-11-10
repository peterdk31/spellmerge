extends RefCounted
## Rim motes: the motes a room's floor edge gives off all the time, as art (`MoteRim`,
## core/base/mote_rim.gd: a hidden `Line2D` in the group `mote_rim` with what it gives off as its
## metadata; the hub's island, docs/milestones/online-lobby.md, L1). When a room is entered
## (`take`), every such node in the tree is read once into its own copy (the points in the world,
## their running length, its `MoteRim`), so no node is held; each frame (`give_off`) each rim gives
## off its rate's share of motes at random points along it, thrown outward from the edge, each in
## one of its ramps at random. They are motes of many a frame (`often`): in a crowded frame they
## give way to the moments and the hits first.
##
## View only: nothing in the game reads a rim, its dice are its own, and it runs on Feel's clock. A
## room with no rim node has none; the look is the node's data and its mote kind (content/motes).

const MotesScript := preload("res://gameplay/feel/mote.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")

## The longest frame it gives off for (s): a frame after a stall gives off no more.
const LONGEST_FRAME: float = 0.1
## How far from the edge a mote is born, at most, either way (px).
const JITTER: float = 1.5


## One rim, read from its node.
class Rim:
	var points: PackedVector2Array = PackedVector2Array()
	## The length of the rim up to each point (the first 0), and its whole length.
	var running: PackedFloat32Array = PackedFloat32Array()
	var length: float = 0.0
	var look: MoteRim = null
	## Motes owed from the frames before (a part of one).
	var owed: float = 0.0


var _rims: Array[Rim] = []
var _rng := RandomNumberGenerator.new()
var _last: float = -1.0


## The rims in the room now: every node of `tree` in MoteRim.GROUP with a sound `MoteRim`, read once.
func take(tree: SceneTree) -> void:
	_rims.clear()
	_last = -1.0
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(MoteRim.GROUP):
		var line := node as Line2D
		var look: MoteRim = MoteRim.of(node)
		if line == null or look == null or not look.problems().is_empty() or line.points.size() < 2:
			continue
		var rim := Rim.new()
		rim.look = look
		var to_world: Transform2D = line.global_transform
		for point: Vector2 in line.points:
			rim.points.append(to_world * point)
		if line.closed:
			rim.points.append(rim.points[0])
		rim.running.append(0.0)
		for i in range(1, rim.points.size()):
			rim.length += rim.points[i - 1].distance_to(rim.points[i])
			rim.running.append(rim.length)
		if rim.length > 0.0:
			_rims.append(rim)


## How many rims the room has (for tests).
func rim_count() -> int:
	return _rims.size()


## Give off the motes owed since the last call, at Feel's clock `now`, into `pool` (null: none, the
## particles are off) in the ramps of `table`.
func give_off(now: float, pool: MotesScript, table: RampTableScript) -> void:
	var dt: float = clampf(now - _last, 0.0, LONGEST_FRAME) if _last >= 0.0 else 0.0
	_last = now
	if pool == null or table == null or dt <= 0.0:
		return
	for rim in _rims:
		var k: int = pool.kind_index(rim.look.kind)
		if k < 0:
			continue
		rim.owed += rim.look.rate * rim.length / 100.0 * dt
		while rim.owed >= 1.0:
			rim.owed -= 1.0
			_throw(rim, k, pool, table)


func _throw(rim: Rim, k: int, pool: MotesScript, table: RampTableScript) -> void:
	var along: float = _rng.randf() * rim.length
	# The segment `along` falls in: the last point whose running length is at most it.
	var i: int = clampi(rim.running.bsearch(along, true) - 1, 0, rim.points.size() - 2)
	var a: Vector2 = rim.points[i]
	var b: Vector2 = rim.points[i + 1]
	var way: Vector2 = (b - a).normalized()
	# Clockwise on screen: the outside is on the left of the way the points run.
	var outward := Vector2(way.y, -way.x)
	var at: Vector2 = a + way * (along - rim.running[i]) + outward * _rng.randf_range(-JITTER, JITTER)
	var ramp: PackedColorArray = rim.look.ramps[_rng.randi() % rim.look.ramps.size()]
	pool.throw_part(k, at, outward, table.source(ramp), Color.WHITE, 1, rim.look.reach, rim.look.spread, 1.0, false, true)
