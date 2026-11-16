extends Node
## The cover area (autoload `Cover`; ground cover GC5, docs/milestones/ground-cover.md, rules 3 to 6):
## the game's part of the room's ground cover. One simulation area, never an actor a tuft (W8c): each
## cell of the room's cover (`CoverLayout`, 16 px) is in a state of its kind (`CoverKind.states`,
## the first at rest), and the area plays the states' data, never one kind by name.
##
## - **Touched** (rule 5): `floor_touched` (Spells: a blast, a pulse's ring, a pool, a shot's end) is
##   queued and, at the next step, fires the `element` triggers of the cells inside its circle (the
##   cell it lands in, and every cell whose middle is within its radius), touches in the order heard,
##   cells in cell order.
## - **Stepped:** the cells not at rest (`_active`, in cell order) count their seconds in their state;
##   the first `after` trigger whose seconds have passed moves a cell on; a state that spreads touches
##   each of its four neighbours that its element would move on with the chance `spread_chance` a
##   second (`sim.chance(&"cover_spread", cell * 4 + direction, counter)`, the area's one counter), the
##   spreads applied after every cell has stepped. So cell order alone fixes the rolls.
## - **Standing bodies** (rule 4): every open actor with a body (props included), in actor id order,
##   standing in a cell whose state gives a status is asked that status (`status_requested`, as any
##   status is: Combat applies it by its own rules, resist and all, and a prop's `status` trigger
##   lights a dust heap or a barrel) at once and again every `status_every` seconds while it stays in
##   such a cell. Its time to the next is kept by actor id and key, and dropped the tick it leaves
##   (or its id goes: ids are handed out again).
## - **Said** (rule 6): `cover_changed(cells, states)`, once a tick with that tick's changes; after a
##   `room_built`, every cell not at rest (Feel, an earlier autoload, has laid the room at rest by
##   then); after a restore (`rebuild_derived`), every cell whose state this machine's view was last
##   told otherwise.
##
## **State and derived:** each cell's state and seconds in it, the active cells, the queued touches,
## each harmed body's time to its next status and the roll counter are state. The layout and the kinds
## are derived, set by `room_built` (Flow, whenever it lays a room out), which never touches the state
## but to size it at rest when it is empty (a room with no cover keeps it empty). **The state is reset
## to rest only where a room starts in play:** `room_entered` (Flow's `_announce_room`: a run's start
## and each room the party goes on into; never a restore), so a snapshot's fire survives the
## `room_built` its restore sends. A room where nothing has happened hashes as arrays of zeros.
##
## It knows nothing of the HUD, the AI, Spells or Combat, and calls no other area: it hears events and
## reads the actor table and the registry.

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const ROOM_FOLDER: StringName = &"rooms"
const COVER_FOLDER: StringName = &"cover"
## The purpose of a spread's roll (`Sim.chance`).
const SPREAD: StringName = &"cover_spread"
## The four neighbours a spread touches, as steps in cells: up, right, down, left.
const NEIGHBOURS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Not state: services, the room's layout (from `room_built`), what this machine's view was told, and
## scratch emptied within a step (core/sim/README.md).
const DERIVED: Array[StringName] = [
	&"events", &"actors", &"registry", &"sim", &"layout", &"_given", &"_use_given", &"_said",
	&"_changed_cells", &"_changed_states", &"_ids", &"_spread_cells", &"_spread_elements",
	&"_next_ids", &"_next_keys", &"_next_left",
]

## The services. Only tests set these, before adding the node; otherwise the autoloads (and the
## Tick's `sim`).
var events: EventsScript = null
var actors: ActorsScript = null
var registry: RegistryScript = null
var sim: Sim = null

## The room's cover, worked out from its layout as built (`room_built`); null before a room.
var layout: CoverLayout = null
## Kinds given instead of the registry's (`use_kinds`: tests, before the game has cover of its own).
var _given: Array[CoverKind] = []
var _use_given: bool = false
## Each cell's state as this machine's view was last told (`cover_changed`); a new layout is told
## at rest. Not state: what was said here.
var _said: PackedByteArray = PackedByteArray()
## This tick's changes, sent once (`_flush`).
var _changed_cells: PackedInt32Array = PackedInt32Array()
var _changed_states: PackedInt32Array = PackedInt32Array()
## Scratch: the open actor ids, the spreads rolled this step, the harmed bodies being worked out.
var _ids: PackedInt32Array = PackedInt32Array()
var _spread_cells: PackedInt32Array = PackedInt32Array()
var _spread_elements: Array[StringName] = []
var _next_ids: PackedInt32Array = PackedInt32Array()
var _next_keys: PackedInt64Array = PackedInt64Array()
var _next_left: PackedFloat32Array = PackedFloat32Array()

## Each cell's state (its index in its kind's states; 0 at rest) and its seconds in it, the
## layout's size, or empty for a room with no cover.
var _state: PackedByteArray = PackedByteArray()
var _age: PackedFloat32Array = PackedFloat32Array()
## The cells not at rest, in cell order.
var _active: PackedInt32Array = PackedInt32Array()
## The touches heard since the last step: each element, where and how far.
var _touch_elements: Array[StringName] = []
var _touch_at: PackedVector2Array = PackedVector2Array()
var _touch_radius: PackedFloat32Array = PackedFloat32Array()
## The bodies standing in harmful cover, in actor id order: each id, its key (`Actors.key_of`) and
## the seconds to its next status.
var _harm_ids: PackedInt32Array = PackedInt32Array()
var _harm_keys: PackedInt64Array = PackedInt64Array()
var _harm_left: PackedFloat32Array = PackedFloat32Array()
## The rolls made (the counter of `sim.chance`).
var _rolls: int = 0


func _ready() -> void:
	# The tick steps it after the bodies moved (core/sim/tick.gd, core/sim/sim_area.gd).
	SimArea.join(self, &"Cover").steps(&"Cover", step).renewed_by(begin_run)
	if events == null:
		events = get_node_or_null(^"/root/Events") as EventsScript
	if actors == null:
		actors = get_node_or_null(^"/root/Actors") as ActorsScript
	if registry == null:
		registry = get_node_or_null(^"/root/Registry") as RegistryScript
	_ids.resize(ActorsScript.ACTORS)
	if events == null:
		push_warning("Cover: the Events autoload is missing, so the ground cover plays nothing.")
		return
	events.room_built.connect(_on_room_built)
	events.room_entered.connect(_on_room_entered)
	events.floor_touched.connect(_on_floor_touched)


## A run's start: the area is a fresh one's (the room laid next sizes it).
func begin_run() -> void:
	SimFresh.renew(self)


## Work the cover out with `kinds` instead of the registry's from the next room on (tests, before
## the game has cover of its own); null: the registry's again. Feel's look takes the same
## (`Feel.cover().use_kinds`).
func use_kinds(kinds: Variant) -> void:
	_use_given = kinds != null
	_given = [] as Array[CoverKind]
	if kinds != null:
		for kind: CoverKind in kinds as Array:
			_given.append(kind)


## The cover kinds a room's cover is worked out with: the registry's that can be laid
## (`CoverSketch.usable`, as Feel and the editor take them; Feel warns of the rest).
func kinds() -> Array[CoverKind]:
	if _use_given:
		return _given
	var found: Array[CoverKind] = []
	if registry != null:
		for item: Resource in registry.get_all(COVER_FOLDER):
			if item is CoverKind and CoverSketch.usable(item as CoverKind):
				found.append(item as CoverKind)
	return found


# --- Read ------------------------------------------------------------------------------

## The state of cell `cell` (its index in its kind's states; 0 at rest, and for a cell of none).
func state_at(cell: int) -> int:
	return _state[cell] if cell >= 0 and cell < _state.size() else 0


## The `CoverState` cell `cell` is in (null for a cell of no cover, or outside the room).
func cover_state_at(cell: int) -> CoverState:
	if layout == null:
		return null
	var kind: CoverKind = layout.kind_at(cell)
	return kind.states[state_at(cell)] if kind != null else null


## The seconds cell `cell` has been in its state (0 at rest).
func age_at(cell: int) -> float:
	return _age[cell] if cell >= 0 and cell < _age.size() else 0.0


## The cells not at rest, in cell order. Read only.
func active_cells() -> PackedInt32Array:
	return _active


## The rolls made so far (`sim.chance`'s counter).
func rolls() -> int:
	return _rolls


## The bodies standing in harmful cover, in actor id order. Read only.
func harmed() -> PackedInt32Array:
	return _harm_ids


# --- Heard -----------------------------------------------------------------------------

## A room was laid out: its cover worked out from its layout. The state is only sized, at rest, when
## it is empty; then the view is told every cell not at rest.
func _on_room_built(room_id: StringName, layout_root: Node) -> void:
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, room_id) as RoomBase if registry != null else null
	layout = CoverLayout.of(layout_root, room, kinds())
	if _state.is_empty():
		_size_at_rest()
	_said.resize(layout.cells.size())
	_said.fill(0)
	_tell_all()
	_flush()


## A room starts in play (a run's start, each room the party goes on into; never a restore): every
## cell at rest, nothing queued and nobody harmed.
func _on_room_entered(_room_id: StringName) -> void:
	_size_at_rest()
	_active.resize(0)
	_clear_touches()
	_harm_ids.resize(0)
	_harm_keys.resize(0)
	_harm_left.resize(0)
	_tell_all()
	_flush()


## An element touched the floor: queued for the next step (nothing in a room with no cover).
func _on_floor_touched(_caster: int, element: StringName, at: Vector2, radius: float) -> void:
	if _state.is_empty() or element == &"" or not at.is_finite():
		return
	_touch_elements.append(element)
	_touch_at.append(at)
	_touch_radius.append(radius)


## After a snapshot was restored: the view is told every cell whose state it was told otherwise.
func rebuild_derived() -> void:
	_tell_all()
	_flush()


# --- The step --------------------------------------------------------------------------

## The tick's step: the touches heard fire their cells' triggers, the cells not at rest step and
## spread, and the bodies standing in harmful cover are given its status.
func step(delta: float) -> void:
	if layout == null or _state.is_empty() or _state.size() != layout.cells.size():
		_clear_touches()
		return
	_apply_touches()
	_step_cells(delta)
	_affect_bodies(delta)
	_flush()


## Every queued touch, in the order heard: the cells inside its circle in cell order.
func _apply_touches() -> void:
	var cell_size: float = float(CoverLayout.CELL)
	for t in _touch_elements.size():
		var at: Vector2 = _touch_at[t]
		var radius: float = _touch_radius[t]
		var element: StringName = _touch_elements[t]
		var centre: int = layout.cell_of(at)
		var x0: int = maxi(floori((at.x - radius) / cell_size), 0)
		var x1: int = mini(floori((at.x + radius) / cell_size), layout.columns - 1)
		var y0: int = maxi(floori((at.y - radius) / cell_size), 0)
		var y1: int = mini(floori((at.y + radius) / cell_size), layout.rows - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var cell: int = y * layout.columns + x
				var middle := Vector2((float(x) + 0.5) * cell_size, (float(y) + 0.5) * cell_size)
				if cell == centre or middle.distance_squared_to(at) <= radius * radius:
					_touch_cell(cell, element)
	_clear_touches()


## The cells not at rest count on: an `after` trigger moves one on; one that spreads rolls for each
## neighbour its element would move on. The spreads apply once every cell has stepped.
func _step_cells(delta: float) -> void:
	var game: Sim = sim if sim != null else Sim.found(self)
	var i: int = 0
	while i < _active.size():
		var cell: int = _active[i]
		var kind: CoverKind = layout.kind_at(cell)
		var now: int = _state[cell]
		var state: CoverState = kind.states[now]
		_age[cell] += delta
		var moved: bool = false
		for row in state.triggers:
			if row != null and row.when == CoverTrigger.When.AFTER and _age[cell] >= row.seconds:
				var to: int = kind.state_at(row.then)
				if to >= 0 and to != now:
					_enter(cell, to)
					moved = true
					break
		if not moved and state.spreads != &"" and state.spread_chance > 0.0:
			_roll_spreads(game, cell, state, delta)
		# A cell gone to rest left the list; the next is in its place.
		if i < _active.size() and _active[i] == cell:
			i += 1
	for s in _spread_cells.size():
		_touch_cell(_spread_cells[s], _spread_elements[s])
	_spread_cells.resize(0)
	_spread_elements.clear()


## Cell `cell` in `state` rolls for each of its four neighbours (in NEIGHBOURS' order) that its
## element would move on: one roll each, the chance `spread_chance` a second.
func _roll_spreads(game: Sim, cell: int, state: CoverState, delta: float) -> void:
	var x: int = cell % layout.columns
	var y: int = cell / layout.columns
	for direction in NEIGHBOURS.size():
		var nx: int = x + NEIGHBOURS[direction].x
		var ny: int = y + NEIGHBOURS[direction].y
		if nx < 0 or ny < 0 or nx >= layout.columns or ny >= layout.rows:
			continue
		var other: int = ny * layout.columns + nx
		var kind: CoverKind = layout.kind_at(other)
		if kind == null or kind.states[_state[other]].on_element(state.spreads) == &"":
			continue
		var roll: float = game.chance(SPREAD, cell * NEIGHBOURS.size() + direction, _rolls)
		_rolls += 1
		if roll < state.spread_chance * delta:
			_spread_cells.append(other)
			_spread_elements.append(state.spreads)


## `element` touched cell `cell`: its state's trigger on it (if any) moves it on.
func _touch_cell(cell: int, element: StringName) -> void:
	var kind: CoverKind = layout.kind_at(cell)
	if kind == null:
		return
	var then: StringName = kind.states[_state[cell]].on_element(element)
	if then == &"":
		return
	var to: int = kind.state_at(then)
	if to >= 0 and to != _state[cell]:
		_enter(cell, to)


## Cell `cell` enters state `to`: its seconds from 0, in or out of the active cells, told.
func _enter(cell: int, to: int) -> void:
	var was: int = _state[cell]
	_state[cell] = to
	_age[cell] = 0.0
	if was == 0 and to != 0:
		_active.insert(_active.bsearch(cell), cell)
	elif was != 0 and to == 0:
		_active.remove_at(_active.bsearch(cell))
	_tell(cell, to)


## Every open actor's body, in id order, standing in a cell whose state gives a status: asked it at
## once and again every `status_every` seconds while it stays in such cover.
func _affect_bodies(delta: float) -> void:
	_next_ids.resize(0)
	_next_keys.resize(0)
	_next_left.resize(0)
	var count: int = actors.open_ids(_ids) if actors != null else 0
	var old: int = 0
	for n in count:
		var id: int = _ids[n]
		var body := actors.node_of(id) as Node2D
		if body == null or not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var state: CoverState = cover_state_at(layout.cell_of(body.global_position))
		if state == null or state.status == &"":
			continue
		var key: int = actors.key_of(id)
		while old < _harm_ids.size() and _harm_ids[old] < id:
			old += 1
		var left: float = 0.0
		if old < _harm_ids.size() and _harm_ids[old] == id and _harm_keys[old] == key:
			left = _harm_left[old] - delta
		if left <= 0.0:
			left = maxf(state.status_every, delta)
			if events != null:
				events.status_requested.emit(EventsScript.NO_PLAYER, body, state.status, state.status_duration, state.status_strength)
		_next_ids.append(id)
		_next_keys.append(key)
		_next_left.append(left)
	if _harm_ids.is_empty() and _next_ids.is_empty():
		return
	var ids: PackedInt32Array = _harm_ids
	_harm_ids = _next_ids
	_next_ids = ids
	var keys: PackedInt64Array = _harm_keys
	_harm_keys = _next_keys
	_next_keys = keys
	var lefts: PackedFloat32Array = _harm_left
	_harm_left = _next_left
	_next_left = lefts


# --- Upkeep ----------------------------------------------------------------------------

## Every cell at rest, the layout's size (none for a room with no cover).
func _size_at_rest() -> void:
	var cells: int = layout.cells.size() if layout != null and layout.count() > 0 else 0
	_state.resize(cells)
	_state.fill(0)
	_age.resize(cells)
	_age.fill(0.0)


func _clear_touches() -> void:
	if _touch_elements.is_empty():
		return
	_touch_elements.clear()
	_touch_at.resize(0)
	_touch_radius.resize(0)


## Cell `cell` shows `state` from now on: told at the next `_flush` unless the view already shows it.
func _tell(cell: int, state: int) -> void:
	if cell < 0 or cell >= _said.size() or _said[cell] == state:
		return
	_said[cell] = state
	_changed_cells.append(cell)
	_changed_states.append(state)


## Every cell whose state the view was told otherwise (all at rest for a room with no cover).
func _tell_all() -> void:
	if layout == null or _said.size() != layout.cells.size():
		return
	if _state.size() == _said.size():
		for cell in _state.size():
			_tell(cell, _state[cell])
	elif _state.is_empty():
		for cell in _said.size():
			_tell(cell, 0)


## The changes told since the last, sent as one `cover_changed`.
func _flush() -> void:
	if _changed_cells.is_empty():
		return
	if events != null:
		events.cover_changed.emit(_changed_cells, _changed_states)
	_changed_cells.resize(0)
	_changed_states.resize(0)
