extends RefCounted
## The world's stirs (docs/milestones/atmosphere.md, E: "a world that notices"): what the shots and
## the blasts do to the air round them, for the things that take notice of it to read: the room's
## lights duck and lean (`spot_stirs.gd`), the ground cover sways (`cover.gdshader`) and the dust in
## the air and in the shafts is pushed (`mote.gdshader`, a kind's `MoteKind.stirred`). One source,
## stepped once a frame by the spectacle (`step`); none of the readers looks for shots or blasts
## itself, and this knows nothing of who reads it. View only: Feel's clock, nothing of the game's.
##
## - **The shots' wake** (`field`): a grid of CELL px cells over a window round the view (FIELD_W x
##   FIELD_H, moved with the view by whole cells, what it holds moved with it), each cell the way the
##   air there is dragged (a vector, at most 1 long). The shots are read from their tail births (the
##   projectile manager's `spark_births`, which Feel throws as their tails' motes in any case: points
##   along every flying shot's path since the last frame and the way back along it, thinned fairly
##   by staff in a crowd), at most BIRTHS_READ a frame (every few in a flood): each drags its cell
##   along its way by PASS_PUSH. What a cell shows eases to what it is dragged to at most SHOWN_RATE
##   a second (at least 4 frames from still to full) and the drag dies away by halves every
##   WAKE_HALF seconds, so nothing pops when a shot comes or goes. It is handed to the shaders as a
##   small texture (`texture`, the window's FIELD_W x FIELD_H, read with bilinear filtering).
## - **The blasts** (`blast`): up to BLASTS at once (an explosion's two parts are one), each a push
##   wave running out from its middle at WAVE_SPEED px a second to BLAST_REACH times its radius plus
##   BLAST_PAD, a place it passes pushed out over RISE seconds, then swaying back past rest and
##   settling over FALL (`blast_push`, `blast_envelope`): worked out from its age by the shaders
##   (`stir.gdshaderinc`) and here alike, so it is smooth on Feel's clock with nothing stepped.
## - **The shots near a point** (`shots_near`): the births read this frame, filed by cell, so the
##   room's few lights find the shots passing close (and which side) without looking at every shot.
##
## **Off** (`enabled`, the "Environment interaction" setting): no shot is read and no blast starts,
## so what was stirred eases back to rest as it would with no shots (a frame's share at a time, the
## blasts under way running out) and every reader is then handed a still field.
##
## Nothing is allocated a frame: every array is sized once. The texture's image is written only
## where a cell changed, and handed over only when one did.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## A cell of the wake, in world px, and the window's cells (1,536 x 1,024 px: the widest view, the
## party camera zoomed out to its MIN_ZOOM 0.5, 1,280 x 720, and a margin round it, so a shot just off
## screen still drags what is on it and no cell on screen is let go as the window moves).
const CELL: float = 16.0
const FIELD_W: int = 96
const FIELD_H: int = 64
## The most births read a frame (past it, every few: `stride`), and how much each drags its cell
## (times the births it stands for).
const BIRTHS_READ: int = 256
const PASS_PUSH: float = 0.2
## How fast what a cell shows follows its drag (a second; 1 is full), and how fast the drag dies
## away (its half life, s). Below FADED a cell is still again.
const SHOWN_RATE: float = 12.0
const WAKE_HALF: float = 0.18
const FADED: float = 0.004
## The blasts at once, how far one pushes (times its radius, plus a pad, px), how fast its wave
## runs out (px/s), how long a place takes to be pushed out and to sway back and settle (s), and the
## radius from which a blast pushes its fullest (smaller ones push less, to at least BLAST_LEAST).
const BLASTS: int = 16
const BLAST_REACH: float = 2.5
const BLAST_PAD: float = 24.0
const WAVE_SPEED: float = 260.0
const RISE: float = 0.08
const FALL: float = 0.6
const BLAST_FULL: float = 24.0
const BLAST_LEAST: float = 0.4
## Two blasts this near (px) and in the same frame (s apart at most) are one (an explosion's shell and
## fireball, shown together).
const SAME_PLACE: float = 6.0
const SAME_TIME: float = 0.001

## The wake's texture (FIELD_W x FIELD_H, red and green the way a cell is dragged), its window's
## corner in world px, and how many times anything handed to a shader changed (`hand_to`). Read only.
var texture: ImageTexture = null
var origin: Vector2 = Vector2.ZERO
var version: int = 0
## How many births were read last frame (for tests and the benchmark).
var read: int = 0
## Whether the shots and the blasts stir anything (the "Environment interaction" setting; see the
## top). Off, `step` reads no birth and `blast` starts nothing.
var enabled: bool = true

## The window's corner cell, and its image.
var _corner: Vector2i = Vector2i.ZERO
var _image: Image = null
## Each cell's drag and what it shows (FIELD_W * FIELD_H), the cells that are not still (`_live`,
## `_live_count`; `_is_live` a byte a cell), and a spare pair the window's move fills.
var _wake: PackedVector2Array = PackedVector2Array()
var _shown: PackedVector2Array = PackedVector2Array()
var _spare_wake: PackedVector2Array = PackedVector2Array()
var _spare_shown: PackedVector2Array = PackedVector2Array()
var _live: PackedInt32Array = PackedInt32Array()
var _live_count: int = 0
var _is_live: PackedByteArray = PackedByteArray()
var _spare_live: PackedInt32Array = PackedInt32Array()
## The image changed since it was last handed over.
var _image_dirty: bool = false
## The births read this frame: where, the way the shot flies, and each cell's first (-1: none) and
## each one's next in its cell.
var _point_at: PackedVector2Array = PackedVector2Array()
var _point_way: PackedVector2Array = PackedVector2Array()
var _point_next: PackedInt32Array = PackedInt32Array()
var _point_cell: PackedInt32Array = PackedInt32Array()
var _cell_first: PackedInt32Array = PackedInt32Array()
var _points: int = 0
## The blasts (by slot): middle and reach (x, y, reach, Feel's clock at its start), and how strongly
## it pushes (0: none in the slot).
var _blasts: PackedVector4Array = PackedVector4Array()
var _blast_strength: PackedFloat32Array = PackedFloat32Array()
## The two pairs of copies the blasts are handed to the shaders in, in turn (`_sent` the one handed
## last, copied at the `version` `_sent_version`), so the working arrays are never held by a material
## and a write never copies one (as cover.gd's bodies).
var _send_blasts: Array[PackedVector4Array] = []
var _send_strength: Array[PackedFloat32Array] = []
var _sent: int = 0
var _sent_version: int = -1
## Feel's clock at the last step.
var _now: float = 0.0


func _init() -> void:
	var cells: int = FIELD_W * FIELD_H
	_wake.resize(cells)
	_shown.resize(cells)
	_spare_wake.resize(cells)
	_spare_shown.resize(cells)
	_live.resize(cells)
	_spare_live.resize(cells)
	_is_live.resize(cells)
	_cell_first.resize(cells)
	_cell_first.fill(-1)
	_point_at.resize(BIRTHS_READ)
	_point_way.resize(BIRTHS_READ)
	_point_next.resize(BIRTHS_READ)
	_point_cell.resize(BIRTHS_READ)
	_blasts.resize(BLASTS)
	_blast_strength.resize(BLASTS)
	for pair in 2:
		var blasts := PackedVector4Array()
		blasts.resize(BLASTS)
		_send_blasts.append(blasts)
		var strength := PackedFloat32Array()
		strength.resize(BLASTS)
		_send_strength.append(strength)
	# Half floats: filtered on every renderer (32-bit float textures need an extension to filter on
	# WebGL 2 and GLES 3).
	_image = Image.create_empty(FIELD_W, FIELD_H, false, Image.FORMAT_RGH)
	texture = ImageTexture.create_from_image(_image)


## A blast at `at` of `radius` px (an explosion's part; Feel's `show_flash`), at Feel's clock `now`:
## its push wave runs out from there. A second part of the same explosion (as near, as soon) makes
## it no stronger, only as big as the bigger. With all BLASTS pushing, a new one is let go: taking a
## live one's slot would snap its push back.
func blast(at: Vector2, radius: float, now: float) -> void:
	if not enabled or not at.is_finite() or not (radius > 0.0):
		return
	var reach: float = radius * BLAST_REACH + BLAST_PAD
	var strength: float = clampf(radius / BLAST_FULL, BLAST_LEAST, 1.0)
	for slot in BLASTS:
		var held: Vector4 = _blasts[slot]
		if _blast_strength[slot] > 0.0 and absf(now - held.w) <= SAME_TIME and Vector2(held.x, held.y).distance_to(at) <= SAME_PLACE:
			_blasts[slot] = Vector4(held.x, held.y, maxf(held.z, reach), held.w)
			_blast_strength[slot] = maxf(_blast_strength[slot], strength)
			version += 1
			return
	# A slot whose blast is over; none: the new one is let go.
	var slot: int = -1
	for k in BLASTS:
		if _blast_strength[k] <= 0.0 or now - _blasts[k].w >= blast_seconds(_blasts[k].z):
			slot = k
			break
	if slot < 0:
		return
	_blasts[slot] = Vector4(at.x, at.y, reach, now)
	_blast_strength[slot] = strength
	version += 1


## How long a blast reaching `reach` px pushes anything (its wave out to its edge, and the sway).
static func blast_seconds(reach: float) -> float:
	return reach / WAVE_SPEED + RISE + FALL


## How far out a place is pushed `age` seconds after a blast's wave reached it (0 to 1, below 0 as
## it sways back past rest): out over RISE, then back, a little past and still over FALL. The
## shader's `stir_envelope`, line for line.
static func blast_envelope(age: float) -> float:
	if age <= 0.0:
		return 0.0
	if age < RISE:
		var r: float = age / RISE
		return r * r * (3.0 - 2.0 * r)
	var t: float = minf((age - RISE) / FALL, 1.0)
	return (1.0 - t) * (1.0 - t) * cos(t * PI * 1.5)


## The blasts' push at `point` at Feel's clock `now`: the way out from each blast that reaches it,
## as strong as it is there (nearer its middle more), added, the sum at most 1 long (blasts side by
## side push no further than one). The shader's `stir_blasts_at`, line for line.
func blast_push(point: Vector2, now: float) -> Vector2:
	var push := Vector2.ZERO
	for slot in BLASTS:
		var strength: float = _blast_strength[slot]
		if strength <= 0.0:
			continue
		var held: Vector4 = _blasts[slot]
		var away := Vector2(point.x - held.x, point.y - held.y)
		var far: float = away.length()
		if far >= held.z or far < 0.5:
			continue
		var age: float = now - held.w - far / WAVE_SPEED
		push += away / far * (strength * (1.0 - far / held.z) * blast_envelope(age))
	var most: float = push.length()
	return push / most if most > 1.0 else push


## Once a frame, at Feel's clock `now`, with the view `view` (world px; empty: left where it is): the
## window moved with the view, the wake dragged by `count` births of `births` (the projectile
## manager's `spark_births`; SPARK_BIRTH_STRIDE floats each) and eased, and the blasts that are over
## let go.
func step(now: float, births: PackedFloat32Array, count: int, view: Rect2) -> void:
	var delta: float = clampf(now - _now, 0.0, 0.25)
	_now = now
	if view.has_area():
		_follow(view)
	_read(births, count if enabled else 0)
	_ease(delta)
	for slot in BLASTS:
		if _blast_strength[slot] > 0.0 and now - _blasts[slot].w >= blast_seconds(_blasts[slot].z):
			_blast_strength[slot] = 0.0
			version += 1
	if _image_dirty:
		_image_dirty = false
		texture.update(_image)


## The window's corner cell for the view `view`: the view in its middle.
static func corner_for(view: Rect2) -> Vector2i:
	var middle: Vector2 = view.get_center() / CELL
	return Vector2i(floori(middle.x) - FIELD_W / 2, floori(middle.y) - FIELD_H / 2)


func _follow(view: Rect2) -> void:
	var corner: Vector2i = corner_for(view)
	if corner == _corner:
		return
	var shift: Vector2i = corner - _corner
	_corner = corner
	origin = Vector2(corner) * CELL
	version += 1
	# What each live cell holds, moved to its place in the moved window (gone past its edge).
	_spare_wake.fill(Vector2.ZERO)
	_spare_shown.fill(Vector2.ZERO)
	_is_live.fill(0)
	_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var kept: int = 0
	for n in _live_count:
		var cell: int = _live[n]
		var x: int = cell % FIELD_W - shift.x
		var y: int = cell / FIELD_W - shift.y
		if x < 0 or x >= FIELD_W or y < 0 or y >= FIELD_H:
			continue
		var to: int = y * FIELD_W + x
		_spare_wake[to] = _wake[cell]
		_spare_shown[to] = _shown[cell]
		_is_live[to] = 1
		_spare_live[kept] = to
		_image.set_pixel(x, y, Color(_shown[cell].x, _shown[cell].y, 0.0, 0.0))
		kept += 1
	var wake: PackedVector2Array = _wake
	_wake = _spare_wake
	_spare_wake = wake
	var shown: PackedVector2Array = _shown
	_shown = _spare_shown
	_spare_shown = shown
	var live: PackedInt32Array = _live
	_live = _spare_live
	_spare_live = live
	_live_count = kept
	_image_dirty = true


## The window's cell holding `point` (-1: outside).
func cell_of(point: Vector2) -> int:
	var x: int = floori(point.x / CELL) - _corner.x
	var y: int = floori(point.y / CELL) - _corner.y
	return y * FIELD_W + x if x >= 0 and x < FIELD_W and y >= 0 and y < FIELD_H else -1


func _read(births: PackedFloat32Array, count: int) -> void:
	for n in _points:
		_cell_first[_point_cell[n]] = -1
	_points = 0
	count = mini(count, births.size() / ProjectilesScript.SPARK_BIRTH_STRIDE)
	var stride: int = maxi(ceili(float(count) / float(BIRTHS_READ)), 1)
	var push: float = PASS_PUSH * float(stride)
	var n: int = 0
	while n < count:
		var i: int = n * ProjectilesScript.SPARK_BIRTH_STRIDE
		n += stride
		var way := Vector2(-births[i + ProjectilesScript.SPARK_BACK_X], -births[i + ProjectilesScript.SPARK_BACK_Y])
		if way.length_squared() < 0.25:
			continue
		var at := Vector2(births[i + ProjectilesScript.SPARK_X], births[i + ProjectilesScript.SPARK_Y])
		var cell: int = cell_of(at)
		if cell < 0:
			continue
		way = way.normalized()
		_wake[cell] = (_wake[cell] + way * push).limit_length(1.0)
		_wake_live(cell)
		_point_at[_points] = at
		_point_way[_points] = way
		_point_next[_points] = _cell_first[cell]
		_point_cell[_points] = cell
		_cell_first[cell] = _points
		_points += 1
		if _points >= BIRTHS_READ:
			break
	read = _points


func _wake_live(cell: int) -> void:
	if _is_live[cell] == 0:
		_is_live[cell] = 1
		_live[_live_count] = cell
		_live_count += 1


## Every live cell's drag dying away and what it shows following it; a cell still again leaves the list.
func _ease(delta: float) -> void:
	if _live_count == 0:
		return
	var fade: float = pow(0.5, delta / WAKE_HALF)
	var most: float = SHOWN_RATE * delta
	var kept: int = 0
	for n in _live_count:
		var cell: int = _live[n]
		var shown: Vector2 = _shown[cell].move_toward(_wake[cell], most)
		var wake: Vector2 = _wake[cell] * fade
		if wake.length_squared() < FADED * FADED and shown.length_squared() < FADED * FADED:
			wake = Vector2.ZERO
			shown = Vector2.ZERO
			_is_live[cell] = 0
		else:
			_live[kept] = cell
			kept += 1
		_wake[cell] = wake
		if shown != _shown[cell]:
			_shown[cell] = shown
			_image.set_pixel(cell % FIELD_W, cell / FIELD_W, Color(shown.x, shown.y, 0.0, 0.0))
			_image_dirty = true
	_live_count = kept


## What the cell holding `point` shows (the way it is dragged; zero outside the window).
func shown_at_cell(point: Vector2) -> Vector2:
	var cell: int = cell_of(point)
	return _shown[cell] if cell >= 0 else Vector2.ZERO


## The wake at `point` as the shaders read it (`stir_wake`: the cells round it, bilinear; zero
## outside the window).
func wake_at(point: Vector2) -> Vector2:
	var at: Vector2 = (point - origin) / CELL - Vector2(0.5, 0.5)
	if at.x < -0.5 or at.y < -0.5 or at.x > float(FIELD_W) - 0.5 or at.y > float(FIELD_H) - 0.5:
		return Vector2.ZERO
	var x0: int = clampi(floori(at.x), 0, FIELD_W - 1)
	var y0: int = clampi(floori(at.y), 0, FIELD_H - 1)
	var x1: int = mini(x0 + 1, FIELD_W - 1)
	var y1: int = mini(y0 + 1, FIELD_H - 1)
	var fx: float = clampf(at.x - float(x0), 0.0, 1.0)
	var fy: float = clampf(at.y - float(y0), 0.0, 1.0)
	var top: Vector2 = _shown[y0 * FIELD_W + x0].lerp(_shown[y0 * FIELD_W + x1], fx)
	var bottom: Vector2 = _shown[y1 * FIELD_W + x0].lerp(_shown[y1 * FIELD_W + x1], fx)
	return top.lerp(bottom, fy)


## How the shots read this frame pass `point` within `reach` px: the way away from them (each, unit,
## weighted by how near it is, added) in x and y, and how near the nearest is in z (1 on it, 0 at
## `reach` or none).
func shots_near(point: Vector2, reach: float) -> Vector3:
	if _points == 0 or not (reach > 0.0):
		return Vector3.ZERO
	var away := Vector2.ZERO
	var nearest: float = 0.0
	var x0: int = floori((point.x - reach) / CELL) - _corner.x
	var x1: int = floori((point.x + reach) / CELL) - _corner.x
	var y0: int = floori((point.y - reach) / CELL) - _corner.y
	var y1: int = floori((point.y + reach) / CELL) - _corner.y
	for y in range(maxi(y0, 0), mini(y1, FIELD_H - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, FIELD_W - 1) + 1):
			var n: int = _cell_first[y * FIELD_W + x]
			while n >= 0:
				var off: Vector2 = point - _point_at[n]
				var far: float = off.length()
				if far < reach:
					var near: float = 1.0 - far / reach
					nearest = maxf(nearest, near)
					# Right on its line: away to its side (its left), not nowhere.
					var side: Vector2 = off / far if far > 0.5 else _point_way[n].orthogonal()
					away += side * near
				n = _point_next[n]
	return Vector3(away.x, away.y, nearest)


## Hand everything the shaders read (`stir.gdshaderinc`) to `material`: the wake's texture and its
## window, and the blasts.
func hand_to(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"stir_field", texture)
	material.set_shader_parameter(&"stir_origin", origin)
	if _sent_version != version:
		_sent_version = version
		_sent = 1 - _sent
		var blasts: PackedVector4Array = _send_blasts[_sent]
		var strength: PackedFloat32Array = _send_strength[_sent]
		# Taken out while they are written, so the writes are in place.
		_send_blasts[_sent] = PackedVector4Array()
		_send_strength[_sent] = PackedFloat32Array()
		for slot in BLASTS:
			blasts[slot] = _blasts[slot]
			strength[slot] = _blast_strength[slot]
		_send_blasts[_sent] = blasts
		_send_strength[_sent] = strength
	material.set_shader_parameter(&"stir_blasts", _send_blasts[_sent])
	material.set_shader_parameter(&"stir_strength", _send_strength[_sent])


## How many cells are not still (for tests).
func live_cells() -> int:
	return _live_count


## How many blasts push now (for tests).
func blast_count() -> int:
	var live: int = 0
	for slot in BLASTS:
		if _blast_strength[slot] > 0.0:
			live += 1
	return live


## Everything still again: no wake, no blasts (a new room: `Spectacle.use_room`).
func clear() -> void:
	_wake.fill(Vector2.ZERO)
	_shown.fill(Vector2.ZERO)
	_is_live.fill(0)
	_live_count = 0
	_blast_strength.fill(0.0)
	_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	_image_dirty = true
	version += 1
