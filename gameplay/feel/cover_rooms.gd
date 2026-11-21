extends Node2D
## Ground cover's look in every room of the world (connected biomes CB3b, docs/milestones/connected-biomes.md):
## one view a piece (`cover.gd`, by the piece's number as `room_built` gives it: a row run's one room,
## a biome's rooms then bridges), each drawing its room's tufts at the room's place, mirrored with it.
## Feel's own script (`Feel.cover_rooms()`; `Feel.cover()` is the first room's view), never more of
## feel.gd.
##
## **Heard here, handed to the views:** `room_built` lays its piece's view (`CoverLayout.of_piece`,
## worked out with the first view's kinds, so a test's `Feel.cover().use_kinds` holds for every room);
## a new world's first piece (FIRST_ROOM) lays every other view empty first, so a room of the last
## world never shows in this one. `cover_changed` shows its room's cells. Feel hears both before the
## cover area does (an earlier autoload), so a room is laid at rest before it is told what burns.
##
## **A frame** (`step`): the first view finds the bodies (the nearest the camera's middle, as ever);
## every other view with cover takes the same ones (`step_with`), so they are gathered once. Every
## view steps, wherever its room lies: the wind and a trample are look only, and cheap at rest. A
## view switched off that no body found reaches (`found_box`) walks none of them and takes them only
## when shown again, and a room far out of the picture rolls no motes (`CoverMotes.give_off`).
##
## Pure view: nothing here is the game's, and nothing here is read by the simulation.

const CoverScript := preload("res://gameplay/feel/cover.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")

## The bus and the registry (Feel's).
var events: EventsScript = null
var registry: RegistryScript = null

## Each piece's view, by its number; the first (FIRST_ROOM's) is always there.
var _views: Array[CoverScript] = []
## The z every view draws at (Feel's MARK_Z).
var _z: int = 0
## The spectacle's ramps, which every view's motes cool through (GC8; null until Feel sets them).
var _ramps: RampTableScript = null


## Views drawn at `z` (Feel's MARK_Z).
func _init(z: int) -> void:
	_z = z
	_views.append(_view(EventsScript.FIRST_ROOM))


func _ready() -> void:
	for view in _views:
		view.registry = registry
	if events != null and not events.room_built.is_connected(_on_room_built):
		events.room_built.connect(_on_room_built)
	if events != null and not events.cover_changed.is_connected(_on_cover_changed):
		events.cover_changed.connect(_on_cover_changed)


## The first room's view (a row run's room, a biome's start room).
func first() -> CoverScript:
	return _views[EventsScript.FIRST_ROOM]


## The view of piece `number` (null for none made).
func view_of(number: int) -> CoverScript:
	return _views[number] if number >= 0 and number < _views.size() else null


## How many views there are (laid or empty).
func count() -> int:
	return _views.size()


## The spectacle's ramps, for every view's motes (`CoverMotes.ramp_table`).
func set_ramp_table(ramps: RampTableScript) -> void:
	_ramps = ramps
	for view in _views:
		view.motes.ramp_table = ramps


## A piece was laid out (`room_built`): its view laid from its layout at its place.
func _on_room_built(room_id: StringName, number: int, layout_root: Node) -> void:
	if number < 0:
		return
	if number == EventsScript.FIRST_ROOM:
		# A new world: no room of the last one shows in it.
		for other in range(1, _views.size()):
			if _views[other].layout != null and not _views[other].layout.cells.is_empty():
				_views[other].lay(CoverLayout.new())
	while _views.size() <= number:
		_views.append(_view(_views.size()))
	_views[number].lay(first().laid_from(room_id, layout_root))


## The cover area's changes (`cover_changed`): its room's cells show their new states.
func _on_cover_changed(room: int, cells: PackedInt32Array, states: PackedInt32Array) -> void:
	var view: CoverScript = view_of(room)
	if view != null:
		view.show_states(cells, states)


## Once a frame (`cover.gd`'s `step`, its arguments the same): the first view finds the bodies, and
## every other view with cover draws with them.
func step(now: float, table: ActorsScript = null, focus: Vector2 = Vector2.INF, pool: MotesScript = null, view: Rect2 = Rect2(), stirs_version: int = -1, hand_stirs: Callable = Callable()) -> void:
	var lead: CoverScript = first()
	lead.step(now, table, focus, pool, view, stirs_version, hand_stirs)
	for number in range(1, _views.size()):
		var other: CoverScript = _views[number]
		if other.layout != null and not other.batches().is_empty():
			other.step_with(lead.bodies(), lead.body_count(), now, pool, view, stirs_version, hand_stirs, lead.found_box())


## A view for piece `number`, a child of this node.
func _view(number: int) -> CoverScript:
	var made := CoverScript.new(_z)
	made.name = "Cover" if number == EventsScript.FIRST_ROOM else "Cover%d" % number
	made.registry = registry
	if _ramps != null:
		made.motes.ramp_table = _ramps
	add_child(made)
	return made
