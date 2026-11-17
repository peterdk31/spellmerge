extends Node
## The arrival look's frame cost (arrive_cost.gd starts it; see there for the command). A node, so
## an export's main menu could add it as it adds the storm (hud/menus/main_menu, `--storm`).
##
## It plays the pinned crypt arena (tests/support/pinned_run.gd) after the game's own warm-up, then
## stops the Tick (`set_physics_process(false)`: nothing in the simulation steps, so a body held at
## a share of its arrival stays there) and frees the room's own enemies. Feel goes on drawing every
## frame from the state, as it does in play. For each variant and each count N it stands N enemies
## (the crypt's kinds in turn, on a grid over the screen), holds each at HOLD_SHARE of its arrival
## (mid-rise: half of it above the floor line), waits `warm` frames (the rise cue's dust has gone),
## then times `frames` frames:
##
## - `stand`: the N standing, not arriving (what N bodies cost with no arrival look);
## - `clip`: as built (`ArriveLook`: the root a clip parent, its mask drawn, its parts shifted);
## - `noclip`: the same, but after the cut each root is no clip parent and draws no mask (shifted
##   only: what the clip itself costs is `clip` less this);
## - `region`: `noclip` plus a per-sprite `region_rect` cut (the plan's fallback, a prototype here
##   only: each direct `Sprite2D` part keeps only its rows above the line; a part that is no sprite
##   is shifted but not cut, which a real fallback would have to solve);
## - `clip_nomarks`: as built with the marks hidden (the `draw_rect` rows of `_draw_mark` not drawn);
## - `clip_nocue`: as built with no rise cue (no dust motes, no sound), timed from the first frame,
##   against `clip` timed from the first frame too (`dust_ms`: the motes' share).
##
## Each line: the frame's wall time (mean, p95), the viewport's render time on the CPU and the GPU
## (`RenderingServer.viewport_get_measured_render_time_*`), and the hardware-independent counters
## (`RenderingServer.get_rendering_info`: draw calls, objects, primitives in the frame), and the
## GDScript of the look timed by hand: `cut` (called here in place of its own `frame_pre_draw`
## connection), one extra `step` a frame (Feel's own is not timed apart), and the variant's own
## work after the cut.

const WarmUp := preload("res://tests/support/warm_up.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
const PINNED_ROOM: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")

const VARIANTS: PackedStringArray = ["stand", "clip", "noclip", "region", "clip_nomarks", "clip_nocue"]
const COUNTS: PackedInt32Array = [0, 1, 4, 8, 16, 32]
## Where each body is held: 0.4 is the rise's start (ArriveLook.MARK_END), 1 its landing.
const HOLD_SHARE: float = 0.7
const FRAMES: int = 300
const WARM: int = 120
## The grid the bodies stand on, round the screen's middle (world pixels), filled in an order that
## spreads a few over the whole screen.
const GRID_COLUMNS: int = 8
const GRID_ROWS: int = 4
const GRID_STEP: Vector2 = Vector2(64.0, 64.0)

var _counts: PackedInt32Array = COUNTS
var _frames: int = FRAMES
var _warm: int = WARM
var _variants: PackedStringArray = VARIANTS
## Where each scene's last frame is saved (`--shots=DIR`; none: not saved), to check the variants by eye.
var _shots: String = ""
var _flow: Node = null
var _look: ArriveLook = null
var _parent: Node2D = null
var _kinds: Array[EnemyBase] = []
var _spots: PackedVector2Array = PackedVector2Array()
var _bodies: Array[Actor] = []
var _variant: String = ""
## The region prototype's sprites, laid out at spawn: each sprite, its body, its frame's texture
## rect, the top of its drawn rect in its body's pixels and its vertical scale.
var _sprites: Array[Sprite2D] = []
var _sprite_body: Array[Actor] = []
var _sprite_frame: Array[Rect2] = []
var _sprite_top: PackedFloat32Array = PackedFloat32Array()
var _sprite_scale: PackedFloat32Array = PackedFloat32Array()
## This frame's hand timings, in microseconds.
var _cut_us: int = 0
var _extra_us: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--counts="):
			_counts = PackedInt32Array()
			for part: String in arg.substr(9).split(","):
				_counts.append(maxi(part.to_int(), 0))
		elif arg.begins_with("--frames="):
			_frames = maxi(arg.substr(9).to_int(), 10)
		elif arg.begins_with("--warm="):
			_warm = maxi(arg.substr(7).to_int(), 0)
		elif arg.begins_with("--only="):
			_variants = arg.substr(7).split(",")
		elif arg.begins_with("--shots="):
			_shots = arg.substr(8)
			DirAccess.make_dir_recursive_absolute(_shots)
	_run.call_deferred()


func _run() -> void:
	var tree: SceneTree = get_tree()
	var root: Window = tree.root
	if not await WarmUp.run(root):
		_fail("the warm-up did not finish")
		return
	_flow = root.get_node("Flow")
	_flow.set("run_id_to_play", PinnedRun.pin(root.get_node("Registry"), PINNED_ROOM))
	root.get_node("PlayerInput").call("add_virtual_device", 0)
	_flow.call("start_run", 0)
	for i in 600:
		if not (_flow.get(&"_enemies") as Array).is_empty():
			break
		await tree.process_frame
	var enemies: Array = _flow.get(&"_enemies")
	if enemies.is_empty():
		_fail("the arena stood no enemy")
		return
	_parent = (enemies[0] as Node).get_parent() as Node2D
	_look = root.get_node("Feel").get_node_or_null(^"ArriveLook") as ArriveLook
	if _look == null:
		_fail("Feel has no ArriveLook")
		return
	# Nothing in the simulation steps from here: the bodies stay where they are held.
	root.get_node("Tick").set_physics_process(false)
	for enemy: Node in enemies.duplicate():
		_free_body(enemy as Actor)
	(_flow.get(&"arrivals") as Object).call("clear")
	_find_kinds(root.get_node("Registry"))
	if _kinds.is_empty():
		_fail("no enemy kinds")
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	if RenderingServer.frame_pre_draw.is_connected(_look.cut):
		RenderingServer.frame_pre_draw.disconnect(_look.cut)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	await tree.process_frame
	_lay_spots(root)
	print("BENCH: arrive on %s (%s), window %s, kinds %s, held at %.2f" % [RenderingServer.get_video_adapter_name(), OS.get_name(), str(DisplayServer.window_get_size()), ",".join(_kind_ids()), HOLD_SHARE])
	print("BENCH: arrive variant N frame_mean_ms frame_p95_ms render_cpu_ms render_gpu_ms draw_calls objects primitives cut_us step_us extra_us")
	for variant: String in _variants:
		for count: int in _counts:
			await _scene(variant, count)
	RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	RenderingServer.frame_pre_draw.connect(_look.cut)
	print("ARRIVE COST OK")
	tree.quit(0)


## One variant at one count: stood, warmed, timed, printed, freed.
func _scene(variant: String, count: int) -> void:
	var tree: SceneTree = get_tree()
	_variant = variant
	_look.visible = variant != "clip_nomarks"
	var cue: Callable = _look.play_cue
	if variant == "clip_nocue":
		_look.play_cue = Callable()
	var arrive: bool = variant != "stand"
	for n in count:
		var body := _flow.call("_stand_enemy", _parent, _kinds[n % _kinds.size()], _spots[n % _spots.size()], arrive) as Actor
		if body == null:
			continue
		if arrive:
			body.arrive_left = body.arrive_seconds * (1.0 - HOLD_SHARE)
		_bodies.append(body)
	if variant == "region":
		_lay_sprites()
	# The dust window is timed for the cue's pair (clip_nocue against clip from the first frame).
	var warm: int = 0 if variant == "clip_nocue" else _warm
	for i in warm:
		await tree.process_frame
	var walls: PackedFloat64Array = PackedFloat64Array()
	var cpus: PackedFloat64Array = PackedFloat64Array()
	var gpus: PackedFloat64Array = PackedFloat64Array()
	var calls: PackedFloat64Array = PackedFloat64Array()
	var objects: PackedFloat64Array = PackedFloat64Array()
	var primitives: PackedFloat64Array = PackedFloat64Array()
	var cut_us: PackedFloat64Array = PackedFloat64Array()
	var step_us: PackedFloat64Array = PackedFloat64Array()
	var extra_us: PackedFloat64Array = PackedFloat64Array()
	var vp: RID = get_tree().root.get_viewport_rid()
	await tree.process_frame
	var last: int = Time.get_ticks_usec()
	for f in _frames:
		var stepped: int = Time.get_ticks_usec()
		_look.step(_look.get(&"_table"), 0.0)
		step_us.append(float(Time.get_ticks_usec() - stepped))
		await tree.process_frame
		var now: int = Time.get_ticks_usec()
		walls.append(float(now - last) / 1000.0)
		last = now
		cpus.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		gpus.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		calls.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		objects.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)))
		primitives.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
		cut_us.append(float(_cut_us))
		extra_us.append(float(_extra_us))
	if not _shots.is_empty():
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png("%s/%s_%d.png" % [_shots, variant, count])
	print("BENCH: arrive %s %d %.2f %.2f %.2f %.2f %.0f %.0f %.0f %.0f %.0f %.0f" % [variant, _bodies.size(), _mean(walls), _p95(walls), _mean(cpus), _mean(gpus), _mean(calls), _mean(objects), _mean(primitives), _mean(cut_us), _mean(step_us), _mean(extra_us)])
	if variant == "clip_nocue" and count > 0:
		print("BENCH: arrive dust window (first %d frames, no warm) clip_nocue %d: %.2f ms; run --only=clip --warm=0 for the same with the cue" % [_frames, count, _mean(walls)])
	_look.play_cue = cue
	_look.visible = true
	for body: Actor in _bodies.duplicate():
		_free_body(body)
	_bodies.clear()
	_sprites.clear()
	_sprite_body.clear()
	_sprite_frame.clear()
	_sprite_top.clear()
	_sprite_scale.clear()
	# The look puts back what it cut once the bodies are gone.
	for i in 10:
		await tree.process_frame


## Just before the frame is drawn, in place of the look's own connection: its cut, timed, then the
## variant's own work after it.
func _pre_draw() -> void:
	var before: int = Time.get_ticks_usec()
	_look.cut()
	var cut: int = Time.get_ticks_usec()
	_cut_us = cut - before
	if _variant == "noclip" or _variant == "region":
		for body: Actor in _bodies:
			if is_instance_valid(body):
				_unclip(body)
		if _variant == "region":
			_cut_sprites()
	_extra_us = Time.get_ticks_usec() - cut


## The body is no clip parent and draws no mask: its parts stay shifted by the look.
static func _unclip(body: Actor) -> void:
	body.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	RenderingServer.canvas_item_clear(body.get_canvas_item())


## The prototype's layout: every direct, not top-level `Sprite2D` of every body, its frame made its
## region (one frame, not centred, its old place as its offset) so a cut is a shorter region.
func _lay_sprites() -> void:
	for body: Actor in _bodies:
		for i in body.get_child_count():
			var sprite := body.get_child(i) as Sprite2D
			if sprite == null or sprite.top_level or sprite.texture == null:
				continue
			var drawn: Rect2 = sprite.get_rect()
			var whole: Rect2 = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, sprite.texture.get_size())
			var cell: Vector2 = whole.size / Vector2(sprite.hframes, sprite.vframes)
			var frame := Rect2(whole.position + cell * Vector2(sprite.frame_coords), cell)
			sprite.hframes = 1
			sprite.vframes = 1
			sprite.region_enabled = true
			sprite.region_rect = frame
			sprite.centered = false
			sprite.offset = drawn.position
			_sprites.append(sprite)
			_sprite_body.append(body)
			_sprite_frame.append(frame)
			_sprite_top.append(sprite.position.y + drawn.position.y * absf(sprite.scale.y))
			_sprite_scale.append(maxf(absf(sprite.scale.y), 0.001))


## Each sprite keeps its rows that are above its body's line once shifted (whole rows).
func _cut_sprites() -> void:
	for s in _sprites.size():
		var body: Actor = _sprite_body[s]
		if not is_instance_valid(body):
			continue
		var size: float = maxf(absf(body.size), 0.01)
		var line: float = ArriveLook.body_bottom(body) / size
		var by: float = maxf(_look.shift_of(body), 0.0) / size
		var frame: Rect2 = _sprite_frame[s]
		var rows: float = clampf(floorf((line - _sprite_top[s] - by) / _sprite_scale[s]), 0.0, frame.size.y)
		_sprites[s].region_rect = Rect2(frame.position, Vector2(frame.size.x, rows))


func _free_body(body: Actor) -> void:
	if body == null or not is_instance_valid(body):
		return
	(_flow.get(&"_enemies") as Array).erase(body)
	body.get_parent().remove_child(body)
	body.queue_free()


## The registry's enemies that are no boss and no dummy, in id order.
func _find_kinds(registry: Node) -> void:
	for data: Resource in registry.call("get_all", &"enemies"):
		var enemy := data as EnemyBase
		if enemy == null or enemy.boss or enemy.scene == null or String(enemy.id).contains("dummy"):
			continue
		_kinds.append(enemy)
	_kinds.sort_custom(func(a: EnemyBase, b: EnemyBase) -> bool: return String(a.id) < String(b.id))


func _kind_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for kind: EnemyBase in _kinds:
		ids.append(String(kind.id))
	return ids


## The grid round the screen's middle, in the order its spots are used: every other column and row
## first, so 4 or 8 bodies are spread over the screen.
func _lay_spots(root: Window) -> void:
	var middle: Vector2 = root.get_canvas_transform().affine_inverse() * (root.get_visible_rect().size * 0.5)
	var origin: Vector2 = middle - GRID_STEP * Vector2(GRID_COLUMNS - 1, GRID_ROWS - 1) * 0.5 + Vector2(0.0, 12.0)
	for pass_row in 2:
		for pass_column in 2:
			for row in range(pass_row, GRID_ROWS, 2):
				for column in range(pass_column, GRID_COLUMNS, 2):
					_spots.append((origin + GRID_STEP * Vector2(column, row)).round())


static func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


static func _p95(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return sorted[mini(int(float(sorted.size()) * 0.95), sorted.size() - 1)]


func _fail(message: String) -> void:
	printerr("ARRIVE COST FAILED: " + message)
	get_tree().quit(1)
