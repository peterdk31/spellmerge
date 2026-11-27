extends CanvasLayer
## The held Y map (connected biomes CB9, decision 28: "Holding Y shows the map over that player's own
## view; nobody else stops"): while a player of this machine holds `map` (Y; M on the keyboard), the
## party's map of the biome opens over that player's own view, inside its cell of the split screen
## (`ScreenViews`), and closes as it is let go. Nobody else stops and nothing in the game waits: the
## hold is read from the device here and never reaches the simulation, and what is drawn is the
## party's map as Flow tells it (`rooms_seen`, its state). View only; nothing in the game reads it.
##
## **What it shows:** every room the party has entered (the floor's light stone) and every room only
## shown (the run stat `map_reveal`: the stone's shadow), each in its own shape (its floor at
## MAP_CELL world pixels a map pixel, read once from the grid as the biome is laid); each bridge with a
## seen room at an end, and the room at its other end in the stone's shadow too, so no bridge ends in
## the dark (the owner, 2026-11-20: "There should be no dead ends!"; a secret room not yet found, and
## its bridge, stay undrawn); each room's kind symbol (`RoomKind.symbol`) on the rooms seen and on those a
## drawn bridge leads to (their mouth tells it already, `mouth_symbols.gd`), with a reward room's
## type under it (`reward_glyphs.gd`, the owner's ask of 2026-11-19), rising with it; and every wizard, a dot in
## its hat colour. **A player's own sense** (the run stat `secret_sense`, told for each seat by
## `run_stats_told`; the owner's answer of 2026-11-19): on that player's map only, each secret
## room (a kind whose door is `RoomKind.DOOR_SECRET`) not otherwise drawn whose rectangle lies within
## `secret_sense` pixels of a room the party entered is drawn too, in a look of its own so it reads
## as secret (the owner, 2026-11-19): a faint void light, the palette's Void shadow and base
## (`SENSED_STAGES`). It is worked out each frame from the party's map, the pieces and the seat's stat, so it is
## the same on every machine and needs nothing of its own saved: per player, and view only.
##
## **Where:** a frame round the map, centred on the anchor of the player's view (where its wizards are
## drawn), as large as fits inside that view's cell EDGE layout pixels in (a convex cell: a rectangle
## whose corners are inside it is inside it), the map at a whole scale (1 to MAX_SCALE); a cell too
## small for it all shows the part round the player's wizard, cut at the frame. With one picture the
## cell is the screen.
##
## **Smooth** (docs/STYLE.md): it opens from its middle row out through OPEN_STAGES heights at FPS and
## closes the same way back. While it is open, a piece newly drawn comes in through the stone's shades
## (none, shadow, base, light; a room only shown stops at its shadow, a bridge at its base; a sensed
## secret room through the stone's shadow, the void's shadow and the void's base), a room
## entered climbs from its shadow to its light, and a symbol rises in by rows, each a step a frame at
## FPS; and a piece's shape comes in by IN_STAGES too (the owner, 2026-11-20: a room only known through
## a bridge never pops in): a quarter of its pixels, then half (keeping the quarter), then all, a stage
## a frame beside its shades; with every map shut they are drawn as they stand. A frame whose size or scale must change (the
## screen split or merged under it) closes and opens again at its new size; it never jumps. Whole
## pixels; nothing fades.
##
## **A done room** (the owner, 2026-11-20, #883 and #888): a room that is done (Feel's room hearing,
## `is_done`: a fight's cleared, a fountain drawn dry, a reward, treasure or secret room's rewards
## taken; `KindSymbol.done_by`, never a shop) shows its symbol in the calm done look
## (`kind_symbol.gd`: dimmed, a check across it), as its doorway signs do; on an open map it steps in a
## stage a frame at FPS, with every map shut (or told again after a restore) drawn as it stands. A
## secret room's symbol is drawn only once the room is found (its rock broken: `is_opened`).
##
## **Told to the HUD:** each seat's frame and whether it is fully open (`map_frame_shown`, as either
## changes), so the HUD's legend sits under it (`hud/panels/map_legend.gd`).
##
## Feel's: a canvas layer under the HUD's (`LAYER`), a frame (a Control that clips) a seat; stepped once
## a frame (`step`). Nothing is allocated while it is drawn.

const ActorsScript := preload("res://core/actors/actors.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")
const KindSymbolScript := preload("res://gameplay/feel/kind_symbol.gd")
const RewardGlyphsScript := preload("res://gameplay/feel/reward_glyphs.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

## Under the HUD's panels and menus (layer 10, `hud/panels/panels.tscn`), over the world's views.
const LAYER: int = 9
## The action held (project.godot: Y on a pad, M on the keyboard).
const ACTION: StringName = &"map"
## World pixels a map pixel.
const MAP_CELL: float = 16.0
## The opening's heights (0 shut ... OPEN_STAGES open) and the frames a second it steps at.
const OPEN_STAGES: int = 4
const FPS: float = 12.0
## The most a map pixel grows to (screen pixels).
const MAX_SCALE: int = 3
## Screen pixels kept between the frame and its cell's edge, and between the frame and the map.
const EDGE: float = 4.0
const PAD: int = 4
## A room's level in `rooms_seen`.
const SHOWN: int = 1
const ENTERED: int = 2
## A wizard's dot, its side in map pixels (inside its dark edge of a screen pixel).
const DOT: int = 2
## The pick's outline round a room (`map_pick_changed`, the HUD's; the owner, 2026-11-19): its stages
## at FPS, 0 none, then its four corners' dots, then brackets of BRACKET map pixels, then the whole
## outline, in the seat's own colour, a screen pixel wide outside the room's box.
const PICK_STAGES: int = 3
const BRACKET: int = 3

## The pieces (Feel's room hearing: which places are walkways, each room's kind) and the input manager
## (`core/input`, the "PlayerInput" autoload; null: nothing is held).
var pieces: RoomHearingScript = null
var input: InputManagerScript = null

## The biome as the map draws it, by place: its rectangle (world pixels), its floor (a white mask at
## MAP_CELL), whether it is a room, a walkway's two rooms (-1: none), a room's symbol and its shades.
var _rects: Array[Rect2] = []
var _floors: Array[ImageTexture] = []
## By place, its floor thinned to each stage before whole (`thinned`: IN_STAGES - 1 of them), and the
## stage its shape is drawn at (0 none ... IN_STAGES whole).
var _floors_in: Array = []
var _in: PackedInt32Array = PackedInt32Array()
var _room: PackedByteArray = PackedByteArray()
var _ends: PackedInt32Array = PackedInt32Array()
var _symbols: Array[PackedByteArray] = []
var _symbol_shades: Array[PackedColorArray] = []
## By place: its reward type's glyphs (an Array[PackedByteArray] and an Array[PackedColorArray] each;
## empty: none).
var _glyphs: Array = []
var _glyph_shades: Array = []
## The pieces' box (world pixels).
var _area: Rect2 = Rect2()
## The party's map as told last (`rooms_seen`).
var _seen: PackedByteArray = PackedByteArray()
## By place: a secret room (1). By seat: its `secret_sense` (pixels; `run_stats_told`).
var _secret: PackedByteArray = PackedByteArray()
var _sense: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## By seat and place (seat * places + place): a secret room sensed by that seat drawn (0 none, then
## its stage of `_sensed_shades`, up to SENSED_STAGES).
var _sense_shade: PackedInt32Array = PackedInt32Array()
## By seat and place: sensed now (1), worked out again only when the party's map, a seat's stat or
## the biome changes (`_sensed_stale`).
var _sensed: PackedByteArray = PackedByteArray()
var _sensed_stale: bool = true
## True while every map is shut and the pieces' looks were not yet settled to what they want: they
## are only drawn once a map opens, so they are settled when read (`_settled`), not every frame (the
## performance pass, 2026-11-21: half a millisecond a frame in a biome, the map shut).
var _unsettled: bool = false
## How many secret rooms were found (opened) when last read: a change works the senses out again.
var _found_secrets: int = 0
## By seat: held now, the opening's stage, its frame (screen pixels) and scale, and where the map's
## corner sits in its frame (screen pixels).
var _held: PackedByteArray = PackedByteArray([0, 0, 0, 0])
var _stage: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _frame: Array[Rect2i] = [Rect2i(), Rect2i(), Rect2i(), Rect2i()]
var _scale: PackedInt32Array = PackedInt32Array([1, 1, 1, 1])
var _origin: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _maps: Array[SeatMap] = []
## By seat: its frame closing to open again at a new size or scale (1).
var _reopen: PackedByteArray = PackedByteArray([0, 0, 0, 0])
## By seat: the views it was laid out in while open (their count and its view): a frame keeps its size
## while it stays in them and still fits (a moving player or camera never closes it), and reopens
## only when the split changes under it or it no longer fits.
var _laid_views: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _laid_view: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
## By seat: the room outlined on its map, the room picked next (`map_pick_changed`; -1 none: the
## outline steps out of the old room before it steps into the new) and the outline's stage.
var _pick: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _pick_next: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _pick_stage: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## By place: the stone's shade drawn (0 none, 1 shadow, 2 base, 3 light) and its symbol's rows shown.
var _shade: PackedInt32Array = PackedInt32Array()
var _symbol_rows: PackedInt32Array = PackedInt32Array()
## By place: a room whose kind shows the done look once done (1), and that look's stage drawn; the room
## hearing's `done_again` read last.
var _tells_done: PackedByteArray = PackedByteArray()
var _done: PackedInt32Array = PackedInt32Array()
var _read_again: int = 0
## The wizards' places and colours this frame (world pixels; INF: none), by seat.
var _wizard_at: PackedVector2Array = PackedVector2Array([Vector2.INF, Vector2.INF, Vector2.INF, Vector2.INF])
var _wizard_colour: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
## The bus (`map_frame_shown`, told to the HUD's legend) and, by seat, the frame told last and whether
## it was open then.
var _events: Node = null
var _told_frame: Array[Rect2i] = [Rect2i(), Rect2i(), Rect2i(), Rect2i()]
var _told_open: PackedByteArray = PackedByteArray([0, 0, 0, 0])
var _laid_places: int = -1
var _laid_world: int = -1
var _clock: float = 0.0
## The stone's shades (shadow, base, light).
var _stone: PackedColorArray = Palette.shades_of(&"stone")
## A sensed secret room's stages, coming in: as a room only shown (the stone's shadow), then the
## void's shadow, then its faint light (the void's base; the owner, 2026-11-19).
const SENSED_STAGES: int = 3
## The stages a piece's shape comes in by on an open map: a quarter of its pixels, half, all.
const IN_STAGES: int = 3
var _sensed_shades: PackedColorArray = PackedColorArray([Palette.shades_of(&"stone")[0], Palette.shades_of(&"void")[0], Palette.shades_of(&"void")[1]])


## One seat's frame: a Control that clips, drawing its seat's map.
class SeatMap extends Control:
	var seat: int = 0
	var view: Object = null
	## Its frame's rows hidden above it while it opens.
	var top: int = 0

	func _draw() -> void:
		view.call(&"draw_map", self, seat)


func _init() -> void:
	layer = LAYER
	for seat in ActorsScript.SEATS:
		var map := SeatMap.new()
		map.name = "Map%d" % (seat + 1)
		map.seat = seat
		map.view = self
		map.clip_contents = true
		map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map.visible = false
		_maps.append(map)
		add_child(map)


func bind(events: Node) -> void:
	# Laid out in layout pixels and drawn at the picture's scale (core/display/picture_grid.gd); Feel
	# hands it the views in layout pixels.
	PictureGrid.keep_fitted(self)
	_events = events
	if events != null:
		events.rooms_seen.connect(_on_rooms_seen)
		events.run_stats_told.connect(_on_run_stats_told)
		events.map_pick_changed.connect(_on_map_pick_changed)


## The room seat `seat` picked on its map (the HUD's `map_pick_changed`): the old outline steps out
## to nothing, then the new one steps in (from its corners), never a jump.
func _on_map_pick_changed(seat: int, room: int) -> void:
	if seat < 0 or seat >= ActorsScript.SEATS:
		return
	_pick_next[seat] = room


## The room seat `seat` has picked (the one outlined next) and its outline's stage (for tests).
func pick_of(seat: int) -> int:
	return _pick_next[seat]


## The room seat `seat`'s outline is drawn round now (for tests).
func outlined_of(seat: int) -> int:
	return _pick[seat]


func pick_stage_of(seat: int) -> int:
	return _pick_stage[seat]


func _on_rooms_seen(seen: PackedByteArray, _again: bool) -> void:
	_seen = seen
	_sensed_stale = true
	if not _any_open():
		_settle()


func _on_run_stats_told(player: int, stats: Dictionary) -> void:
	if player < 0 or player >= _sense.size():
		return
	_sense[player] = float(stats.get(&"secret_sense", 0.0))
	_sensed_stale = true
	if not _any_open():
		_settle()


## Seat `seat`'s opening (0 shut ... OPEN_STAGES), its frame (screen pixels) and its map's scale (for
## tests).
func stage_of(seat: int) -> int:
	return _stage[seat] if seat >= 0 and seat < _stage.size() else 0


func frame_of(seat: int) -> Rect2i:
	return _frame[seat] if seat >= 0 and seat < _frame.size() else Rect2i()


func scale_of(seat: int) -> int:
	return _scale[seat] if seat >= 0 and seat < _scale.size() else 1


## The part of the screen seat `seat`'s map covers now (its frame as far as it has opened).
func shown_rect(seat: int) -> Rect2i:
	var map: SeatMap = _maps[seat] if seat >= 0 and seat < _maps.size() else null
	if map == null or not map.visible:
		return Rect2i()
	return Rect2i(Vector2i(map.position), Vector2i(map.size))


## Place `place`'s shade drawn now (0 none, 1 the stone's shadow, 2 its base, 3 its light) and its
## symbol's rows shown (for tests).
func shade_of(place: int) -> int:
	_settled()
	return _shade[place] if place >= 0 and place < _shade.size() else 0


## Room `place`'s symbol's done look's stage (0 none ... `KindSymbol.DONE_STAGES`; for tests).
func done_of(place: int) -> int:
	_settled()
	return _done[place] if place >= 0 and place < _done.size() else 0


func symbol_rows_of(place: int) -> int:
	_settled()
	return _symbol_rows[place] if place >= 0 and place < _symbol_rows.size() else 0


## How many glyphs of its reward type room `place` shows with its symbol (for tests).
func glyphs_of(place: int) -> int:
	return (_glyphs[place] as Array).size() if place >= 0 and place < _glyphs.size() else 0


## Room `place` as sensed on seat `seat`'s map now (0 not drawn, then its stage: 1 the stone's
## shadow, 2 the void's shadow, 3 the void's base; for tests).
func sense_shade_of(seat: int, place: int) -> int:
	_settled()
	var at: int = seat * _rects.size() + place
	return _sense_shade[at] if seat >= 0 and place >= 0 and place < _rects.size() and at < _sense_shade.size() else 0


## The colour place `place` is drawn in on seat `seat`'s map now (transparent: not drawn). A secret
## room the seat senses is drawn in its own look while its stage is past the stone's shadow, so as
## the party's map takes it over (entered, shown) it steps down through the void's shadow, never
## jumping from the void's light to the stone (the review's).
func drawn_colour(seat: int, place: int) -> Color:
	_settled()
	var shade: int = _shade[place] if place >= 0 and place < _shade.size() else 0
	var sensed: int = sense_shade_of(seat, place)
	if sensed > 1 or (shade <= 0 and sensed > 0):
		return _sensed_shades[sensed - 1]
	return _stone[shade - 1] if shade > 0 else Color.TRANSPARENT


func _drawn(seat: int, place: int) -> bool:
	_settled()
	return (place < _shade.size() and _shade[place] > 0) or sense_shade_of(seat, place) > 0


## True when seat `seat`'s own map draws secret room `place`, which the party's map does not, by the
## seat's `secret_sense`: it lies within that many pixels (rectangle to rectangle) of a room entered.
func senses(seat: int, place: int) -> bool:
	if seat < 0 or seat >= _sense.size() or _sense[seat] <= 0.0 or place < 0 or place >= _rects.size():
		return false
	if _secret[place] == 0 or draws(place):
		return false
	var reach: float = _sense[seat]
	for room in _rects.size():
		if _room[room] != 0 and _level(room) >= ENTERED and gap_between(_rects[place], _rects[room]) <= reach:
			return true
	return false


## The distance between rectangles `a` and `b` (0 when they touch or overlap).
static func gap_between(a: Rect2, b: Rect2) -> float:
	var x: float = maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var y: float = maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(x, y).length()


## How many places the map knows.
func places() -> int:
	return _rects.size()


## True when the map draws place `place` now: a room seen, or led to by a bridge drawn (in the shown
## room's shadow); a bridge with a seen room at one end and a room the map may draw at the other. So
## no bridge on the map ends in the dark (the owner, 2026-11-20: "There should be no dead ends!"): a
## secret room not yet found is never drawn for its bridge, and so neither is its bridge. A secret
## room is drawn only once found, whichever way it is reached (the owner, 2026-11-20): never for being
## shown on the party's map (`map_reveal`), and a found one reached by a rune, with no bridge to draw
## it for, in the shown room's shadow.
func draws(place: int) -> bool:
	if place < 0 or place >= _rects.size():
		return false
	if _room[place] == 0:
		return _bridge_drawn(place)
	if _secret[place] != 0:
		return _level(place) >= ENTERED or (pieces != null and pieces.is_opened(place))
	if _level(place) >= SHOWN:
		return true
	if not _may_draw(place):
		return false
	for other in _rects.size():
		if _room[other] == 0 and (_ends[other * 2] == place or _ends[other * 2 + 1] == place) and _bridge_drawn(other):
			return true
	return false


## How many secret rooms are opened now (a cheap count, read once a frame).
func _secrets_found() -> int:
	var count: int = 0
	if pieces == null:
		return count
	for place in _secret.size():
		if _secret[place] != 0 and pieces.is_opened(place):
			count += 1
	return count


## True when bridge `bridge` is drawn: a seen room at one end, and both its rooms ones the map may
## draw (a secret room only once found, however it was seen).
func _bridge_drawn(bridge: int) -> bool:
	var a: int = _ends[bridge * 2]
	var b: int = _ends[bridge * 2 + 1]
	return (_level(a) >= SHOWN or _level(b) >= SHOWN) and _may_draw(a) and _may_draw(b)


## True when room `room` may be drawn for a bridge leading to it: seen, or no secret room still
## hidden (its rock not broken).
func _may_draw(room: int) -> bool:
	if room < 0 or room >= _rects.size():
		return false
	if _secret[room] == 0:
		return true
	# A secret room only once found, as `draws` (shown by `map_reveal` is not found).
	return _level(room) >= ENTERED or (pieces != null and pieces.is_opened(room))


## True when the map draws room `place`'s symbol now (seen, or led to by a drawn bridge).
func draws_symbol(place: int) -> bool:
	if place < 0 or place >= _rects.size() or _room[place] == 0 or _symbols[place].is_empty():
		return false
	if _secret[place] != 0 and (pieces == null or not pieces.is_opened(place)):
		# A secret room's symbol only once it is discovered (its rock broken; the owner, #888).
		return false
	if _secret[place] != 0:
		# Found: drawn with its room, however it is reached (a rune's has no bridge to draw it for).
		return true
	if _level(place) >= SHOWN:
		return true
	for other in _rects.size():
		if _room[other] == 0 and draws(other) and (_ends[other * 2] == place or _ends[other * 2 + 1] == place):
			return true
	return false


## Once a frame, `delta` real seconds on: the biome read again when a new one is laid (`grid`), each of
## this machine's seats (`seats_here`) held or not, each opening stepped at FPS, and each open map put
## inside its seat's view's cell of `views` (the screen's views now), its wizards from `table`.
func step(delta: float, table: ActorsScript, seats_here: int, grid: RoomGrid, views: ScreenViewsScript) -> void:
	var places: int = grid.places() if grid != null else 0
	var world_now: int = pieces.world() if pieces != null else 0
	if places != _laid_places or world_now != _laid_world:
		_lay(grid, places, world_now)
	var found: int = _secrets_found()
	if found != _found_secrets:
		# A secret room found draws it for its bridge, so no seat senses it any more (the review's).
		_found_secrets = found
		_sensed_stale = true
	var again: int = pieces.done_again() if pieces != null else 0
	if again != _read_again:
		# The rooms done (cleared, opened, rewards left, fountains) told again after a restore: drawn as
		# they stand, a secret room's symbol found or lost by it too.
		_read_again = again
		for place in _done.size():
			_done[place] = _done_wanted(place)
			if _secret[place] != 0:
				_symbol_rows[place] = _rows_wanted(place)
	for seat in ActorsScript.SEATS:
		_held[seat] = 1 if not _rects.is_empty() and seats_here & (1 << seat) != 0 and _holds(seat) else 0
	if not _any_open():
		_unsettled = true
	_clock += delta
	var change: float = 1.0 / FPS
	if not is_moving():
		_clock = 0.0
	while _clock >= change:
		_clock -= change
		advance()
	_read_wizards(table)
	for seat in ActorsScript.SEATS:
		_place(seat, views)
		_tell_frame(seat)


## Tell the HUD seat `seat`'s frame and whether it is fully open (`map_frame_shown`), as it changes.
func _tell_frame(seat: int) -> void:
	var shown: bool = _maps[seat].visible
	var frame: Rect2i = _frame[seat] if shown else Rect2i()
	var open: int = 1 if shown and _stage[seat] >= OPEN_STAGES else 0
	if frame == _told_frame[seat] and open == _told_open[seat]:
		return
	_told_frame[seat] = frame
	_told_open[seat] = open
	if _events != null:
		# Told in the picture's pixels: the frame is laid out in layout pixels, on a layer drawn at
		# the picture's scale (PictureGrid).
		var by: int = roundi(transform.get_scale().x)
		_events.map_frame_shown.emit(seat, Rect2i(frame.position * by, frame.size * by), open == 1)


## True while an opening still opens or closes, or a piece's look still changes on an open map.
func is_moving() -> bool:
	for seat in ActorsScript.SEATS:
		if _stage[seat] != _stage_wanted(seat) or _pick_stage[seat] != _pick_wanted(seat) or (_pick[seat] != _pick_next[seat] and _pick_wanted_next(seat) > 0):
			return true
	if _any_open():
		for place in _shade.size():
			if _shade[place] != _shade_wanted(place) or _in[place] != _in_wanted(place) or _symbol_rows[place] != _rows_wanted(place) or _done[place] != _done_wanted(place):
				return true
		for at in _sense_shade.size():
			if _sense_shade[at] != _sense_wanted(at):
				return true
	return false


## One stage of every opening and every piece's look (a frame at FPS).
func advance() -> void:
	# A map opening steps from the looks settled now, as a frame of it shut settled them.
	_settled()
	for seat in ActorsScript.SEATS:
		_stage[seat] += signi(_stage_wanted(seat) - _stage[seat])
		if _stage[seat] == 0:
			_reopen[seat] = 0
		if _pick_stage[seat] == 0 and _pick[seat] != _pick_next[seat]:
			_pick[seat] = _pick_next[seat]
		_pick_stage[seat] += signi(_pick_wanted(seat) - _pick_stage[seat])
	for place in _shade.size():
		_shade[place] += signi(_shade_wanted(place) - _shade[place])
		_in[place] += signi(_in_wanted(place) - _in[place])
		_symbol_rows[place] += signi(_rows_wanted(place) - _symbol_rows[place])
		_done[place] += signi(_done_wanted(place) - _done[place])
	for at in _sense_shade.size():
		_sense_shade[at] += signi(_sense_wanted(at) - _sense_shade[at])


## The sensed shade wanted at `at` (seat * places + place).
func _sense_wanted(at: int) -> int:
	if _sensed_stale:
		_sensed_stale = false
		var places: int = _rects.size()
		_sensed.resize(places * ActorsScript.SEATS)
		for each in _sensed.size():
			_sensed[each] = SENSED_STAGES if senses(each / places, each % places) else 0
	return _sensed[at] if at < _sensed.size() else 0


## A picked room's outline is drawn while its map is open, the room is one of the map's and no
## other room is picked next (then it steps out first).
func _pick_wanted(seat: int) -> int:
	if _pick[seat] != _pick_next[seat]:
		return 0
	return _pick_wanted_next(seat)


func _pick_wanted_next(seat: int) -> int:
	var room: int = _pick_next[seat]
	return PICK_STAGES if _stage[seat] > 0 and room >= 0 and room < _rects.size() else 0


func _stage_wanted(seat: int) -> int:
	return OPEN_STAGES if _held[seat] != 0 and _reopen[seat] == 0 else 0


func _shade_wanted(place: int) -> int:
	if not draws(place):
		return 0
	if _room[place] == 0:
		return 2
	return 3 if _level(place) >= ENTERED else 1


## Whole once the party's map draws it (its sense alone draws a secret room whole, in its own shades).
func _in_wanted(place: int) -> int:
	return IN_STAGES if draws(place) else 0


func _rows_wanted(place: int) -> int:
	return RoomKind.SYMBOL_SIDE if draws_symbol(place) else 0


func _done_wanted(place: int) -> int:
	if _tells_done[place] == 0 or pieces == null or not pieces.is_done(place):
		return 0
	return KindSymbolScript.DONE_STAGES


func _any_open() -> bool:
	for seat in ActorsScript.SEATS:
		if _stage[seat] > 0:
			return true
	return false


## True while every map is shut and the pieces' looks wait to be settled when read (for tests).
func waits_to_settle() -> bool:
	return _unsettled


## The pieces' looks settled if they wait to be (`_unsettled`).
func _settled() -> void:
	if _unsettled:
		_unsettled = false
		_settle()


## Every piece's look as it stands (with every map shut, nothing is seen changing).
func _settle() -> void:
	for place in _shade.size():
		_shade[place] = _shade_wanted(place)
		_in[place] = _in_wanted(place)
		_symbol_rows[place] = _rows_wanted(place)
		_done[place] = _done_wanted(place)
	for at in _sense_shade.size():
		_sense_shade[at] = _sense_wanted(at)


## Seat `seat` holds the map's button, and no menu of its holds its input (its builder's Y is its own).
func _holds(seat: int) -> bool:
	if input == null:
		return false
	return not input.is_captured(seat) and input.is_held(seat, ACTION)


func _level(room: int) -> int:
	return _seen[room] if room >= 0 and room < _seen.size() else 0


func _read_wizards(table: ActorsScript) -> void:
	for seat in ActorsScript.SEATS:
		_wizard_at[seat] = Vector2.INF
		if table == null:
			continue
		var id: int = table.home_of_seat(seat)
		var body := table.node_of(id) as Node2D
		if body != null and is_instance_valid(body) and body.is_inside_tree():
			_wizard_at[seat] = body.global_position
			_wizard_colour[seat] = ProjectileManagerScript.ramp_color(table.ramp_of(id))


## Seat `seat`'s frame put in its view's cell, as far open as its stage (hidden while shut).
func _place(seat: int, views: ScreenViewsScript) -> void:
	var map: SeatMap = _maps[seat]
	if _stage[seat] <= 0 or views == null or views.count <= 0:
		map.visible = false
		return
	var view: int = views.view_of_seat(seat)
	if view < 0 and views.count == 1:
		view = 0
	if view < 0:
		# No view holds the seat (its wizard is not in the world): never over another player's view.
		map.visible = false
		_stage[seat] = 0
		return
	var content: Vector2 = (_area.size / MAP_CELL).ceil()
	var want: Vector2 = content + Vector2(PAD, PAD) * 2.0
	var fit: float = fit_scale(views, view, views.anchor[view], want, float(MAX_SCALE))
	var scale: int = maxi(floori(fit), 1)
	var size: Vector2i = Vector2i(want * scale) if fit >= 1.0 else Vector2i((want * fit).floor())
	var was: Rect2i = _frame[seat]
	if map.visible and (size != was.size or scale != _scale[seat]):
		# Moving (its anchor and the camera's zoom shift a little every frame) never closes it: it
		# keeps its size while the split is the same and it still fits its cell where it stands now.
		# Only a split changed under it, or a cell it no longer fits, closes it at the size it has to
		# open again at the new one.
		var same_split: bool = views.count == _laid_views[seat] and view == _laid_view[seat]
		if not (same_split and _fits_at(views, view, views.anchor[view], Vector2(was.size))):
			_reopen[seat] = 1
		size = was.size
		scale = _scale[seat]
	elif not map.visible:
		_laid_views[seat] = views.count
		_laid_view[seat] = view
	if size.x <= PAD * 2 or size.y <= PAD * 2:
		map.visible = false
		_stage[seat] = 0
		return
	var corner: Vector2i = Vector2i((views.anchor[view] - Vector2(size) * 0.5).round())
	_frame[seat] = Rect2i(corner, size)
	_scale[seat] = scale
	# The map's corner in its frame: centred, or, cut by a small frame, round the seat's wizard.
	var origin := Vector2(PAD, PAD)
	if fit < 1.0 and _wizard_at[seat] != Vector2.INF:
		var wizard: Vector2 = (_wizard_at[seat] - _area.position) / MAP_CELL
		origin = (Vector2(size) * 0.5 - wizard).round()
		origin.x = clampf(origin.x, float(size.x - PAD) - content.x, float(PAD))
		origin.y = clampf(origin.y, float(size.y - PAD) - content.y, float(PAD))
	_origin[seat] = origin
	# Open from its middle row out.
	var tall: int = maxi((size.y * _stage[seat]) / OPEN_STAGES, 2)
	var top: int = (size.y - tall) / 2
	map.position = Vector2(corner.x, corner.y + top)
	map.size = Vector2(size.x, tall)
	map.top = top
	map.visible = true
	map.queue_redraw()


## The most `want` (screen pixels) may be scaled by, up to `most`, and still lie, centred on `anchor`,
## inside view `view`'s cell of `views`, EDGE pixels in (0 when even a point does not).
static func fit_scale(views: ScreenViewsScript, view: int, anchor: Vector2, want: Vector2, most: float) -> float:
	if _fits(views, view, anchor, want * most):
		return most
	var low: float = 0.0
	var high: float = most
	for _try in 16:
		var middle: float = (low + high) * 0.5
		if _fits(views, view, anchor, want * middle):
			low = middle
		else:
			high = middle
	return low


## True when a frame of `size` (screen pixels), centred on `anchor`, still lies inside view `view`'s
## cell (no margin: a frame kept open may come to its edge, never past it).
static func _fits_at(views: ScreenViewsScript, view: int, anchor: Vector2, size: Vector2) -> bool:
	var half: Vector2 = size * 0.5
	return views.cell_holds(view, anchor - half, 0.0) and views.cell_holds(view, anchor + Vector2(half.x, -half.y), 0.0) \
		and views.cell_holds(view, anchor + half, 0.0) and views.cell_holds(view, anchor + Vector2(-half.x, half.y), 0.0)


static func _fits(views: ScreenViewsScript, view: int, anchor: Vector2, size: Vector2) -> bool:
	var half: Vector2 = size * 0.5
	return views.cell_holds(view, anchor - half, -EDGE) and views.cell_holds(view, anchor + Vector2(half.x, -half.y), -EDGE) \
		and views.cell_holds(view, anchor + half, -EDGE) and views.cell_holds(view, anchor + Vector2(-half.x, half.y), -EDGE)


## Draw seat `seat`'s map on `canvas` (its frame, opened as far as its stage: its top `top` rows hidden).
func draw_map(canvas: SeatMap, seat: int) -> void:
	var size: Vector2 = Vector2(_frame[seat].size)
	var shift := Vector2(0.0, -canvas.top)
	# Its dark field with no frame round it, its corners cut by a pixel (ART4, the owner, 2026-11-27:
	# "The border is too much"; the HUD's menus are drawn the same way).
	canvas.draw_rect(Rect2(shift + Vector2(1.0, 0.0), size - Vector2(2.0, 0.0)), Palette.OUTLINE)
	canvas.draw_rect(Rect2(shift + Vector2(0.0, 1.0), size - Vector2(0.0, 2.0)), Palette.OUTLINE)
	var scale: int = _scale[seat]
	var origin: Vector2 = _origin[seat] + shift
	var places: int = _rects.size()
	for place in places:
		if not _drawn(seat, place):
			continue
		var colour: Color = drawn_colour(seat, place)
		var at: Vector2 = origin + ((_rects[place].position - _area.position) / MAP_CELL).floor() * scale
		var texture: ImageTexture = _floors[place]
		var stage: int = _in[place]
		if _shade[place] > 0 and stage > 0 and stage < IN_STAGES and texture != null:
			texture = (_floors_in[stage - 1] as Array)[place] as ImageTexture
		if texture != null:
			canvas.draw_texture_rect(texture, Rect2(at, texture.get_size() * scale), false, colour)
	for place in _rects.size():
		if _symbol_rows[place] > 0:
			var middle: Vector2 = origin + ((_rects[place].get_center() - _area.position) / MAP_CELL).floor() * scale
			var half: float = float(RoomKind.SYMBOL_SIDE * scale / 2)
			KindSymbolScript.draw(canvas, _symbols[place], _symbol_shades[place], middle - Vector2(half, half), _symbol_rows[place], scale, RoomKind.SYMBOL_SIDE, _done[place])
			if (_glyphs[place] as Array).size() > 0:
				RewardGlyphsScript.draw(canvas, _glyphs[place], _glyph_shades[place], glyphs_corner(middle, (_glyphs[place] as Array).size(), scale), true, _symbol_rows[place], scale)
	_draw_pick(canvas, seat, origin, scale)
	for wizard in ActorsScript.SEATS:
		if _wizard_at[wizard] == Vector2.INF:
			continue
		var side: int = DOT * scale
		var dot: Vector2 = origin + ((_wizard_at[wizard] - _area.position) / MAP_CELL).floor() * scale - Vector2(side / 2, side / 2)
		canvas.draw_rect(Rect2(dot - Vector2(1, 1), Vector2(side + 2, side + 2)), Palette.OUTLINE)
		canvas.draw_rect(Rect2(dot, Vector2(side, side)), _wizard_colour[wizard])


## Seat `seat`'s picked room's outline on `canvas` at its stage (the class doc's PICK_STAGES): a screen
## pixel outside the room's box on the map, in the seat's own colour over the dark outline's edge.
func _draw_pick(canvas: SeatMap, seat: int, origin: Vector2, scale: int) -> void:
	var stage: int = _pick_stage[seat]
	var room: int = _pick[seat]
	if stage <= 0 or room < 0 or room >= _rects.size():
		return
	var corner: Vector2 = origin + ((_rects[room].position - _area.position) / MAP_CELL).floor() * scale - Vector2(2, 2)
	var size: Vector2 = (_rects[room].size / MAP_CELL).ceil() * scale + Vector2(4, 4)
	var colour: Color = _wizard_colour[seat]
	if stage >= PICK_STAGES:
		_frame_rect(canvas, Rect2(corner - Vector2.ONE, size + Vector2(2, 2)), Palette.OUTLINE)
		_frame_rect(canvas, Rect2(corner, size), colour)
		_frame_rect(canvas, Rect2(corner + Vector2.ONE, size - Vector2(2, 2)), Palette.OUTLINE)
		return
	var arm: float = 1.0 if stage == 1 else float(mini(BRACKET * scale, int(minf(size.x, size.y) * 0.5)))
	for x in 2:
		for y in 2:
			var at: Vector2 = corner + Vector2(size.x - 1.0 if x == 1 else 0.0, size.y - 1.0 if y == 1 else 0.0)
			var across := Vector2(-arm + 1.0 if x == 1 else 0.0, 0.0)
			var down := Vector2(0.0, -arm + 1.0 if y == 1 else 0.0)
			canvas.draw_rect(Rect2(at + across, Vector2(arm, 1.0)), colour)
			canvas.draw_rect(Rect2(at + down, Vector2(1.0, arm)), colour)


## A one-pixel frame round `rect`, by four filled rectangles (whole pixels, never a stroked line).
static func _frame_rect(canvas: Control, rect: Rect2, colour: Color) -> void:
	canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1.0)), colour)
	canvas.draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - 1.0), Vector2(rect.size.x, 1.0)), colour)
	canvas.draw_rect(Rect2(rect.position, Vector2(1.0, rect.size.y)), colour)
	canvas.draw_rect(Rect2(rect.position + Vector2(rect.size.x - 1.0, 0.0), Vector2(1.0, rect.size.y)), colour)


## A new biome's pieces as the map draws them: each place's floor read from `grid` at MAP_CELL (once a
## biome), its walkway's rooms and its room's symbol.
func _lay(grid: RoomGrid, places: int, world_now: int) -> void:
	_laid_places = places
	_laid_world = world_now
	_rects.clear()
	_floors.clear()
	_floors_in.clear()
	for stage in IN_STAGES - 1:
		_floors_in.append([])
	_in.resize(places)
	_symbols.clear()
	_symbol_shades.clear()
	_glyphs.clear()
	_glyph_shades.clear()
	_room.resize(places)
	_secret.resize(places)
	_sense_shade.resize(places * ActorsScript.SEATS)
	_sense_shade.fill(0)
	_sensed_stale = true
	_shade.resize(places)
	_symbol_rows.resize(places)
	_tells_done.resize(places)
	_done.resize(places)
	_done.fill(0)
	_read_again = pieces.done_again() if pieces != null else 0
	_ends.resize(places * 2)
	_ends.fill(-1)
	_area = Rect2()
	for place in places:
		var rect: Rect2 = grid.place_rect(place)
		_rects.append(rect)
		_area = rect if place == 0 else _area.merge(rect)
		_room[place] = 0 if pieces != null and pieces.is_walkway(place) else 1
		_floors.append(floor_of(grid, place))
		for stage in IN_STAGES - 1:
			(_floors_in[stage] as Array).append(thinned(_floors[place], stage + 1))
		var kind: RoomKind = pieces.kind_of(place) if pieces != null and _room[place] != 0 else null
		_secret[place] = 1 if KindSymbolScript.hidden_until_opened(kind) else 0
		_tells_done[place] = 1 if KindSymbolScript.shows_done(kind) else 0
		_symbols.append(kind.symbol_pixels() if kind != null else PackedByteArray())
		_symbol_shades.append(KindSymbolScript.shades_of(kind))
		var type: RewardType = pieces.type_of(place) if kind != null else null
		var glyphs: Array[PackedByteArray] = []
		var glyph_shades: Array[PackedColorArray] = []
		RewardGlyphsScript.glyphs_of(type, pieces.content(RewardGlyphsScript.card_folder(), type.element) if type != null else null, glyphs, glyph_shades)
		_glyphs.append(glyphs)
		_glyph_shades.append(glyph_shades)
	for place in places:
		if _room[place] != 0 or pieces == null:
			continue
		# Its real ends, as Flow put them on its layout (a room merely touching it is none of them:
		# the review's, 2026-11-20).
		for end in 2:
			_ends[place * 2 + end] = pieces.end_room(place, end)
	# A biome laid is drawn as it stands, every map shut (a new world opens nothing already open).
	_stage.fill(0)
	_reopen.fill(0)
	for map in _maps:
		map.visible = false
	_settle()
	for map in _maps:
		map.queue_redraw()


## The corner of a row of `count` reward glyphs under a room's symbol centred on `middle` (screen
## pixels), `scale` screen pixels a map pixel: centred, a glyph's gap under the symbol, whole pixels.
static func glyphs_corner(middle: Vector2, count: int, scale: int) -> Vector2:
	var half_symbol: int = RoomKind.SYMBOL_SIDE * scale / 2
	var width: int = RewardGlyphsScript.row_width(count) * scale
	return middle + Vector2(-(width / 2), RoomKind.SYMBOL_SIDE * scale - half_symbol + RewardGlyphsScript.GAP * scale)


## Place `place`'s floor on `grid` as a white mask, a pixel a MAP_CELL square (open ground of the
## place: no wall, no hole), or null when it has none.
## `texture` (a floor, `floor_of`) at coming-in stage `stage` (1 to IN_STAGES - 1): stage 1 only its
## pixels at even columns of even rows (a quarter), stage 2 those whose column and row add up even
## (half, the quarter among them). Null for none.
static func thinned(texture: ImageTexture, stage: int) -> ImageTexture:
	if texture == null:
		return null
	var image: Image = texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			var kept: bool = (x % 2 == 0 and y % 2 == 0) if stage <= 1 else (x + y) % 2 == 0
			if not kept:
				image.set_pixel(x, y, Color.TRANSPARENT)
	return ImageTexture.create_from_image(image)


## The stage place `place`'s shape is drawn at (0 none ... IN_STAGES whole; for tests).
func in_stage_of(place: int) -> int:
	_settled()
	return _in[place] if place >= 0 and place < _in.size() else 0


static func floor_of(grid: RoomGrid, place: int) -> ImageTexture:
	var rect: Rect2 = grid.place_rect(place)
	var w: int = ceili(rect.size.x / MAP_CELL)
	var h: int = ceili(rect.size.y / MAP_CELL)
	if w <= 0 or h <= 0:
		return null
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var any: bool = false
	for y in h:
		for x in w:
			var at: Vector2 = rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * MAP_CELL
			if grid.place_at(at) == place and (grid.cell_at(at) & RoomGrid.ROOM_CELL) == 0 and not grid.is_hole(at):
				image.set_pixel(x, y, Color.WHITE)
				any = true
	return ImageTexture.create_from_image(image) if any else null
