extends Node2D
## The health bar over a wizard whose seat is away (items I8, docs/milestones/items.md, "During a
## possession"; owner, 2026-11-13, decision 10): while a seat drives another body (it possesses
## one), its corner panel and menus are that body's, so its own wizard, standing empty and
## vulnerable, shows its health in a small bar just over its head. The bar is the possession
## overlay's (`PossessedLook`): health in Fire on a Stone trough with a 1 px outline, the corner
## panel's colour (docs/STYLE.md). A wizard that is itself possessed meanwhile shows its possession's
## timer there, so the bar sits over that ring.
##
## It reads the actor table (`Actors.home_of_seat`, `actor_of_seat`) and each wizard's Health. A
## child of Feel, top level (world space). View only: never state, nothing in the game reads it,
## and nothing is allocated after it is made; it redraws only when a bar moves or changes.

const ActorsScript := preload("res://core/actors/actors.gd")

## Over the damage numbers, as the altar's code.
const Z: int = 22
## The bar's lower edge above the feet: just over a 32 px character (`PossessedLook.TOP`), and how
## much higher it sits over a possession's timer ring.
const TOP: float = -31.0
const OVER_RING: float = 11.0
## The bar: inner width and height (a possessed body's bars' size).
const BAR_WIDTH: int = 16
const BAR_HEIGHT: int = 2
const OUTLINE_COLOR: Color = Color("14121f")
const TROUGH_COLOR: Color = Color("2b2840")
const HEALTH_COLOR: Color = Color("e0592f")

## How many bars show, and each one's seat, place (the bar's lower middle, world, whole pixels) and
## filled pixels. Sized once (a bar a seat).
var count: int = 0
var _seat: PackedInt32Array = PackedInt32Array()
var _at: PackedVector2Array = PackedVector2Array()
var _filled: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	_seat.resize(ActorsScript.SEATS)
	_at.resize(ActorsScript.SEATS)
	_filled.resize(ActorsScript.SEATS)


func _ready() -> void:
	top_level = true
	z_index = Z


## Find the wizards whose seat drives another body in `table`, and redraw when a bar changed.
func step(table: ActorsScript) -> void:
	var changed: bool = false
	var before: int = count
	count = 0
	if table != null:
		for seat in ActorsScript.SEATS:
			var home: int = table.home_of_seat(seat)
			var driven: int = table.actor_of_seat(seat)
			if home == ActorsScript.NONE or driven == ActorsScript.NONE or driven == home:
				continue
			var body := table.node_of(home) as Actor
			if body == null or not body.is_inside_tree():
				continue
			var lift: float = TOP - (OVER_RING if body.possessed_by != null else 0.0)
			var at: Vector2 = (body.global_position + Vector2(0.0, lift * body.size)).round()
			var filled: int = health_pixels(body)
			if count >= before or _seat[count] != seat or _at[count] != at or _filled[count] != filled:
				changed = true
			_seat[count] = seat
			_at[count] = at
			_filled[count] = filled
			count += 1
	if changed or count != before:
		queue_redraw()


## The filled pixels of `body`'s bar (0 to BAR_WIDTH); a hurt wizard shows at least one until 0.
static func health_pixels(body: Actor) -> int:
	if body == null or body.health == null or body.health.max_health <= 0.0:
		return 0
	var share: float = body.health.health / body.health.max_health
	if share <= 0.0:
		return 0
	return clampi(floori(share * float(BAR_WIDTH)), 1, BAR_WIDTH)


## The seat of bar `at` (0 to `count` - 1), its place (the lower middle) and its filled pixels.
func seat_of(at: int) -> int:
	return _seat[at]


func position_of(at: int) -> Vector2:
	return _at[at]


func filled_of(at: int) -> int:
	return _filled[at]


func _draw() -> void:
	var width: float = float(BAR_WIDTH + 2)
	var height: float = float(BAR_HEIGHT + 2)
	for at in count:
		var corner := Vector2(_at[at].x - roundf(width * 0.5), _at[at].y - height)
		draw_rect(Rect2(corner, Vector2(width, height)), OUTLINE_COLOR)
		draw_rect(Rect2(corner + Vector2.ONE, Vector2(float(BAR_WIDTH), float(BAR_HEIGHT))), TROUGH_COLOR)
		if _filled[at] > 0:
			draw_rect(Rect2(corner + Vector2.ONE, Vector2(float(_filled[at]), float(BAR_HEIGHT))), HEALTH_COLOR)
