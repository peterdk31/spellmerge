extends RefCounted
## Which of a biome's places this machine hears, and which room its music follows (connected biomes
## CB12, decision 29: "sound only from rooms this machine's wizards are in; music follows the most
## intense of them"). View only: it reads the bodies' places and the grid's seals once a frame and
## changes nothing; nothing in the game reads it.
##
## **Heard places:** every place (a room or a bridge, the grid's numbers, `RoomGrid.add_place`) a
## wizard of this machine's seats (`Frames.seats_here`; 0: every seat) stands in, and the places
## touching it (a room's bridges, a bridge's rooms), so a shot stopping at a room's mouth (on its
## bridge) is heard from inside and a wizard on a bridge hears both ends. A point in no place (the
## void, a world with no places: a row run, the hub) is heard. While none of this machine's wizards
## stands in a place (one falling, freed, not stood yet) the places heard last stay heard, so the
## biome never goes silent for a frame. Audio asks `hears` for every world
## sound (`Ears.heard`, core/audio).
##
## **The music** follows the room (not a bridge) of this machine's wizards that is the most intense:
## a sealed fight (`INTENSE_FIGHT`) over a quiet room (`INTENSE_QUIET`); between equals the one it
## follows already, else the lowest seat's. A wizard on a bridge leaves it where it was. Its track is
## the room's kind's (`RoomKind.music`), else its template's (`RoomBase.music`), and its bed the
## kind's air (`RoomKind.air`), else the template's (`RoomBase.ambience`). A living boss's own music
## is still played over it, if the boss is in a heard place (`body_sounds.gd`).
##
## It learns the pieces from `room_built` (their templates, rooms first and then bridges, a new world
## from FIRST_ROOM) and a room's kind from the layout's `RoomKind.LAYOUT_META`, else the first kind its
## template hosts; a reward room's type (`RewardType`, the owner's ask of 2026-11-19) from the layout's
## `RewardType.LAYOUT_META` (none: any), for the mouths' signs and the held map; and which rooms
## are cleared (`rooms_cleared`, Flow's state as told; the owner, 2026-11-20), for their cleared look;
## and (the owner, 2026-11-20, after #884) which are opened (`rooms_opened`, Flow's), which fountains
## were used (`fountain_changed`, Rewards') and which rooms still hold a reward to take
## (`rooms_rewards_left`, Rewards'), so a room is done (`is_done`) by its kind's rule
## (`KindSymbol.done_by`).

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const KindSymbolScript := preload("res://gameplay/feel/kind_symbol.gd")

## Where the rooms and kinds are in the registry.
const ROOM_FOLDER: StringName = &"rooms"
const KIND_FOLDER: StringName = &"room_kinds"
## How far apart two places' rectangles may be and still touch (a mouth's cell, a lip's wander).
const TOUCH: float = 16.0
## A room's intensity for the music: quiet, or a fight under way (sealed).
const INTENSE_QUIET: int = 1
const INTENSE_FIGHT: int = 2
## None.
const NONE: int = -1

## The registry the rooms and kinds are read from (Feel's).
var registry: Node = null

## By piece number (`room_built`'s): its template, whether it is a walkway, its kind.
var _templates: Array[StringName] = []
var _walkway: PackedByteArray = PackedByteArray()
var _kinds: Array[RoomKind] = []
var _types: Array[RewardType] = []
## By place: heard this frame (1) or not; the places touching it (from `_touch_from`, `_touch_count`).
var _heard: PackedByteArray = PackedByteArray()
var _touch: PackedInt32Array = PackedInt32Array()
var _touch_from: PackedInt32Array = PackedInt32Array()
var _touch_count: PackedInt32Array = PackedInt32Array()
## The places the touch lists were worked out for (-1: none yet; a new world works them out again).
var _touch_places: int = -1
## The grid read this frame (null: none), and the room the music follows (NONE: none yet).
var _grid: RoomGrid = null
var _followed: int = NONE
## How many worlds were laid (`room_built` of FIRST_ROOM): the looks that read the grid lay theirs
## again when it changes.
var _world: int = 0
## By room number: cleared (1), as Flow told it last (`rooms_cleared`), and how many times it was told
## `again` (after a restore): the looks that play the cleared look in draw it as it stands then.
var _cleared: PackedByteArray = PackedByteArray()
var _cleared_again: int = 0
## By room number, as told last: opened (1; `rooms_opened`, Flow's), its fountain used (1;
## `fountain_changed`, Rewards': drawn on at all), a reward still to take there (1;
## `rooms_rewards_left`, Rewards'). Each sender tells its own afresh (a world gone, a restore).
var _opened: PackedByteArray = PackedByteArray()
var _used: PackedByteArray = PackedByteArray()
var _left: PackedByteArray = PackedByteArray()


func bind(events: EventsScript) -> void:
	if events != null:
		events.room_built.connect(_on_room_built)
		events.rooms_cleared.connect(_on_rooms_cleared)
		events.rooms_opened.connect(_on_rooms_opened)
		events.rooms_rewards_left.connect(_on_rooms_rewards_left)
		events.fountain_changed.connect(_on_fountain_changed)


func _on_rooms_cleared(cleared: PackedByteArray, again: bool) -> void:
	_cleared = cleared
	if again:
		_cleared_again += 1


func _on_rooms_opened(opened: PackedByteArray, again: bool) -> void:
	_opened = opened
	if again:
		_cleared_again += 1


func _on_rooms_rewards_left(left: PackedByteArray, again: bool) -> void:
	_left = left
	if again:
		_cleared_again += 1


## A fountain's pool as it stands (room -1: every one forgotten): used once it holds less than its
## most (a restore says every pool again after -1, with the rooms cleared told again).
func _on_fountain_changed(room: int, _area: Rect2, left: float, most: float) -> void:
	if room < 0:
		_used = PackedByteArray()
		return
	if _used.size() <= room:
		_used.resize(room + 1)
	_used[room] = 1 if left < most else 0


## True when room `room` is cleared (as Flow told it last).
func is_cleared(room: int) -> bool:
	return _has(_cleared, room)


## True when room `room` is done, by its kind's rule (`KindSymbol.done_by`): cleared, opened, its
## fountain used, or (a reward room) entered with no reward left to take in it.
func is_done(room: int) -> bool:
	match KindSymbolScript.done_by(kind_of(room)):
		KindSymbolScript.DONE_CLEARED:
			return _has(_cleared, room)
		KindSymbolScript.DONE_OPENED:
			return _has(_opened, room)
		KindSymbolScript.DONE_USED:
			return _has(_used, room)
		KindSymbolScript.DONE_TAKEN:
			return _has(_cleared, room) and not _has(_left, room)
	return false


static func _has(rooms: PackedByteArray, room: int) -> bool:
	return room >= 0 and room < rooms.size() and rooms[room] != 0


## How many times the rooms done were told again after a restore (`rooms_cleared`, `rooms_opened`,
## `rooms_rewards_left`; it changes with each): the looks draw the cleared look as it stands then.
func cleared_again() -> int:
	return _cleared_again


## A piece laid (`room_built`): its template and kind kept by its number.
func _on_room_built(room_id: StringName, number: int, layout_root: Node) -> void:
	if number == EventsScript.FIRST_ROOM:
		_templates.clear()
		_walkway.resize(0)
		_kinds.clear()
		_types.clear()
		_followed = NONE
		_touch_places = -1
		_world += 1
		# A new world's rooms are none of them cleared until Flow says so (an old biome's never carry
		# over by number: a restore into the hub or a row run tells no empty map).
		_cleared = PackedByteArray()
		_opened = PackedByteArray()
	if number < 0:
		return
	while _templates.size() <= number:
		_templates.append(&"")
		_walkway.append(0)
		_kinds.append(null)
		_types.append(null)
	_templates[number] = room_id
	var room: RoomBase = _room(room_id)
	_walkway[number] = 1 if room != null and room.walkway else 0
	var kind_id: StringName = &""
	if layout_root != null and layout_root.has_meta(RoomKind.LAYOUT_META):
		kind_id = StringName(layout_root.get_meta(RoomKind.LAYOUT_META))
	elif room != null and not room.kinds.is_empty():
		kind_id = room.kinds[0]
	var type: RewardType = null
	if layout_root != null and layout_root.has_meta(RewardType.LAYOUT_META):
		type = RewardType.from_row(PackedStringArray(layout_root.get_meta(RewardType.LAYOUT_META)))
	_types[number] = type
	_kinds[number] = registry.call(&"get_resource", KIND_FOLDER, kind_id) as RoomKind if registry != null and kind_id != &"" else null


## Once a frame: the places this machine's wizards stand in (`table`'s bodies of the seats in
## `seats_here`, a bit a seat, 0 every seat) and those touching them are heard, on `grid` (null:
## everything is heard); the room the music follows is worked out again.
func step(table: ActorsScript, seats_here: int, grid: RoomGrid) -> void:
	_grid = grid
	var places: int = grid.places() if grid != null else 0
	if places == 0:
		_heard.resize(0)
		return
	if places != _touch_places:
		_work_out_touches(grid, places)
	if _heard.size() != places:
		_heard.resize(places)
		_heard.fill(1)
	if table == null:
		return
	var best: int = NONE
	var best_intensity: int = 0
	var keep: bool = false
	var found: bool = false
	for seat in ActorsScript.SEATS:
		if seats_here != 0 and seats_here & (1 << seat) == 0:
			continue
		var body := table.node_of(table.home_of_seat(seat)) as Node2D
		if body == null or not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var place: int = grid.place_at(body.global_position)
		if place < 0 or place >= places:
			continue
		if not found:
			found = true
			_heard.fill(0)
		_heard[place] = 1
		for k in _touch_count[place]:
			_heard[_touch[_touch_from[place] + k]] = 1
		if is_walkway(place):
			continue
		var intensity: int = intensity_of(place)
		if intensity > best_intensity:
			best = place
			best_intensity = intensity
			keep = place == _followed
		elif intensity == best_intensity and place == _followed:
			keep = true
	if best != NONE:
		_followed = _followed if keep else best


## Each place's touching places, once a biome.
func _work_out_touches(grid: RoomGrid, places: int) -> void:
	_touch_places = places
	_touch.resize(0)
	_touch_from.resize(places)
	_touch_count.resize(places)
	for place in places:
		_touch_from[place] = _touch.size()
		var grown: Rect2 = grid.place_rect(place).grow(TOUCH)
		for other in places:
			if other != place and grown.intersects(grid.place_rect(other)):
				_touch.append(other)
		_touch_count[place] = _touch.size() - _touch_from[place]


## The number of the world laid last (it changes with each new one: a biome, a row run's room).
func world() -> int:
	return _world


## True when a sound at world point `at` is heard (see the top).
func hears(at: Vector2) -> bool:
	if _heard.is_empty() or _grid == null:
		return true
	var place: int = _grid.place_at(at)
	return place < 0 or place >= _heard.size() or _heard[place] != 0


## True while place `place` is heard (always in a world with no places).
func is_heard(place: int) -> bool:
	return _heard.is_empty() or place < 0 or place >= _heard.size() or _heard[place] != 0


## True when a biome's places are heard by this (false in a world with none: a row run, the hub).
func in_biome() -> bool:
	return not _heard.is_empty()


## True when piece `place` is a walkway (a bridge).
func is_walkway(place: int) -> bool:
	return place >= 0 and place < _walkway.size() and _walkway[place] != 0


## The music's intensity for room `place`: a sealed fight's, else quiet.
func intensity_of(place: int) -> int:
	return INTENSE_FIGHT if _grid != null and _grid.is_sealed(place) else INTENSE_QUIET


## The room the music follows (NONE: none yet).
func followed() -> int:
	return _followed


## The kind of piece `place` (null: none known).
func kind_of(place: int) -> RoomKind:
	return _kinds[place] if place >= 0 and place < _kinds.size() else null


## The reward type of piece `place` (null: none, or any).
func type_of(place: int) -> RewardType:
	var type: RewardType = _types[place] if place >= 0 and place < _types.size() else null
	return type if type != null and not type.is_any() else null


## The registry's resource `id` in `folder` (null: none; for the views that read a piece's content).
func content(folder: StringName, id: StringName) -> Resource:
	return registry.call(&"get_resource", folder, id) as Resource if registry != null and id != &"" else null


## The track the music plays for the room it follows (its kind's, else its template's; null: none).
func music() -> MusicTrack:
	var kind: RoomKind = kind_of(_followed)
	if kind != null and kind.music != null:
		return kind.music
	var room: RoomBase = _room(_templates[_followed]) if _followed >= 0 and _followed < _templates.size() else null
	return room.music if room != null else null


## The bed heard for the room it follows (its kind's air, else its template's ambience; null: none).
func air() -> Ambience:
	var kind: RoomKind = kind_of(_followed)
	if kind != null and kind.air != null:
		return kind.air
	var room: RoomBase = _room(_templates[_followed]) if _followed >= 0 and _followed < _templates.size() else null
	return room.ambience if room != null else null


func _room(room_id: StringName) -> RoomBase:
	if registry == null or room_id == &"":
		return null
	return registry.call(&"get_resource", ROOM_FOLDER, room_id) as RoomBase
