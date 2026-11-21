extends Node2D
## The void between a biome's slabs (the owner, 2026-11-19: "the crypt's background around the rooms
## is black"): a rectangle of pure black under everything else in the world, over the biome's bounds
## and far past them (GROW), so whatever no room, bridge or look covers shows the void, in every view
## of a split screen alike (they share the world). Its sparse drifting motes are the spectacle's
## (`Spectacle.void_air`). Outside a biome (a world with no places: the hub, a single room) it draws
## nothing and the world is as before. The dark of unentered rooms is the same black
## (`unseen_dark.gd`), and the void's motes drift over it too (`Spectacle.void_pool`, drawn over that
## dark), so a room nobody has been in is one with the void until it is lit.
##
## A child of Feel, top level (world space), at the lowest z there is. Drawn again only when the
## bounds change; nothing is allocated in a frame. View only.

## Pure black: the void, and the dark over a room nobody has entered.
const COLOUR := Color(0.0, 0.0, 0.0, 1.0)
## Under everything in the world.
const Z: int = RenderingServer.CANVAS_ITEM_Z_MIN
## How far past the biome's bounds it reaches (pixels): past any picture's edge at the widest zoom.
const GROW: float = 2048.0

## The rectangle drawn (none: nothing).
var _rect: Rect2 = Rect2()


func _ready() -> void:
	top_level = true
	z_index = Z


## Once a frame: black over `bounds` (the biome's, `ProjectileManager.bounds`) grown by GROW while
## `grid` has places (a biome), else nothing.
func step(grid: RoomGrid, bounds: Rect2) -> void:
	var want: Rect2 = bounds.grow(GROW) if grid != null and grid.places() > 0 and bounds.has_area() else Rect2()
	if want != _rect:
		_rect = want
		queue_redraw()


## The rectangle it draws now (empty: none; for tests).
func rect() -> Rect2:
	return _rect


func _draw() -> void:
	if _rect.has_area():
		draw_rect(_rect, COLOUR)
