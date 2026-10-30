extends RefCounted
## A stand-in for the swarm (`gameplay/horde/swarm.gd`, horde swarm S1) with the rows S1 gives the
## look (docs/milestones/horde-swarm.md, "The rows S1 gives S2"), filled by the tests by hand:
## `count`, `kinds` into `kinds_list` (each a `Kind` with its full `scene`), `positions`,
## `velocities`, `aims`, `seeds`, `down` and `ran` (the seconds each row stepped). Rows are
## swap-removed as S1 removes them, telling the look (`look.on_row_removed`).


## A kind of swarmer: the full enemy scene it is drawn like.
class Kind:
	extends RefCounted
	var scene: PackedScene = null

	func _init(of_scene: PackedScene) -> void:
		scene = of_scene


var count: int = 0
var kinds_list: Array = []
var kinds: PackedInt32Array = PackedInt32Array()
var positions: PackedVector2Array = PackedVector2Array()
var velocities: PackedVector2Array = PackedVector2Array()
var aims: PackedVector2Array = PackedVector2Array()
var seeds: PackedInt64Array = PackedInt64Array()
var down: PackedByteArray = PackedByteArray()
var ran: PackedFloat64Array = PackedFloat64Array()
## The look told of removals (null: nobody).
var look: Object = null


## The index of a kind drawn like `scene` (added the first time).
func kind_of(scene: PackedScene) -> int:
	for at in kinds_list.size():
		if (kinds_list[at] as Kind).scene == scene:
			return at
	kinds_list.append(Kind.new(scene))
	return kinds_list.size() - 1


## A new row of `kind` at `at`, aiming right, its habits seeded with `seed_value`; returns its row.
func add(kind: int, at: Vector2, seed_value: int) -> int:
	kinds.append(kind)
	positions.append(at)
	velocities.append(Vector2.ZERO)
	aims.append(Vector2.RIGHT)
	seeds.append(seed_value)
	down.append(0)
	ran.append(0.0)
	count += 1
	return count - 1


## Every row stepped `seconds` (none held).
func run_all(seconds: float) -> void:
	ran.fill(seconds)


## Row `row` goes: the last row takes its place (S1's swap-remove), and the look is told.
func remove(row: int) -> void:
	var last: int = count - 1
	kinds[row] = kinds[last]
	positions[row] = positions[last]
	velocities[row] = velocities[last]
	aims[row] = aims[last]
	seeds[row] = seeds[last]
	down[row] = down[last]
	ran[row] = ran[last]
	kinds.resize(last)
	positions.resize(last)
	velocities.resize(last)
	aims.resize(last)
	seeds.resize(last)
	down.resize(last)
	ran.resize(last)
	count = last
	if look != null:
		look.call(&"on_row_removed", row)


## Moves every row by its velocity for `seconds` (the swarm's walk, with no walls).
func move(seconds: float) -> void:
	for row in count:
		positions[row] += velocities[row] * seconds
