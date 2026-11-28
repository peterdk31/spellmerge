extends "res://tests/support/suite.gd"
## The frame's looks in one pass (perf plan F4, docs/milestones/perf-plan.md; `Actor.step_all_looks`,
## the Tick's `_process`): which bodies' looks are due and on screen is found in one call
## (`Actor.looks_due`: the native module's `BodyKernel.looks_due`, or its twin `gd_looks_due`), and
## the looks step as when each body asked the screen itself (`step_looks_due`, the Tick before F4):
## the same bodies, the same frames, the same seconds, on one screen and split, for bodies walking on
## and off it, waiting off it, with no ticks since, and drawn on another canvas. The kernel writes
## the bits its twin writes.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

const STEP: float = 1.0 / 60.0

var _world: Fixture
var _layer: CanvasLayer = null


## A look that counts its steps and the seconds they were given.
class CountingLook:
	extends ActorLook
	var steps: int = 0
	var seconds: float = 0.0

	func step(delta: float) -> void:
		steps += 1
		seconds += delta


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	ScreenViews.withdraw(root.get_viewport())
	Actor.looks_native = true
	_world.free_all()
	if _layer != null:
		_layer.free()
		_layer = null


## Bodies on and off the screen and round its edge, each with a counting look; the last drawn on a
## canvas layer of its own (another canvas: it asks the screen itself).
func _bodies() -> Array[Actor]:
	var out: Array[Actor] = []
	var size: Vector2 = root.get_viewport().get_visible_rect().size
	var places: Array[Vector2] = [Vector2(10.0, 10.0), size * 0.5, size * 0.75, Vector2(-50.0, 40.0), Vector2(-200.0, -200.0), size + Vector2(90.0, 0.0), size + Vector2(120.0, 120.0), Vector2(-5000.0, 0.0), Vector2(size.x * 0.5 - 1.0, 30.0), Vector2(size.x * 0.5 + 1.0, size.y - 3.0)]
	for at in places:
		var body: Actor = _world.actor(at, [&"health"] as Array[StringName], Fixture.Scripted.new())
		body.add_look(CountingLook.new())
		out.append(body)
	_layer = CanvasLayer.new()
	root.add_child(_layer)
	var layered: Actor = _world.actor(Vector2(30.0, 30.0), [&"health"] as Array[StringName], Fixture.Scripted.new())
	layered.reparent(_layer)
	layered.add_look(CountingLook.new())
	out.append(layered)
	return out


## Two views side by side, each a half of the screen with its own world to screen.
func _split() -> ScreenViews:
	var size: Vector2 = root.get_viewport().get_visible_rect().size
	var views := ScreenViews.new()
	views.set_single(size, Transform2D.IDENTITY, 1)
	views.count = 2
	views.set_view(0, 1, Transform2D(0.0, Vector2(1.5, 1.5), 0.0, Vector2(-40.0, 10.0)), Vector2(size.x * 0.25, size.y * 0.5))
	views.set_view(1, 2, Transform2D(0.0, Vector2(0.75, 0.75), 0.0, Vector2(size.x * 0.5, -20.0)), Vector2(size.x * 0.75, size.y * 0.5))
	var half: float = size.x * 0.5
	var cells: Array[PackedVector2Array] = [PackedVector2Array([Vector2.ZERO, Vector2(half, 0.0), Vector2(half, size.y), Vector2(0.0, size.y)]), PackedVector2Array([Vector2(half, 0.0), Vector2(size.x, 0.0), size, Vector2(half, size.y)])]
	for view in 2:
		for at in 4:
			views.set_corner(view, at, cells[view][at])
		views.set_corners(view, 4)
	return views


func _look(body: Actor) -> CountingLook:
	for child in body.get_children():
		if child is CountingLook:
			return child as CountingLook
	return null


## Moves every body a little (on and off the screen as it goes) and leaves its looks a tick, but a
## few with no tick since.
func _tick(bodies: Array[Actor], frame: int) -> void:
	for i in bodies.size():
		var body: Actor = bodies[i]
		body.global_position += Vector2(37.0 * sin(0.21 * frame + i), 23.0 * cos(0.17 * frame + 2.0 * i))
		if (frame + i) % 5 != 0:
			body.tick_step(STEP, true)


## Every look's steps and seconds, and every body's waiting time, as bytes.
func _seen(bodies: Array[Actor]) -> PackedByteArray:
	var out: Array = []
	for body in bodies:
		var look: CountingLook = _look(body)
		out.append([look.steps, look.seconds, body._look_time])
	return var_to_bytes(out)


## The old Tick's frame: each body asks the screen itself, handed the frame's (none while split).
func _ask_each(bodies: Array[Actor]) -> void:
	var view: Viewport = root.get_viewport()
	var views: ScreenViews = ScreenViews.on(view)
	if views != null and views.is_split():
		view = null
	var screen: Rect2 = view.get_visible_rect().grow(Actor.ON_SCREEN_MARGIN) if view != null else Rect2()
	for body in bodies:
		if body.is_inside_tree():
			body.step_looks_due(view, screen)


## The pass steps each body's looks in the frames and for the seconds the body asking would, on one
## screen and split, the kernel and its twin alike.
func _check_pass_as_asking(split: bool) -> void:
	var kinds: Array = [true, false] if WallSlide.native_on() else [false]
	for native in kinds:
		var asked: Array[Actor] = _bodies()
		var passed: Array[Actor] = _bodies()
		var view: Viewport = root.get_viewport()
		if split:
			ScreenViews.publish(view, _split())
		Actor.looks_native = native
		var ids := PackedInt32Array()
		for body in passed:
			ids.append(body.id)
		var stepped: int = 0
		for frame in 90:
			_tick(asked, frame)
			_tick(passed, frame)
			_ask_each(asked)
			Actor.step_all_looks(_world.table, ids, ids.size(), view)
			check_equal(_seen(passed), _seen(asked), "frame %d (native %s, split %s): as each body asking" % [frame, native, split])
		for body in passed:
			stepped += _look(body).steps
		var waited: int = 0
		for body in passed:
			waited += 1 if _look(body).steps < 70 else 0
		check(stepped > 300 and waited >= 3, "looks stepped (%d) and some waited off screen (%d)" % [stepped, waited])
		ScreenViews.withdraw(view)
		_world.free_all()
		if _layer != null:
			_layer.free()
			_layer = null
		_world = Fixture.new(root)


func test_the_pass_steps_the_looks_as_each_body_asking() -> void:
	_check_pass_as_asking(false)


func test_the_pass_steps_the_looks_as_each_body_asking_while_split() -> void:
	_check_pass_as_asking(true)


## `BodyKernel.looks_due` lists the bodies, writes their seconds and their waiting times as
## `Actor.gd_looks_due` does, to the bit, on one screen and split.
func test_the_kernel_finds_the_due_looks_as_its_twin() -> void:
	if not WallSlide.native_on() and OS.get_environment("SPELLMERGE_NATIVE") == "required":
		check(false, "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
	if not WallSlide.native_on():
		return
	var bodies: Array[Actor] = _bodies()
	var ids := PackedInt32Array()
	for body in bodies:
		ids.append(body.id)
	# An open id with no actor (a plain node) and one with none: never listed.
	var plain := Node2D.new()
	root.add_child(plain)
	var plain_id: int = _world.table.open(0, 0)
	_world.table.set_node(plain_id, plain)
	ids.append(plain_id)
	ids.append(_world.table.open(0, 0))
	var view: Viewport = root.get_viewport()
	var screen: Rect2 = view.get_visible_rect().grow(Actor.ON_SCREEN_MARGIN)
	var canvas: RID = view.find_world_2d().canvas
	var due := PackedInt32Array()
	due.resize(ids.size())
	var seconds := PackedFloat64Array()
	seconds.resize(ids.size())
	var listed_seen: int = 0
	for split in [false, true]:
		var views: ScreenViews = _split() if split else null
		for frame in 60:
			_tick(bodies, frame)
			if frame % 7 == 0:
				# A long wait off screen: held at LOOK_TIME_MOST.
				bodies[frame % bodies.size()]._look_time = 0.9
			var times: Array[float] = []
			for body in bodies:
				times.append(body._look_time)
			var runs: Array = []
			for native in [true, false]:
				for i in bodies.size():
					bodies[i]._look_time = times[i]
				due.fill(-7)
				seconds.fill(-7.0)
				var listed: int = 0
				if native:
					listed = WallSlide.kernel().call(&"looks_due", _world.table.nodes(), ids, ids.size(), canvas, split, screen, views.to_screen if split else Actor.NO_VIEWS, views.count if split else 0, views.cell_points if split else PackedVector2Array(), views.cell_counts if split else PackedInt32Array(), ScreenViews.CORNERS_MOST, Actor.ON_SCREEN_MARGIN, Actor.LOOK_TIME_MOST, due, seconds)
				else:
					listed = Actor.gd_looks_due(_world.table.nodes(), ids, ids.size(), canvas, views, screen, due, seconds)
				var after: Array[float] = []
				for body in bodies:
					after.append(body._look_time)
				runs.append(var_to_bytes([listed, due, seconds, after]))
				listed_seen += listed
			check_equal(runs[0], runs[1], "frame %d (split %s): the kernel's list is the twin's" % [frame, split])
	check(listed_seen > 100, "bodies listed (%d)" % listed_seen)
	plain.free()
