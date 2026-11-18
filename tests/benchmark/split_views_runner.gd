extends "res://tests/benchmark/stress_runner.gd"
## The camera spike (connected biomes CB1, docs/milestones/connected-biomes.md), kept as a stress
## test (the owner, 2026-11-18): the stress fight (stress_runner.gd: four bots with built spells, a
## crowd and the shots held at the cap, full effects) drawn as a Voronoi split screen of 2, 3 and 4
## views (`voronoi_views.gd`: a SubViewport a view, each masked to its cell), against the same
## fight drawn once. Run it again whenever the camera, the motes or the light change.
##
## The scenarios, each the stress run's (its checks, its `BENCH:` lines) with its views:
##  - desktop (the desktop's 200 enemies and shot cap): no split, 1 view (the split's own cost:
##    the world drawn through one SubViewport), 2, 3 and 4 views; then 4 views with the light off
##    and 4 with the fewest motes (the fallbacks a view might need);
##  - web (the web's 100 enemies and cap): no split, 2, 3 and 4 views, 4 with the light off and 4
##    with the fewest motes. A web build runs only these.
## Each prints `BENCH: split views <label>` (the GPU time a frame of the views, the light buffers
## and the root) beside the stress run's frame lines, and the run ends with `SPLIT VIEWS OK`.
##
## `--shots` saves the screen once a scenario, halfway through its measured window, to
## `user://split_views/<label>.png` (outside the measured frames' averages it is one slow frame).
##
## Started by `split_views.gd` from the command line (it needs a window: a GPU, or `xvfb-run`,
## where llvmpipe draws), or by the main menu on `--split-views` in the Linux Test and Web Test
## exports, as `--stress` is.

const ViewsScript := preload("res://tests/benchmark/voronoi_views.gd")

## The fewest motes (the "Particles" setting's Minimal).
const FEWEST_MOTES: int = MoteCap.STOPS[0]
## Where `--shots` saves the screens.
const SHOTS_DIR: String = "user://split_views"
const SPLIT_SCENARIOS: Array[Dictionary] = [
	{"label": "desktop no split", "enemies": 200, "shots": ProjectileManagerScript.DEFAULT_CAP_DESKTOP, "views": 0, "desktop_only": true},
	{"label": "desktop 1 view", "enemies": 200, "shots": ProjectileManagerScript.DEFAULT_CAP_DESKTOP, "views": 1, "desktop_only": true},
	{"label": "desktop 2 views", "enemies": 200, "shots": ProjectileManagerScript.DEFAULT_CAP_DESKTOP, "views": 2, "desktop_only": true},
	{"label": "desktop 3 views", "enemies": 200, "shots": ProjectileManagerScript.DEFAULT_CAP_DESKTOP, "views": 3, "desktop_only": true},
	{"label": "desktop 4 views", "enemies": 200, "shots": ProjectileManagerScript.DEFAULT_CAP_DESKTOP, "views": 4, "desktop_only": true},
	{"label": "desktop 4 views light off", "enemies": 200, "shots": ProjectileManagerScript.DEFAULT_CAP_DESKTOP, "views": 4, "light": false, "desktop_only": true},
	{"label": "desktop 4 views fewest motes", "enemies": 200, "shots": ProjectileManagerScript.DEFAULT_CAP_DESKTOP, "views": 4, "motes": FEWEST_MOTES, "desktop_only": true},
	{"label": "web no split", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "views": 0},
	{"label": "web 2 views", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "views": 2},
	{"label": "web 3 views", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "views": 3},
	{"label": "web 4 views", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "views": 4},
	{"label": "web 4 views light off", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "views": 4, "light": false},
	{"label": "web 4 views fewest motes", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "views": 4, "motes": FEWEST_MOTES},
]

var _views: ViewsScript = null
## The settings as they were before a scenario changed them (put back as it ends).
var _light_before: bool = true
var _motes_before: int = 0
var _wizard_places := PackedVector2Array()
## `--shots`: whether to save a screen a scenario, and whether this scenario's is saved.
var _shots: bool = false
var _shot_taken: bool = false


func _init() -> void:
	rows = SPLIT_SCENARIOS
	scenarios = []
	for index in SPLIT_SCENARIOS.size():
		scenarios.append(index)
	result_word = "SPLIT VIEWS"
	_shots = (OS.get_cmdline_user_args() + OS.get_cmdline_args()).has("--shots")


func _scenario_started(scenario: Dictionary) -> void:
	var spectacle: Node = _spectacle()
	if spectacle != null:
		_light_before = bool(spectacle.get(&"spell_light"))
		_motes_before = int(spectacle.get(&"mote_cap"))
		spectacle.call(&"set_spell_light", bool(scenario.get("light", _light_before)))
		spectacle.call(&"set_mote_cap", int(scenario.get("motes", _motes_before)))
	_shot_taken = false
	_views = ViewsScript.new(int(scenario.get("views", 0)))
	add_child(_views)
	var light: Node = spectacle.get(&"light") if spectacle != null else null
	_views.use_light(light.get(&"viewport") as SubViewport if light != null else null)
	print("BENCH: split views scenario %s: %d views, light %s, motes %d" % [scenario["label"], _views.views.size(), "on" if light != null else "off", int(spectacle.get(&"mote_cap")) if spectacle != null else 0])


func _measuring_started() -> void:
	if _views != null:
		_views.start_measuring()


func _report_more(label: String) -> void:
	if _views != null:
		_views.report(label)
		if _views.frames_counted() == 0:
			_failures.append("%s: the views counted no frames" % label)


func _scenario_ending() -> void:
	if _views != null:
		_views.queue_free()
		remove_child(_views)
		_views = null
	var spectacle: Node = _spectacle()
	if spectacle != null:
		spectacle.call(&"set_spell_light", _light_before)
		spectacle.call(&"set_mote_cap", _motes_before)


func _process(delta: float) -> void:
	super(delta)
	if _views == null or _wizards.is_empty():
		return
	_wizard_places.resize(_wizards.size())
	for index in _wizards.size():
		var wizard: Actor = _wizards[index]
		if is_instance_valid(wizard):
			_wizard_places[index] = wizard.global_position
	_views.place(_wizard_places)
	if _shots and not _shot_taken and _measuring and _elapsed >= warm_up + measure * 0.5:
		_shot_taken = true
		_save_shot(String(rows[scenarios[_current]]["label"]))


## The screen as last drawn, saved as `SHOTS_DIR/<label>.png` (spaces as underscores).
func _save_shot(label: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [SHOTS_DIR, label.replace(" ", "_")]
	if image != null and image.save_png(path) == OK:
		print("BENCH: split views %s: screen saved to %s" % [label, ProjectSettings.globalize_path(path)])


func _spectacle() -> Node:
	return _feel.call(&"spectacle") as Node if _feel != null and _feel.has_method(&"spectacle") else null
