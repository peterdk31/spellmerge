extends RefCounted
## Where bodies part a room's mist (docs/milestones/atmosphere.md, F): a grid of the room, a cell
## CELL px (bigger in a room wider than MOST_CELLS of them), each cell how far the mist there is
## parted (0 to 1). Each frame the feet handed over (`step`: a short list, the bodies the ground cover
## already gathers near the camera's middle, `Cover.bodies`) part the cells within REACH of them (an
## oval, flatter than wide: the floor seen from above), and a cell left behind closes again:
## what a cell shows opens toward its parting at most OPEN_RATE a second (5 frames from closed to
## open, so a body that comes never pops a hole) and closes at CLOSE_RATE (over about 1.2 s), so a
## wizard walking through leaves a short trail closing behind it. Handed to `mist.gdshader` as a small
## R8 texture (filtered on every renderer), written only where a cell changed.
##
## Only the cells that are not closed are walked (`_live`); every array is sized when a room is laid
## (`lay`), never a frame. View only, Feel's clock.

## A cell (px) and the most cells a side.
const CELL: float = 8.0
const MOST_CELLS: int = 256
## How far a body parts the mist round its feet (px; across, and up and down), and how far below its
## position its feet are (px).
const REACH: float = 13.0
const REACH_DOWN: float = 7.0
const FEET_DROP: float = 2.0
## How fast a cell opens toward its parting and closes again (a second; 1 is all the way).
const OPEN_RATE: float = 12.0
const CLOSE_RATE: float = 0.85
## Below this a cell is closed.
const CLOSED: float = 0.004

## The grid's texture (`width` x `height` cells, red how far each is parted) and how many px a cell
## is. Read only.
var texture: ImageTexture = null
var cell: float = CELL
## Where the grid's first cell begins (world px): the room's place. Read only.
var origin: Vector2 = Vector2.ZERO
var width: int = 0
var height: int = 0

var _image: Image = null
## How far each cell should be parted this frame, how far it is, and the cells not closed (`_live`,
## `_live_count`, `_is_live` a byte a cell).
var _wanted: PackedFloat32Array = PackedFloat32Array()
var _shown: PackedFloat32Array = PackedFloat32Array()
var _live: PackedInt32Array = PackedInt32Array()
var _is_live: PackedByteArray = PackedByteArray()
var _live_count: int = 0
var _dirty: bool = false


## The grid for a room of `size` px from `at` (world px, its place): every cell closed.
func lay(size: Vector2, at: Vector2 = Vector2.ZERO) -> void:
	origin = at
	cell = maxf(CELL, ceilf(maxf(size.x, size.y) / float(MOST_CELLS)))
	width = maxi(ceili(size.x / cell), 1)
	height = maxi(ceili(size.y / cell), 1)
	var cells: int = width * height
	_wanted.resize(cells)
	_wanted.fill(0.0)
	_shown.resize(cells)
	_shown.fill(0.0)
	_live.resize(cells)
	_is_live.resize(cells)
	_is_live.fill(0)
	_live_count = 0
	_image = Image.create_empty(width, height, false, Image.FORMAT_R8)
	if texture != null and texture.get_width() == width and texture.get_height() == height:
		texture.update(_image)
	else:
		texture = ImageTexture.create_from_image(_image)
	_dirty = false


## The px the grid covers (`width` x `height` cells).
func size() -> Vector2:
	return Vector2(float(width), float(height)) * cell


## Once a frame, `delta` s after the last: the mist parted round the first `count` of `feet` (bodies'
## positions, world px) and every cell eased toward it; the texture updated when a cell changed.
## `work` then `upload`.
func step(delta: float, feet: PackedVector2Array, count: int) -> void:
	work(delta, feet, count)
	upload()


## `step`'s part on this grid's own arrays and picture, which may run on a worker thread
## (`feel_jobs.gd`): it touches no texture, no node and nothing another grid holds.
func work(delta: float, feet: PackedVector2Array, count: int) -> void:
	if _image == null:
		return
	delta = clampf(delta, 0.0, 0.25)
	for n in _live_count:
		_wanted[_live[n]] = 0.0
	for k in mini(count, feet.size()):
		_part(feet[k] + Vector2(0.0, FEET_DROP) - origin)
	var opens: float = OPEN_RATE * delta
	var closes: float = CLOSE_RATE * delta
	var kept: int = 0
	for n in _live_count:
		var at: int = _live[n]
		var was: float = _shown[at]
		var wanted: float = _wanted[at]
		var now: float = minf(was + opens, wanted) if wanted > was else maxf(was - closes, wanted)
		if now < CLOSED and wanted <= 0.0:
			now = 0.0
			_is_live[at] = 0
		else:
			_live[kept] = at
			kept += 1
		if now != was:
			_shown[at] = now
			_image.set_pixel(at % width, at / width, Color(now, 0.0, 0.0, 1.0))
			_dirty = true
	_live_count = kept


## `step`'s part on the main thread, after `work`: the picture handed to the texture when a cell
## changed.
func upload() -> void:
	if _dirty and texture != null:
		_dirty = false
		texture.update(_image)


## Every cell within REACH of `foot` (the grid's px) wants to be parted as much as it is near.
func _part(foot: Vector2) -> void:
	if not foot.is_finite():
		return
	var x0: int = maxi(floori((foot.x - REACH) / cell), 0)
	var x1: int = mini(floori((foot.x + REACH) / cell), width - 1)
	var y0: int = maxi(floori((foot.y - REACH_DOWN) / cell), 0)
	var y1: int = mini(floori((foot.y + REACH_DOWN) / cell), height - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var off := Vector2((float(x) + 0.5) * cell - foot.x, ((float(y) + 0.5) * cell - foot.y) * REACH / REACH_DOWN)
			var near: float = 1.0 - off.length() / REACH
			if near <= 0.0:
				continue
			var at: int = y * width + x
			# Full well inside its reach, easing out at its rim.
			near = minf(near * 2.0, 1.0)
			_wanted[at] = maxf(_wanted[at], near)
			if _is_live[at] == 0:
				_is_live[at] = 1
				_live[_live_count] = at
				_live_count += 1


## How far the cell holding `point` (world px) is parted (0 outside the grid).
func parted_at(point: Vector2) -> float:
	var x: int = floori((point.x - origin.x) / cell)
	var y: int = floori((point.y - origin.y) / cell)
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0.0
	return _shown[y * width + x]


## The picture's bytes as `work` left them (for tests: the texture's own copy is the renderer's).
func picture_data() -> PackedByteArray:
	return _image.get_data() if _image != null else PackedByteArray()


## How many cells are not closed (for tests).
func live_cells() -> int:
	return _live_count


## Every cell closed at once (a new room).
func clear() -> void:
	if _image == null:
		return
	_wanted.fill(0.0)
	_shown.fill(0.0)
	_is_live.fill(0)
	_live_count = 0
	_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	texture.update(_image)
