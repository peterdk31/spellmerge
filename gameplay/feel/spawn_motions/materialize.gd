extends "res://gameplay/feel/spawn_motions/spawn_motion.gd"
## The motion `materialize` (spawn styles AS3, docs/milestones/spawn-styles.md, "How it is built"; the
## owner, 2026-11-18: "materialize in from nothing, a cool sci-fi look"): the body is built up out of
## light, row by row, by whole pixels, with no fade, no blur and no glow gradient (docs/STYLE.md,
## "Smooth" and "Light and shading"). Its stages, in frames at `SpawnStyle.CHECK_FPS` from the end of
## the mark (`timings`):
##
## - **The pad** (the mark stage, the look's): the mark in the style's colours, its rim running round
##   it from the top, clockwise, as it grows (`rim_share`). The body is not drawn.
## - **The scan:** a 1-pixel line in the light shade of the style's colours, as wide as the mark,
##   sweeps up from the lowest row of its art to its top (`line_row`). Behind it each row shows
##   **interlaced** by how long ago the line passed it (`row_stride`): every 4th row for `BAND_FRAMES`,
##   then every 2nd for as long, then all, so the body is a striped ghost filling in from the feet up.
##   It is built out of light: a row shown every 4th is the body's shape in the light shade, flat, one
##   shown every 2nd in the base shade, and then its own colours (`row_shade`), so it cools from the
##   line down as a mote cools, by whole steps, never a fade.
## - **The glitch:** while rows still fill, the body's parts are shifted sideways by whole pixels, 1
##   or 2 now and then (`glitch`), rolled from a hash of its actor id and the moment (Feel's own dice,
##   view only: the same on every machine and after a snapshot), settling to 0 in the last frames.
## - **The landing:** the line, at the top, goes out in 3 looks over `OUT_FRAMES` (narrower to a dot,
##   by whole pixels), the last rows fill, and the body stands whole for `TAIL_FRAMES` while the mark
##   closes; as it is whole the style's cue plays (`cue_share`: square sparks off the body).
##
## **The cut** is `rise`'s (spawn_motions/rise.gd): the body's root a clip parent whose own canvas item
## draws the mask, here one rect a band of shown rows (up to the body's height in rows), so it adds no
## render pass beyond `rise`'s. The light is two canvas items of the motion's under the body's (its
## children, drawn after its parts, so the same mask clips them: the line's row is in the mask): the
## line, and the lit rows (its body sprite's frame, those rows only, drawn flat in their shade by
## `flat.gdshader`, warmed before play), made when the body is first drawn and freed as it is put back.
## Its parts are shifted sideways only (the glitch), never down, and the lit rows with them. Nothing in
## the simulation reads any of it.
##
## Nothing here allocates while bodies spawn in: its dictionaries grow only when a body is first drawn.

const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
## Draws what it is given flat in its colour (the light's material).
const FLAT_SHADER: Shader = preload("res://gameplay/feel/spawn_motions/flat.gdshader")

## The frames a row shows every 4th, then every 2nd, behind the line, before it is whole.
const BAND_FRAMES: float = 4.0
## The frames the line goes out in, in 3 looks (each at least one frame at 60 fps).
const OUT_FRAMES: float = 4.5
## The frames the body stands whole at the end, the mark closing.
const TAIL_FRAMES: float = 3.0
## The least frames the line sweeps up in.
const SCAN_FRAMES: float = 6.0
## How long one glitch holds, in frames, and the most pixels it shifts by.
const GLITCH_FRAMES: float = 3.0
const GLITCH_MOST: int = 2
## The frames before the body is whole from which the glitch is at most 1, and none.
const SETTLE_ONE: float = 6.0
const SETTLE_NONE: float = 3.0
## The light's draw index under the body: after every part.
const LIGHT_INDEX: int = 1 << 20

## The bodies drawn (by instance id): the canvas items of each one's line and lit rows; and what each
## was drawn as at its last cut (the line's row, its width, the glitch and the rows shown), with a hash
## of the rows shown.
var _line: Dictionary[int, RID] = {}
var _lit: Dictionary[int, RID] = {}
var _drawn: Dictionary[int, Vector4i] = {}
var _rows_hash: Dictionary[int, int] = {}
## The light's material: one for the game, made with the first motion and kept.
static var _flat: ShaderMaterial = null


func _init() -> void:
	if _flat == null:
		_flat = ShaderMaterial.new()
		_flat.shader = FLAT_SHADER
	ShaderWarmupScript.want(FLAT_SHADER, ShaderWarmupScript.RECT)


## Where its stages hand over, in frames from the mark's end, for `style`: the scan's end (the line at
## the top), the moment the body is whole, and the motion's whole length.
static func timings(style: SpawnStyle) -> Vector3:
	var length: float = style.motion_stage_frames()
	var whole: float = maxf(length - TAIL_FRAMES, 0.0)
	var scan_end: float = maxf(whole - 2.0 * BAND_FRAMES, minf(SCAN_FRAMES, whole))
	return Vector3(scan_end, whole, length)


## Frames since the mark's end at `share` of the spawn as `style` times it (below 0: still the mark).
static func frame_of(share: float, style: SpawnStyle) -> float:
	if share < style.mark_end:
		return -1.0
	return (share - style.mark_end) / (1.0 - style.mark_end) * style.motion_stage_frames()


## The share of the spawn `frames` after the mark's end.
static func share_at(frames: float, style: SpawnStyle) -> float:
	var length: float = style.motion_stage_frames()
	if length <= 0.0:
		return 1.0
	return style.mark_end + (1.0 - style.mark_end) * frames / length


## How row `row` (0 its art's lowest, of `rows`) shows at `frame` with the scan ending at `scan_end`: 0
## not yet (the line has not passed it), 4 (shown if it is every 4th row), 2 (every 2nd) or 1 (shown).
static func row_stride(row: int, rows: int, frame: float, scan_end: float) -> int:
	var age: float = frame - scan_end * float(row) / float(maxi(rows, 1))
	if frame < 0.0 or age < 0.0:
		return 0
	if age < BAND_FRAMES:
		return 4
	if age < 2.0 * BAND_FRAMES:
		return 2
	return 1


static func row_shown(row: int, rows: int, frame: float, scan_end: float) -> bool:
	var stride: int = row_stride(row, rows, frame, scan_end)
	return stride > 0 and row % stride == 0


## Which shade a row shown with `stride` is drawn in: 0 the light (every 4th), 1 the base (every
## 2nd), -1 its own colours.
static func row_shade(stride: int) -> int:
	if stride == 4:
		return 0
	if stride == 2:
		return 1
	return -1


## The row the line is on at `frame` (-1: none, before the scan and once it is out).
static func line_row(rows: int, frame: float, scan_end: float) -> int:
	if frame < 0.0 or frame >= scan_end + OUT_FRAMES or rows <= 0:
		return -1
	return mini(floori(frame / maxf(scan_end, 0.001) * float(rows)), rows - 1)


## The line's width at `frame`, for art `width` pixels wide: all of it while it sweeps, then two
## thirds, a third and a dot as it goes out, then none.
static func line_width(width: int, frame: float, scan_end: float) -> int:
	if frame < 0.0:
		return 0
	if frame < scan_end:
		return width
	var look: int = floori((frame - scan_end) / (OUT_FRAMES / 3.0))
	match look:
		0:
			return maxi(roundi(float(width) * 2.0 / 3.0), 3)
		1:
			return maxi(roundi(float(width) / 3.0), 2)
		2:
			return 1
	return 0


## The sideways shift of the body of actor id `seed` at `frame` while it fills (whole pixels, at most
## `GLITCH_MOST`): mostly 0, now and then 1 or 2 either way, held `GLITCH_FRAMES`, at most 1 from
## `SETTLE_ONE` frames before it is whole (`whole`) and 0 from `SETTLE_NONE`.
static func glitch(seed: int, frame: float, whole: float) -> int:
	var left: float = whole - frame
	if frame < 0.0 or left < SETTLE_NONE:
		return 0
	var most: int = 1 if left < SETTLE_ONE else GLITCH_MOST
	var roll: int = hash(Vector2i(maxi(seed, 0), floori(frame / GLITCH_FRAMES))) & 15
	var by: int = 0
	if roll >= 13:
		by = 2
	elif roll >= 9:
		by = 1
	if roll & 1 == 1:
		by = -by
	return clampi(by, -most, most)


## Its stage's least frames (`SpawnStyle.MOTION_FRAMES` holds the same): the scan's, the two
## interlaced sets' and the tail.
func least_frames() -> int:
	return ceili(SCAN_FRAMES + 2.0 * BAND_FRAMES + TAIL_FRAMES)


func cue_share(style: SpawnStyle) -> float:
	return share_at(timings(style).y, style)


## The rim runs round as the mark grows, a step each of its frames.
func rim_share(share: float, style: SpawnStyle) -> float:
	if share >= style.mark_end or share < 0.0:
		return 1.0
	var k: int = mini(floori(share / style.mark_end * style.mark_frames), style.mark_frames - 1)
	return float(k + 1) / float(style.mark_frames)


func stages(style: SpawnStyle) -> PackedFloat32Array:
	var at: Vector3 = timings(style)
	return PackedFloat32Array([0.0, style.mark_end, share_at(at.x, style), share_at(at.y, style)])


## One spawning body drawn at `share`: its shown rows (and the line's) as the mask, its lit rows and
## its line drawn, its parts shifted by the glitch.
func apply(body: Actor, share: float, style: SpawnStyle) -> void:
	var key: int = body.get_instance_id()
	var item: RID = body.get_canvas_item()
	var line: RID = _line.get(key, RID())
	var lit_rows: RID = _lit.get(key, RID())
	# Every frame: another look putting the body back (a fresh look's) must not leave it uncut.
	body.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	if not line.is_valid():
		line = _light_item(item)
		lit_rows = _light_item(item)
		_line[key] = line
		_lit[key] = lit_rows
	var size: float = maxf(absf(body.size), 0.01)
	var bottom: float = body_bottom(body)
	var rows: int = roundi(height_of(body, key) + bottom)
	var at: Vector3 = timings(style)
	var frame: float = frame_of(share, style)
	var shift: int = glitch(body.id, frame, at.y)
	var by := Vector2(float(shift) / size, 0.0)
	shift_parts(body, by)
	RenderingServer.canvas_item_clear(item)
	RenderingServer.canvas_item_clear(line)
	RenderingServer.canvas_item_clear(lit_rows)
	var sprite := body.get_node_or_null(^"Sprite") as Sprite2D
	if sprite != null and sprite.texture == null:
		sprite = null
	if sprite != null:
		RenderingServer.canvas_item_set_transform(lit_rows, sprite.get_transform().translated(by))
	var shade: PackedColorArray = shades.call(style) if shades.is_valid() else PackedColorArray()
	if shade.size() < 2:
		shade = PackedColorArray([Palette.WHITE_HOT, Palette.WHITE_HOT])
	var lit: int = line_row(rows, frame, at.x)
	var hashed: int = 0
	var shown: int = 0
	if frame >= at.y:
		# Whole: everything above its lowest row's line, as `rise` stands.
		RenderingServer.canvas_item_add_rect(item, mask_rect(bottom, size), Color.WHITE)
		shown = rows
		hashed = -1
	else:
		# The mask always draws (a clip parent that draws nothing clips nothing): through the mark a
		# clear rect, so nothing of the body shows.
		RenderingServer.canvas_item_add_rect(item, mask_rect(bottom, size), Color(1.0, 1.0, 1.0, 0.0))
		var run_from: int = -1
		for row in rows + 1:
			var stride: int = row_stride(row, rows, frame, at.x) if row < rows else 0
			var in_set: bool = stride > 0 and row % stride == 0
			if row < rows and in_set:
				shown += 1
				hashed = (hashed * 31 + row + 1) & 0x7fffffff
				if run_from < 0:
					run_from = row
				var tone: int = row_shade(stride) if in_set else -1
				if tone >= 0 and sprite != null:
					_light_row(lit_rows, sprite, row, bottom, size, shade[tone])
			elif run_from >= 0:
				_add_rows(item, run_from, row, bottom, size)
				run_from = -1
			if row == lit and not in_set:
				shown += 1
				hashed = (hashed * 31 + row + 1) & 0x7fffffff
	var width: int = 0
	if lit >= 0:
		var full: int = maxi(roundi(body.wall_radius()), 2)
		width = line_width(2 * full + 1, frame, at.x)
		if width > 0:
			var left: float = float(-full) + floorf(float(2 * full + 1 - width) / 2.0)
			var y: float = bottom - float(lit) - 1.0
			var bar := Rect2(left / size, y / size, float(width) / size, 1.0 / size)
			RenderingServer.canvas_item_add_rect(line, bar, shade[0])
			# The line's row is in the mask only as wide as the line, so no art shows past its ends.
			if not row_shown(lit, rows, frame, at.x):
				RenderingServer.canvas_item_add_rect(item, bar, Color.WHITE)
	_drawn[key] = Vector4i(lit if width > 0 else -1, width, shift, shown)
	_rows_hash[key] = hashed


## A canvas item of the light under the body's canvas item `parent`: drawn after its parts, flat.
func _light_item(parent: RID) -> RID:
	var light: RID = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(light, parent)
	RenderingServer.canvas_item_set_draw_index(light, LIGHT_INDEX)
	RenderingServer.canvas_item_set_material(light, _flat.get_rid())
	return light


## The mask's rect of rows `from` up to (not with) `to`, at its lowest row's line `bottom` pixels below
## the feet, in the body's own pixels.
static func _add_rows(item: RID, from: int, to: int, bottom: float, size: float) -> void:
	var top: float = bottom - float(to)
	RenderingServer.canvas_item_add_rect(item, Rect2(-MASK_HALF_WIDTH, top / size, 2.0 * MASK_HALF_WIDTH, float(to - from) / size), Color.WHITE)


## Row `row` (0 the lowest of its art, whose line is `bottom` pixels below the feet) of `sprite`'s
## frame as it is drawn now, in `colour`, flat, into `light` (drawn where the sprite is: its
## transform), when the sprite has that row.
static func _light_row(light: RID, sprite: Sprite2D, row: int, bottom: float, size: float, colour: Color) -> void:
	var place: Rect2 = lit_place(sprite, row, bottom, size)
	if place.size.y <= 0.0:
		return
	var rect: Rect2 = sprite.get_rect()
	var source := Rect2(Vector2.ZERO, sprite.texture.get_size())
	if sprite.region_enabled:
		source = sprite.region_rect
	var frame_size: Vector2 = source.size / Vector2(maxi(sprite.hframes, 1), maxi(sprite.vframes, 1))
	var frame_at: Vector2 = source.position + frame_size * Vector2(sprite.frame_coords)
	var cut := Rect2(frame_at.x, frame_at.y + place.position.y - rect.position.y, frame_size.x, place.size.y)
	RenderingServer.canvas_item_add_texture_rect_region(light, place, sprite.texture.get_rid(), cut, colour)


## Where row `row` of `sprite`'s frame is drawn, in the sprite's own pixels (no height: it has no such
## row). A flipped sprite's has a negative width at the same place, as Sprite2D draws one (the
## renderer flips the texture).
static func lit_place(sprite: Sprite2D, row: int, bottom: float, size: float) -> Rect2:
	var rect: Rect2 = sprite.get_rect()
	var down: float = sprite.scale.y if sprite.scale.y != 0.0 else 1.0
	# The row's top and bottom in the sprite's own pixels.
	var top: float = ((bottom - float(row) - 1.0) / size - sprite.position.y) / down
	var foot: float = ((bottom - float(row)) / size - sprite.position.y) / down
	var from: float = maxf(minf(top, foot), rect.position.y)
	var to: float = minf(maxf(top, foot), rect.end.y)
	if to <= from:
		return Rect2()
	var place := Rect2(rect.position.x, from, rect.size.x, to - from)
	if sprite.flip_h:
		place.size.x = -place.size.x
	return place


## The body spawns in no more (or went): its parts' own transforms back, no clip parent any more, and
## its light freed.
func put_back(key: int, body: Actor) -> void:
	if body != null:
		body.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
		RenderingServer.canvas_item_clear(body.get_canvas_item())
		shift_parts(body, Vector2.ZERO)
	for light: RID in [_line.get(key, RID()), _lit.get(key, RID())]:
		if light.is_valid():
			RenderingServer.free_rid(light)
	_line.erase(key)
	_lit.erase(key)
	_drawn.erase(key)
	_rows_hash.erase(key)
	forget(key)


## What it drew `body` as at its last cut: the line's row (-1: none), its width, the glitch, the rows
## shown and a hash of which (empty: not drawn; tests).
func look_of(body: Actor) -> PackedInt32Array:
	var key: int = body.get_instance_id()
	if not _drawn.has(key):
		return PackedInt32Array()
	var drawn: Vector4i = _drawn[key]
	return PackedInt32Array([drawn.x, drawn.y, drawn.z, drawn.w, _rows_hash[key]])


## For how many bodies it keeps a line (tests).
func lines_kept() -> int:
	return _line.size()
