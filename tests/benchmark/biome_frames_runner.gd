extends "res://tests/benchmark/stress_runner.gd"
## The performance pass's measure (the owner, 2026-11-20; targets 16.7 ms a frame on desktop and
## 33 ms on the web): four local players in a generated crypt biome of 16 rooms, busy fights in the
## rooms they stand in, drawn by the game's own split screen (Feel's `split_screen.gd`) in both of
## its modes, Dynamic (the Voronoi split) and Equal (panes), over seeded runs.
##
## Each scenario is the stress run's (stress_runner.gd: four bots with built spells, a crowd kept up
## and the shots held at the cap, its checks and its `BENCH:` lines) on the crypt run of a replay
## seed (`Frames.record`, as the 4-bot test plays one), with:
##  - **spread** "apart": each wizard put in a fight room of its own (the four largest fight rooms
##    of the map), the crowd shared out over those rooms, so the screen is split four ways; or
##    "together": all four in one fight room, one picture (the baseline the split is measured from);
##  - **split**: the pause menu's "Split screen" mode (`SplitScreenSetting`), set through Feel;
##  - the load: the desktop's 200 enemies and shot cap, or the web's 100 and cap.
##
## On top of the stress run's lines, each prints (`_report_more`):
##  - `BENCH: biome frames <label> map`: the seed, the map's rooms and the rooms the wizards stand in;
##  - `... frame`: the frame's average, p95 and worst, and the views drawn a frame;
##  - `... gpu`: each kind of viewport's render time a frame (the split's views, the light buffers,
##    the floor marks, the root, the rest), GPU and the renderer's CPU, from `RenderingServer`'s
##    viewport timing (no GPU timer queries on the web: there only the frame is a measure);
##  - `... feel parts`: Feel's step by part (`Feel.profile_parts`), milliseconds a drawn frame;
##  - `... worst frames`: the slowest WORST frames, each with its ticks, the tick's time and the GPU's.
## With `--profile` the tree profile rides along (each script's process time: the HUD's among them).
## `--picture=WxH` draws the game's picture at that size (the root's `content_scale_size`; the shipped
## picture is PictureGrid.SIZE, 640 x 360): the cameras draw the same world finer and the light keeps its
## resolution (gameplay/feel/picture_grid.gd; the owner's decision of 2026-11-21: 1280x720 measured before
## the 64 x 64 art). The window must be at least that big (`xvfb-run -s "-screen 0 1280x720x24"`).
## `--shots` saves the screen once a scenario, halfway through its measured window, to
## `user://biome_frames/<label>.png` (one slow frame, outside the averages' sense).
##
## Started by `biome_frames.gd` (it needs a window: a GPU, or `xvfb-run`, where llvmpipe draws).

const SEEDS: PackedInt64Array = [11, 23, 37]
## A map with fewer rooms than this is reported (the crypt makes 12 to 16; the pass measures 16).
const ROOMS_WANTED: int = 16
## The slowest frames reported.
const WORST: int = 5
## Seconds between scans for new viewports to time (a light buffer or a view is made on first use).
const RESCAN: float = 0.5
## How far from a wall a stress enemy or a wizard is put (world pixels), and tries a spot.
const CLEAR_RADIUS: float = 10.0
const SPOT_TRIES: int = 24
const FIGHT_KIND: StringName = &"fight"

var _frames_service: Node = null
var _replay_seed: int = 0
## The rooms the wizards stand in this scenario (map indexes) and their world rects.
var _rooms: PackedInt32Array = PackedInt32Array()
var _room_rects: Array[Rect2] = []
var _spot_turn: int = 0
## The viewports timed, by kind, and their sums over the measured frames (milliseconds).
var _timed: Array[Viewport] = []
var _timed_kind: PackedStringArray = PackedStringArray()
var _gpu_by_kind: Dictionary[String, float] = {}
var _cpu_by_kind: Dictionary[String, float] = {}
var _rescan_left: float = 0.0
## Each measured frame: its time, the views drawn, its ticks, the ticks' time and the GPU's.
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _frame_views: PackedInt32Array = PackedInt32Array()
var _frame_ticks: PackedInt32Array = PackedInt32Array()
var _frame_tick_ms: PackedFloat32Array = PackedFloat32Array()
var _frame_gpu_ms: PackedFloat32Array = PackedFloat32Array()
## Each measured frame's draw calls and primitives (`RenderingServer.get_rendering_info`): the work
## drawn, which unlike the times does not move with a busy machine.
var _frame_calls: PackedInt32Array = PackedInt32Array()
var _frame_primitives: PackedInt32Array = PackedInt32Array()
var _last_usec: int = 0
var _ticks_seen: int = 0
var _tick_usec_seen: int = 0
var _counting: bool = false
## `--shots`: whether to save a screen a scenario, and whether this scenario's is saved.
var _shots: bool = false
var _shot_taken: bool = false
const SHOTS_DIR: String = "user://biome_frames"


func _init() -> void:
	rows = scenario_rows()
	scenarios = []
	for index in rows.size():
		scenarios.append(index)
	result_word = "BIOME FRAMES"
	_shots = (OS.get_cmdline_user_args() + OS.get_cmdline_args()).has("--shots")


func _enter_tree() -> void:
	var picture: Vector2i = picture_asked(OS.get_cmdline_user_args() + OS.get_cmdline_args())
	if picture != Vector2i.ZERO:
		get_tree().root.content_scale_size = picture
		print("BENCH: biome frames picture %dx%d" % [picture.x, picture.y])


## The picture `--picture=WxH` asks for among `args` (zero: none asked, the project's).
static func picture_asked(args: PackedStringArray) -> Vector2i:
	for arg in args:
		if arg.begins_with("--picture="):
			var parts: PackedStringArray = arg.trim_prefix("--picture=").split("x")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				return Vector2i(maxi(parts[0].to_int(), 1), maxi(parts[1].to_int(), 1))
	return Vector2i.ZERO


## Every scenario: for each seed, the two splits apart at the desktop's and the web's load, and the
## wizards together once at each load (the one picture both splits share).
static func scenario_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seed in SEEDS:
		for load: Array in [["desktop", 200, ProjectileManagerScript.DEFAULT_CAP_DESKTOP, true], ["web", 100, ProjectileManagerScript.DEFAULT_CAP_WEB, false]]:
			for row: Array in [["together", SplitScreenSetting.DYNAMIC], ["apart", SplitScreenSetting.DYNAMIC], ["apart", SplitScreenSetting.EQUAL]]:
				var split_word: String = "dynamic" if int(row[1]) == SplitScreenSetting.DYNAMIC else "equal"
				var label: String = "seed %d %s %s %s" % [seed, load[0], row[0], split_word]
				if row[0] == "together":
					label = "seed %d %s together" % [seed, load[0]]
				out.append({"label": label, "enemies": load[1], "shots": load[2], "desktop_only": load[3], "seed": seed, "spread": row[0], "split": row[1]})
	return out


func _start_play(scenario: Dictionary) -> void:
	_frames_service = get_tree().root.get_node_or_null("Frames")
	_replay_seed = int(scenario.get("seed", SEEDS[0]))
	if _feel != null and _feel.has_method(&"set_split_mode"):
		_feel.call(&"set_split_mode", int(scenario.get("split", SplitScreenSetting.DYNAMIC)))
	_flow.set(&"run_id_to_play", &"crypt")
	if _frames_service == null:
		_events.emit_signal("play_requested", 0)
		return
	# The run of this replay seed, as the 4-bot test plays one: the map and its fights are the seed's.
	_frames_service.call(&"record", &"play_requested", 0, _replay_seed)


func _scenario_started(scenario: Dictionary) -> void:
	var map: BiomeMap = _map()
	if map == null:
		_failures.append("%s: no biome map" % scenario["label"])
		return
	if map.rooms() < ROOMS_WANTED:
		print("BENCH: biome frames %s: the map has %d rooms, not %d" % [scenario["label"], map.rooms(), ROOMS_WANTED])
	# A row's "room": "largest" fight rooms (the default), the "smallest", or "start": the wizards
	# left where the run put them (the start room, the rooms round it not yet entered).
	var room_rule: String = String(scenario.get("room", "largest"))
	var biome: Object = _flow.get(&"biome")
	if room_rule == "start":
		_rooms = PackedInt32Array([_room_of(map, _wizards[0].global_position)])
	else:
		_rooms = _fight_rooms(map, 1 if scenario.get("spread", "apart") == "together" else _wizards.size(), room_rule == "smallest")
	_room_rects.clear()
	for room in _rooms:
		_room_rects.append(biome.call(&"room_rect", room) as Rect2)
	var grid: RoomGrid = _projectiles.call(&"grid") as RoomGrid
	for index in (0 if room_rule == "start" else _wizards.size()):
		var rect: Rect2 = _room_rects[index % _room_rects.size()]
		var at: Vector2 = rect.get_center() + Vector2(24.0 * float(index / _room_rects.size()), 0.0)
		if grid != null:
			at = grid.nearest_ground(at, CLEAR_RADIUS)
		_wizards[index].global_position = at
		# As a gate puts the party in (Flow's `_open_gate`): the move is a placing, not a walk.
		_wizards[index].placed()
		_wizards[index].find_room()
	var names := PackedStringArray()
	for room in _rooms:
		names.append("%d %s (%s)" % [room, map.room_templates[room], map.room_kinds[room]])
	print("BENCH: biome frames %s map: replay seed %d, %d rooms, %d bridges, style %s; wizards in %s" % [scenario["label"], _replay_seed, map.rooms(), map.bridges(), map.style, ", ".join(names)])
	_timed.clear()
	_timed_kind.clear()
	_rescan_left = 0.0
	_counting = false
	_shot_taken = false
	if _feel != null and _feel.has_method(&"profile_parts"):
		_feel.call(&"profile_parts", Time.get_ticks_usec)


## The map of the run under way (null when none).
func _map() -> BiomeMap:
	var biome: Object = _flow.get(&"biome") if _flow != null else null
	return biome.get(&"map") as BiomeMap if biome != null else null


## `count` fight rooms of `map` far apart (the largest first, then each the room farthest from
## those taken, by their rects' middles), so wizards put in them part into a view each: rooms side
## by side can fit one picture, the party camera zoomed out over them.
func _fight_rooms(map: BiomeMap, count: int, smallest: bool = false) -> PackedInt32Array:
	var biome: Object = _flow.get(&"biome")
	var fights: Array[int] = []
	for room in map.rooms():
		if map.room_kinds[room] == FIGHT_KIND:
			fights.append(room)
	fights.sort_custom(func(a: int, b: int) -> bool:
		var area_a: float = (biome.call(&"room_rect", a) as Rect2).get_area()
		var area_b: float = (biome.call(&"room_rect", b) as Rect2).get_area()
		return area_a < area_b if smallest else area_a > area_b)
	var out := PackedInt32Array()
	if fights.is_empty():
		out.append(0)
		return out
	out.append(fights[0])
	while out.size() < mini(count, fights.size()):
		var best: int = -1
		var best_far: float = -1.0
		for room in fights:
			if out.has(room):
				continue
			var middle: Vector2 = (biome.call(&"room_rect", room) as Rect2).get_center()
			var nearest: float = INF
			for taken in out:
				nearest = minf(nearest, middle.distance_to((biome.call(&"room_rect", taken) as Rect2).get_center()))
			if nearest > best_far:
				best_far = nearest
				best = room
		out.append(best)
	return out


## The room of `map` whose rect holds `at` (0 when none does).
func _room_of(map: BiomeMap, at: Vector2) -> int:
	var biome: Object = _flow.get(&"biome")
	for room in map.rooms():
		if (biome.call(&"room_rect", room) as Rect2).has_point(at):
			return room
	return 0


## The crowd shared out over the rooms the wizards stand in, each on clear ground.
func _enemy_spot() -> Vector2:
	if _room_rects.is_empty():
		return super()
	var rect: Rect2 = _room_rects[_spot_turn % _room_rects.size()].grow(-24.0)
	_spot_turn += 1
	var grid: RoomGrid = _projectiles.call(&"grid") as RoomGrid
	var at: Vector2 = rect.get_center()
	for i in SPOT_TRIES:
		at = rect.position + Vector2(_rng.randf() * rect.size.x, _rng.randf() * rect.size.y)
		if grid == null or not grid.circle_blocked(at, CLEAR_RADIUS, true):
			return at
	return grid.nearest_ground(rect.get_center(), CLEAR_RADIUS) if grid != null else at


func _measuring_started() -> void:
	_frame_ms.clear()
	_frame_views.clear()
	_frame_ticks.clear()
	_frame_tick_ms.clear()
	_frame_gpu_ms.clear()
	_frame_calls.clear()
	_frame_primitives.clear()
	_gpu_by_kind.clear()
	_cpu_by_kind.clear()
	_last_usec = Time.get_ticks_usec()
	var tick: TickScript = get_tree().root.get_node_or_null("Tick") as TickScript
	_ticks_seen = tick.count if tick != null else 0
	_tick_usec_seen = _tick_usec(tick)
	if _feel != null and _feel.has_method(&"profile_parts"):
		_feel.call(&"profile_parts", Time.get_ticks_usec)
	_counting = true


func _process(delta: float) -> void:
	super(delta)
	if not _active:
		return
	_rescan_left -= delta
	if _rescan_left <= 0.0:
		_rescan_left = RESCAN
		_scan_viewports()
	if not _counting:
		return
	if _shots and not _shot_taken and _elapsed >= warm_up + measure * 0.5:
		_shot_taken = true
		_save_shot(String(rows[scenarios[_current]]["label"]))
	var now: int = Time.get_ticks_usec()
	var tick: TickScript = get_tree().root.get_node_or_null("Tick") as TickScript
	var tick_usec: int = _tick_usec(tick)
	var gpu: float = 0.0
	for i in _timed.size():
		var viewport: Viewport = _timed[i]
		if not is_instance_valid(viewport) or not _draws(viewport):
			continue
		var rid: RID = viewport.get_viewport_rid()
		var kind: String = _timed_kind[i]
		var g: float = RenderingServer.viewport_get_measured_render_time_gpu(rid)
		gpu += g
		_gpu_by_kind[kind] = _gpu_by_kind.get(kind, 0.0) + g
		_cpu_by_kind[kind] = _cpu_by_kind.get(kind, 0.0) + RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_frame_ms.append(float(now - _last_usec) / 1000.0)
	_frame_views.append(_views_drawn())
	_frame_ticks.append((tick.count if tick != null else 0) - _ticks_seen)
	_frame_tick_ms.append(float(tick_usec - _tick_usec_seen) / 1000.0)
	_frame_gpu_ms.append(gpu)
	_frame_calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_frame_primitives.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	_last_usec = now
	_ticks_seen = tick.count if tick != null else 0
	_tick_usec_seen = tick_usec


## True when `viewport` draws this frame (a viewport not drawn keeps its last measured time).
static func _draws(viewport: Viewport) -> bool:
	var sub := viewport as SubViewport
	if sub == null:
		return true
	if sub.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		return false
	if sub.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE or sub.render_target_update_mode == SubViewport.UPDATE_WHEN_PARENT_VISIBLE:
		return sub.is_visible_in_tree() if sub.has_method(&"is_visible_in_tree") else true
	return true


## The screen as last drawn, saved as `SHOTS_DIR/<label>.png` (spaces as underscores).
func _save_shot(label: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [SHOTS_DIR, label.replace(" ", "_")]
	if image != null and image.save_png(path) == OK:
		print("BENCH: biome frames %s: screen saved to %s" % [label, ProjectSettings.globalize_path(path)])


## The Tick's profiled time so far (microseconds; 0 with no profile).
func _tick_usec(tick: TickScript) -> int:
	var total: int = 0
	if tick != null:
		for usec in tick.step_profile:
			total += usec
	return total


## The views the split screen draws now (0: one picture).
func _views_drawn() -> int:
	var split: Object = _feel.get(&"split_screen") if _feel != null else null
	return (split.call(&"views") as Array).size() if split != null else 0


## Every viewport in the tree timed (`RenderingServer` measures a viewport only when asked), by kind.
func _scan_viewports() -> void:
	var root: Viewport = get_tree().root
	var found: Array[Node] = root.find_children("*", "SubViewport", true, false)
	found.append(root)
	for node in found:
		var viewport := node as Viewport
		if viewport == null or _timed.has(viewport):
			continue
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
		_timed.append(viewport)
		_timed_kind.append(_kind_of(viewport, root))


## What a viewport draws, for the report: the root, a split view, the void view, a light buffer,
## the floor marks, or another.
static func _kind_of(viewport: Viewport, root: Viewport) -> String:
	if viewport == root:
		return "root"
	var named: String = String(viewport.name)
	var parent: String = String(viewport.get_parent().name) if viewport.get_parent() != null else ""
	var path: String = String(viewport.get_path())
	if named.begins_with("View") and path.contains("Split"):
		return "views"
	if named == "VoidView":
		return "void view"
	if path.contains("Light") or parent.contains("Light") or named.contains("Light") or named.contains("light"):
		return "light buffers"
	if path.contains("Mark") or named.contains("Mark"):
		return "floor marks"
	return "other (%s)" % named


func _report_more(label: String) -> void:
	_counting = false
	var frames: int = _frame_ms.size()
	if frames == 0:
		_failures.append("%s: no frames counted" % label)
		return
	var sorted: PackedFloat32Array = _frame_ms.duplicate()
	sorted.sort()
	var total: float = 0.0
	var views: int = 0
	for i in frames:
		total += _frame_ms[i]
		views += _frame_views[i]
	var by_views: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
	for i in frames:
		by_views[clampi(_frame_views[i], 0, 4)] += 1
	var row: Dictionary = rows[scenarios[_current]]
	var apart_views: int = clampi(_wizards.size(), 1, 4)
	if row.get("spread", "apart") == "apart" and by_views[apart_views] < frames / 2:
		print("BENCH WARNING: biome frames %s: the wizards stood apart but most frames drew other than %d views (%s): not a %d-way split" % [label, apart_views, str(by_views), apart_views])
	print("BENCH: biome frames %s frame: avg %.2f ms, p95 %.2f ms, worst %.2f ms over %d frames, %.2f views a frame (frames by views 0-4: %s)" % [label, total / float(frames), sorted[int(float(frames - 1) * 0.95)], sorted[frames - 1], frames, float(views) / float(frames), str(by_views)])
	var tick_total: float = 0.0
	var ticks_total: int = 0
	var gpu_total: float = 0.0
	var calls_total: float = 0.0
	var primitives_total: float = 0.0
	for i in frames:
		calls_total += _frame_calls[i]
		primitives_total += _frame_primitives[i]
		tick_total += _frame_tick_ms[i]
		ticks_total += _frame_ticks[i]
		gpu_total += _frame_gpu_ms[i]
	var cpu_total: float = 0.0
	for kind: String in _cpu_by_kind:
		cpu_total += _cpu_by_kind[kind]
	# The frame apart: the simulation (the Tick's steps), the renderer's GPU time and its CPU time.
	print("BENCH: biome frames %s split (ms a frame): frame %.2f, sim %.2f (%.2f ticks), gpu %.2f, renderer cpu %.2f; %.0f draw calls, %.0f primitives a frame" % [label, total / float(frames), tick_total / float(frames), float(ticks_total) / float(frames), gpu_total / float(frames), cpu_total / float(frames), calls_total / float(frames), primitives_total / float(frames)])
	var kinds: Array = _gpu_by_kind.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return _gpu_by_kind[a] > _gpu_by_kind[b])
	var parts := PackedStringArray()
	for kind: String in kinds:
		parts.append("%s %.2f (cpu %.2f)" % [kind, _gpu_by_kind[kind] / float(frames), _cpu_by_kind.get(kind, 0.0) / float(frames)])
	print("BENCH: biome frames %s gpu (ms a frame): %s" % [label, ", ".join(parts)])
	var profile: PackedInt64Array = _feel.get(&"step_profile") if _feel != null and _feel.has_method(&"profile_parts") else PackedInt64Array()
	if not profile.is_empty():
		var names: PackedStringArray = _feel.get(&"PROFILE_PARTS")
		var feel_parts := PackedStringArray()
		var feel_total: int = 0
		for i in profile.size():
			feel_total += profile[i]
			feel_parts.append("%s %.3f" % [names[i], float(profile[i]) / float(frames) / 1000.0])
		print("BENCH: biome frames %s feel parts (ms a frame, total %.3f): %s" % [label, float(feel_total) / float(frames) / 1000.0, ", ".join(feel_parts)])
		_feel.set(&"step_profile", PackedInt64Array())
	var order: Array[int] = []
	for i in frames:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _frame_ms[a] > _frame_ms[b])
	var worst := PackedStringArray()
	for i in order.slice(0, WORST):
		worst.append("#%d %.1f ms (%d ticks %.1f ms, gpu %.1f ms, %d views)" % [i, _frame_ms[i], _frame_ticks[i], _frame_tick_ms[i], _frame_gpu_ms[i], _frame_views[i]])
	print("BENCH: biome frames %s worst frames: %s" % [label, ", ".join(worst)])


func _scenario_ending() -> void:
	_counting = false
	if _frames_service != null and _frames_service.has_method(&"stop_recording"):
		_frames_service.call(&"stop_recording")
	_room_rects.clear()
	_rooms = PackedInt32Array()
	_timed.clear()
	_timed_kind.clear()
