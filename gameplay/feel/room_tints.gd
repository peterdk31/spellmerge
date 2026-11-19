extends RefCounted
## Each room's own light tinted by its kind (connected biomes CB12b, docs/milestones/connected-biomes.md;
## the owner's "also tint the room"): a room whose kind names a `light_tint` has its dark and every
## light falling in it lean toward its kind's light (`RoomKind.light`, the base shade of that palette
## material; the spark's when it names none) by that share. Drawn by the spell light's apply pass
## (`SpellLight.set_room_tints`, `light_apply.gdshader`), which finds the room a world pixel is in by
## its place's rectangle, so it is the room's wherever a view stands: two rooms side by side in one
## view are each their own, and two views of a split screen each tint the rooms they show. **Its edge**
## (the owner, 2026-11-19): past a room's rectangle its tint steps down onto its bridges in EDGE_BANDS
## whole-pixel bands EDGE_BAND px wide (two thirds of its tint, a third, then none), never one hard
## edge; the rest of a bridge is untinted. The bands ring the whole rectangle (a room's rectangle
## holds its void frame, so past it is a bridge or the void, where a band shows on nothing lit), and
## rooms stand at least a bridge apart, so a band never reaches another room. Only while dynamic lighting is on (with it off there is no apply pass to tint).
##
## **Smooth:** a room's tint comes in once the party's map says it was entered (`rooms_seen`, as the
## dark over it lifts, `unseen_dark.gd`), a stage a frame at FPS through STAGES (a third, two thirds,
## all of its share), each pixel by whole steps of the apply pass, never a fade. A view moving between
## rooms of different tints changes no pixel's look in one jump: the tint stands in the world, and the
## edge between two tints is the void and the bridge between their rooms. A biome laid (a new one, a
## restore's, told `again`) is drawn as it stands.
##
## View only: nothing in the game reads it. It knows the rooms by the grid's places and Feel's room
## hearing (`kind_of`, `is_walkway`), and the light by `set_room_tints` alone. Feel steps it once a
## frame (`step`).

const EventsScript := preload("res://core/events/events.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")

## Frames a second a tint comes in at, and its stages (from none to all of its share).
const FPS: float = 12.0
const STAGES: int = 3
## The edge's bands past a room's rectangle (world px each, and how many): light_apply.gdshader's
## EDGE_BAND and EDGE_BANDS.
const EDGE_BAND: float = 6.0
const EDGE_BANDS: int = 2
## A room's level in `rooms_seen` once it was entered (0 unseen, 1 only shown on the map).
const ENTERED: int = 2
## The light a kind's tint leans toward when it names none (the mouths' own).
const DEFAULT_LIGHT: StringName = &"spark"

## The pieces (Feel's room hearing: each place's kind, which places are walkways).
var pieces: RoomHearingScript = null

## By tinted room (up to SpellLight.MAX_TINTS): its place, its rectangle (x0, y0, x1, y1), its hue
## (the light's base shade, its brightest channel 1), its share and the stage drawn (0 ... STAGES).
var _places: PackedInt32Array = PackedInt32Array()
var _rects: PackedVector4Array = PackedVector4Array()
var _hues: PackedColorArray = PackedColorArray()
var _shares: PackedFloat32Array = PackedFloat32Array()
var _stage: PackedInt32Array = PackedInt32Array()
## The rows handed to the light (MAX_TINTS each, made once): rectangles, and hue with its tint now.
var _rect_rows: PackedVector4Array = PackedVector4Array()
var _tint_rows: PackedVector4Array = PackedVector4Array()
## The party's map as told last, and whether it was told again after a restore.
var _seen: PackedByteArray = PackedByteArray()
var _as_stands: bool = false
var _laid_places: int = -1
var _laid_world: int = -1
## The pieces' versions read last (`RoomHearing.versions`, `relaid`): a room laid again alone (a
## room reroll's) is read again alone, every other tint playing on as it was.
var _laid_versions: PackedInt32Array = PackedInt32Array()
var _laid_relaid: int = -1
var _clock: float = 0.0
## The light written to last (its instance id; 0: none) and whether the rows changed since.
var _light_id: int = 0
var _dirty: bool = true


func _init() -> void:
	_rect_rows.resize(SpellLightScript.MAX_TINTS)
	_tint_rows.resize(SpellLightScript.MAX_TINTS)


func bind(events: EventsScript) -> void:
	if events != null:
		events.rooms_seen.connect(_on_rooms_seen)


func _on_rooms_seen(seen: PackedByteArray, again: bool) -> void:
	_seen = seen
	_as_stands = _as_stands or again


## Once a frame, `delta` real seconds on, from `grid` (null: no places), onto `light` (null: dynamic
## lighting off): the rooms read again for a new biome, each tint stepped toward what the party's map
## wants at FPS (drawn as it stands after a restore), and the rows handed over when they changed or
## the light is a new one.
func step(delta: float, grid: RoomGrid, light: SpellLightScript) -> void:
	var places: int = grid.places() if grid != null else 0
	var world: int = pieces.world() if pieces != null else 0
	if places != _laid_places or world != _laid_world:
		_lay(grid, places, world)
	elif pieces != null and pieces.relaid() != _laid_relaid:
		var stages: Dictionary = {}
		for i in _places.size():
			stages[_places[i]] = _stage[i]
		var changed: PackedInt32Array = pieces.changed_since(_laid_versions, places)
		_lay(grid, places, world)
		for i in _places.size():
			if stages.has(_places[i]) and not changed.has(_places[i]):
				_stage[i] = stages[_places[i]]
	if _as_stands:
		_as_stands = false
		for i in _places.size():
			_stage[i] = _wanted(i)
		_dirty = true
	if is_moving():
		_clock += delta
		var change: float = 1.0 / FPS
		while _clock >= change and is_moving():
			_clock -= change
			advance()
	else:
		_clock = 0.0
	var id: int = light.get_instance_id() if light != null else 0
	if light != null and (_dirty or id != _light_id):
		_write(light)
	_light_id = id


## True while a room's tint still changes.
func is_moving() -> bool:
	for i in _places.size():
		if _stage[i] != _wanted(i):
			return true
	return false


## One stage of every change (a frame at FPS).
func advance() -> void:
	for i in _places.size():
		_stage[i] += signi(_wanted(i) - _stage[i])
	_dirty = true


## The tinted rooms, and the stage of place `place`'s tint (0 none ... STAGES; -1: not a tinted room).
func rooms() -> int:
	return _places.size()


func stage_of(place: int) -> int:
	var i: int = _places.find(place)
	return _stage[i] if i >= 0 else -1


## The tint at world point `at` as the apply pass reads it: the hue of the room it is in, and how
## far its light leans toward it now (alpha; past a room's edge its bands, then 0 on a bridge, in the
## void or an untinted room). A room at no tint yet is passed over, as the shader is never handed it.
func tint_at(at: Vector2) -> Color:
	var p := Vector2(floorf(at.x) + 0.5, floorf(at.y) + 0.5)
	var edge := Color(1.0, 1.0, 1.0, 0.0)
	for i in _places.size():
		var r: Vector4 = _rects[i]
		if _tint_now(i) <= 0.0:
			continue
		if at.x >= r.x and at.y >= r.y and at.x < r.z and at.y < r.w:
			return Color(_hues[i].r, _hues[i].g, _hues[i].b, _tint_now(i))
		var out_x: float = maxf(maxf(r.x - p.x, p.x - r.z), 0.0)
		var out_y: float = maxf(maxf(r.y - p.y, p.y - r.w), 0.0)
		var band: int = floori(maxf(out_x, out_y) / EDGE_BAND)
		if band < EDGE_BANDS:
			var a: float = _tint_now(i) * float(EDGE_BANDS - band) / float(EDGE_BANDS + 1)
			if a > edge.a:
				edge = Color(_hues[i].r, _hues[i].g, _hues[i].b, a)
	return edge


## The hue a kind's tint leans toward: its light's base shade, scaled so its brightest channel is 1
## (a tint changes a colour's hue, never makes the room brighter).
static func hue_of(kind: RoomKind) -> Color:
	var material: StringName = kind.light if kind != null and kind.light != &"" else DEFAULT_LIGHT
	var shades: PackedColorArray = Palette.shades_of(material)
	var base: Color = shades[1] if shades.size() == 3 else Palette.shades_of(DEFAULT_LIGHT)[1]
	var most: float = maxf(base.r, maxf(base.g, base.b))
	return Color(base.r / most, base.g / most, base.b / most) if most > 0.0 else Color.WHITE


func _tint_now(i: int) -> float:
	return _shares[i] * float(_stage[i]) / float(STAGES)


func _wanted(i: int) -> int:
	var place: int = _places[i]
	return STAGES if place < _seen.size() and _seen[place] >= ENTERED else 0


## A new biome's rooms: each room whose kind names a tint, its tint as it stands (a new world is
## never played in).
func _lay(grid: RoomGrid, places: int, world: int) -> void:
	_laid_places = places
	_laid_world = world
	_laid_relaid = pieces.relaid() if pieces != null else 0
	_laid_versions = pieces.versions() if pieces != null else PackedInt32Array()
	_places.resize(0)
	_rects.resize(0)
	_hues.resize(0)
	_shares.resize(0)
	_stage.resize(0)
	_dirty = true
	if pieces == null:
		return
	for place in places:
		if pieces.is_walkway(place):
			continue
		var kind: RoomKind = pieces.kind_of(place)
		if kind == null or kind.light_tint <= 0.0:
			continue
		if _places.size() >= SpellLightScript.MAX_TINTS:
			push_warning("Room tints: more than %d tinted rooms; the rest are drawn untinted." % SpellLightScript.MAX_TINTS)
			break
		var rect: Rect2 = grid.place_rect(place)
		_places.append(place)
		_rects.append(Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y))
		_hues.append(hue_of(kind))
		_shares.append(minf(kind.light_tint, RoomKind.LIGHT_TINT_MOST))
		_stage.append(0)
	for i in _places.size():
		_stage[i] = _wanted(i)


## The rows onto `light`: only the rooms with some tint now (the apply pass reads `count` of them).
func _write(light: SpellLightScript) -> void:
	_dirty = false
	var count: int = 0
	for i in _places.size():
		var tint: float = _tint_now(i)
		if tint <= 0.0:
			continue
		_rect_rows[count] = _rects[i]
		_tint_rows[count] = Vector4(_hues[i].r, _hues[i].g, _hues[i].b, tint)
		count += 1
	light.set_room_tints(_rect_rows, _tint_rows, count)
