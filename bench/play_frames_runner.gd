extends "res://bench/biome_frames_runner.gd"
## The frames of a run as it is played, not stressed (the owner's report of 2026-11-21: "I'm
## noticing worse performance in the game now"): the biome frames' crypt biome of seed 11, its
## measures and its `BENCH:` lines (biome_frames_runner.gd), with the load a room walked through
## or fought in has, not the stress crowd and the shot cap: 1 to 4 players, no filler shots.
##
## Each at the desktop's defaults, and the one wizard's also at the web's ("web": the web build's
## mote ring, `MoteCap.DEFAULT_WEB`, and shot cap), where the owner plays:
##  - **1p near**: one wizard standing in a fight room with no foe, the camera at its own zoom (the
##    room, the void round it and the rooms not yet entered on screen);
##  - **1p start web** and **1p start** (the desktop's): one wizard standing where the run puts it (the start room, the rooms round it
##    not yet entered and the void on screen);
##  - **1p small far web**: one wizard fighting a few foes in the smallest fight room, the rooms
##    and the void round it on screen;
##  - **1p far**: one wizard fighting a few foes round it, the camera on the wizard at its own
##    zoom (the name is from 2026-11-19 to 2026-11-23, when the camera zoomed out to hold close
##    foes, #872, down to 0.5; the rows keep their names, the shipped benchmark's keys);
##  - **Np together** (2 to 4): the party in one fight room among a few foes, one picture;
##  - **Np apart dynamic / equal**: each wizard in a fight room of its own with a few foes, the
##    split screen in each mode.
##
## Started by `play_frames.gd` (it needs a window: a GPU, or `xvfb-run`, where llvmpipe draws).

const PLAY_SEED: int = 11
## The foes a room's fight holds (each room the wizards stand in gets its share of these).
const FOES_A_ROOM: int = 12
## `--off=` names and the Feel setting each switches off.
const EffectsQualityScript := preload("res://gameplay/feel/effects_quality.gd")
const PASS_SETTERS: Dictionary[String, StringName] = {"light": &"set_spell_light", "shadows": &"set_shadows", "air": &"set_ambient_particles", "fog": &"set_fog"}


## The rows' words for `--quality=` and each one's fixed "Effects" mode (`EffectsSetting`).
const QUALITY_MODES: Dictionary[String, int] = {"low": EffectsSetting.LOW, "medium": EffectsSetting.MEDIUM, "high": EffectsSetting.HIGH}


## The row each scenario's effects were drawn at, by label ("Low", "Medium", "High"; the shipped
## benchmark's table shows it).
var effects_drawn: Dictionary[String, String] = {}
## `--lake`: a big lake beside each wizard (the floor's look, docs/milestones/floor-look.md), wet
## again every LAKE_WATER seconds and struck by lightning every LAKE_STRIKE (live, spent, wet), so the
## floor's drawing, lights and motes are in every frame measured.
const LAKE_OFFSET := Vector2(96.0, 0.0)
const LAKE_RADIUS: float = 72.0
const LAKE_WATER: float = 3.0
const LAKE_STRIKE: float = 2.0
var _lake: bool = false
var _lake_water: float = 0.0
var _lake_strike: float = 0.0


func _init() -> void:
	super()
	rows = with_quality(play_rows(), quality_asked(OS.get_cmdline_user_args() + OS.get_cmdline_args()))
	scenarios = []
	for index in rows.size():
		scenarios.append(index)
	result_word = "PLAY FRAMES"


## Every scenario: one wizard near and far, then 2 to 4 players together and apart in each split.
static func play_rows() -> Array[Dictionary]:
	var cap: int = ProjectileManagerScript.DEFAULT_CAP_DESKTOP
	var out: Array[Dictionary] = []
	out.append(_row("1p near web", 1, 0, true, "together", SplitScreenSetting.DYNAMIC, ProjectileManagerScript.DEFAULT_CAP_WEB, MoteCap.DEFAULT_WEB))
	out.append(_row("1p far web", 1, FOES_A_ROOM, false, "together", SplitScreenSetting.DYNAMIC, ProjectileManagerScript.DEFAULT_CAP_WEB, MoteCap.DEFAULT_WEB))
	var start: Dictionary = _row("1p start web", 1, 0, true, "together", SplitScreenSetting.DYNAMIC, ProjectileManagerScript.DEFAULT_CAP_WEB, MoteCap.DEFAULT_WEB)
	start["room"] = "start"
	out.append(start)
	var small: Dictionary = _row("1p small far web", 1, FOES_A_ROOM, false, "together", SplitScreenSetting.DYNAMIC, ProjectileManagerScript.DEFAULT_CAP_WEB, MoteCap.DEFAULT_WEB)
	small["room"] = "smallest"
	out.append(small)
	var start_desktop: Dictionary = _row("1p start", 1, 0, true, "together", SplitScreenSetting.DYNAMIC, cap)
	start_desktop["room"] = "start"
	out.append(start_desktop)
	out.append(_row("1p near", 1, 0, true, "together", SplitScreenSetting.DYNAMIC, cap))
	out.append(_row("1p far", 1, FOES_A_ROOM, false, "together", SplitScreenSetting.DYNAMIC, cap))
	for players: int in [2, 3, 4]:
		out.append(_row("%dp together" % players, players, FOES_A_ROOM, false, "together", SplitScreenSetting.DYNAMIC, cap))
		out.append(_row("%dp apart dynamic" % players, players, FOES_A_ROOM * players, false, "apart", SplitScreenSetting.DYNAMIC, cap))
		out.append(_row("%dp apart equal" % players, players, FOES_A_ROOM * players, false, "apart", SplitScreenSetting.EQUAL, cap))
	# The shipped benchmark's split rows at the web's settings (bench/benchmark.gd, `WEB_LABELS`).
	out.append(_row("2p apart dynamic web", 2, FOES_A_ROOM * 2, false, "apart", SplitScreenSetting.DYNAMIC, ProjectileManagerScript.DEFAULT_CAP_WEB, MoteCap.DEFAULT_WEB))
	out.append(_row("4p apart equal web", 4, FOES_A_ROOM * 4, false, "apart", SplitScreenSetting.EQUAL, ProjectileManagerScript.DEFAULT_CAP_WEB, MoteCap.DEFAULT_WEB))
	return out


static func _row(label: String, players: int, enemies: int, idle: bool, spread: String, split: int, cap: int, motes: int = MoteCap.DEFAULT_DESKTOP) -> Dictionary:
	return {"label": label, "players": players, "enemies": enemies, "shots": cap, "fill": 0, "idle": idle, "seed": PLAY_SEED, "spread": spread, "split": split, "motes": motes}


## The effects' rows `--quality=` asks for in `args`: low, medium or high alone, or each of them
## (`--quality=each`); high when it names none.
static func quality_asked(args: PackedStringArray) -> PackedStringArray:
	for arg in args:
		if arg.begins_with("--quality="):
			var asked: String = arg.trim_prefix("--quality=")
			if asked == "each":
				return PackedStringArray(QUALITY_MODES.keys())
			if QUALITY_MODES.has(asked):
				return PackedStringArray([asked])
	return PackedStringArray(["high"])


## `scenarios` at each row of `qualities` (its "quality"); with more than one, each label says its row
## ("1p near low"), so `--only=` names them so.
static func with_quality(scenarios: Array[Dictionary], qualities: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for scenario: Dictionary in scenarios:
		for quality: String in qualities:
			var row: Dictionary = scenario.duplicate()
			row["quality"] = quality
			if qualities.size() > 1:
				row["label"] = "%s %s" % [scenario["label"], quality]
			out.append(row)
	return out


## The scenario's mote ring (the "Particles" setting) taken before its run starts, and the passes
## `--off=` names switched off by their settings (light, shadows, air, fog: Feel's `set_spell_light`,
## `set_shadows`, `set_ambient_particles`, `set_fog`), to tell what each pass costs; the effects drawn
## at the scenario's fixed row (its "quality", `--quality=`: Feel's `set_effects_mode`,
## gameplay/feel/effects_quality.gd; never Auto, whose row follows the machine), told in a `BENCH:` line.
func _start_play(scenario: Dictionary) -> void:
	var quality: String = String(scenario.get("quality", "high"))
	if _feel != null and _feel.has_method(&"set_effects_mode"):
		_feel.call(&"set_effects_mode", QUALITY_MODES.get(quality, EffectsSetting.HIGH))
		var drawn: int = int(((_feel.call(&"spectacle") as Object).get(&"quality") as Object).get(&"level"))
		effects_drawn[String(scenario["label"])] = String(EffectsQualityScript.Level.keys()[drawn]).capitalize()
		print("BENCH: play frames %s: effects at %s" % [scenario["label"], String(EffectsQualityScript.Level.keys()[drawn]).to_lower()])
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--off=") and _feel != null:
			for part in arg.trim_prefix("--off=").split(","):
				var setter: StringName = PASS_SETTERS.get(part, &"")
				if setter != &"" and _feel.has_method(setter):
					_feel.call(setter, false)
					print("BENCH: play frames %s: %s off" % [scenario["label"], part])
	_lake = (OS.get_cmdline_user_args() + OS.get_cmdline_args()).has("--lake")
	_lake_water = 0.0
	_lake_strike = LAKE_STRIKE
	if _lake:
		print("BENCH: play frames %s: a lake beside each wizard" % scenario["label"])
	if _feel != null and _feel.has_method(&"set_mote_cap"):
		var taken: int = int(_feel.call(&"set_mote_cap", int(scenario.get("motes", MoteCap.DEFAULT_DESKTOP))))
		print("BENCH: play frames %s: mote ring %d rows" % [scenario["label"], taken])
	super(scenario)


## `--lake`: each wizard's lake watered and struck on its clock (`delta` seconds on).
func _process(delta: float) -> void:
	super(delta)
	if not _lake or not _active:
		return
	_lake_water -= delta
	_lake_strike -= delta
	var events: Node = get_tree().root.get_node_or_null("Events")
	if events == null:
		return
	for each in _wizards:
		if not is_instance_valid(each):
			continue
		var wizard := each as Node2D
		var middle: Vector2 = wizard.global_position + LAKE_OFFSET
		if _lake_water <= 0.0:
			events.emit_signal(&"floor_touched", -1, &"water", middle, LAKE_RADIUS, 0)
		if _lake_strike <= 0.0:
			events.emit_signal(&"floor_touched", -1, &"lightning", middle, 0.0, 0)
	if _lake_water <= 0.0:
		_lake_water = LAKE_WATER
	if _lake_strike <= 0.0:
		_lake_strike = LAKE_STRIKE
