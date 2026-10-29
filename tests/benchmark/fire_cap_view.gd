extends SceneTree
## The fire cost burst of fire_cap_runner.gd, to watch: a nova split three times goes off in the
## middle of a 100-target crowd every few seconds, with `on hit` and a payload, on the real
## autoloads (the projectile manager draws the shots, Feel the impacts), and a panel shows what
## each physics step costs: the step time (the game's physics time, all autoloads together), the
## payloads fired and waiting this step, the shots in flight, and a graph of the last seconds of
## step times against the 16.7 ms frame. Not a test: it runs until the window is closed.
##
##   1, 2, 3   payload: a bolt, a split bolt, a nova
##   P         pacing on (`SpellLimits.FIRE_SHOTS_PER_STEP` shots a step) or off
##   T         the trigger on or off (the same burst without payloads, to compare)
##   Space     a burst now
##
## With the user argument `--auto` it runs each case for PHASE_SECONDS on its own (idle, the burst
## without a trigger, each payload paced, the nova unpaced, idle with the panel hidden) and prints
## a `VIEW:` line for each: the real frame time (average, worst, frames over one and two 60 FPS
## frames), the worst physics and process time and the most physics steps in one frame, so a
## slow window can be told apart from a slow burst; then it quits.
##
## godot --path . --script res://tests/benchmark/fire_cap_view.gd
## godot --path . --script res://tests/benchmark/fire_cap_view.gd -- --auto

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const StaffKit := preload("res://tests/support/staff_kit.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const FLOOR := preload("res://art/tilesets/crypt/floor.svg")

const SCREEN := Vector2(640.0, 360.0)
const WALL: float = 8.0
const CROWD_CENTER := Vector2(400.0, 180.0)
## Seconds between bursts.
const EVERY: float = 3.0
const CARRIER: Array[StringName] = [&"split", &"split", &"split", &"nova"]
const PAYLOADS: Array[Array] = [[&"bolt"], [&"split", &"bolt"], [&"nova"]]
const PAYLOAD_NAMES: Array[String] = ["a bolt", "a split bolt", "a nova"]
## The cases `--auto` runs, and how long each.
const PHASES: Array[Dictionary] = [
	{"label": "idle (no bursts)", "burst": false},
	{"label": "burst, no trigger", "trigger": false},
	{"label": "burst, bolt payload, paced", "payload": 0},
	{"label": "burst, split bolt payload, paced", "payload": 1},
	{"label": "burst, nova payload, paced", "payload": 2},
	{"label": "burst, nova payload, unpaced", "payload": 2, "paced": false},
	{"label": "idle, panel hidden", "burst": false, "panel": false},
]
const PHASE_SECONDS: float = 6.0
## Physics steps the graph shows.
const HISTORY: int = 240
const FRAME_MS: float = 1000.0 / 60.0


## A target: a small ring on the floor.
class Dot:
	extends Node2D

	func _draw() -> void:
		draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 16, Color(0.9, 0.85, 0.7, 0.5), 1.0)


## The step time graph and the numbers.
class Readout:
	extends Control
	var history: PackedFloat32Array = PackedFloat32Array()
	var lines: PackedStringArray = PackedStringArray()

	func _draw() -> void:
		var box := Rect2(Vector2(8.0, 8.0), Vector2(250.0, 96.0))
		draw_rect(Rect2(Vector2(4.0, 4.0), Vector2(258.0, 168.0)), Color(0.0, 0.0, 0.0, 0.72))
		# 0 to 40 ms high; the 16.7 ms frame as a line.
		var top: float = 40.0
		var frame_y: float = box.end.y - box.size.y * (FRAME_MS / top)
		draw_line(Vector2(box.position.x, frame_y), Vector2(box.end.x, frame_y), Color(1.0, 0.35, 0.3, 0.8), 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(box.end.x - 52.0, frame_y - 2.0), "16.7 ms", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.45, 0.4))
		var n: int = history.size()
		for i in n:
			var ms: float = minf(history[i], top)
			var x: float = box.position.x + box.size.x * float(i) / float(HISTORY)
			var h: float = box.size.y * ms / top
			var tint: Color = Color(0.45, 0.85, 0.5) if history[i] < FRAME_MS else Color(1.0, 0.4, 0.35)
			draw_line(Vector2(x, box.end.y), Vector2(x, box.end.y - h), tint, 1.0)
		var y: float = box.end.y + 12.0
		for line in lines:
			draw_string(ThemeDB.fallback_font, Vector2(10.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.95, 0.95, 0.9))
			y += 10.0


var _shots: Node
var _spells: Node
var _panel: Readout
var _caster: int = -1
var _payload: int = 2
var _paced: bool = true
var _trigger: bool = true
var _clock: float = 0.0
var _made: int = 0
var _waited: int = 0
var _worst: float = 0.0
var _burst_worst: float = 0.0
var _burst_fires: int = 0
var _peak_fires: int = 0
var _bursting: bool = true
var _auto: bool = false
var _phase: int = -1
var _phase_clock: float = 0.0
var _last_usec: int = 0
var _steps_this_frame: int = 0
var _frames: int = 0
var _frame_sum: float = 0.0
var _frame_worst: float = 0.0
var _over_one: int = 0
var _over_two: int = 0
var _physics_worst: float = 0.0
var _process_worst: float = 0.0
var _steps_most: int = 0


func _initialize() -> void:
	await process_frame
	_shots = root.get_node_or_null(^"Projectiles")
	_spells = root.get_node_or_null(^"Spells")
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if _shots == null or _spells == null or actors == null:
		push_error("fire_cap_view: the Projectiles, Spells and Actors autoloads must exist")
		quit(1)
		return
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOOR
	floor_sprite.centered = false
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(Vector2.ZERO, SCREEN)
	floor_sprite.z_index = -10
	root.add_child(floor_sprite)
	_shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	_shots.call("set_cap", ManagerScript.DEFAULT_CAP_DESKTOP)
	_shots.call("set_walls", [
		Rect2(0.0, 0.0, SCREEN.x, WALL), Rect2(0.0, SCREEN.y - WALL, SCREEN.x, WALL),
		Rect2(0.0, 0.0, WALL, SCREEN.y), Rect2(SCREEN.x - WALL, 0.0, WALL, SCREEN.y),
	] as Array[Rect2])
	_caster = ActorSeats.seat_wizards(actors, 1)[0]
	for i in 100:
		var dot := Dot.new()
		dot.position = CROWD_CENTER + Vector2(float(i % 10) - 4.5, float(i / 10) - 4.5) * 14.0
		root.add_child(dot)
		_shots.call("add_target", dot, 6.0, ManagerScript.LAYER_ENEMY)
	var layer := CanvasLayer.new()
	layer.layer = 10
	root.add_child(layer)
	_panel = Readout.new()
	_panel.size = SCREEN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_panel)
	_build()
	physics_frame.connect(_on_physics_frame)
	_auto = OS.get_cmdline_user_args().has("--auto")
	print("VIEW: renderer %s, adapter %s (%s), driver %s" % [ProjectSettings.get_setting("rendering/renderer/rendering_method"), RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), " ".join(OS.get_video_adapter_driver_info())])
	if _auto:
		_next_phase()


## `--auto`: report the case that ran and start the next, or quit after the last.
func _next_phase() -> void:
	if _phase >= 0:
		var frames: float = maxf(1.0, float(_frames))
		print("VIEW: %s: frame avg %.1f ms worst %.1f ms, %d of %d frames over 16.7 ms, %d over 33 ms; worst physics %.1f ms, worst process %.1f ms, up to %d physics steps in a frame" % [
			PHASES[_phase]["label"], _frame_sum / frames, _frame_worst, _over_one, _frames, _over_two,
			_physics_worst, _process_worst, _steps_most])
	_phase += 1
	if _phase >= PHASES.size():
		quit(0)
		return
	var phase: Dictionary = PHASES[_phase]
	_bursting = phase.get("burst", true)
	_trigger = phase.get("trigger", true)
	_payload = phase.get("payload", 2)
	_paced = phase.get("paced", true)
	_panel.visible = phase.get("panel", true)
	_build()
	_phase_clock = 0.0
	# The first burst half a second in, the next one EVERY later.
	_clock = EVERY - 0.5
	_frames = 0
	_frame_sum = 0.0
	_frame_worst = 0.0
	_over_one = 0
	_over_two = 0
	_physics_worst = 0.0
	_process_worst = 0.0
	_steps_most = 0


func _build() -> void:
	var cards: Array[StringName] = []
	if _trigger:
		cards.append(&"on_hit")
	cards.append_array(CARRIER)
	if _trigger:
		for card: StringName in PAYLOADS[_payload]:
			cards.append(card)
	StaffKit.build(_spells, _caster, 0, cards)
	_spells.set("fire_shots_per_step", SpellLimits.FIRE_SHOTS_PER_STEP if _paced else 1 << 30)


func _burst() -> void:
	_shots.call("set_anchor", _caster, CROWD_CENTER)
	_spells.call("cast_staff", _caster, 0, CROWD_CENTER, Vector2.RIGHT, 1.0e9)
	_burst_worst = 0.0
	_burst_fires = 0
	_peak_fires = 0
	_clock = 0.0


func _process(_delta: float) -> bool:
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		return true
	var now: int = Time.get_ticks_usec()
	if _last_usec > 0:
		var ms: float = float(now - _last_usec) / 1000.0
		_frames += 1
		_frame_sum += ms
		_frame_worst = maxf(_frame_worst, ms)
		_over_one += 1 if ms > FRAME_MS + 1.0 else 0
		_over_two += 1 if ms > FRAME_MS * 2.0 + 1.0 else 0
		_process_worst = maxf(_process_worst, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_steps_most = maxi(_steps_most, _steps_this_frame)
	_last_usec = now
	_steps_this_frame = 0
	if _auto:
		_phase_clock += _delta
		if _phase_clock >= PHASE_SECONDS:
			_next_phase()
	return false


func _on_physics_frame() -> void:
	_clock += 1.0 / 60.0
	if _clock >= EVERY and _bursting:
		_burst()
	_steps_this_frame += 1
	var ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_physics_worst = maxf(_physics_worst, ms)
	var made: int = int(_spells.get("fires_made"))
	var waited: int = int(_spells.get("fires_waited"))
	var fired: int = made - _made
	var waiting: int = waited - _waited
	_made = made
	_waited = waited
	_burst_worst = maxf(_burst_worst, ms)
	_burst_fires += fired
	_peak_fires = maxi(_peak_fires, fired)
	_panel.history.append(ms)
	if _panel.history.size() > HISTORY:
		_panel.history.remove_at(0)
	_panel.lines = PackedStringArray([
		"payload: %s   [1] [2] [3]" % (PAYLOAD_NAMES[_payload] if _trigger else "none (trigger off)"),
		"pacing: %s   [P]    trigger: %s   [T]" % ["%d shots a step" % SpellLimits.FIRE_SHOTS_PER_STEP if _paced else "off", "on" if _trigger else "off"],
		"step %.2f ms    shots in flight %d" % [ms, int(_shots.call("get_count"))],
		"this burst: %d fires, most %d in one step" % [_burst_fires, _peak_fires],
		"this burst: worst step %.2f ms    waiting now %d" % [_burst_worst, waiting],
		"[Space] a burst now    next in %.1f s" % maxf(EVERY - _clock, 0.0),
	])
	_panel.queue_redraw()
	_keys()


var _down: Dictionary = {}


## Each key once per press.
func _pressed(key: Key) -> bool:
	var now: bool = Input.is_physical_key_pressed(key)
	var was: bool = _down.get(key, false)
	_down[key] = now
	return now and not was


func _keys() -> void:
	for i in 3:
		if _pressed(KEY_1 + i):
			_payload = i
			_trigger = true
			_build()
			_burst()
	if _pressed(KEY_P):
		_paced = not _paced
		_build()
		_burst()
	if _pressed(KEY_T):
		_trigger = not _trigger
		_build()
		_burst()
	if _pressed(KEY_SPACE):
		_burst()
