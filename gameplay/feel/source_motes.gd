extends RefCounted
## Source motes: what the world's things give off all the time, as art (props W7,
## docs/milestones/props.md): every node in the group `mote_source` with a sound `MoteSource`
## (core/base/mote_source.gd), the room's own (the hub's island edge) and those a prop's look adds
## for the state it is in. It follows the tree as spell light follows its spots (`watch`: a node in
## the group read when it enters, let go when it leaves; `take` reads them all again), each read
## once into its own copy (where it is in the world, its points, its mask's pixels, its colours), so
## no node is held and nothing is asked of one each frame. Each frame (`give_off`) a source near the
## view gives off its rate's share of motes, each in one of its ramps at random, as motes of many a
## frame (`often`: in a crowded frame they give way to the moments and the hits first), and a
## standing mask places a mote on every lit pixel (`placed_motes.gd`), each cooling in its own turn.
##
## View only: nothing in the game reads a source, its dice are its own, and it runs on Feel's clock.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const MotePlaces := preload("res://gameplay/feel/mote_places.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const PlacedMotesScript := preload("res://gameplay/feel/placed_motes.gd")

## The longest frame it gives off for (s): a frame after a stall gives off no more.
const LONGEST_FRAME: float = 0.1
## How far from a line a mote is born, at most, either way (px).
const JITTER: float = 1.5
## How far past the view a source still gives off (px): what flies in from just outside it.
const VIEW_MARGIN: float = 64.0


## One source, read from its node.
class Source:
	var node: int = 0
	var look: MoteSource = null
	## Where it is: its node's world transform; the world box it gives off in (for the view).
	var to_world: Transform2D = Transform2D.IDENTITY
	var bounds: Rect2 = Rect2()
	## POINT, AREA, RIM: its middle and half-size in the world; the way it throws, in the world.
	var middle: Vector2 = Vector2.ZERO
	var half: Vector2 = Vector2.ZERO
	var way: Vector2 = Vector2.UP
	## LINE: its points in the world and the length up to each (the first 0); MASK: its lit
	## pixels' middles in the world.
	var points: PackedVector2Array = PackedVector2Array()
	var running: PackedFloat32Array = PackedFloat32Array()
	var length: float = 0.0
	## Its ramps as the ramp table's sources.
	var sources: PackedInt32Array = PackedInt32Array()
	## A standing mask: each pixel's own turn (0 to 1).
	var seeds: PackedFloat32Array = PackedFloat32Array()
	## Feel's clock when it appeared (below 0: at the next frame), and motes owed (a part of one).
	var born: float = -1.0
	var owed: float = 0.0


var _sources: Array[Source] = []
## Nodes that entered the group, read at the next frame (their mask's sprite, a sibling, may enter
## the tree after them): instance ids.
var _pending: PackedInt64Array = PackedInt64Array()
var _table: RampTableScript = null
var _tree: SceneTree = null
var _rng := RandomNumberGenerator.new()
var _last: float = -1.0
## The lit pixels and colours of a texture's frame, read once: {[texture, rect]: ...}.
var _art_pixels: Dictionary = {}
var _art_colours: Dictionary = {}
## Motes given off and placed, all told (for tests).
var given: int = 0
var placed: int = 0


## Sources whose colours are rows of `table` (the spectacle's, shared with the motes).
func _init(table: RampTableScript) -> void:
	_table = table


## Follow the sources of `tree` (null: none): every node in the group now, and each that enters or
## leaves it from now on.
func watch(tree: SceneTree) -> void:
	if _tree != null and _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.disconnect(_on_node_added)
		_tree.node_removed.disconnect(_on_node_removed)
	_tree = tree
	if tree != null:
		tree.node_added.connect(_on_node_added)
		tree.node_removed.connect(_on_node_removed)
	take(tree)


## Read every source in `tree` again (null: none), each from now (a new room: the art read for
## the last one is let go).
func take(tree: SceneTree) -> void:
	_sources.clear()
	_pending.clear()
	_art_pixels.clear()
	_art_colours.clear()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(MoteSource.GROUP):
		read(node)


## How many sources it gives off from (for tests).
func source_count() -> int:
	return _sources.size()


## Read `node`'s source at the next frame (`give_off`), as it is then.
func add(node: Node) -> void:
	var id: int = node.get_instance_id()
	if not _pending.has(id):
		_pending.append(id)


## Read `node`'s source now (one of the group with a sound `MoteSource`; anything else is left
## out), from now. A node read again replaces what was read before.
func read(node: Node) -> void:
	remove(node)
	var look: MoteSource = MoteSource.of(node)
	var where := node as Node2D
	if look == null or where == null or not where.is_inside_tree():
		return
	var art: Sprite2D = MoteSource.art_of(node)
	if not look.problems(art != null and art.texture != null).is_empty():
		return
	var source := Source.new()
	source.node = node.get_instance_id()
	source.look = look
	source.to_world = where.global_transform
	if not _read_place(source, where, art):
		return
	source.sources = _sources_of(look, art)
	if source.sources.is_empty():
		return
	if look.stand:
		for i in source.points.size():
			source.seeds.append(_rng.randf())
	_sources.append(source)


## Let go of `node`'s source, if it had one.
func remove(node: Node) -> void:
	var id: int = node.get_instance_id()
	var waiting: int = _pending.find(id)
	if waiting >= 0:
		_pending.remove_at(waiting)
	for i in _sources.size():
		if _sources[i].node == id:
			_sources.remove_at(i)
			return


## Give off the motes owed since the last call, at Feel's clock `now`, into `pool` (null: none,
## the particles are off), from the sources within VIEW_MARGIN of `view` (the world's part on
## screen; an empty one: everywhere); a standing mask's motes are placed in `stand` (null: none).
func give_off(now: float, pool: MotesScript, view: Rect2 = Rect2(), stand: PlacedMotesScript = null) -> void:
	var dt: float = clampf(now - _last, 0.0, LONGEST_FRAME) if _last >= 0.0 else 0.0
	_last = now
	if not _pending.is_empty():
		var waiting: PackedInt64Array = _pending
		_pending = PackedInt64Array()
		for id: int in waiting:
			var node := instance_from_id(id) as Node
			if node != null and node.is_inside_tree():
				read(node)
	var standing: bool = stand != null and stand.begin(pool, now)
	var near: Rect2 = view.grow(VIEW_MARGIN) if view.has_area() else Rect2()
	for source in _sources:
		if source.born < 0.0:
			source.born = now
		if pool == null or (near.has_area() and not near.intersects(source.bounds)):
			source.owed = 0.0
			continue
		var since: float = now - source.born
		var look: MoteSource = source.look
		if since < look.start or (look.stop > 0.0 and since >= look.stop):
			source.owed = 0.0
			continue
		var k: int = pool.kind_index(look.kind)
		if k < 0:
			continue
		if look.stand:
			if standing:
				_stand(source, k, since, stand)
			continue
		source.owed += look.rate * dt
		while source.owed >= 1.0:
			source.owed -= 1.0
			_throw(source, k, pool)
	if standing:
		stand.finish()


## Where `source` gives off from, read from its node `where` (and its mask's `art`); false when
## there is nowhere (a line of no length, a mask with no lit pixel).
func _read_place(source: Source, where: Node2D, art: Sprite2D) -> bool:
	var look: MoteSource = source.look
	var to_world: Transform2D = source.to_world
	var scale: Vector2 = to_world.get_scale().abs()
	source.way = to_world.basis_xform(look.way).normalized() if not look.way.is_zero_approx() else Vector2.UP
	source.middle = to_world * look.at
	source.half = look.size * 0.5 * scale
	match look.from:
		MoteSource.From.LINE:
			var local: PackedVector2Array = look.points
			var closed: bool = look.closed
			if local.is_empty() and where is Line2D:
				local = (where as Line2D).points
				closed = (where as Line2D).closed
			for point in local:
				source.points.append(to_world * point)
			if closed and source.points.size() > 1:
				source.points.append(source.points[0])
			source.running.append(0.0)
			for i in range(1, source.points.size()):
				source.length += source.points[i - 1].distance_to(source.points[i])
				source.running.append(source.length)
			if source.points.size() < 2 or source.length <= 0.0:
				return false
			source.bounds = _box_of(source.points)
		MoteSource.From.MASK:
			source.points = _mask_points(art)
			if source.points.is_empty():
				return false
			source.bounds = _box_of(source.points)
		MoteSource.From.AREA, MoteSource.From.RIM:
			source.bounds = Rect2(source.middle - source.half, source.half * 2.0)
		_:
			source.bounds = Rect2(source.middle, Vector2.ZERO)
	# What it throws flies a little past where it leaves from.
	source.bounds = source.bounds.grow(look.reach + look.height + JITTER)
	return true


## The world middles of the lit pixels of the frame `art` shows, read once a texture's frame.
func _mask_points(art: Sprite2D) -> PackedVector2Array:
	var rect: Rect2i = ArtPixels.frame_of(art)
	var key: Array = [art.texture, rect]
	var pixels: Variant = _art_pixels.get(key)
	if pixels == null:
		pixels = ArtPixels.pixels_of(art.texture, rect)
		_art_pixels[key] = pixels
	var size := Vector2(rect.size)
	var corner: Vector2 = art.offset - (size * 0.5 if art.centered else Vector2.ZERO)
	var to_world: Transform2D = art.global_transform
	var found := PackedVector2Array()
	for p: Vector2 in pixels as PackedVector2Array:
		if art.flip_h:
			p.x = size.x - 1.0 - p.x
		found.append(to_world * (corner + p + Vector2(0.5, 0.5)))
	return found


## The ramp table's sources of `look`'s ramps, else of its art's colours (lightest first, read once
## a texture's frame); empty when it has neither.
func _sources_of(look: MoteSource, art: Sprite2D) -> PackedInt32Array:
	var found := PackedInt32Array()
	if _table == null:
		return found
	for ramp: PackedColorArray in look.ramps:
		found.append(_table.source(ramp))
	if found.is_empty() and art != null and art.texture != null:
		var rect: Rect2i = ArtPixels.frame_of(art)
		var key: Array = [art.texture, rect]
		var colours: Variant = _art_colours.get(key)
		if colours == null:
			colours = ArtPixels.colours_of(art.texture, rect)
			_art_colours[key] = colours
		if not (colours as PackedColorArray).is_empty():
			found.append(_table.source(colours as PackedColorArray))
	return found


## One mote of kind `k` off `source`, into `pool`.
func _throw(source: Source, k: int, pool: MotesScript) -> void:
	var look: MoteSource = source.look
	var at: Vector2 = source.middle
	var dir: Vector2 = source.way
	match look.from:
		MoteSource.From.LINE:
			var along: float = clampf(MotePlaces.on_grid(_rng.randf() * source.length, 0.0, look.spacing), 0.0, source.length)
			# The segment `along` falls in: the last point whose running length is at most it.
			var i: int = clampi(source.running.bsearch(along, true) - 1, 0, source.points.size() - 2)
			var a: Vector2 = source.points[i]
			var b: Vector2 = source.points[i + 1]
			var on: Vector2 = (b - a).normalized()
			# Clockwise on screen: the outside is on the left of the way the points run.
			dir = Vector2(on.y, -on.x)
			at = a + on * (along - source.running[i]) + dir * _rng.randf_range(-JITTER, JITTER)
		MoteSource.From.AREA:
			at += Vector2(_rng.randf_range(-1.0, 1.0) * source.half.x, _rng.randf_range(-1.0, 1.0) * source.half.y)
			if look.spacing > 0.0:
				at = (at / look.spacing).round() * look.spacing
		MoteSource.From.RIM:
			var off: Vector2 = MotePlaces.on_oval(_rng, source.half, look.spacing)
			at += off
			dir = off.normalized() if not off.is_zero_approx() else source.way
		MoteSource.From.MASK:
			at = source.points[_rng.randi() % source.points.size()]
	var ramp: int = source.sources[_rng.randi() % source.sources.size()]
	var height: float = look.height if look.height > 0.0 else -1.0
	var shown: Vector2 = at - Vector2(0.0, look.height) if look.height > 0.0 else at
	pool.throw_part(k, shown, dir, ramp, Color.WHITE, 1, look.reach, look.spread, 1.0, false, true, Vector2.ZERO, 1.0, 0, height)
	given += 1


## A standing mask: a mote of kind `k` on every lit pixel of `source`, `since` seconds after it
## appeared, each in its own turn of the round (`life`), placed in `stand`.
func _stand(source: Source, k: int, since: float, stand: PlacedMotesScript) -> void:
	var life: float = source.look.life
	var count: int = source.sources.size()
	stand.hold(stand.rows + source.points.size())
	for i in source.points.size():
		var seed: float = source.seeds[i]
		var ramp: int = source.sources[mini(floori(seed * count), count - 1)]
		stand.put(source.points[i], k, ramp, Color.WHITE, fposmod(since + seed * life, life), seed, life)
	placed += source.points.size()


static func _box_of(points: PackedVector2Array) -> Rect2:
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	return box


func _on_node_added(node: Node) -> void:
	if node.is_in_group(MoteSource.GROUP):
		add(node)


func _on_node_removed(node: Node) -> void:
	if node.is_in_group(MoteSource.GROUP):
		remove(node)
