extends RefCounted
## The parts of the world this machine shows now, one box a view (the performance pass, the owner's
## decision of 2026-11-20): what gives off motes near what is seen (the mote sources, the room's and
## each kind's air, the void's) and the bodies' shadows work by each view's own box, not one box round
## every view, which across a biome holds the rooms and the void between the views too. With one
## picture it is one box (`set_one`); while the screen is split, each view's cell's box in the world
## (`set_views`, from `ScreenViews`). View only.
##
## The boxes may overlap (two views of one fight, as a split begins): `has_point` and `intersects`
## ask any box, and `pick`, a point in the boxes at random, picks each part of the world they cover
## as often as any other, overlap or not (a point in an earlier box's part is refused), so what is
## given off over them is as thick as over one picture. Nothing is made a frame.

const ScreenViewsScript := preload("res://core/display/screen_views.gd")

const MOST: int = ScreenViewsScript.VIEWS_MOST

## The boxes (world px): the first `count` of `boxes`. Read only.
var count: int = 0
var boxes: Array[Rect2] = []


func _init() -> void:
	boxes.resize(MOST)


## One box: `box` (empty: none; then nothing is near, and a reader that gives off everywhere with
## no box does so: `is_empty`).
func set_one(box: Rect2) -> void:
	boxes[0] = box
	count = 1 if box.has_area() else 0


## Each view's own box of `views` (its cell's corners in the world; box `k` view `k`'s, empty for a
## view with no cell), or with no view the one box `fallback`.
func set_views(views: ScreenViewsScript, fallback: Rect2 = Rect2()) -> void:
	if views == null or views.count == 0:
		set_one(fallback)
		return
	count = mini(views.count, MOST)
	for view in count:
		boxes[view] = views.view_world_box(view)


## One more box, `box`, after the others (at most MOST; an empty box is kept empty, in its place).
func add(box: Rect2) -> void:
	if count < MOST:
		boxes[count] = box
		count += 1


## Whether there is no box (then readers act as they do with no view: everywhere).
func is_empty() -> bool:
	for k in count:
		if boxes[k].has_area():
			return false
	return true


## The box round every box (empty for none).
func union() -> Rect2:
	var out := Rect2()
	for k in count:
		if boxes[k].has_area():
			out = boxes[k] if not out.has_area() else out.merge(boxes[k])
	return out


## Whether `point` is within `margin` of a box.
func has_point(point: Vector2, margin: float = 0.0) -> bool:
	for k in count:
		if boxes[k].has_area() and boxes[k].grow(margin).has_point(point):
			return true
	return false


## Whether `rect` meets a box grown by `margin`.
func intersects(rect: Rect2, margin: float = 0.0) -> bool:
	for k in count:
		if boxes[k].has_area() and boxes[k].grow(margin).intersects(rect):
			return true
	return false


## Box `k` grown by `margin` within `bounds` (empty bounds: no limit); empty when they do not meet,
## or when box `k` is empty.
func area_of(k: int, margin: float, bounds: Rect2) -> Rect2:
	if not boxes[k].has_area():
		return Rect2()
	var near: Rect2 = boxes[k].grow(margin)
	return near.intersection(bounds) if bounds.has_area() else near


## The area of the boxes, each grown by `margin` within `bounds`, added up (overlaps counted twice:
## `pick` refuses a point in an earlier one's part, so a rate over this area and points from `pick`
## are as thick over the overlap as anywhere).
func total_area(margin: float, bounds: Rect2) -> float:
	var sum: float = 0.0
	for k in count:
		sum += area_of(k, margin, bounds).get_area()
	return sum


## A point in the boxes (each grown by `margin` within `bounds`) at random by `rng`, every box picked
## by its area; INF when the point falls in an earlier box's part (it is counted there: skip it).
func pick(rng: RandomNumberGenerator, margin: float, bounds: Rect2) -> Vector2:
	var total: float = total_area(margin, bounds)
	if total <= 0.0:
		return Vector2.INF
	# One box takes no roll to pick it (a single picture's points as they always were).
	var at: float = rng.randf() * total if count > 1 else 0.0
	for k in count:
		var area: Rect2 = area_of(k, margin, bounds)
		var size: float = area.get_area()
		if size <= 0.0 or (at > size and k < count - 1):
			at -= size
			continue
		var point := Vector2(area.position.x + rng.randf() * area.size.x, area.position.y + rng.randf() * area.size.y)
		for earlier in k:
			if area_of(earlier, margin, bounds).has_point(point):
				return Vector2.INF
		return point
	return Vector2.INF
