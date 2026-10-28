extends Node2D
## The intro (living staffs H6, docs/milestones/M2-living-staffs.md, "The intro"): "New staff
## day." The wizard walks in with the old staff asleep in one hand and the shiny new one (the
## Favourite) in the other, glances round, whistles, drops the old staff down a hole in the
## floor ("Oops."), dusts off their hands ("Oh well.") and skips away. The camera follows the
## staff down a long shaft past strays' eyes in the walls; it wakes on the way down, its eyes
## trailing above it; THUD on a hard floor (a shake, dust, a bounce, dizzy stars); "Thrown out?
## No. Dropped. By accident. Obviously."; it rises and looks up the shaft: "Home is up there."
##
## One staff per player (`setup(seats)`), each in its seat's colour: the wizard drops them one
## after another, faster each time (DROP_GAPS: "Oops. Oops. Oops."), and they land side by side.
## LENGTH seconds in all, whatever the number of players. Any joined player's accept, back,
## pause or staff button skips it at once, for everyone (`finished(true)`); played out, it sends
## `finished(false)`.
##
## Time moves only by `step(delta)` (Flow calls it), so tests step it with fixed deltas. The
## world is the mockup's: one tall column 128 px wide (the tower room, the shaft, the crypt),
## drawn at PIXEL_SCALE under a camera that follows the first staff down. The background is drawn
## in code from docs/STYLE.md's palette; the wizard is the style N art (content/wizard/base/) in
## a Blight hat (art/story/wizard_hat.svg: the villain wears no player colour); the staffs are
## the curl head sheet with the face sheets' eyes and brows (art/faces/), drawn here frame by
## frame rather than by `Face`, which needs an actor. The captions are here too, until
## content/story has a schema for cutscenes (M3).

signal finished(skipped: bool)

const WIZARD_IDLE: Texture2D = preload("res://content/wizard/base/wizard_idle.svg")
const WIZARD_HAT: Texture2D = preload("res://art/story/wizard_hat.svg")
const FAVOURITE: Texture2D = preload("res://art/story/favourite.svg")
const STAFF_HEAD: Texture2D = preload("res://content/wizard/staffs/curl/head.svg")
const EYES: Texture2D = preload("res://art/faces/eyes.svg")
const BROWS: Texture2D = preload("res://art/faces/brows.svg")

## Seconds from start to end, for one to four players.
const LENGTH: float = 14.5
## The first drop, and the gaps before each later one (faster each time).
const FIRST_DROP: float = 4.0
const DROP_GAPS: Array[float] = [0.45, 0.3, 0.2]
## When the first staff hits the floor; each later one lands HIT_STAGGER later.
const HIT_TIME: float = 7.6
const HIT_STAGGER: float = 0.12
## The actions that skip it.
const SKIP_ACTIONS: Array[StringName] = [&"accept", &"back", &"pause", &"staff_1", &"staff_2", &"staff_3", &"staff_4"]
const SEATS: int = 4

## The world: 128 px wide; the tower room to SHAFT_TOP, the shaft to SHAFT_END, the crypt floor
## at FLOOR; the view is VIEW tall, drawn at PIXEL_SCALE.
const WORLD_W: float = 128.0
const SHAFT_TOP: float = 44.0
const SHAFT_END: float = 420.0
const FLOOR: float = 470.0
const WORLD_H: float = 480.0
const VIEW_H: float = 96.0
const PIXEL_SCALE: float = 3.0
const SCREEN: Vector2 = Vector2(640.0, 360.0)
## The window's top on the screen (the caption goes under it).
const VIEW_TOP: float = 12.0
## Strays watching from niches in the shaft wall.
const WATCHERS: Array[Vector2] = [Vector2(64, 130), Vector2(92, 205), Vector2(63, 290), Vector2(93, 350)]
## Where the hand holding the old staff is on the wizard, and the Favourite's hand.
const STAFF_HAND: Vector2 = Vector2(6.0, 31.0)
## Where the wizard stands to drop: on the hole's edge, the staff hand over the hole.
const STAND_X: float = 66.0
## The shaft's dark column (the hole) and the lanes the staffs fall down: the grip stays inside
## it, LANE_SPREAD apart when several fall at once.
const SHAFT_LEFT: float = 70.0
const SHAFT_RIGHT: float = 86.0
const LANE_SPREAD: float = 3.5
## The falling staff rocks about upright (FALL_ROCK radians, FALL_ROCK_RATE a second) instead
## of tumbling, so it never pokes through the shaft walls.
const FALL_ROCK: float = 0.35
const FALL_ROCK_RATE: float = 7.0
const FAVOURITE_HAND: Vector2 = Vector2(-5.0, 31.0)
## The face on a staff: the eyes' anchor from the grip (the "Close" height) and the sheet frames.
const FACE_ANCHOR: Vector2 = Vector2(-5.0, -8.0)
const FRAME: Vector2i = Vector2i(16, 8)
const BLINK: int = 9
const MOOD_NEUTRAL: int = 0
const MOOD_ANGRY: int = 2
const MOOD_WORRIED: int = 4

## The palette (docs/STYLE.md).
const OUT: Color = Color("14121f")
const STONE: Array[Color] = [Color("2b2840"), Color("4a4663"), Color("7a7694")]
const BONE: Array[Color] = [Color("a39fb8"), Color("d4d0e0"), Color("f4f1ea")]
const FIRE_LIGHT: Color = Color("ffa23c")
const SPARK_LIGHT: Color = Color("fff3a6")

var input: Node = null

var time: float = 0.0
var _seats: Array[int] = []
var _drops: PackedFloat32Array = PackedFloat32Array()
var _presses: Array[PackedInt32Array] = []
var _done: bool = false
var _view: Node2D = null
var _world: Node2D = null
var _wizard: Sprite2D = null
var _hat: Sprite2D = null
var _favourite: Sprite2D = null
var _staffs: Array[Sprite2D] = []
var _eyes: Array[Sprite2D] = []
var _brows: Array[Sprite2D] = []
var _caption: Label = null
## Where each staff is (world), for the background's dust and stars; the camera and the shake.
var _staff_at: Array[Vector2] = []
var _camera: float = 0.0
var _shake: Vector2 = Vector2.ZERO


## Get ready for `seats` (the joined players, one dropped staff each, 1-4) and the input manager
## `input_manager` (null: nobody can skip).
func setup(seats: Array[int], input_manager: Node) -> void:
	input = input_manager
	_seats = seats.duplicate()
	if _seats.is_empty():
		_seats.append(0)
	_seats.resize(mini(_seats.size(), SEATS))
	_drops.resize(_seats.size())
	var at: float = FIRST_DROP
	for i in _seats.size():
		if i > 0:
			at += DROP_GAPS[i - 1]
		_drops[i] = at
	_presses.clear()
	for seat in SEATS:
		var counts := PackedInt32Array()
		for action in SKIP_ACTIONS:
			counts.append(_press_count(seat, action))
		_presses.append(counts)
	_build()
	_pose()


## How many staffs it drops (one per player).
func drops() -> int:
	return _seats.size()


## When staff `index` is dropped, and when it lands.
func drop_time(index: int) -> float:
	return _drops[index]


func hit_time(index: int) -> float:
	return HIT_TIME + HIT_STAGGER * float(index)


## Where staff `index`'s grip is in the world now (the world is 128 px wide; y grows downward).
func staff_position(index: int) -> Vector2:
	return _staff_at[index]


## True once it has finished (played out or skipped).
func is_done() -> bool:
	return _done


## The caption shown now.
func caption() -> String:
	return caption_at(time)


## Advance `delta` seconds: a skip press ends it at once, and so does the end of the last beat.
func step(delta: float) -> void:
	if _done:
		return
	if _skip_pressed():
		_finish(true)
		return
	time += delta
	if time >= LENGTH:
		time = LENGTH
		_pose()
		_finish(false)
		return
	_pose()


## The caption at `at` seconds.
func caption_at(at: float) -> String:
	var last_drop: float = _drops[_drops.size() - 1]
	if at < 2.5:
		return "New staff day."
	if at < FIRST_DROP:
		return "The wizard whistles. Nobody is watching."
	if at < last_drop + 0.8:
		var oops: PackedStringArray = PackedStringArray()
		for drop in _drops:
			if at >= drop:
				oops.append("Oops.")
		return "\"%s\"" % " ".join(oops)
	if at < last_drop + 1.6:
		return "\"Oh well.\""
	var since: float = at - HIT_TIME
	if since < 0.0:
		var falling: float = (at - FIRST_DROP) / (HIT_TIME - FIRST_DROP)
		if at < last_drop + 2.4:
			return ""
		return "......!" if falling >= 0.62 else "..."
	if since < 1.0:
		return "THUD."
	if since < 2.2:
		return ""
	if since < 3.8:
		return "Thrown out? No. Dropped. By accident. Obviously."
	if since < 5.4:
		return "Home is up there."
	return "Merge spells. Find your way home."


func _finish(skipped: bool) -> void:
	_done = true
	finished.emit(skipped)


## True when a joined player pressed a skip button since the last step.
func _skip_pressed() -> bool:
	if input == null:
		return false
	var pressed: bool = false
	for seat in SEATS:
		if not bool(input.call("is_joined", seat)):
			continue
		for i in SKIP_ACTIONS.size():
			var count: int = _press_count(seat, SKIP_ACTIONS[i])
			if count != _presses[seat][i]:
				_presses[seat][i] = count
				pressed = true
	return pressed


func _press_count(seat: int, action: StringName) -> int:
	if input == null or not bool(input.call("is_joined", seat)):
		return 0
	return int(input.call("get_press_count", seat, action))


## The nodes: a clipped window with the view scaled up in it, the world under it (drawn in code), the sprites, the
## caption.
func _build() -> void:
	# The window onto the world: VIEW_H of it, clipped, centred.
	var frame := Control.new()
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size = Vector2(WORLD_W, VIEW_H) * PIXEL_SCALE
	frame.position = Vector2((SCREEN.x - frame.size.x) * 0.5, VIEW_TOP)
	add_child(frame)
	_view = Node2D.new()
	_view.scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
	frame.add_child(_view)
	_world = Node2D.new()
	_world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_world.draw.connect(_draw_world)
	_view.add_child(_world)
	_wizard = _sprite(WIZARD_IDLE, 4, 1)
	_hat = _sprite(WIZARD_HAT, 1, 1)
	_favourite = _sprite(FAVOURITE, 1, 1)
	for i in _seats.size():
		_staffs.append(_sprite(STAFF_HEAD, 16, 4))
		_eyes.append(_sprite(EYES, EYES.get_width() / FRAME.x, EYES.get_height() / FRAME.y))
		_brows.append(_sprite(BROWS, BROWS.get_width() / FRAME.x, BROWS.get_height() / FRAME.y))
		_staff_at.append(Vector2.ZERO)
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.position = Vector2(0.0, VIEW_TOP + VIEW_H * PIXEL_SCALE + 14.0)
	_caption.size = Vector2(SCREEN.x, 32.0)
	add_child(_caption)


func _sprite(texture: Texture2D, columns: int, rows: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.hframes = columns
	sprite.vframes = rows
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_world.add_child(sprite)
	return sprite


## Where everything is at `time`.
func _pose() -> void:
	var last_drop: float = _drops[_drops.size() - 1]
	# The wizard: walks in, glances, looks down, dusts off their hands, skips away.
	var wx: float = 160.0
	var wy: float = 0.0
	var pose: int = 0
	var leave: float = last_drop + 1.6
	if time < 2.5:
		wx = lerpf(10.0, STAND_X, time / 2.5)
		wy = -roundf(absf(sin(time * 9.0)))
	elif time < FIRST_DROP:
		wx = STAND_X
		pose = 2 if time < 2.9 else (3 if time < 3.3 else 1)
	elif time < leave:
		wx = STAND_X
		pose = 0 if time < last_drop + 0.8 else 1
	elif time < leave + 0.8:
		wx = lerpf(STAND_X, 160.0, (time - leave) / 0.8)
		wy = -roundf(absf(sin(time * 14.0)) * 2.0)
		pose = 1
	var on_stage: bool = wx < 150.0
	_wizard.visible = on_stage
	_hat.visible = on_stage
	_favourite.visible = on_stage
	var wizard_at := Vector2(roundf(wx) - 16.0, 11.0 + wy)
	_wizard.position = wizard_at
	_wizard.frame = pose
	_hat.position = wizard_at
	_favourite.position = Vector2(roundf(wx), 0.0) + FAVOURITE_HAND + Vector2(0.0, wy) - Vector2(24.0, 27.0)
	# The staffs: held (asleep, pointing up), falling (spinning, waking), down, then up.
	_camera = 0.0
	_shake = Vector2.ZERO
	var hand := Vector2(roundf(wx), wy) + STAFF_HAND
	var next_held: int = -1
	for i in _seats.size():
		if time < _drops[i] and next_held < 0:
			next_held = i
	for i in _seats.size():
		_pose_staff(i, hand, next_held)
	_camera = roundf(minf(_camera, WORLD_H - VIEW_H))
	_world.position = Vector2(_shake.x, -_camera + _shake.y)
	_caption.text = caption()
	_world.queue_redraw()


## Staff `index`: its sprite frame and place, and its face.
func _pose_staff(index: int, hand: Vector2, next_held: int) -> void:
	var drop: float = _drops[index]
	var hit: float = hit_time(index)
	var lane: float = float(index) - float(_seats.size() - 1) * 0.5
	var land_x: float = 78.0 + lane * 14.0
	var shaft_x: float = (SHAFT_LEFT + SHAFT_RIGHT) * 0.5 + lane * LANE_SPREAD
	var at := Vector2.ZERO
	var angle: float = -PI * 0.5
	var shut: bool = true
	var look := Vector2i.ZERO
	var mood: int = MOOD_NEUTRAL
	var eye_lift: float = 0.0
	var brow_lift: float = 0.0
	var visible_now: bool = true
	if time < drop:
		at = hand
		visible_now = index == next_held and hand.x < 150.0
	elif time < hit:
		var k: float = (time - drop) / (hit - drop)
		var fall: float = (k / 0.2) * (k / 0.2) * 0.1 if k < 0.2 else 0.1 + (k - 0.2) / 0.8 * 0.9
		var y: float = 31.0 + (FLOOR - 4.0 - 31.0) * fall
		# From the hand (over the hole) into its lane, down the shaft inside its walls, and out
		# into the crypt toward where it lands.
		var x: float = lerpf(hand.x if hand.x < 150.0 else shaft_x, shaft_x, minf(k / 0.1, 1.0))
		if y < SHAFT_END:
			x = clampf(x + roundf(sin(time * 9.0 + float(index)) * 0.6), SHAFT_LEFT + 2.0, SHAFT_RIGHT - 2.0)
		else:
			x = lerpf(shaft_x, land_x, (y - SHAFT_END) / (FLOOR - 4.0 - SHAFT_END))
		at = Vector2(x, y)
		angle = -PI * 0.5 + sin((time - drop) * FALL_ROCK_RATE) * FALL_ROCK
		if k >= 0.3:
			shut = false
			mood = MOOD_WORRIED
			look = Vector2i(0, 1)
			eye_lift = -3.0
			brow_lift = -1.0
		if index == 0:
			_camera = maxf(0.0, at.y - SHAFT_TOP)
	else:
		_camera = WORLD_H - VIEW_H
		var since: float = time - hit
		at = Vector2(land_x, FLOOR - 4.0 - (roundf(sin(since / 0.4 * PI) * 7.0) if since < 0.4 else 0.0))
		angle = 0.0
		mood = MOOD_WORRIED
		if since < 0.35:
			var flip: float = 1.0 if int(since * 30.0) % 2 == 0 else -1.0
			_shake = Vector2(flip, -flip)
		if since >= 2.2:
			shut = false
			look = Vector2i(0, -1)
		var rise_from: float = HIT_TIME + 3.8 - hit
		if since >= rise_from:
			var k: float = clampf((since - rise_from) / 0.8, 0.0, 1.0)
			at = Vector2(lerpf(land_x, land_x - 2.0, k), lerpf(FLOOR - 4.0, FLOOR - 16.0, k))
			angle = lerpf(0.0, -PI * 0.5, k)
			mood = MOOD_ANGRY
	at = at.round()
	_staff_at[index] = at
	var direction: int = posmod(roundi(angle / (TAU / 16.0)), 16)
	var staff: Sprite2D = _staffs[index]
	staff.visible = visible_now
	staff.position = at - Vector2(24.0, 27.0)
	staff.frame_coords = Vector2i(direction, clampi(_seats[index], 0, 3))
	var eyes: Sprite2D = _eyes[index]
	var brows: Sprite2D = _brows[index]
	eyes.visible = visible_now
	brows.visible = visible_now
	var anchor: Vector2 = at + FACE_ANCHOR + Vector2(0.0, eye_lift)
	eyes.position = anchor - Vector2(1.0, 1.0)
	eyes.frame_coords = Vector2i(BLINK if shut else (look.y + 1) * 3 + look.x + 1, 0)
	brows.position = anchor + Vector2(0.0, brow_lift) - Vector2(1.0, 5.0)
	brows.frame_coords = Vector2i(mood, 0)


## The tower room, the shaft and its watchers, the crypt and its floor; dust and dizzy stars.
func _draw_world() -> void:
	var g: Node2D = _world
	g.draw_rect(Rect2(-WORLD_W, -WORLD_H, WORLD_W * 3.0, WORLD_H * 3.0), OUT)
	g.draw_rect(Rect2(0, 0, WORLD_W, SHAFT_TOP), STONE[1])
	var x: float = 6.0
	while x < WORLD_W:
		g.draw_rect(Rect2(x, 6, 10, 14), STONE[2])
		g.draw_rect(Rect2(x + 1, 7, 8, 12), STONE[0])
		x += 24.0
	g.draw_rect(Rect2(0, SHAFT_TOP, WORLD_W, SHAFT_END - SHAFT_TOP), STONE[0])
	g.draw_rect(Rect2(70, 40, 16, SHAFT_END - 40), OUT)
	var y: float = SHAFT_TOP
	while y < SHAFT_END:
		g.draw_rect(Rect2(64, y, 6, 5), STONE[1])
		g.draw_rect(Rect2(86, y, 6, 5), STONE[1])
		g.draw_rect(Rect2(64, y, 6, 1), STONE[2])
		g.draw_rect(Rect2(86, y, 6, 1), STONE[2])
		y += 6.0
	for watcher in WATCHERS:
		g.draw_rect(Rect2(watcher.x - 3, watcher.y - 2, 7, 5), OUT)
		if sin(time * 2.0 + watcher.x) > -0.7:
			g.draw_rect(Rect2(watcher.x - 2, watcher.y, 2, 1), FIRE_LIGHT)
			g.draw_rect(Rect2(watcher.x + 1, watcher.y, 2, 1), FIRE_LIGHT)
	# The tower floor, with the hole.
	g.draw_rect(Rect2(0, 40, 70, 1), STONE[2])
	g.draw_rect(Rect2(86, 40, 42, 1), STONE[2])
	g.draw_rect(Rect2(0, 41, 70, 3), STONE[1])
	g.draw_rect(Rect2(86, 41, 42, 3), STONE[1])
	# The crypt and its hard floor.
	g.draw_rect(Rect2(0, SHAFT_END, WORLD_W, FLOOR - SHAFT_END), STONE[0])
	g.draw_rect(Rect2(70, SHAFT_END, 16, 2), OUT)
	y = SHAFT_END + 6.0
	while y < FLOOR:
		g.draw_rect(Rect2(0, y, WORLD_W, 1), OUT)
		var bx: float = 8.0 if int(y / 8.0) % 2 == 1 else 0.0
		while bx < WORLD_W:
			g.draw_rect(Rect2(bx, y, 1, minf(8.0, FLOOR - y)), OUT)
			bx += 16.0
		y += 8.0
	g.draw_rect(Rect2(0, FLOOR, WORLD_W, WORLD_H - FLOOR), STONE[1])
	g.draw_rect(Rect2(0, FLOOR, WORLD_W, 1), STONE[2])
	# A whistled note over the wizard.
	if time >= 2.6 and time < FIRST_DROP:
		var nx: float = STAND_X + 4.0
		var ny: float = 6.0 + roundf(sin(time * 6.0))
		g.draw_rect(Rect2(nx, ny, 1, 4), BONE[2])
		g.draw_rect(Rect2(nx + 1, ny, 2, 1), BONE[2])
		g.draw_rect(Rect2(nx - 2, ny + 3, 2, 2), BONE[2])
	for i in _seats.size():
		var since: float = time - hit_time(i)
		var at: Vector2 = _staff_at[i]
		if since >= 0.0:
			g.draw_rect(Rect2(at.x - 3, FLOOR + 2, 9, 1), STONE[0])
		if since >= 0.0 and since < 0.45:
			var grow: float = since / 0.12 if since < 0.12 else 1.0 - (since - 0.12) / 0.33
			for puff: Vector2 in [Vector2(-12, 3), Vector2(-6, 4), Vector2(0, 3), Vector2(7, 4), Vector2(13, 3)]:
				var r: float = roundf(puff.y * grow)
				if r <= 0.0:
					continue
				var centre := Vector2(at.x + puff.x * (1.0 + since * 2.0), FLOOR - 1.0).round()
				g.draw_circle(centre, r + 1.0, BONE[0])
				g.draw_circle(centre, r, BONE[2])
		if since >= 0.4 and since < 3.0:
			for k in 3:
				var spin: float = time * 5.0 + float(k) * 2.1
				g.draw_rect(Rect2(roundf(at.x - 4.0 + cos(spin) * 6.0), roundf(FLOOR - 16.0 + sin(spin) * 2.0), 1, 1), SPARK_LIGHT)
