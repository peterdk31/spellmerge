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
##   such a cell. Its time to the next is kept by actor id and key, and runs on after it leaves:
##   it is dropped once that time is out (GC8: stepping in and out is asked no oftener than
##   standing in it) or its id goes (ids are handed out again).
## - **Said** (rule 6): `cover_changed(cells, states)`, once a tick with that tick's changes; after a
##   `room_built`, every cell not at rest (Feel, an earlier autoload, has laid the room at rest by
##   then); after a restore (`rebuild_derived`), every cell whose state this machine's view was last
##   told otherwise.
## - **Looked at** (rule 8, GC7): `cover_danger_looked` asks where the floor round a place would harm
##   a body; `look` fills the asker's `CoverSight` at once, marking each cell of its window whose
##   state gives a status (the cells `_affect_bodies` would ask one for). The AI steers by it.
##
## **State and derived:** each cell's state and seconds in it, the active cells, the queued touches,
## each harmed body's time to its next status and the roll counter are state. The layout and the kinds
## are derived, set by `room_built` (Flow, whenever it lays a room out), which never touches the state
## but to size it at rest when it is empty (a room with no cover keeps it empty). **The state is reset
## to rest only where a room starts in play:** `room_entered` (Flow's `_announce_room`: a run's start
## and each room the party goes on into; never a restore), so a snapshot's fire survives the
## `room_built` its restore sends. A room where nothing has happened hashes as arrays of zeros.
##
## **A cover a room** (connected biomes CB3b): every piece of the world has its own (`CoverRoom`, by
## the piece's number: a row run's one room, a biome's rooms then bridges), laid at its place and
## mirrored with it (`CoverLayout.of_piece`), with its own state and rolls. A room's cells step only
## while its place is awake (the projectile manager's grid, `RoomGrid.is_awake`, told by Flow's room
## life), so a sleeping room's fire waits as if no time had passed; a touch lands in whichever rooms
## its circle reaches, awake or not (it lights, it does not count time), and a sleeping body
## (`Actors.asleep`) is neither harmed nor counts its time to its next status. Every room's cover is
## laid as the world is (`room_built`, each piece once), never more than once a piece.
##
## It knows nothing of the HUD, the AI, Spells or Combat, and calls no other area: it hears events and
## reads the actor table, the registry and the projectile manager's grid (core/projectiles).

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const ROOM_FOLDER: StringName = &"rooms"
const COVER_FOLDER: StringName = &"cover"
## The purpose of a spread's roll (`Sim.chance`).
const SPREAD: StringName = CoverRoom.SPREAD

## Not state: services, the world's pieces' layouts (from `room_built`), and scratch emptied within a
## step (core/sim/README.md).
const DERIVED: Array[StringName] = [
	&"events", &"actors", &"registry", &"projectiles", &"sim", &"layout", &"_layouts", &"_given", &"_use_given",
	&"_ids", &"_next_ids", &"_next_keys", &"_next_left",
]

## The services. Only tests set these, before adding the node; otherwise the autoloads (and the
## Tick's `sim`). Without a projectile manager every room is awake and found by its grid alone.
var events: EventsScript = null
var actors: ActorsScript = null
var registry: RegistryScript = null
var projectiles: ProjectileManagerScript = null
var sim: Sim = null

## The first room's cover (`FIRST_ROOM`: a row run's room, a biome's start room), as built; null
## before a room. Read only (`layout_of` for another room).
var layout: CoverLayout:
	get:
		return layout_of(EventsScript.FIRST_ROOM)
## Each piece's cover as laid (`room_built`), by its number: the world's laid last (a new world's
## first piece, FIRST_ROOM, begins the list again).
var _layouts: Array[CoverLayout] = []
## Kinds given instead of the registry's (`use_kinds`: tests, before the game has cover of its own).
var _given: Array[CoverKind] = []
var _use_given: bool = false
## Scratch: the open actor ids, the harmed bodies being worked out (sized for every actor once, so a
## step with bodies in harmful cover makes no array).
var _ids: PackedInt32Array = PackedInt32Array()
var _next_ids: PackedInt32Array = PackedInt32Array()
var _next_keys: PackedInt64Array = PackedInt64Array()
var _next_left: PackedFloat32Array = PackedFloat32Array()

## Each piece's cover in play, by its number (README, "State").
var _rooms: Array[CoverRoom] = []
## The touches heard since the last step: each element, where and how far.
var _touch_elements: Array[StringName] = []
var _touch_at: PackedVector2Array = PackedVector2Array()
var _touch_radius: PackedFloat32Array = PackedFloat32Array()
## The bodies standing in harmful cover, in actor id order: each id, its key (`Actors.key_of`) and
## the seconds to its next status.
var _harm_ids: PackedInt32Array = PackedInt32Array()
var _harm_keys: PackedInt64Array = PackedInt64Array()
var _harm_left: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	# The tick steps it after the bodies moved (core/sim/tick.gd, core/sim/sim_area.gd).
	SimArea.join(self, &"Cover").steps(&"Cover", step).renewed_by(begin_run)
	if events == null:
		events = get_node_or_null(^"/root/Events") as EventsScript
	if actors == null:
		actors = get_node_or_null(^"/root/Actors") as ActorsScript
	if registry == null:
		registry = get_node_or_null(^"/root/Registry") as RegistryScript
	if projectiles == null:
		projectiles = get_node_or_null(^"/root/Projectiles") as ProjectileManagerScript
	_ids.resize(ActorsScript.ACTORS)
	_next_ids.resize(ActorsScript.ACTORS)
	_next_keys.resize(ActorsScript.ACTORS)
	_next_left.resize(ActorsScript.ACTORS)
	if events == null:
		push_warning("Cover: the Events autoload is missing, so the ground cover plays nothing.")
		return
	events.room_built.connect(_on_room_built)
	events.room_entered.connect(_on_room_entered)
	events.floor_touched.connect(_on_floor_touched)
	events.cover_danger_looked.connect(_on_cover_danger_looked)


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

## The cover of piece `number` as laid (null for none laid).
func layout_of(number: int) -> CoverLayout:
	return _layouts[number] if number >= 0 and number < _layouts.size() else null


## The cover in play of piece `number` (null for none). Read only: tests.
func room(number: int = EventsScript.FIRST_ROOM) -> CoverRoom:
	return _rooms[number] if number >= 0 and number < _rooms.size() else null


## How many pieces have a cover in play (laid or not).
func rooms() -> int:
	return _rooms.size()


## The state of cell `cell` of room `number` (its index in its kind's states; 0 at rest, and for a
## cell of none).
func state_at(cell: int, number: int = EventsScript.FIRST_ROOM) -> int:
	return _rooms[number].state_at(cell) if number >= 0 and number < _rooms.size() else 0


## The `CoverState` cell `cell` of room `number` is in (null for a cell of no cover, or outside it).
func cover_state_at(cell: int, number: int = EventsScript.FIRST_ROOM) -> CoverState:
	return _rooms[number].cover_state_at(cell) if number >= 0 and number < _rooms.size() else null


## The seconds cell `cell` of room `number` has been in its state (0 at rest).
func age_at(cell: int, number: int = EventsScript.FIRST_ROOM) -> float:
	return _rooms[number].age_at(cell) if number >= 0 and number < _rooms.size() else 0.0


## The cells of room `number` not at rest, in cell order. Read only.
func active_cells(number: int = EventsScript.FIRST_ROOM) -> PackedInt32Array:
	return _rooms[number].active_cells() if number >= 0 and number < _rooms.size() else PackedInt32Array()


## How many cells of room `number` the state holds (its layout's, or 0 for a room with no cover).
func cell_count(number: int = EventsScript.FIRST_ROOM) -> int:
	return _rooms[number]._state.size() if number >= 0 and number < _rooms.size() else 0


## The rolls made so far, every room's (`sim.chance`'s counters).
func rolls() -> int:
	var made: int = 0
	for room in _rooms:
		made += room.rolls()
	return made


## The bodies standing in harmful cover, in actor id order. Read only.
func harmed() -> PackedInt32Array:
	return _harm_ids


## The room whose cover lies under `at` (world pixels), or -1: the grid's place there (a biome's), else
## the first room whose grid holds it (a world with no places: a row run's room).
func room_at(at: Vector2) -> int:
	var grid: RoomGrid = projectiles.grid() if projectiles != null else null
	if grid != null and grid.places() > 0:
		var place: int = grid.place_at(at)
		return place if place >= 0 and place < _rooms.size() and _rooms[place].holds(at) else -1
	for number in _rooms.size():
		if _rooms[number].holds(at):
			return number
	return -1


## Fill `sight` with where the floor within `reach` of `at` would harm a body standing on it (rule 8):
## its window's cells whose state gives a status, in the room `at` is in. Empty where there is no
## cover, and at once when no cell of that room is in such a state (`CoverRoom._harming`: grass at
## rest and ash harm nobody), so a look costs a fight with nothing burning almost nothing. Allocates
## nothing.
func look(at: Vector2, reach: float, sight: CoverSight) -> void:
	sight.clear()
	if not at.is_finite():
		return
	var number: int = room_at(at)
	if number >= 0:
		_rooms[number].look(at, reach, sight)


# --- Heard -----------------------------------------------------------------------------

## A piece was laid out: its cover worked out from its layout at its place, mirrored with it. Its
## state is only sized, at rest, when it is empty (a restore's state is kept); then the view is told
## every cell not at rest. A new world's first piece (FIRST_ROOM) begins the layouts again.
func _on_room_built(room_id: StringName, number: int, layout_root: Node) -> void:
	if number < 0:
		return
	if number == EventsScript.FIRST_ROOM:
		# A new world's pieces: the last world's rooms play nothing until theirs come.
		_layouts.clear()
		for other in range(1, _rooms.size()):
			_rooms[other].unbind()
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, room_id) as RoomBase if registry != null else null
	var laid: CoverLayout = CoverLayout.of_piece(layout_root, room, kinds())
	while _layouts.size() <= number:
		_layouts.append(null)
	_layouts[number] = laid
	while _rooms.size() <= number:
		_rooms.append(CoverRoom.new())
	_rooms[number].bind(laid)
	_rooms[number].flush(events, number)


## A new world starts in play (`room_entered` of FIRST_ROOM: a run's start, each row room the party
## goes on into, a biome's start; never a restore): every piece's cover at rest, nothing queued and
## nobody harmed. A biome's later rooms' first entries change nothing: what burnt there before
## anyone came in stays burnt.
func _on_room_entered(_room_id: StringName, number: int) -> void:
	if number != EventsScript.FIRST_ROOM:
		return
	_rooms.resize(_layouts.size())
	for at in _rooms.size():
		if _rooms[at] == null or _layouts[at] == null:
			_rooms[at] = CoverRoom.new()
		if _layouts[at] != null:
			if _rooms[at].layout != _layouts[at]:
				_rooms[at].bind(_layouts[at])
			_rooms[at].rest()
	_clear_touches()
	_harm_ids.resize(0)
	_harm_keys.resize(0)
	_harm_left.resize(0)
	_flush()


## An element touched the floor: queued for the next step (nothing in a world with no cover).
func _on_floor_touched(_caster: int, element: StringName, at: Vector2, radius: float) -> void:
	if _rooms.is_empty() or element == &"" or not at.is_finite():
		return
	_touch_elements.append(element)
	_touch_at.append(at)
	_touch_radius.append(radius)


## An actor looked at the floor round it (`cover_danger_looked`, rule 8): its sight is filled at once.
func _on_cover_danger_looked(_actor: int, at: Vector2, reach: float, sight: CoverSight) -> void:
	if sight != null:
		look(at, reach, sight)


## After a snapshot was restored: each room bound to its piece's layout again (the restored rooms
## hold none), and the view told every cell whose state it was told otherwise.
func rebuild_derived() -> void:
	for number in _rooms.size():
		var room: CoverRoom = _rooms[number]
		var laid: CoverLayout = layout_of(number)
		if laid == null:
			# A piece this world does not lay (a restore into another world): it plays nothing.
			room.unbind()
			continue
		if room.layout != laid:
			room.bind(laid)
		else:
			room.retell()
	_flush()


# --- The step --------------------------------------------------------------------------

## The tick's step: the touches heard fire their cells' triggers in every room they reach, the cells
## of each awake room not at rest step and spread, and the bodies standing in harmful cover are given
## its status.
func step(delta: float) -> void:
	_apply_touches()
	var game: Sim = sim if sim != null else Sim.found(self)
	var grid: RoomGrid = projectiles.grid() if projectiles != null else null
	var may_harm: bool = not _harm_ids.is_empty()
	for number in _rooms.size():
		var room: CoverRoom = _rooms[number]
		if not room.plays():
			continue
		if grid == null or grid.is_awake(number):
			room.step_cells(delta, game, number)
		may_harm = may_harm or room.may_harm()
	# With every cell at rest, none harmful at rest and nobody harmed, no body can be harmed: the
	# bodies are not looked at (what a room at rest costs, GC6).
	if may_harm:
		_affect_bodies(delta)
	_flush()


## Every queued touch, in the order heard, in every room whose cover its circle reaches (rooms in
## number order; each room's cells in cell order).
func _apply_touches() -> void:
	for t in _touch_elements.size():
		var at: Vector2 = _touch_at[t]
		var radius: float = _touch_radius[t]
		var reach := Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		for room in _rooms:
			if room.plays() and room.layout.rect().intersects(reach, true):
				room.touch(_touch_elements[t], at, radius)
	_clear_touches()


## Every open actor's body, in id order, standing in a cell whose state gives a status: asked it at
## once and again every `status_every` seconds while it stays in such cover. A body that steps out
## keeps its time till its next one running, and is dropped only when it runs out (GC8): stepping
## in and out of cobwebs is asked no oftener than standing in them, so a short chill never stacks.
## A sleeping body (its place asleep, `Actors.asleep`) is asked nothing and its time waits.
func _affect_bodies(delta: float) -> void:
	var count: int = actors.open_ids(_ids) if actors != null else 0
	var old: int = 0
	var harmed: int = 0
	for n in count:
		var id: int = _ids[n]
		var body := actors.node_of(id) as Node2D
		if body == null or not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var key: int = actors.key_of(id)
		while old < _harm_ids.size() and _harm_ids[old] < id:
			old += 1
		var kept: bool = old < _harm_ids.size() and _harm_ids[old] == id and _harm_keys[old] == key
		if actors.asleep[id] != 0:
			# Asleep with its place: its time waits as it is.
			if kept:
				_next_ids[harmed] = id
				_next_keys[harmed] = key
				_next_left[harmed] = _harm_left[old]
				harmed += 1
			continue
		var left: float = _harm_left[old] - delta if kept else 0.0
		var at: Vector2 = body.global_position
		var number: int = room_at(at)
		var state: CoverState = _rooms[number].cover_state_at(_rooms[number].layout.cell_of(at)) if number >= 0 else null
		if state == null or state.status == &"":
			# Out of harmful cover: its time runs on, and it is dropped once it is out.
			if left > 0.0:
				_next_ids[harmed] = id
				_next_keys[harmed] = key
				_next_left[harmed] = left
				harmed += 1
			continue
		if left <= 0.0:
			left = maxf(state.status_every, delta)
			if events != null:
				events.status_requested.emit(EventsScript.NO_PLAYER, body, state.status, state.status_duration, state.status_strength)
		_next_ids[harmed] = id
		_next_keys[harmed] = key
		_next_left[harmed] = left
		harmed += 1
	# Written over in place: the same count resizes nothing.
	_harm_ids.resize(harmed)
	_harm_keys.resize(harmed)
	_harm_left.resize(harmed)
	for n in harmed:
		_harm_ids[n] = _next_ids[n]
		_harm_keys[n] = _next_keys[n]
		_harm_left[n] = _next_left[n]


# --- Upkeep ----------------------------------------------------------------------------

func _clear_touches() -> void:
	if _touch_elements.is_empty():
		return
	_touch_elements.clear()
	_touch_at.resize(0)
	_touch_radius.resize(0)


## Each room's changes told since the last, sent as one `cover_changed` a room.
func _flush() -> void:
	for number in _rooms.size():
		_rooms[number].flush(events, number)
