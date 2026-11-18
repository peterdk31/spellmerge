class_name SpawnLook
extends Node2D
## The look of an enemy spawning (enemy spawning EA2, docs/milestones/enemy-spawning.md, "The look";
## spawn styles, docs/milestones/spawn-styles.md): first a mark grows on the floor where the body
## will stand, then the body comes out of it as its style's motion draws it. It is drawn from the
## body's state alone (`Actor.spawn_share`), never from a moment it was told of, so a machine that
## joins mid-spawn or a snapshot restored mid-spawn shows it where it is. Feel steps it once a
## frame (`step`: the marks and the cues) over the actor table's open bodies, as it does `FallLook`;
## the bodies are drawn by their motions just before the frame is drawn (`cut`, on
## `RenderingServer.frame_pre_draw`), after every `_process` and deferred call, so a body added
## after Feel's step (a run started as a load ends) is never drawn whole for a frame.
##
## **A style says the numbers** (`SpawnStyle`, content/spawn_styles/): where the stages hand over, the
## mark's frames and the cue. Feel hands the look a lookup of the styles by id (`style_of`, the
## registry's `spawn_styles`), and draws each body by its own (`Actor.spawn_style`, state, which Flow
## picked: `SpawnStyle.pick`, spawn styles AS2). An id it cannot find (a style missing on this machine,
## an old snapshot, a deleted folder) is drawn as `rise`, and with no `rise` as `SpawnStyle.DEFAULT`.
## **A motion draws the body** (`MOTIONS`, gameplay/feel/spawn_motions/: one object each, keyed by
## the names of `SpawnStyle.MOTIONS`; a test holds the two lists together): a motion it does not
## have is drawn as `rise`, so a body is never drawn whole mid-spawn. What every style shares is here:
##
## - **0 to `mark_end`, the mark:** a disc on the floor at the body's feet, as wide as its footprint,
##   a hole in the room's floor (`RoomBase.floor_colors`: its shadow, darkened; `use_room`) ringed by
##   a rim in the light shade of the style's `colours` (`shades_for`: the floor's own for `floor`,
##   else a palette material's, docs/STYLE.md), growing from a dot in `mark_frames` frames; the motion
##   says how far round its rim is drawn (`rim_share`: `materialize`'s runs round as it grows). A
##   style with a `mark_strip` (spawn styles AS4) has its art instead: its frames played in order
##   over the stage (`SpawnStyle.strip_frame`), drawn at whole pixels centred on the feet at a
##   whole-number scale that fits the footprint (`SpawnStyle.strip_scale`). The body is not drawn yet.
## - **`mark_end` to 1, the motion** (`rise`: the body comes up out of the mark, cut at its feet's
##   line, spawn_motions/rise.gd; `materialize`: built up out of light behind a scan line,
##   spawn_motions/materialize.gd). When the motion says (`cue_share`: `rise`'s as it starts,
##   `materialize`'s as it is whole) the style's cue plays at the body's feet (`rise`'s `enemy_spawn`:
##   dust off the mark, a soft sound): its sound at most every SOUND_EVERY seconds, so a group does
##   not stack it (the cue is played unweighted in between: its dust only). From `close_from` the mark
##   closes in `close_frames` frames as the feet land, down to a dot (a strip: its last frame held
##   till then, then `close_frames` of its frames backwards to its first), so the motion ends where
##   standing begins (docs/STYLE.md, "Smooth").
##
## View only. Nothing here allocates while bodies spawn in: its scratch of ids and marks is made once,
## and the dictionaries of the bodies it drew, whose cue it played, the styles it looked up and the
## materials' shades grow only when a body, a style or a material is first seen (and are walked only
## as one is done).

const ActorsScript := preload("res://core/actors/actors.gd")
const SpawnMotionScript := preload("res://gameplay/feel/spawn_motions/spawn_motion.gd")
const RiseScript := preload("res://gameplay/feel/spawn_motions/rise.gd")
const MaterializeScript := preload("res://gameplay/feel/spawn_motions/materialize.gd")

const VIEW_ONLY: bool = true

## The motions it draws, by the names of `SpawnStyle.MOTIONS` (the same names: a test checks).
const MOTIONS: Dictionary[StringName, Script] = {
	&"rise": RiseScript,
	&"materialize": MaterializeScript,
}
## The motion a style whose motion it does not have is drawn by.
const FALLBACK_MOTION: StringName = &"rise"
## How much darker than the floor's shadow the mark's inside is: a hole, read at a glance.
const MARK_DARKEN: float = 0.35
## The least seconds between two sounds of the cues it plays.
const SOUND_EVERY: float = 0.1
## The mark's colours with no room known (light, base, shadow).
const NO_FLOOR: PackedColorArray = [Color(0.55, 0.55, 0.6), Color(0.35, 0.35, 0.4), Color(0.2, 0.2, 0.24)]

## Plays a cue: (cue: StringName, at: Vector2, weighted: bool). Set by Feel; none plays nothing.
var play_cue: Callable = Callable()
## Finds a style by its id: (id: StringName) -> SpawnStyle, null for none. Set by Feel (the
## registry's `spawn_styles`); a style it does not find is `rise`'s, and with none of those (or no
## lookup) `SpawnStyle.DEFAULT`. Setting it forgets the styles looked up.
var style_of: Callable = Callable():
	set(value):
		style_of = value
		forget_styles()

## The open ids, scratch.
var _ids: PackedInt32Array = PackedInt32Array()
## The table `step` was last given (Feel's actor table), read again by `cut`.
var _table: ActorsScript = null
## One of each motion, by name.
var _motions: Dictionary[StringName, SpawnMotionScript] = {}
## The bodies drawn (by instance id), and the motion that drew each; and the bodies whose motion's
## cue was played.
var _cut: Dictionary[int, SpawnMotionScript] = {}
var _risen: Dictionary[int, bool] = {}
## The styles looked up, by id (a style not found is kept as `rise`'s or the default), and the default.
var _styles: Dictionary[StringName, SpawnStyle] = {}
var _default_style: SpawnStyle = SpawnStyle.from_default()
## This frame's marks: where (whole pixels), how wide (a strip's: half its drawn side), their fill and
## rim, how much of the rim is drawn (0 to 1, round from the top), and a strip's art, frame (-1: the
## ring) and scale; `_marks` of them are in use.
var _mark_at: PackedVector2Array = PackedVector2Array()
var _mark_radius: PackedInt32Array = PackedInt32Array()
var _mark_fill: PackedColorArray = PackedColorArray()
var _mark_rim: PackedColorArray = PackedColorArray()
var _mark_rim_share: PackedFloat32Array = PackedFloat32Array()
var _mark_strip: Array[Texture2D] = []
var _mark_frame: PackedInt32Array = PackedInt32Array()
var _mark_scale: PackedInt32Array = PackedInt32Array()
var _marks: int = 0
## How many marks the last draw drew (to clear them once when there are none).
var _drawn_marks: int = 0
## The room's floor's shades (light, base, shadow), and each palette material's a style named, by name.
var _floor_shades: PackedColorArray = NO_FLOOR
var _material_shades: Dictionary[StringName, PackedColorArray] = {}
## Real seconds since it started, and when a cue last sounded.
var _clock: float = 0.0
var _sounded_at: float = -INF


func _init() -> void:
	_ids.resize(ActorsScript.ACTORS)
	_mark_at.resize(ActorsScript.ACTORS)
	_mark_radius.resize(ActorsScript.ACTORS)
	_mark_fill.resize(ActorsScript.ACTORS)
	_mark_rim.resize(ActorsScript.ACTORS)
	_mark_rim_share.resize(ActorsScript.ACTORS)
	_mark_strip.resize(ActorsScript.ACTORS)
	_mark_frame.resize(ActorsScript.ACTORS)
	_mark_scale.resize(ActorsScript.ACTORS)
	var shades: Callable = shades_for
	for motion: StringName in MOTIONS:
		_motions[motion] = MOTIONS[motion].new() as SpawnMotionScript
		_motions[motion].shades = shades


func _ready() -> void:
	top_level = true


func _enter_tree() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(cut):
		RenderingServer.frame_pre_draw.connect(cut)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(cut):
		RenderingServer.frame_pre_draw.disconnect(cut)
	put_back_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		put_back_all()


## Every body it draws is put back by its motion now (the look leaves the tree or goes, mid-spawn):
## its own drawing back, and a motion's own canvas items freed.
func put_back_all() -> void:
	for key: int in _cut.keys():
		_cut[key].put_back(key, instance_from_id(key) as Actor)
	_cut.clear()


## The room played in now (null for none): a style of `floor` colours takes its floor's.
func use_room(room: RoomBase) -> void:
	var colours: PackedColorArray = room.floor_colors() if room != null else PackedColorArray()
	if colours.is_empty():
		colours = NO_FLOOR
	_floor_shades = PackedColorArray([colours[0], colours[mini(1, colours.size() - 1)], colours[mini(2, colours.size() - 1)]])


## The shades of `style`'s `colours` (light, base, shadow): the room's floor's for `floor` (and for a
## name the palette does not have), else the palette material's (docs/STYLE.md, "Palette").
func shades_for(style: SpawnStyle) -> PackedColorArray:
	if style.colours == SpawnStyle.FLOOR:
		return _floor_shades
	var shades: PackedColorArray = _material_shades.get(style.colours, PackedColorArray())
	if shades.is_empty():
		var palette: PackedColorArray = Palette.shades_of(style.colours)
		shades = PackedColorArray([palette[2], palette[1], palette[0]]) if palette.size() == 3 else _floor_shades
		_material_shades[style.colours] = shades
	return shades


## Forget the styles looked up, so each is looked up again: Feel calls it when its registry is set
## (a registry rescanned in place, `Registry.scan` or `add`, is not noticed; the game never does).
func forget_styles() -> void:
	_styles.clear()


## The style `body` spawns in in: its own (`Actor.spawn_style`), or `rise` for an id not found.
func style_for(body: Actor) -> SpawnStyle:
	return _style(body.spawn_style)


## The style of id `id`, looked up once (`style_of`); `rise` when there is none, and the default when
## there is no `rise` either.
func _style(id: StringName) -> SpawnStyle:
	var style: SpawnStyle = _styles.get(id)
	if style != null:
		return style
	if style_of.is_valid():
		style = style_of.call(id) as SpawnStyle
		if style == null and id != SpawnStyle.DEFAULT["id"]:
			style = _style(SpawnStyle.DEFAULT["id"])
	if style == null:
		style = _default_style
	_styles[id] = style
	return style


## The motion `style` is drawn by (`rise` for one it does not have).
func _motion_of(style: SpawnStyle) -> SpawnMotionScript:
	var motion: SpawnMotionScript = _motions.get(style.motion)
	return motion if motion != null else _motions[FALLBACK_MOTION]


## How wide the mark under a body whose footprint is `radius` pixels is at `share` of its spawn as
## `style` times it, in whole pixels (0: none): growing from a dot in its `mark_frames` frames by its
## `mark_end`, held, then closing from its `close_from` in its `close_frames` frames down to a dot.
static func mark_radius(radius: float, share: float, style: SpawnStyle) -> int:
	if share >= 1.0 or share < 0.0:
		return 0
	var full: int = maxi(roundi(radius), 2)
	if share < style.mark_end:
		var k: int = mini(floori(share / style.mark_end * style.mark_frames), style.mark_frames - 1)
		return roundi(lerpf(1.0, float(full), float(k) / float(style.mark_frames - 1)))
	if share < style.close_from:
		return full
	var j: int = mini(floori((share - style.close_from) / (1.0 - style.close_from) * style.close_frames), style.close_frames - 1)
	return maxi(roundi(lerpf(float(full), 1.0, float(j + 1) / float(style.close_frames))), 1)


## Lay out every spawning body of `table`'s mark, and play each one's style's cue once as its motion
## starts, as far through its spawn as it is; the bodies themselves are drawn by `cut`, just before
## the frame is drawn. `real_delta` is the frame's real seconds (the cue's sound is spaced by them).
func step(table: ActorsScript, real_delta: float) -> void:
	_table = table
	_clock += real_delta
	_marks = 0
	var rising: int = 0
	if table != null:
		var count: int = table.open_ids(_ids)
		for n in count:
			var body := table.node_of(_ids[n]) as Actor
			if body == null or not body.is_spawning() or not body.is_inside_tree():
				continue
			var style: SpawnStyle = style_for(body)
			var motion: SpawnMotionScript = _motion_of(style)
			var share: float = body.spawn_share()
			if share >= motion.cue_share(style):
				rising += 1
				var key: int = body.get_instance_id()
				if not _risen.has(key):
					_risen[key] = true
					_play_rise_cue(style.cue, body.global_position)
			if _marks < _mark_at.size():
				_lay_mark(body, share, style, motion)
	if _risen.size() > rising:
		_forget_risen()
	if _marks > 0 or _drawn_marks > 0:
		queue_redraw()


## Draw every spawning body of the table `step` was last given by its style's motion, and put back
## the bodies done. Called just before every frame is drawn (`RenderingServer.frame_pre_draw`), after
## every `_process` and deferred call, so a body added after Feel's step (a run started as a load
## ends) is never drawn whole for a frame; tests call it by hand.
func cut() -> void:
	var spawning: int = 0
	if _table != null and is_instance_valid(_table):
		var count: int = _table.open_ids(_ids)
		for n in count:
			var body := _table.node_of(_ids[n]) as Actor
			if body == null or not body.is_spawning() or not body.is_inside_tree():
				continue
			spawning += 1
			var style: SpawnStyle = style_for(body)
			var motion: SpawnMotionScript = _motion_of(style)
			var key: int = body.get_instance_id()
			var before: SpawnMotionScript = _cut.get(key)
			if before != motion:
				if before != null:
					before.put_back(key, body)
				_cut[key] = motion
			motion.apply(body, body.spawn_share(), style)
	if _cut.size() > spawning:
		_put_back()


## Lay `body`'s mark at `share` of its spawn as `style` says, if it has one now: its strip's frame,
## or the ring.
func _lay_mark(body: Actor, share: float, style: SpawnStyle, motion: SpawnMotionScript) -> void:
	var strip: Texture2D = style.mark_strip
	var frames: int = SpawnStyle.strip_frames(strip)
	if frames > 0:
		var frame: int = SpawnStyle.strip_frame(frames, share, style)
		if frame < 0:
			return
		var scale: int = SpawnStyle.strip_scale(strip.get_height(), body.wall_radius())
		_mark_radius[_marks] = strip.get_height() * scale / 2
		_mark_strip[_marks] = strip
		_mark_frame[_marks] = frame
		_mark_scale[_marks] = scale
	else:
		var radius: int = mark_radius(body.wall_radius(), share, style)
		if radius <= 0:
			return
		_mark_radius[_marks] = radius
		# A hole in the floor (its shadow darkened), ringed in the light shade of the style's colours.
		_mark_rim[_marks] = shades_for(style)[0]
		_mark_fill[_marks] = _floor_shades[2].darkened(MARK_DARKEN)
		_mark_rim_share[_marks] = motion.rim_share(share, style)
		_mark_strip[_marks] = null
		_mark_frame[_marks] = -1
		_mark_scale[_marks] = 0
	_mark_at[_marks] = body.global_position.round()
	_marks += 1


func _play_rise_cue(cue: StringName, at: Vector2) -> void:
	if not play_cue.is_valid() or cue == &"":
		return
	var weighted: bool = _clock - _sounded_at >= SOUND_EVERY
	if weighted:
		_sounded_at = _clock
	play_cue.call(cue, at, weighted)


## The bodies whose cue played that spawn in no more (or went) are forgotten.
func _forget_risen() -> void:
	for key: int in _risen.keys():
		var body := instance_from_id(key) as Actor
		if body == null or not body.is_spawning() or not body.is_inside_tree():
			_risen.erase(key)


## Every body drawn that spawns in no more (or went) is handed back to its motion to put back.
func _put_back() -> void:
	for key: int in _cut.keys():
		var body := instance_from_id(key) as Actor
		if body != null and body.is_spawning() and body.is_inside_tree():
			continue
		_cut[key].put_back(key, body)
		_cut.erase(key)


func _draw() -> void:
	_drawn_marks = _marks
	for m in _marks:
		if _mark_frame[m] >= 0:
			_draw_strip_mark(_mark_at[m], _mark_strip[m], _mark_frame[m], _mark_scale[m])
		else:
			_draw_mark(_mark_at[m], _mark_radius[m], _mark_fill[m], _mark_rim[m], _mark_rim_share[m])


## A mark `radius` pixels wide each way at `at` (radius 1: a dot), half as high (it lies on the floor),
## row by row in whole pixels: its inside in `fill`, its edge in `rim`, of which `rim_share` is drawn
## (round from the top, clockwise; the rest of the edge in the fill).
func _draw_mark(at: Vector2, radius: int, fill: Color, rim: Color, rim_share: float) -> void:
	var high: int = maxi(radius / 2, 0)
	for row in range(-high, high + 1):
		var across: float = 1.0 - (float(row) / float(high + 1)) ** 2 if high > 0 else 1.0
		var half: int = maxi(floori((float(radius) - 0.5) * sqrt(across)), 0)
		var y: float = at.y + float(row)
		var width: float = float(2 * half + 1)
		if rim_share < 1.0 and radius > 1:
			_draw_mark_row(at, row, half, fill, rim, rim_share, row == -high or row == high or half <= 1)
			continue
		if row == -high or row == high or half <= 1:
			draw_rect(Rect2(at.x - float(half), y, width, 1.0), rim)
			continue
		draw_rect(Rect2(at.x - float(half), y, 1.0, 1.0), rim)
		draw_rect(Rect2(at.x - float(half) + 1.0, y, width - 2.0, 1.0), fill)
		draw_rect(Rect2(at.x + float(half), y, 1.0, 1.0), rim)


## Frame `frame` of the strip `strip` (square frames side by side) drawn `scale` times its size,
## its centre on `at` (whole pixels): the top-left corner whole too, so every art pixel is
## `scale` screen pixels.
func _draw_strip_mark(at: Vector2, strip: Texture2D, frame: int, scale: int) -> void:
	var side: int = strip.get_height()
	var drawn: float = float(side * scale)
	draw_texture_rect_region(strip, Rect2(strip_corner(at, side, scale), Vector2(drawn, drawn)), Rect2(float(frame * side), 0.0, float(side), float(side)))


## The top-left corner of a strip frame `side` pixels square drawn `scale` times its size centred on
## `at` (whole pixels): whole pixels too, half its drawn side (rounded down) up and left.
static func strip_corner(at: Vector2, side: int, scale: int) -> Vector2:
	var half: float = float(side * scale / 2)
	return at - Vector2(half, half)


## One row of a mark whose rim is drawn only `rim_share` round, pixel by pixel on its edge (`edge`: the
## whole row is edge, its top or bottom).
func _draw_mark_row(at: Vector2, row: int, half: int, fill: Color, rim: Color, rim_share: float, edge: bool) -> void:
	var y: float = at.y + float(row)
	for dx in range(-half, half + 1):
		var on_edge: bool = edge or dx == -half or dx == half
		var colour: Color = fill
		if on_edge and fposmod(atan2(float(dx), -2.0 * float(row)), TAU) <= rim_share * TAU + 0.001:
			colour = rim
		draw_rect(Rect2(at.x + float(dx), y, 1.0, 1.0), colour)


## How many bodies it draws now (tests).
func drawn() -> int:
	return _cut.size()


## The motion of name `motion` it draws by (tests).
func motion_named(motion_name: StringName) -> SpawnMotionScript:
	return _motions.get(motion_name)


## The `rise` motion's: the `size_top` it keeps for `body` (NAN: none), for how many bodies it keeps
## one, how far below its feet `body`'s mask reached and how far below its place it was drawn at its
## last cut (-1: not cut; tests).
func size_top_kept(body: Actor) -> float:
	return _motions[&"rise"].size_top_kept(body)


func size_tops_kept() -> int:
	return _motions[&"rise"].size_tops_kept()


func bottom_of(body: Actor) -> float:
	return (_motions[&"rise"] as RiseScript).bottom_of(body)


func shift_of(body: Actor) -> float:
	return (_motions[&"rise"] as RiseScript).shift_of(body)


func marks() -> int:
	return _marks


## The mark `n` of this frame: where and how wide (tests).
func mark(n: int) -> Vector3:
	return Vector3(_mark_at[n].x, _mark_at[n].y, float(_mark_radius[n]))


## The mark `n` of this frame's strip frame (-1: the ring), its scale, and its strip (tests).
func mark_frame(n: int) -> int:
	return _mark_frame[n]


func mark_scale(n: int) -> int:
	return _mark_scale[n]


func mark_strip(n: int) -> Texture2D:
	return _mark_strip[n]


## The mark `n` of this frame's fill and rim colours, and how much of its rim is drawn (tests).
func mark_fill(n: int) -> Color:
	return _mark_fill[n]


func mark_rim(n: int) -> Color:
	return _mark_rim[n]


func mark_rim_share(n: int) -> float:
	return _mark_rim_share[n]
