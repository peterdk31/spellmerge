extends "res://tests/support/screenshot.gd"
## Screenshots of the floor's own cover (the floor's first slice, docs/milestones/floor.md): in the
## crypt's first arena, round the first wizard, a lake laid by water (`floor_touched`, as a water
## Nova's or a fountain's), then the lake struck by lightning (its live water running through it,
## spent, wet again), frozen by frost into ice and thawed by fire, and fire on water as steam. And a
## real water bolt's trail, cast by the wizard: every shot touches the floor as it passes.
##
## Shots: `floor_lake` (the lake, 4×), `floor_lake_strip` (wetting in, from the touch), `floor_live_strip`
## (lightning running through it, spent, wet again), `floor_ice_strip` (frost, ice, then fire
## thawing it), `floor_steam_strip` (fire on water: steam, then dry floor), `floor_trail` (a water
## bolt's wet trail across the arena).

const FeelScript := preload("res://gameplay/feel/feel.gd")

## The lake's touches: a ring of circles round its middle (px from it, and their radius).
const LAKE: Array[Vector2] = [Vector2(0, 0), Vector2(30, 6), Vector2(-26, 10), Vector2(10, 26), Vector2(-8, -22), Vector2(40, -14)]
const LAKE_RADIUS: float = 22.0
const STRIP_HALF := Vector2i(56, 40)
const GAP: int = 2

var _events: Node = null


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel", "Events"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	_events = root.get_node("Events")
	input.call("add_virtual_device", 0)
	if not flow.call("start_run", 0):
		fail("the run did not start")
		return
	await settle(30)
	var wizard: Node2D = flow.call("get_wizard", 0) as Node2D
	if wizard == null:
		fail("no wizard")
		return
	var middle: Vector2 = wizard.global_position + Vector2(64.0, 0.0)
	await _strip(middle, "floor_lake_strip", [0, 2, 4, 8, 16], func() -> void: _lake(middle))
	await snap(middle, "floor_lake", Vector2i(72, 48))
	await _strip(middle, "floor_live_strip", [0, 3, 6, 10, 20, 40, 70, 110], func() -> void: _touch(&"lightning", middle + LAKE[2], 0.0))
	await settle(60)
	await _strip(middle, "floor_ice_strip", [0, 3, 6, 12, 24, 30, 36, 50], func() -> void: _touch(&"frost", middle, 30.0), 24, func() -> void: _touch(&"fire", middle, 18.0))
	await settle(30)
	# Fresh water first (the lake has frozen and thawed by now), then fire on it: steam.
	var steam_at: Vector2 = middle
	_touch(&"water", steam_at, 24.0)
	await settle(30)
	await _strip(steam_at, "floor_steam_strip", [0, 3, 6, 12, 20, 32], func() -> void: _touch(&"fire", steam_at, 24.0))
	var cover: Node = root.get_node("Cover")
	var state: CoverState = cover.call("cover_state_at", (cover.get("layout") as CoverLayout).cell_of(steam_at))
	if state == null or state.state_id != &"dry":
		fail("fire on the fresh water did not steam it away (%s)" % (state.state_id if state != null else &"no cell"))
		return
	# A fresh run for the trail: the lake's lightning may have downed the wizard beside it.
	flow.call("stop_run")
	await settle(10)
	if not flow.call("start_run", 0):
		fail("the second run did not start")
		return
	await settle(30)
	await _trail(flow.call("get_wizard", 0) as Node2D)


## Water over the lake's circles.
func _lake(middle: Vector2) -> void:
	for at in LAKE:
		_touch(&"water", middle + at, LAKE_RADIUS)


func _touch(element: StringName, at: Vector2, radius: float) -> void:
	_events.emit_signal("floor_touched", -1, element, at, radius, 0)


## `start` done, then the floor round `middle` pictured at each of `frames` (from it), side by side,
## at 4×, as `shot_name`; `then` done at frame `then_at` (none: -1).
func _strip(middle: Vector2, shot_name: String, frames: Array[int], start: Callable, then_at: int = -1, then: Callable = Callable()) -> void:
	var cell: Vector2i = STRIP_HALF * 2
	var strip := Image.create((cell.x + GAP) * frames.size(), cell.y, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.05, 0.05, 0.07))
	start.call()
	var frame: int = 0
	for column in frames.size():
		var want: int = frames[column]
		if then_at >= 0 and frame < then_at and want >= then_at:
			await settle(then_at - frame)
			frame = then_at
			then.call()
		if want > frame:
			await settle(want - frame)
			frame = want
		var image: Image = await grab()
		var crop: Image = crop_round(image, on_screen(middle), STRIP_HALF)
		crop.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(crop, Rect2i(Vector2i.ZERO, cell), Vector2i(column * (cell.x + GAP), 0))
	strip.resize(strip.get_width() * 3, strip.get_height() * 3, Image.INTERPOLATE_NEAREST)
	save(strip, shot_name)


## The wizard's first staff given a water bolt and cast right: its wet trail across the arena.
func _trail(wizard: Node2D) -> void:
	var spells: Node = root.get_node_or_null("Spells")
	var actor := wizard as Actor
	if spells == null or not is_instance_valid(actor) or actor.caster == null:
		fail("no caster to cast the water bolt")
		return
	actor.caster.set_staff(0, [&"water", &"bolt"] as Array[StringName])
	actor.aim = Vector2.RIGHT
	for i in 3:
		actor.caster.cast(0)
		await settle(14)
	await settle(10)
	await snap(wizard.global_position + Vector2(110.0, 0.0), "floor_trail", Vector2i(140, 50), 3)
