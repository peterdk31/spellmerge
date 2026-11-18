extends RefCounted
## Light blocked (docs/milestones/atmosphere.md, C): the boxes that stop spell light, worked out from
## the room and the props in it and handed to the spell light (`SpellLight.set_blockers`), which
## draws every light with them (`light.gdshader`); the spell light knows nothing of rooms or props,
## and this knows nothing of how light is drawn. View only: it reads the room's layout and the
## bodies once a frame, and changes nothing.
##
## - **Standing walls:** the room's walls that stand inside it (a sarcophagus, a low wall of bones,
##   an old room's pillar walls), read from its layout as it is built (`use_walls`, from Flow's
##   `room_built`). A wall joined to the room's outer edge through other walls (a floating room's
##   void, a tiled room's outer walls: `standing`) is no blocker: light is never drawn past it, and a
##   floating slab's wavy edge would only cut the pools along it.
## - **Props that block light:** a prop whose data says so (`PropBase.blocks_light`: the crypt's
##   pillars) blocks by the ground it stands on (its `Footprint` box) while that blocks the bodies
##   that walk (its state's `blocks`), and has a column drawn over it: its hurt box, the shaft, lit as
##   the floor in front of its base (light.gdshader). Found each frame in the actor table, so a body
##   made again from a snapshot is found as any other.
## - **Smooth:** a prop's box comes with the room at full strength, and when it stops blocking (a
##   pillar crumbles into rubble) its strength eases to nothing over FADE_SECONDS and its column
##   shrinks down to its base with it, so the light comes back over the rubble a band at a time as
##   the shaft falls, never in one jump.
##
## Up to MAX boxes (light.gdshader's MAX_BLOCKERS), the walls first; any past it are left out (every
## room's are counted by a test). `lit_as` and `shade_between` are the shader's pick in GDScript (for
## the bodies' shadows and the tests).

const ActorsScript := preload("res://core/actors/actors.gd")

## The most boxes (light.gdshader's MAX_BLOCKERS: its uniform arrays' length).
const MAX: int = 32
## How long a prop's box takes to ease out once it stops blocking (s): about its crumble's strip
## (the crypt pillar's rubble is 9 frames at 12 a second).
const FADE_SECONDS: float = 0.6
## How near two walls are to count as joined (px).
const JOIN: float = 0.5
## Below this strength a box is gone.
const OUT: float = 0.002

## The boxes this frame, `count` of them (MAX each, made once): a base as x0, y0, x1, y1, and the
## column over it as x0, top, x1 and its strength (a top at y0: no column). Read only.
var boxes: PackedVector4Array = PackedVector4Array()
var bodies: PackedVector4Array = PackedVector4Array()
var count: int = 0
## The room's standing walls (`use_walls`). Read only.
var walls: Array[Rect2] = []
## Each actor's prop box as drawn: its strength (-1: not a prop that blocks light), and its base and
## full column (x0, top, x1) as last seen. Read only.
var strength: PackedFloat32Array = PackedFloat32Array()
var _base: PackedVector4Array = PackedVector4Array()
var _column: PackedVector3Array = PackedVector3Array()
## The props seen this frame and the last (ids), and the open ids' buffer.
var _props: PackedInt32Array = PackedInt32Array()
var _prop_count: int = 0
var _ids: PackedInt32Array = PackedInt32Array()
## The boxes changed since they were last handed over (`step`), and Feel's clock at the last step.
var _dirty: bool = true
var _last: float = -1.0


func _init() -> void:
	boxes.resize(MAX)
	bodies.resize(MAX)
	strength.resize(ActorsScript.ACTORS)
	strength.fill(-1.0)
	_base.resize(ActorsScript.ACTORS)
	_column.resize(ActorsScript.ACTORS)
	_props.resize(MAX)


## A room was laid out: its walls (`RoomPlaces.wall_rects` of its layout, room pixels), of which the
## standing ones block light from now on. Its props are found as they come (`step`).
func use_walls(rects: Array[Rect2]) -> void:
	walls = standing(rects)
	_dirty = true


## The boxes are handed over again at the next step (a spell light made anew).
func refresh() -> void:
	_dirty = true


## The walls of `rects` that stand inside the room: those not joined to the edge of the box round
## them all through walls that touch (within JOIN). Made each call (once a room).
static func standing(rects: Array[Rect2]) -> Array[Rect2]:
	var found: Array[Rect2] = []
	if rects.is_empty():
		return found
	var room: Rect2 = rects[0]
	for rect in rects:
		room = room.merge(rect)
	var edge := PackedByteArray()
	edge.resize(rects.size())
	var reach: Array[int] = []
	for i in rects.size():
		var rect: Rect2 = rects[i]
		if rect.position.x <= room.position.x + JOIN or rect.position.y <= room.position.y + JOIN or rect.end.x >= room.end.x - JOIN or rect.end.y >= room.end.y - JOIN:
			edge[i] = 1
			reach.append(i)
	while not reach.is_empty():
		var near: Rect2 = rects[reach.pop_back()].grow(JOIN)
		for j in rects.size():
			if edge[j] == 0 and near.intersects(rects[j]):
				edge[j] = 1
				reach.append(j)
	for i in rects.size():
		if edge[i] == 0:
			found.append(rects[i])
	return found


## Once a frame at Feel's clock `now` (real seconds): the props that block light read from `table`
## (the actor table; null: none), their strengths eased, and the boxes written. Returns whether they
## changed since they were last handed over (then hand `boxes`, `bodies` and `count` on).
func step(table: ActorsScript, now: float) -> bool:
	var delta: float = clampf(now - _last, 0.0, 0.25) if _last >= 0.0 else 0.0
	_last = now
	var most: float = delta / FADE_SECONDS
	var seen: int = 0
	var open: int = table.open_ids(_ids) if table != null else 0
	for at in open:
		var id: int = _ids[at]
		var body := table.node_of(id) as Actor
		if body == null or body.prop == null or not body.prop.blocks_light or body.mover != null or body.footprint == null or not body.is_inside_tree():
			continue
		if seen >= MAX:
			break
		var feet: Vector2 = body.global_position
		var box: Rect2 = body.footprint.rect_at(feet)
		var base := Vector4(box.position.x, box.position.y, box.end.x, box.end.y)
		var column: Vector3 = _column_of(body.prop, feet, base)
		var want: float = 1.0 if body.footprint.solid else 0.0
		var now_strength: float = strength[id]
		if now_strength < 0.0:
			# Come with the room: as it stands, no ease in.
			now_strength = want
			_dirty = true
		elif now_strength != want:
			now_strength = move_toward(now_strength, want, most)
			_dirty = true
		if base != _base[id] or column != _column[id]:
			_dirty = true
		strength[id] = now_strength
		_base[id] = base
		_column[id] = column
		if seen >= _prop_count or _props[seen] != id:
			_dirty = true
		_props[seen] = id
		seen += 1
	# A prop gone from the table (a room left) is forgotten: it comes again as new.
	for at in range(seen, _prop_count):
		var gone: int = _props[at]
		if not _holds(_props, seen, gone):
			strength[gone] = -1.0
		_dirty = true
	_prop_count = seen
	if not _dirty:
		return false
	_dirty = false
	_write()
	return true


## Whether `ids` holds `id` among its first `n`.
static func _holds(ids: PackedInt32Array, n: int, id: int) -> bool:
	for at in n:
		if ids[at] == id:
			return true
	return false


## The column drawn over a prop's base (its hurt shape's box: x0, top, x1) at `feet`, or none (its
## top at the base's top).
static func _column_of(prop: PropBase, feet: Vector2, base: Vector4) -> Vector3:
	var half: Vector2 = prop.size * 0.5 if prop.size != Vector2.ZERO else Vector2(prop.radius, prop.radius)
	var centre: Vector2 = feet + prop.offset
	var top: float = minf(centre.y - half.y, base.y)
	return Vector3(minf(centre.x - half.x, base.x), top, maxf(centre.x + half.x, base.z))


## Write the boxes: the standing walls, then each prop seen with any strength left, its column's top
## coming down to its base as its strength goes.
func _write() -> void:
	count = 0
	for wall in walls:
		if count >= MAX:
			return
		boxes[count] = Vector4(wall.position.x, wall.position.y, wall.end.x, wall.end.y)
		bodies[count] = Vector4(wall.position.x, wall.position.y, wall.end.x, 1.0)
		count += 1
	for at in _prop_count:
		var id: int = _props[at]
		var share: float = strength[id]
		if share <= OUT or count >= MAX:
			continue
		var base: Vector4 = _base[id]
		var column: Vector3 = _column[id]
		boxes[count] = base
		bodies[count] = Vector4(column.x, lerpf(base.y, column.y, share), column.z, share)
		count += 1


# --- The shader's pick (light.gdshader), in GDScript ---------------------------------------------

## Where `p` is lit as: just in front of the base of the first box whose column holds it, else
## itself (light.gdshader's `lit_as`).
static func lit_as(p: Vector2, box_list: PackedVector4Array, body_list: PackedVector4Array, n: int) -> Vector2:
	for k in mini(n, MAX):
		var box: Vector4 = box_list[k]
		var body: Vector4 = body_list[k]
		if body.w > 0.0 and body.y < box.y and p.x >= body.x and p.x <= body.z and p.y >= body.y and p.y <= box.w:
			return Vector2(p.x, box.w + 0.5)
	return p


## The first box whose column holds `p` (-1: none; light.gdshader's `column_of`).
static func column_of(p: Vector2, box_list: PackedVector4Array, body_list: PackedVector4Array, n: int) -> int:
	for k in mini(n, MAX):
		var box: Vector4 = box_list[k]
		var body: Vector4 = body_list[k]
		if body.w > 0.0 and body.y < box.y and p.x >= body.x and p.x <= body.z and p.y >= body.y and p.y <= box.w:
			return k
	return -1


## How much of a light at `l` (where it is lit from: `lit_as` its middle) is blocked on its way to the
## pixel `p` (0 to 1; light.gdshader's `shade_between`, every box counted as near): the strongest box
## the way crosses that holds neither end. A pixel in a column is lit as the floor in front of its
## base, and its own box blocks only a light behind it (past its base's back edge); a point that is
## `on_floor` (a body's feet) is never in a column, whatever is drawn over it.
## Only the boxes whose bits are set in `near_bits` are tested (the shader's `near`; -1: every one).
static func shade_between(p: Vector2, l: Vector2, box_list: PackedVector4Array, body_list: PackedVector4Array, n: int, on_floor: bool = false, near_bits: int = -1) -> float:
	var shade: float = 0.0
	var own: int = -1 if on_floor else column_of(p, box_list, body_list, n)
	var at: Vector2 = p
	if own >= 0:
		at = Vector2(p.x, box_list[own].w + 0.5)
		if l.y < box_list[own].y:
			shade = body_list[own].w
	for k in mini(n, MAX):
		if k == own or (near_bits >> k) & 1 == 0:
			continue
		var box: Vector4 = box_list[k]
		var share: float = body_list[k].w
		if share <= shade or _box_holds(box, at) or _box_holds(box, l):
			continue
		if _crosses(at, l, box):
			shade = share
	return shade


## This frame's boxes' `shade_between` from a point on the floor at `p` (a body's feet: behind a
## pillar is behind it, though its shaft is drawn there) to a light whose middle is at `l`: the
## bodies' shadows ask it.
func shade(p: Vector2, l: Vector2) -> float:
	if count == 0:
		return 0.0
	return shade_from(p, lit_as(l, boxes, bodies, count))


## `shade` from a light already lit from `from` (its `lit_as`), testing only the boxes `near_bits`
## names (`near` of the light; both worked out once a frame).
func shade_from(p: Vector2, from: Vector2, near_bits: int = -1) -> float:
	return shade_between(p, from, boxes, bodies, count, true, near_bits)


## The boxes (with their columns) that come within `reach` of `at`, a bit each (the shader's `near`):
## 0 for a light no box comes near, which is never blocked.
func near(at: Vector2, reach: float) -> int:
	var bits: int = 0
	for k in count:
		var box: Vector4 = boxes[k]
		var body: Vector4 = bodies[k]
		if minf(box.x, body.x) <= at.x + reach and maxf(box.z, body.z) >= at.x - reach and minf(box.y, body.y) <= at.y + reach and box.w >= at.y - reach:
			bits |= 1 << k
	return bits


static func _box_holds(box: Vector4, p: Vector2) -> bool:
	return p.x >= box.x and p.x <= box.z and p.y >= box.y and p.y <= box.w


## Whether the way from `a` to `b` crosses `box` (the slab test, as the shader's `crosses`).
static func _crosses(a: Vector2, b: Vector2, box: Vector4) -> bool:
	var d: Vector2 = b - a
	var t0: float = 0.0
	var t1: float = 1.0
	for axis in 2:
		var from: float = a.x if axis == 0 else a.y
		var way: float = d.x if axis == 0 else d.y
		var low: float = box.x if axis == 0 else box.y
		var high: float = box.z if axis == 0 else box.w
		if absf(way) < 0.0001:
			if from < low or from > high:
				return false
		else:
			var ta: float = (low - from) / way
			var tb: float = (high - from) / way
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
	return true
