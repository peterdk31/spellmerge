extends SceneTree
## The shot trails on the GPU (performance, 2026-11-02): a fixed scene of shots stepped by hand, in
## a window, timed and optionally saved frame by frame. Not run in the build (it needs a GPU, or a
## virtual display: llvmpipe stands in for one, slower, but its time follows the vertex count).
##
##   godot --path . --script res://tests/benchmark/trail_gpu.gd               time each scenario
##   godot --path . --script res://tests/benchmark/trail_gpu.gd -- --frames=DIR
##                                    also save each scenario's frames as DIR/<scenario>_<n>.png
##   ... -- --plain                   no lightning and no dashes (one batch per layer: a change of
##                                    batching cannot move one trail over another)
##   ... -- --no-time                 save the frames only
##   ... -- --only=some               run one scenario (few, some, many)
##   ... -- --timed=N                 time N frames (TIMED_FRAMES; the first quarter left out)
##   ... -- --light                   with spell light (gameplay/feel/spell_light.gd, P3a) on the
##                                    shots: its light buffer's GPU time is printed too
##   ... -- --motes                   the trails' particles as motes (spell spectacle P1d): the
##                                    trails drop their particle slots and a mote pool (Feel's,
##                                    gameplay/feel/mote.gd) throws them; the births' and the throws'
##                                    CPU time is printed too. At every count unless --motes-below=N.
##
## Each scenario fills its own projectile manager (not the autoload) with `shots` shots from a
## seeded generator: four seats' and the enemies' (no actor) bolts, a few orbits, a fifth with
## lightning's look, the rest with up to three of the other card kinds, a third bouncing off the
## room's border, and two wizards dashing. A shot that ends is replaced, so the count holds. The
## manager is stepped and drawn by hand at a fixed 60 steps a second, so a frame is the same on
## every run of the same code: a change that should look the same can be compared pixel by pixel
## (the saved frames of two checkouts). It prints `BENCH: trail gpu` lines: the GPU time of a frame
## (median and p95 over the measured frames, `RenderingServer` viewport timing), the trail
## instances, the vertices the batches send a frame (each runs the trail's vertex stage) and the
## pool's shares.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
## Where motes are drawn (Feel's MOTE_Z), and the pool's rows (the desktop default).
const MOTE_Z: int = 16
const MOTE_CAP: int = 32768
## Where spell light is applied (Feel's LIGHT_Z).
const LIGHT_Z: int = 15

const ROOM := Rect2(0.0, 0.0, 640.0, 360.0)
const DT: float = 1.0 / 60.0
## Steps before the first frame is kept (the trails grow to their length), frames saved and frames timed.
const WARM_STEPS: int = 90
const SAVED_FRAMES: int = 4
const TIMED_FRAMES: int = 120
const SCENARIOS: Array[Dictionary] = [
	{"label": "few", "shots": 60},
	{"label": "some", "shots": 400},
	{"label": "many", "shots": 3000},
]

var _mgr: ManagerScript = null
var _bus: EventsScript = null
var _table: Node = null
var _rng := RandomNumberGenerator.new()
var _frames_dir: String = ""
var _plain: bool = false
var _time: bool = true
var _only: String = ""
var _timed: int = TIMED_FRAMES
var _light: bool = false
var _spell_light: SpellLightScript = null
var _use_motes: bool = false
var _motes_below: int = 1 << 30
var _motes: MotesScript = null
var _mote_kinds: Array[MoteKind] = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			_frames_dir = arg.substr(9)
			DirAccess.make_dir_recursive_absolute(_frames_dir)
		elif arg == "--plain":
			_plain = true
		elif arg == "--no-time":
			_time = false
		elif arg.begins_with("--only="):
			_only = arg.substr(7)
		elif arg == "--light":
			_light = true
		elif arg == "--motes":
			_use_motes = true
		elif arg.begins_with("--motes-below="):
			_motes_below = arg.substr(14).to_int()
		elif arg.begins_with("--timed="):
			_timed = maxi(arg.substr(8).to_int(), 4)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print("BENCH: trail gpu on %s" % RenderingServer.get_video_adapter_name())
	if _use_motes:
		var registry := RegistryScript.new()
		registry.scan()
		for kind: Resource in registry.get_all(&"motes"):
			_mote_kinds.append(kind as MoteKind)
		registry.free()
	for scenario: Dictionary in SCENARIOS:
		if _only.is_empty() or scenario["label"] == _only:
			await _scenario(scenario)
	_teardown()
	print("TRAIL GPU OK")
	quit(0)


func _teardown() -> void:
	if _spell_light != null:
		_spell_light.release()
		_spell_light.free()
		_spell_light = null
	if _motes != null:
		_motes.free()
		_motes = null
	for node: Node in [_mgr, _bus, _table]:
		if node != null and is_instance_valid(node):
			node.free()
	_mgr = null
	_bus = null
	_table = null


func _scenario(scenario: Dictionary) -> void:
	_teardown()
	_rng.seed = 20261102
	_bus = EventsScript.new()
	_table = ActorSeats.table()
	_mgr = ManagerScript.new()
	_mgr.actors = _table
	_mgr.events = _bus
	_mgr.set_bounds(ROOM.grow(32.0))
	var shots: int = scenario["shots"]
	_mgr.set_cap(maxi(shots + 64, 256))
	root.add_child(_mgr)
	if _light:
		_spell_light = SpellLightScript.new(_mgr, LIGHT_Z)
		root.add_child(_spell_light)
		RenderingServer.viewport_set_measure_render_time(_spell_light.viewport.get_viewport_rid(), true)
	if _use_motes:
		_motes = MotesScript.new(MOTE_CAP, MOTE_Z, _mote_kinds)
		root.add_child(_motes)
		_mgr.spark_motes = true
		_mgr.spark_motes_below = _motes_below
	# Stepped and drawn by hand only (see the top).
	_mgr.set_physics_process(false)
	_mgr.set_process(false)
	_mgr.set_walls([Rect2(0.0, 0.0, 640.0, 8.0), Rect2(0.0, 352.0, 640.0, 8.0), Rect2(0.0, 0.0, 8.0, 360.0), Rect2(632.0, 0.0, 8.0, 360.0)] as Array[Rect2])
	for seat in 4:
		_mgr.set_anchor(seat, Vector2(160.0 + 100.0 * seat, 180.0))
	for i in shots:
		_spawn()
	for n in WARM_STEPS:
		_step(n, shots)
	var label: String = scenario["label"]
	if not _frames_dir.is_empty():
		for f in SAVED_FRAMES:
			_step(WARM_STEPS + f, shots)
			_mgr.update_draw(1.0)
			_throw_motes(WARM_STEPS + f)
			await process_frame
			await process_frame
			var image: Image = root.get_texture().get_image()
			image.save_png("%s/%s_%d.png" % [_frames_dir, label, f])
	var times: PackedFloat64Array = PackedFloat64Array()
	var light_times: PackedFloat64Array = PackedFloat64Array()
	var draw_times: PackedFloat64Array = PackedFloat64Array()
	var wall_times: PackedFloat64Array = PackedFloat64Array()
	var mote_times: PackedFloat64Array = PackedFloat64Array()
	var births: int = 0
	var last: int = Time.get_ticks_usec()
	for f in _timed if _time else 0:
		_step(WARM_STEPS + SAVED_FRAMES + f, shots)
		var before: int = Time.get_ticks_usec()
		_mgr.update_draw(1.0)
		draw_times.append(float(Time.get_ticks_usec() - before) / 1000.0)
		births += _mgr.spark_birth_count
		before = Time.get_ticks_usec()
		_throw_motes(WARM_STEPS + SAVED_FRAMES + f)
		mote_times.append(float(Time.get_ticks_usec() - before) / 1000.0)
		await process_frame
		var now: int = Time.get_ticks_usec()
		wall_times.append(float(now - last) / 1000.0)
		last = now
		times.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		if _spell_light != null:
			light_times.append(RenderingServer.viewport_get_measured_render_time_gpu(_spell_light.viewport.get_viewport_rid()))
	if times.is_empty():
		print("BENCH: trail gpu %s: frames saved" % label)
		return
	# The first frames after a change of mesh compile and upload: leave a quarter out.
	times = times.slice(_timed / 4)
	var sorted: PackedFloat64Array = times.duplicate()
	sorted.sort()
	print("BENCH: trail gpu %s: %d shots (%d drawn, %d trail instances, %d vertices a frame), GPU median %.2f ms, p95 %.2f ms; shares particles %.2f, tails %.2f, stride %d" % [
		label, shots, _mgr.drawn, _mgr.drawn + _mgr.drawn_trails, _vertices(), sorted[sorted.size() / 2],
		sorted[int(float(sorted.size()) * 0.95)], _mgr.particle_share, _mgr.trail_share, _mgr.spark_stride])
	draw_times = draw_times.slice(_timed / 4)
	draw_times.sort()
	wall_times = wall_times.slice(_timed / 4)
	wall_times.sort()
	print("BENCH: trail gpu %s: update_draw CPU median %.2f ms; a whole frame median %.1f ms (wall clock)" % [
		label, draw_times[draw_times.size() / 2], wall_times[wall_times.size() / 2]])
	if _motes != null:
		mote_times = mote_times.slice(_timed / 4)
		mote_times.sort()
		print("BENCH: trail gpu %s: motes %s, %.1f births a frame, throwing them CPU median %.3f ms, %d mote chunks shown" % [
			label, "on" if _mgr.sparks_as_motes else "off (over --motes-below)", float(births) / float(_timed), mote_times[mote_times.size() / 2], _motes.chunks_shown()])
	if not light_times.is_empty():
		light_times = light_times.slice(_timed / 4)
		light_times.sort()
		print("BENCH: trail gpu %s: spell light buffer GPU median %.2f ms, p95 %.2f ms (the apply pass is in the frame's)" % [
			label, light_times[light_times.size() / 2], light_times[int(float(light_times.size()) * 0.95)]])


## The trails' particles of the last `update_draw` thrown as motes, and the pool stepped to frame `n`.
func _throw_motes(n: int) -> void:
	if _motes == null:
		return
	_motes.give_off(_mgr.spark_births, _mgr.spark_birth_count)
	_motes.step(float(n) * DT)


## The vertices the batches send the GPU this frame: each batch's instances x its mesh's vertices.
func _vertices() -> int:
	var total: int = 0
	for child in _mgr.get_children():
		var batch := child as MultiMeshInstance2D
		if batch != null and batch.multimesh.mesh is ArrayMesh:
			total += batch.multimesh.visible_instance_count * (batch.multimesh.mesh as ArrayMesh).surface_get_array_len(0)
		elif batch != null:
			total += batch.multimesh.visible_instance_count * 4
	return total


## One step: the dashes, the step, and new shots for the ones that ended.
func _step(n: int, shots: int) -> void:
	if n % 30 == 0 and not _plain:
		for seat in 2:
			_mgr.follow_caster(seat, Color(1.0, 0.6, 0.2), ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_EMBERS + seat])), 0.25)
	for seat in 2:
		var angle: float = float(n) * 0.09 + float(seat) * PI
		_mgr.set_anchor(seat, Vector2(320.0, 180.0) + Vector2(cos(angle), sin(angle)) * 120.0)
	_mgr.step(DT)
	while _mgr.get_count() < shots:
		_spawn()


func _spawn() -> void:
	var caster: int = _rng.randi_range(-1, 3)
	var radius: float = _rng.randf_range(2.0, 8.0)
	var slot: int = -1
	if _rng.randf() < 0.06 and caster >= 0:
		slot = _mgr.spawn_orbit(caster, _rng.randf_range(20.0, 60.0), _rng.randf() * TAU, _rng.randf_range(2.0, 5.0), _rng.randf_range(0.8, 2.0), radius)
	else:
		var at := Vector2(_rng.randf_range(24.0, 616.0), _rng.randf_range(24.0, 336.0))
		var velocity := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(90.0, 520.0)
		slot = _mgr.spawn(caster, at, velocity, _rng.randf_range(0.5, 2.0), radius)
		if slot >= 0 and _rng.randf() < 0.33:
			_mgr.set_bounce(slot, 3)
	if slot < 0:
		return
	var kinds := PackedInt32Array()
	if _rng.randf() < 0.2 and not _plain:
		kinds.append(ManagerScript.LOOK_SPARKS)
	for k in _rng.randi_range(0, 3):
		var kind: int = _rng.randi_range(1, ManagerScript.LOOK_COUNT - 1)
		if kind != ManagerScript.LOOK_SPARKS:
			kinds.append(kind)
	_mgr.set_look(slot, ManagerScript.pack_look(kinds))
	_mgr.set_core(slot, Color.from_hsv(_rng.randf(), 0.7, 1.0))
