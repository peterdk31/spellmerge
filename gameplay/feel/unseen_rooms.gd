extends RefCounted
## What a room nobody has entered holds, and what a room or bridge out of every view holds, is not
## drawn (the owner, 2026-11-21, after the report of worse performance: "hide unvisited rooms, and
## simply render the background everywhere", then "also hide rooms out of view").
##
## **Unvisited:** such a
## room is covered whole by the void's dark (`unseen_dark.gd`, its `covers_whole`), so its layout
## (its floor, walls and decor: the node `room_built` hands over), its floor marks' layer
## (`Marks.set_layer_shown`), its motes' chunks (`MoteRegions.set_region_shown`, the motes' pool's,
## never the void's, which drift over the dark) and its ground cover (`CoverRooms.view_of`) are
## switched off, and the dark over it is all that is drawn there: one rectangle on the void's own
## black. Once its reveal begins they are drawn again, as they stand (the marks and motes kept on
## being written), under the opening blocks. The dark stays the guard for anything else a room
## holds (bodies, pickups, a rune's crack), so nothing shows that did not before.
##
## **Out of view:** a place whose rectangle grown by MARGIN meets none of the views' boxes
## (`ViewBoxes`, the spectacle's: one box, or a box a split view) has the same switched off. Godot
## would not draw them there either, but it walks every node of every room each frame to find that
## out; a room switched off is left out of that walk whole. MARGIN holds what a place draws past its
## rectangle (its motes' reach, `MoteRegions.REACH`, and its lip) and a frame's move of the camera,
## so a place is on before it comes into a view. With no box (outside a tree) none is out of view.
##
## View only: it sets what is drawn and reads no state of the game; `visible` is no member of any
## simulation script, and a layout made again (a restore, a new biome) is handed over again by
## `room_built` and switched as it stands. Each frame it works out which places are off (a test of
## a rectangle against the views' boxes a place) and switches only those that changed; all of them
## again when something was made anew: the dark's stages laid, the places the motes are drawn by,
## the marks' layers, the cover's rooms, or a layout handed over.

const EventsScript := preload("res://core/events/events.gd")
const UnseenDarkScript := preload("res://gameplay/feel/unseen_dark.gd")
const MarksScript := preload("res://gameplay/feel/marks.gd")
const MoteRegionsScript := preload("res://gameplay/feel/mote_regions.gd")
const CoverRoomsScript := preload("res://gameplay/feel/cover_rooms.gd")
const ViewBoxesScript := preload("res://gameplay/feel/view_boxes.gd")

## How far past a view's box a place still counts as in view (world px; see above).
const MARGIN: float = 160.0

## By piece number (`room_built`'s, the grid's place): the layout handed over (null: none).
var _layouts: Array[CanvasItem] = []
## By place: 1 while it is not drawn. Read only (for tests: `is_hidden`).
var _hidden: PackedByteArray = PackedByteArray()
## What every switch was last laid for: the dark's changes, the regions' fits, the marks' layers,
## the cover's rooms and the layouts handed over (-1: not yet).
var _laid: PackedInt64Array = PackedInt64Array([-1, -1, -1, -1, -1])
## The places' wanted states this frame (1: off), worked out in place.
var _wanted: PackedByteArray = PackedByteArray()
var _handed: int = 0


## Hear `room_built` on `events` for the rooms' layouts.
func bind(events: EventsScript) -> void:
	if events != null and not events.room_built.is_connected(_on_room_built):
		events.room_built.connect(_on_room_built)


func _on_room_built(_room_id: StringName, number: int, layout_root: Node) -> void:
	if number == EventsScript.FIRST_ROOM:
		_layouts.clear()
	if number < 0:
		return
	while _layouts.size() <= number:
		_layouts.append(null)
	_layouts[number] = layout_root as CanvasItem
	_handed += 1


## Switch off what lies in each room `dark` covers whole and in each place of `grid` out of every
## box of `seen` (null or empty: none is), and on again what no longer is, in the layouts,
## `marks`' layers, the motes' `regions` and `cover`'s rooms (each may be null).
func step(dark: UnseenDarkScript, grid: RoomGrid, seen: ViewBoxesScript, marks: MarksScript, regions: MoteRegionsScript, cover: CoverRoomsScript) -> void:
	if dark == null:
		return
	var places: int = maxi(_layouts.size(), marks.layer_count() if marks != null else 0)
	if regions != null:
		places = maxi(places, regions.places)
	var now := PackedInt64Array([dark.void_changes(), regions.fits if regions != null else 0, marks.layer_count() if marks != null else 0, cover.count() if cover != null else 0, _handed])
	var all: bool = now != _laid or _hidden.size() != places
	_laid = now
	_wanted.resize(places)
	var viewed: bool = seen != null and not seen.is_empty() and grid != null
	var grid_places: int = grid.places() if grid != null else 0
	for place in places:
		var off: bool = dark.covers_whole(place)
		if not off and viewed and place < grid_places:
			off = not seen.intersects(grid.place_rect(place), MARGIN)
		_wanted[place] = 1 if off else 0
	if _hidden.size() != places:
		_hidden.resize(places)
	for place in places:
		if not all and _hidden[place] == _wanted[place]:
			continue
		_hidden[place] = _wanted[place]
		_switch(place, _wanted[place] == 0, marks, regions, cover)


## Place `place`'s drawing on (`shown`) or off.
func _switch(place: int, shown: bool, marks: MarksScript, regions: MoteRegionsScript, cover: CoverRoomsScript) -> void:
	if place < _layouts.size() and is_instance_valid(_layouts[place]):
		_layouts[place].visible = shown
	if marks != null:
		marks.set_layer_shown(place, shown)
	if regions != null:
		regions.set_region_shown(place + 1, shown)
	var room: Node = cover.view_of(place) if cover != null else null
	if room is CanvasItem:
		(room as CanvasItem).visible = shown


## Whether place `place`'s drawing is switched off now (for tests).
func is_hidden(place: int) -> bool:
	return place >= 0 and place < _hidden.size() and _hidden[place] == 1
