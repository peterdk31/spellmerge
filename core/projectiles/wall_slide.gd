class_name WallSlide
extends RefCounted
## A body's move against the wall grid (online-ready N6, docs/milestones/online-ready.md): a circle
## of `radius` moved by `motion` from `from`, sliding along the walls it meets, the same to the bit
## on every machine. It replaces Godot's `move_and_slide`, whose solver is the engine's and not
## guaranteed the same across platforms and builds. The projectile manager owns the wall grid
## (room walls and solid shots, one byte a `cell`-pixel square from `origin`, 0 for open) and asks
## this through `ProjectileManager.slide_body`; the native module's `BodyKernel` does the same in
## C++ (native/README.md), and `tests/core/test_wall_slide.gd` compares the two to the bit.
##
## **How:** the move is cut into strides of at most half the radius (MIN_STRIDE at least, half a
## cell at most), so a body never crosses into a wall in one stride however fast it goes. After
## each stride the body is pushed out of the walls it overlaps, the deepest first, up to ITERATIONS
## times: out along the line from the nearest point of the cell to its centre, so it slides along a
## flat wall and rounds an outer corner. A centre inside a wall cell is that cell's alone: it leaves
## by the cell's nearest side that opens onto an open cell (or out of the grid), never into another
## wall, and stays where it is in a cell with walls all round. Pushing out of only
## the deepest cell each time keeps the seams between two cells of one wall from snagging. A cell
## the circle only touches is not overlapped. Outside the grid is open, as it was for the physics
## bodies (a room's walls close it). A move with no wall cell near its whole way is `from + motion`.
##
## Everything is worked out in doubles from the inputs (a GDScript float is a double; a Vector2
## single precision), in this order; the C++ mirrors it line by line.

## How many pushes out of the walls a stride gets at most (the deepest overlap each time).
const ITERATIONS: int = 4
## The shortest stride, in pixels (a body of a tiny radius still moves in steps of this).
const MIN_STRIDE: float = 1.0
## The sides of a cell a centre in it leaves by (`_exit`).
const NO_EXIT: int = -1
const LEFT: int = 0
const RIGHT: int = 1
const UP: int = 2
const DOWN: int = 3


## Where a circle of `radius` at `from` ends after moving by `motion` against the wall grid `cells`
## (`w` by `h` cells of `cell` pixels, its corner at `origin`; a cell is a wall when it is not 0).
static func slide(cells: PackedByteArray, w: int, h: int, cell: float, origin: Vector2, from: Vector2, motion: Vector2, radius: float) -> Vector2:
	var px: float = from.x
	var py: float = from.y
	var mx: float = motion.x
	var my: float = motion.y
	var r: float = maxf(radius, 0.0)
	var ox: float = origin.x
	var oy: float = origin.y
	if cells.size() < w * h or not _near(cells, w, h, cell, ox, oy, minf(px, px + mx) - r, minf(py, py + my) - r, maxf(px, px + mx) + r, maxf(py, py + my) + r):
		return Vector2(px + mx, py + my)
	var length: float = sqrt(mx * mx + my * my)
	var stride: float = clampf(r * 0.5, MIN_STRIDE, cell * 0.5)
	var strides: int = maxi(ceili(length / stride), 1)
	var sx: float = mx / float(strides)
	var sy: float = my / float(strides)
	for _s in strides:
		px += sx
		py += sy
		for _i in ITERATIONS:
			var ix: int = floori((px - ox) / cell)
			var iy: int = floori((py - oy) / cell)
			if not _open(cells, w, h, ix, iy):
				var bx: float = ox + float(ix) * cell
				var by: float = oy + float(iy) * cell
				var left: float = px - bx
				var right: float = bx + cell - px
				var up: float = py - by
				var down: float = by + cell - py
				var side: int = _exit(cells, w, h, ix, iy, left, right, up, down)
				if side == NO_EXIT:
					break
				var out: float = _gap(side, left, right, up, down) + r
				px += _way_x(side) * out
				py += _way_y(side) * out
				continue
			var x0: int = maxi(floori((px - r - ox) / cell), 0)
			var x1: int = mini(floori((px + r - ox) / cell), w - 1)
			var y0: int = maxi(floori((py - r - oy) / cell), 0)
			var y1: int = mini(floori((py + r - oy) / cell), h - 1)
			var best: float = 0.0
			var bnx: float = 0.0
			var bny: float = 0.0
			for cy in range(y0, y1 + 1):
				for cx in range(x0, x1 + 1):
					if cells[cy * w + cx] == 0:
						continue
					var bx0: float = ox + float(cx) * cell
					var by0: float = oy + float(cy) * cell
					var bx1: float = bx0 + cell
					var by1: float = by0 + cell
					var qx: float = clampf(px, bx0, bx1)
					var qy: float = clampf(py, by0, by1)
					var dx: float = px - qx
					var dy: float = py - qy
					var d2: float = dx * dx + dy * dy
					var depth: float = 0.0
					var nx: float = 0.0
					var ny: float = 0.0
					if d2 > 0.0:
						if d2 >= r * r:
							continue
						var d: float = sqrt(d2)
						depth = r - d
						nx = dx / d
						ny = dy / d
					else:
						# The centre is on the cell's edge (in an open cell beside it): out by
						# that side.
						var left: float = px - bx0
						var right: float = bx1 - px
						var up: float = py - by0
						var down: float = by1 - py
						var side: int = _exit(cells, w, h, cx, cy, left, right, up, down)
						if side == NO_EXIT:
							continue
						depth = _gap(side, left, right, up, down) + r
						nx = _way_x(side)
						ny = _way_y(side)
					if depth > best:
						best = depth
						bnx = nx
						bny = ny
			if best <= 0.0:
				break
			px += bnx * best
			py += bny * best
	return Vector2(px, py)


## True when a wall cell lies in the box from (`lx`, `ly`) to (`hx`, `hy`).
static func _near(cells: PackedByteArray, w: int, h: int, cell: float, ox: float, oy: float, lx: float, ly: float, hx: float, hy: float) -> bool:
	var x0: int = maxi(floori((lx - ox) / cell), 0)
	var x1: int = mini(floori((hx - ox) / cell), w - 1)
	var y0: int = maxi(floori((ly - oy) / cell), 0)
	var y1: int = mini(floori((hy - oy) / cell), h - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if cells[cy * w + cx] != 0:
				return true
	return false


## The side a centre `left`, `right`, `up` and `down` pixels from the sides of the wall cell
## (`cx`, `cy`) leaves it by: the nearest that opens onto an open cell (left, right, up, down first
## on a tie), or NO_EXIT when every side is a wall.
static func _exit(cells: PackedByteArray, w: int, h: int, cx: int, cy: int, left: float, right: float, up: float, down: float) -> int:
	var side: int = NO_EXIT
	var best: float = INF
	if _open(cells, w, h, cx - 1, cy) and left < best:
		best = left
		side = LEFT
	if _open(cells, w, h, cx + 1, cy) and right < best:
		best = right
		side = RIGHT
	if _open(cells, w, h, cx, cy - 1) and up < best:
		best = up
		side = UP
	if _open(cells, w, h, cx, cy + 1) and down < best:
		side = DOWN
	return side


## How far the centre is from `side`.
static func _gap(side: int, left: float, right: float, up: float, down: float) -> float:
	if side == LEFT:
		return left
	if side == RIGHT:
		return right
	if side == UP:
		return up
	return down


## The way out by `side`, across and down.
static func _way_x(side: int) -> float:
	return -1.0 if side == LEFT else (1.0 if side == RIGHT else 0.0)


static func _way_y(side: int) -> float:
	return -1.0 if side == UP else (1.0 if side == DOWN else 0.0)


## True when the cell (`cx`, `cy`) is open floor or outside the grid.
static func _open(cells: PackedByteArray, w: int, h: int, cx: int, cy: int) -> bool:
	return cx < 0 or cy < 0 or cx >= w or cy >= h or cells[cy * w + cx] == 0
