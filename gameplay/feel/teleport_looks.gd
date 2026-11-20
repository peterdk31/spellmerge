extends Node2D
## Where a wizard teleported from the held Y map left (the owner, 2026-11-19; Flow's
## `wizard_teleported`). View only: nothing in the game reads it.
##
## **Smooth** (docs/STYLE.md): the wizard is gone from where it stood, so a column of its own light
## (its seat's ramp, `ProjectileManager.ramp_light`) stands there in its place and narrows away a step
## a frame at FPS through COLUMNS (as wide as a body, then narrower and taller, to a line, to a dot,
## then none): whole pixels, never a fade. Where it arrives it materializes (its spawn, `Actor.spawn`:
## `SpawnLook` draws it built out of light), so neither end changes in one jump.
##
## A child of Feel, top level (world space), over the bodies; Feel steps it once a frame (`step`) and
## hands it the actor table for the seat's colour. At most one column a seat; nothing is allocated
## once made.

const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## Over the bodies (as the unseen dark's 20 is over them, under it: a teleport out of a dark room
## is never seen there).
const Z: int = 19
const FPS: float = 12.0
## The column's looks, widest first (width, height in pixels), its foot on the feet it left.
const COLUMNS: Array[Vector2i] = [Vector2i(12, 22), Vector2i(8, 26), Vector2i(4, 30), Vector2i(2, 32), Vector2i(2, 2)]
const SEATS: int = 4

## By seat: where its column stands (world pixels), its colour and the look it is at (-1: none).
var _at: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _colour: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
var _look: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _clock: float = 0.0
## The actor table, for the seat's colour (Feel's; null: white).
var table: ActorsScript = null


func _ready() -> void:
	top_level = true
	z_index = Z


func bind(events: Node) -> void:
	if events != null:
		events.wizard_teleported.connect(_on_wizard_teleported)


func _on_wizard_teleported(seat: int, from: Vector2, _to: Vector2) -> void:
	if seat < 0 or seat >= SEATS:
		return
	_at[seat] = from
	_look[seat] = 0
	if table != null:
		_colour[seat] = ProjectileManagerScript.ramp_light(table.ramp_of(table.home_of_seat(seat)))
	queue_redraw()


## The look seat `seat`'s column is at (-1: none; for tests).
func look_of(seat: int) -> int:
	return _look[seat]


## True while a column still narrows away.
func is_moving() -> bool:
	for seat in SEATS:
		if _look[seat] >= 0:
			return true
	return false


## Once a frame, `delta` real seconds on: each column a look narrower at FPS.
func step(delta: float) -> void:
	if not is_moving():
		_clock = 0.0
		return
	_clock += delta
	while _clock >= 1.0 / FPS:
		_clock -= 1.0 / FPS
		advance()


## One look of every column (a frame at FPS).
func advance() -> void:
	for seat in SEATS:
		if _look[seat] >= 0:
			_look[seat] += 1
			if _look[seat] >= COLUMNS.size():
				_look[seat] = -1
	queue_redraw()


func _draw() -> void:
	for seat in SEATS:
		var look: int = _look[seat]
		if look < 0:
			continue
		var size: Vector2i = COLUMNS[look]
		var feet: Vector2i = Vector2i(_at[seat].round())
		var corner := Vector2(feet.x - size.x / 2, feet.y - size.y + 4)
		draw_rect(Rect2(corner - Vector2.ONE, Vector2(size) + Vector2(2, 2)), Palette.OUTLINE)
		draw_rect(Rect2(corner, Vector2(size)), _colour[seat])
