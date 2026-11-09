extends "res://tests/support/suite.gd"
## The simulation/view line (online-ready N9, core/sim/README.md, "The line"): simulation code runs on
## the tick, the same on every machine, so it reads no clock, rolls no dice of the engine's, calls
## none of the engine's maths, reads no device, mouse, camera or window, and keeps no instance id.
## This reads every simulation script's code (tests/support/sim_source.gd: StateWalk.FOLDERS but
## StateWalk.VIEW_FOLDERS; a look that says `VIEW_ONLY` is skipped) against one table, RULES.
##
## View code inside a simulation script is a function the script lists in `VIEW` (its drawing: the
## projectile manager's `update_draw`), or one line marked `# view: why`; neither is read. That a
## view function writes no state is tests/core/test_determinism.gd's ("the view stepped thrice").
##
## Each failure names the file, the line, what it does and the fix.

const SimSource := preload("res://tests/support/sim_source.gd")

## What simulation code may not do: a pattern (on a line's code, without comments and strings), what
## a line that matches does, and the fix.
const RULES: Array[Dictionary] = [
	# The clock.
	{"pattern": "(^|[^\\w])Time\\.", "does": "reads the clock",
		"fix": "the simulation runs on its own time: `delta`, `sim_time`, `sim.tick`"},
	{"pattern": "(^|[^\\w])OS\\.get_(ticks|unix)", "does": "reads the clock",
		"fix": "the simulation runs on its own time: `delta`, `sim_time`, `sim.tick`"},
	{"pattern": "Engine\\.(time_scale|get_physics_frames|get_process_frames|get_frames_drawn|get_frames_per_second|get_physics_interpolation_fraction)",
		"does": "reads the engine's frames or its time scale, which differ with the machine's frame rate",
		"fix": "count ticks (`sim.tick`); a hold or a stop is the sim's (core/sim/README.md, \"Stops and holds\")"},
	{"pattern": "get_(physics_)?process_delta_time\\(", "does": "reads the frame's time",
		"fix": "take the step's `delta` (always Tick.DT)"},
	{"pattern": "(create_timer|create_tween)\\(|(^|[^\\w])(Tween|Timer)([^\\w]|$)",
		"does": "runs on the engine's clock, between frames, outside the tick",
		"fix": "count it down in a member, on the tick (`_left -= delta`)"},
	{"pattern": "(^|[^\\w])await([^\\w]|$)",
		"does": "waits on the engine: the rest runs outside the tick, and the waiting function's state is in no member, so no walk sees it",
		"fix": "keep where it is in a member and go on from it on the tick"},
	{"pattern": "(call_deferred|set_deferred)\\(|CONNECT_DEFERRED",
		"does": "runs after the frame, outside the tick",
		"fix": "do it now, or keep it in a member for the next tick"},
	{"pattern": "^\\s*func\\s+_(physics_)?process\\(",
		"does": "is called by the engine once a frame",
		"fix": "step on the tick (`SimArea.join`, core/sim/README.md, \"The tick\"); a function that only draws goes in VIEW"},
	# The dice.
	{"pattern": "(^|[^\\w])randomize\\(", "does": "seeds a generator by the clock",
		"fix": "take `SimSeed.fresh()` (core/sim)"},
	{"pattern": "(^|[^.\\w])(randf|randi|randf_range|randi_range|randfn|seed)\\(", "does": "rolls the engine's global dice",
		"fix": "take chance from `sim` (core/sim/sim.gd): `sim.chance(purpose, key, counter)`"},
	{"pattern": "(^|[^\\w])RandomNumberGenerator([^\\w]|$)", "does": "makes a generator of its own",
		"fix": "take chance from `sim` (core/sim/sim.gd): `sim.chance(purpose, key, counter)`"},
	# The maths (N7).
	{"pattern": "(^|[^.\\w])(sin|cos|tan|atan|atan2|asin|acos|sinh|cosh|tanh|exp|log|pow|ease|lerp_angle)\\(",
		"does": "calls the engine's maths, which differs between platforms in the last digit",
		"fix": "call DMath's (core/sim/dmath.gd)"},
	{"pattern": "(?<!DMath)\\.(angle|angle_to|angle_to_point|rotated|from_angle|slerp)\\(",
		"does": "calls the engine's maths, which differs between platforms in the last digit",
		"fix": "call DMath's (core/sim/dmath.gd)"},
	# Input.
	{"pattern": "(^|[^\\w.])Input\\.", "does": "reads a device",
		"fix": "take the seat's frame (`frames.frame_of(seat)`, core/sim/README.md, \"Input\")"},
	{"pattern": "(^|[^\\w])(InputManager\\w*|LocalInput|PlayerInput)([^\\w]|$)", "does": "reads the input layer",
		"fix": "take the seat's frame (`frames.frame_of(seat)`), and the joined seats from the frames service"},
	{"pattern": "get_(global|local)_mouse_position\\(", "does": "reads the mouse",
		"fix": "take the seat's aim from its frame"},
	# The picture.
	{"pattern": "(get_viewport|get_visible_rect|get_camera_2d)\\(|(^|[^\\w])Camera2D([^\\w]|$)",
		"does": "reads the picture (the window, a camera), which differs between machines",
		"fix": "work from the game's own sizes (the room, Coop's fitted view); a function that only draws goes in VIEW"},
]

## An instance id differs between machines and runs: simulation code may only look a node up by one,
## on a line that touches one of its DERIVED members (`_row_by_node[node.get_instance_id()]`).
const INSTANCE_ID: String = "get_instance_id\\("


func test_simulation_code_keeps_to_the_tick() -> void:
	var patterns: Array[RegEx] = []
	for rule: Dictionary in RULES:
		patterns.append(RegEx.create_from_string(rule["pattern"]))
	var instance_id := RegEx.create_from_string(INSTANCE_ID)
	var read: int = 0
	for path in SimSource.paths():
		var script: Script = load(path)
		if StateWalk.is_view_only(script):
			continue
		read += 1
		var derived: PackedStringArray = SimSource.listed_in_file(script, "DERIVED")
		for line: Dictionary in SimSource.code_lines(script):
			var code: String = line["code"]
			for i in patterns.size():
				if patterns[i].search(code) != null:
					check(false, "%s:%d %s; %s: %s" % [path, line["line"], RULES[i]["does"], RULES[i]["fix"], String(line["text"]).strip_edges()])
			if instance_id.search(code) != null and not _names_any(code, derived):
				check(false, "%s:%d keeps an instance id, which differs between machines and runs; look a node up by one in a DERIVED member only, and keep the actor's key (`Actors.key_of`) as state (core/sim/README.md, \"Contract\"): %s" % [path, line["line"], String(line["text"]).strip_edges()])
	check(read > 50, "the simulation scripts were read (%d)" % read)


## Each rule finds what it is for, and not what only looks like it.
func test_the_rules_find_what_they_are_for() -> void:
	var finds: Dictionary = {
		"var now: int = Time.get_ticks_msec()": true, "var t: float = sim_time": false,
		"await get_tree().process_frame": true, "var awaited: int = 0": false,
		"get_tree().create_timer(0.5)": true, "var timer_left: float = 0.0": false,
		"call_deferred(&\"_go\")": true, "func _process(delta: float) -> void:": true,
		"func _process_hits() -> void:": false, "if Input.is_action_pressed(&\"x\"):": true,
		"var frame: InputFrame = frames.frame_of(seat)": false, "var aim: Vector2 = LocalInput.aim_at(a, b)": true,
		"var size: Vector2 = get_viewport().get_visible_rect().size": true, "var view: Rect2 = fitted_view": false,
		"var a: float = sin(t)": true, "var a: float = DMath.sin(t)": false, "v = v.rotated(0.5)": true,
		"v = DMath.rotated(v, 0.5)": false, "var r: float = randf()": true, "var r: float = sim.chance(&\"x\", 1, 2)": false,
		"var f: float = Engine.get_physics_interpolation_fraction()": true, "var tree := Engine.get_main_loop()": false,
	}
	var patterns: Array[RegEx] = []
	for rule: Dictionary in RULES:
		patterns.append(RegEx.create_from_string(rule["pattern"]))
	for code: String in finds:
		var found: bool = false
		for pattern in patterns:
			found = found or pattern.search(code) != null
		check_equal(found, finds[code], "a rule finds `%s`" % code)


## A function in VIEW, its header included, and a line marked `# view:` are not read; the rest is.
func test_view_functions_and_view_lines_are_not_read() -> void:
	var lines: Array[Dictionary] = SimSource.code_lines(load("res://tests/core/fixtures/sim_view_fixture.gd"))
	var read := PackedStringArray()
	for line in lines:
		read.append(String(line["code"]).strip_edges())
	check(read.has("_left -= delta"), "the tick's step is read")
	check(read.has("return _left"), "a function after the view one is read")
	for code in read:
		check(not code.contains("Time.") and not code.contains("_process") and not code.contains("sin("), "not read: %s" % code)


## The instance-id rule lets a lookup through a DERIVED member by.
func test_an_instance_id_lookup_through_derived_is_allowed() -> void:
	var derived := PackedStringArray(["_row_by_node"])
	check(_names_any("return _row_by_node.get(node.get_instance_id(), -1)", derived), "a lookup")
	check(not _names_any("_rng.seed = hash(owner.get_instance_id())", derived), "a seed is no lookup")


## Whether `code` names any of `names` as a whole word.
static func _names_any(code: String, names: PackedStringArray) -> bool:
	for name in names:
		var word := RegEx.create_from_string("(^|[^\\w])%s([^\\w]|$)" % name)
		if word.search(code) != null:
			return true
	return false
