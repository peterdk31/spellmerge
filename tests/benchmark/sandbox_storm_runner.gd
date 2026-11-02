extends Node
## The sandbox storm: a showcase of how many shots the game holds, and a count of how many of them
## land. One wizard in the real sandbox (Flow's MODE_SANDBOX: its room, its dummies and the `dev`
## staff on every button) stands among the training dummies and casts the sandbox's Y build
## (Flow.SANDBOX_START_CARDS[STORM_STAFF]: a fire nova split three times, 216 shots, whose every
## shot fires a frost nova split three times when it ends) with its button held through the real
## input path (a virtual device, as a bot holds it), so it casts whenever the staff is ready: about
## every three seconds, the cast delay its cards add. One cast asks
## for about 46,000 shots, far past the projectile cap, so the cap and the trigger pacing
## (`SpellLimits.FIRE_SHOTS_PER_STEP`) decide what flies.
##
## What it counts, from the first cast for SECONDS of game time: the casts, the shots made (the
## projectile manager's spawn sequence), the shots alive (mean and peak, sampled each physics step)
## against the cap, the shots the cap dropped, the trigger fires that waited for a later step, and
## for each dummy the shots that hit it (`projectile_hit` on its body) and the damage it took
## (Combat's health). It prints `BENCH: storm` lines and `STORM OK`, or `STORM FAILED` when the run
## did not start, nothing was cast, no shot hit a dummy or the log has an error.
##
## Run in a window it is the showcase: a line at the top shows the live numbers, and with `--stay`
## it keeps casting after the report. User arguments: `--seconds=N` (SECONDS), `--cap=N` (the projectile cap; the platform's by default), `--no-native` (the
## projectile manager's GDScript), `--stay`, `--profile` (the tree profile, tree_profile.gd: each
## script's time a physics step and a frame) and `--profile-signals` (with it, the time of each
## listener of the hot events, PROFILED_SIGNALS). It is the benchmark for drawing many shots that
## hit: the frame's parts and the manager's drawing (`BENCH: storm draw`) are printed beside the
## counts; in a window (or under xvfb-run) the renderer runs too.
##
## The wizard is placed among the dummies at the start and kept up (mana full, revived and
## protected), since the shooting dummy in the other lane shoots back.

const ErrorLogScript := preload("res://tests/smoke/error_log.gd")
const ProbeScript := preload("res://tests/benchmark/probe.gd")
const TreeProfileScript := preload("res://tests/benchmark/tree_profile.gd")
const FlowScript := preload("res://gameplay/flow/flow.gd")

const PLAYER: int = 0
## The staff that holds the split-and-nova build (Y; Flow.SANDBOX_START_CARDS).
const STORM_STAFF: int = 2
const STAFF_ACTIONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
## Where the wizard stands: in the middle of the training dummies of the sandbox's first lane
## (its dummy spawns 0 and 2 to 5).
const STORM_AT: Vector2 = Vector2(168.0, 150.0)
## Game seconds counted.
const SECONDS: float = 12.0
## The events whose listeners `--profile-signals` times: every event a shot's hit or end sends.
const PROFILED_SIGNALS: Array[StringName] = [&"projectile_hit", &"projectile_impact", &"projectile_expired", &"damage_dealt", &"hit_landed", &"status_applied", &"reaction_triggered"]
## Seconds between the updates of the window's line.
const SHOW_EVERY: float = 0.25

var seconds: float = SECONDS
var stay: bool = false

var _log: Logger = ErrorLogScript.new()
var _logging: bool = false
var _events: Node = null
var _flow: Node = null
var _input: Node = null
var _projectiles: Node = null
var _combat: Node = null
var _spells: Node = null
var _probe: Node = null
var _tree_profile: Node = null
var _draw_usec: int = 0
var _draw_max_usec: int = 0
var _draw_frames: int = 0
var _label: Label = null
var _wizard: Actor = null
var _downed: Downed = null
var _dummies: Array[Actor] = []
var _dummy_hits: PackedInt64Array = PackedInt64Array()
var _dummy_health: PackedFloat64Array = PackedFloat64Array()
var _active: bool = false
var _reported: bool = false
var _elapsed: float = 0.0
var _held: bool = false
var _casts: int = 0
var _hits: int = 0
var _seq_at: int = 0
var _dropped_at: int = 0
var _waited_at: int = 0
var _peak_shots: int = 0
var _shot_sum: int = 0
var _shot_samples: int = 0
var _show_left: float = 0.0


func _ready() -> void:
	OS.add_logger(_log)
	_logging = true
	var root: Node = get_tree().root
	_events = root.get_node_or_null("Events")
	_flow = root.get_node_or_null("Flow")
	_input = root.get_node_or_null("PlayerInput")
	_projectiles = root.get_node_or_null("Projectiles")
	_combat = root.get_node_or_null("Combat")
	_spells = root.get_node_or_null("Spells")
	if _events == null or _flow == null or _input == null or _projectiles == null or _combat == null:
		_finish(["the Events, Flow, PlayerInput, Projectiles and Combat autoloads must exist"])
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	stay = args.has("--stay")
	for arg in args:
		if arg.begins_with("--seconds="):
			seconds = maxf(arg.trim_prefix("--seconds=").to_float(), 1.0)
		elif arg.begins_with("--cap="):
			_projectiles.call("set_cap", maxi(arg.trim_prefix("--cap=").to_int(), 1))
	if args.has("--no-native"):
		_projectiles.set(&"native", false)
	if int(_input.call("add_virtual_device", PLAYER)) == int(_input.get("NO_DEVICE")):
		_finish(["player %d's virtual device is taken" % (PLAYER + 1)])
		return
	_events.connect("projectile_hit", _on_projectile_hit)
	_events.connect("spell_cast", _on_spell_cast)
	if DisplayServer.get_name() != "headless":
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		_label = Label.new()
		# At the bottom edge, clear of the HUD's panel at the top left.
		_label.position = Vector2(4.0, 346.0)
		_label.add_theme_font_size_override(&"font_size", 8)
		layer.add_child(_label)
	_events.emit_signal("sandbox_requested", PLAYER)
	var loading: Node = root.get_node_or_null("Loading")
	if loading != null and bool(loading.call("is_loading")):
		_events.connect("room_entered", _on_loaded, CONNECT_ONE_SHOT)
		return
	_start()


func _exit_tree() -> void:
	if _logging:
		_logging = false
		OS.remove_logger(_log)


func _on_loaded(_room_id: StringName) -> void:
	_start()


func _start() -> void:
	if not bool(_flow.get("sandbox")) or _flow.get("world") == null:
		_finish(["the sandbox did not start"])
		return
	_wizard = _flow.call("get_wizard", PLAYER) as Actor
	if _wizard == null:
		_finish(["player %d's wizard is missing" % (PLAYER + 1)])
		return
	_downed = Downed.of(_wizard)
	_wizard.global_position = STORM_AT
	for node: Node in _flow.call("dummies"):
		var dummy := node as Actor
		if dummy != null and is_instance_valid(dummy):
			_dummies.append(dummy)
			_dummy_hits.append(0)
			_dummy_health.append(float(_combat.call("health_of", dummy)))
	if _dummies.is_empty():
		_finish(["the sandbox has no dummies"])
		return
	var cards: Array = (FlowScript.SANDBOX_START_CARDS[STORM_STAFF] as Array)
	print("BENCH: storm: the sandbox's %s staff on %s, held for %.0f s at %s, %d dummies, cap %d, native %s" % [
		String(_wizard.caster.staffs[STORM_STAFF].id) if _wizard.caster.staffs.size() > STORM_STAFF and _wizard.caster.staffs[STORM_STAFF] != null else "?",
		" ".join(PackedStringArray(cards)), seconds, STORM_AT, _dummies.size(),
		int(_projectiles.call("get_cap")), "on" if bool(_projectiles.call("is_native")) else "off"])
	_seq_at = int(_projectiles.get("_next_seq"))
	_dropped_at = int(_projectiles.get("dropped"))
	_waited_at = int(_spells.get("fires_waited")) if _spells != null else 0
	_probe = ProbeScript.new()
	add_child(_probe)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--profile") or args.has("--profile-signals"):
		_tree_profile = TreeProfileScript.new()
		add_child(_tree_profile)
		if args.has("--profile-signals"):
			var names: Array[StringName] = []
			for name: StringName in PROFILED_SIGNALS:
				if _events.has_signal(name):
					names.append(name)
			_tree_profile.call(&"time_signals", _events, names)
	_active = true


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_keep_wizard_up()
	var count: int = int(_projectiles.call("get_count"))
	if not _reported:
		_peak_shots = maxi(_peak_shots, count)
		_shot_sum += count
		_shot_samples += 1
	_elapsed += delta
	_show_left -= delta
	if _label != null and _show_left <= 0.0:
		_show_left = SHOW_EVERY
		_label.text = _line(count)
	if not _reported and _elapsed >= seconds:
		_report()
		if not stay:
			_finish(_failures())


## The storm's button: held while the run counts (for good with `--stay`), let go after. While it
## counts, the manager's drawing is timed once more here (`update_draw` is safe to call again: it
## writes the same batches), as the manager's own `_process` gives no clock of its own.
func _process(_delta: float) -> void:
	if not _active:
		return
	if not _reported:
		var start: int = Time.get_ticks_usec()
		_projectiles.call(&"update_draw")
		var usec: int = Time.get_ticks_usec() - start
		_draw_usec += usec
		_draw_max_usec = maxi(_draw_max_usec, usec)
		_draw_frames += 1
	var hold: bool = stay or _elapsed < seconds
	if hold != _held:
		_input.call("send_virtual", PLAYER, STAFF_ACTIONS[STORM_STAFF], 1.0 if hold else 0.0)
		_held = hold


func _keep_wizard_up() -> void:
	if not is_instance_valid(_wizard):
		return
	for at in _wizard.caster.staff_count:
		_wizard.caster.set_mana(at, _wizard.caster.max_mana_of(at))
	if _downed != null:
		_downed.revive(PLAYER)
		_downed.protect(1.0)


func _on_projectile_hit(_caster: int, target: Node, _position: Vector2, _tag: int, _shot: int) -> void:
	if _reported or target == null:
		return
	for i in _dummies.size():
		var dummy: Actor = _dummies[i]
		if is_instance_valid(dummy) and (target == dummy or dummy.is_ancestor_of(target)):
			_dummy_hits[i] += 1
			_hits += 1
			return


func _on_spell_cast(player: int, _spell_id: StringName, _origin: Vector2, _direction: Vector2) -> void:
	if player == PLAYER and not _reported:
		_casts += 1


func _shots_made() -> int:
	return int(_projectiles.get("_next_seq")) - _seq_at


func _damage_of(i: int) -> float:
	var dummy: Actor = _dummies[i]
	if not is_instance_valid(dummy):
		return 0.0
	return maxf(_dummy_health[i] - float(_combat.call("health_of", dummy)), 0.0)


## The window's line: what flies now and what has landed.
func _line(count: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i in _dummies.size():
		parts.append(str(_dummy_hits[i]))
	return "shots %d (peak %d, cap %d)  made %d  casts %d  hits on dummies %d [%s]  %d FPS" % [
		count, _peak_shots, int(_projectiles.call("get_cap")), _shots_made(), _casts, _hits,
		" ".join(parts), roundi(Engine.get_frames_per_second())]


func _report() -> void:
	_reported = true
	var made: int = _shots_made()
	var mean: float = float(_shot_sum) / maxf(1.0, float(_shot_samples))
	var waited: int = (int(_spells.get("fires_waited")) if _spells != null else 0) - _waited_at
	print("BENCH: storm: %d casts, %d shots made (%.0f a second), alive mean %.0f peak %d of cap %d, dropped by the cap %d, trigger fires that waited %d" % [
		_casts, made, float(made) / seconds, mean, _peak_shots, int(_projectiles.call("get_cap")),
		int(_projectiles.get("dropped")) - _dropped_at, waited])
	var damage: float = 0.0
	for i in _dummies.size():
		var dummy: Actor = _dummies[i]
		var id: String = String(dummy.data.id) if is_instance_valid(dummy) and dummy.data != null else "?"
		var at: Vector2 = dummy.global_position if is_instance_valid(dummy) else Vector2.INF
		damage += _damage_of(i)
		print("BENCH: storm: dummy %d (%s at %s): %d hits, %.0f damage" % [i + 1, id, at, _dummy_hits[i], _damage_of(i)])
	print("BENCH: storm: %d hits on dummies in all (%.0f a second, %.2f%% of the shots made), %.0f damage" % [
		_hits, float(_hits) / seconds, 100.0 * float(_hits) / maxf(1.0, float(made)), damage])
	var frames: float = maxf(1.0, float(_draw_frames))
	print("BENCH: storm draw: the manager's update_draw avg %.3f ms max %.3f ms a frame (%d frames), %d shots and %d trails drawn at the end" % [
		float(_draw_usec) / frames / 1000.0, float(_draw_max_usec) / 1000.0, _draw_frames,
		int(_projectiles.get("drawn")), int(_projectiles.get("drawn_trails"))])
	if _probe != null:
		_probe.call("report")
	if _tree_profile != null:
		_tree_profile.call(&"report")


func _failures() -> Array[String]:
	var found: Array[String] = []
	if _casts == 0:
		found.append("the wizard never cast")
	if _hits == 0:
		found.append("no shot hit a dummy")
	var lines: Array[String] = _log.call("get_lines")
	for line in lines:
		found.append("the log has an error: " + line.trim_prefix("ERROR:").strip_edges())
	return found


func _finish(failed: Array[String]) -> void:
	_active = false
	if failed.is_empty():
		print("STORM OK: %d casts, %d hits on %d dummies" % [_casts, _hits, _dummies.size()])
		get_tree().quit(0)
	else:
		for reason in failed:
			printerr("STORM FAILED: " + reason)
		get_tree().quit(1)
