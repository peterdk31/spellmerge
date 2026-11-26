extends "res://tests/support/suite.gd"
## Feel's code split by effect family (gameplay/feel/README.md, "Feel's jobs"): each job works on
## Feel's containers through members of its own of the same names, aliases of Feel's, so an alias
## that is not Feel's own (never linked, or left on a container Feel no longer holds) would draw
## from stale rows in silence. These check that every member a job declares is linked, that each
## alias is Feel's own (a write through it is Feel's) when made and after a drawn frame, that a job
## links only what Feel never puts another in the place of, and that Feel frees its jobs with itself.

const FeelScript := preload("res://gameplay/feel/feel.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

## Feel's members that hold its jobs, by the job's script.
const JOBS: Dictionary[StringName, Script] = {
	&"_job_flashes": preload("res://gameplay/feel/feel_flashes.gd"),
	&"_job_cues": preload("res://gameplay/feel/feel_cues.gd"),
	&"_job_hits": preload("res://gameplay/feel/feel_hits.gd"),
	&"_job_statuses": preload("res://gameplay/feel/feel_statuses.gd"),
	&"_job_beams": preload("res://gameplay/feel/feel_beams.gd"),
	&"_job_casts": preload("res://gameplay/feel/feel_casts.gd"),
	&"_job_view": preload("res://gameplay/feel/feel_view.gd"),
}


func test_every_job_is_feels() -> void:
	var feel: Node = FeelScript.new()
	for name: StringName in JOBS:
		var job: Object = feel.get(name)
		check(job != null and job.get_script() == JOBS[name], "Feel's %s is a %s" % [name, JOBS[name].resource_path])
	feel.free()


func test_every_member_of_a_job_is_linked() -> void:
	for name: StringName in JOBS:
		var script: Script = JOBS[name]
		var listed: Array = script.get_script_constant_map()["LINKED"]
		for info: Dictionary in script.get_script_property_list():
			if int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			check(listed.has(StringName(info["name"])), "%s: %s is in LINKED, so `link` sets it from Feel" % [script.resource_path, info["name"]])


func test_each_alias_is_feels_own() -> void:
	var feel: Node = FeelScript.new()
	_check_linked(feel, "made")
	feel.free()


## Feel's `_ready` sizes and fills its containers and makes its nodes, and a drawn frame works on
## them: every alias is still Feel's own (Feel only ever changes a linked container in place).
func test_the_aliases_stay_feels_own_through_ready_and_a_frame() -> void:
	var bus := EventsScript.new()
	var actors: Node = ActorSeats.table()
	var feel: Node = FeelScript.new()
	feel.set(&"events", bus)
	feel.set(&"actors", actors)
	feel.set(&"drive_engine", false)
	feel.set(&"preset", FeelPresetScript.new())
	root.add_child(feel)
	feel.call(&"step", 0.0625)
	feel.call(&"set_effect_slots", 64)
	_check_linked(feel, "after _ready, a step and new effect slots")
	feel.free()
	actors.free()
	bus.free()


## A linked member is one Feel never assigns whole (its own code only resizes, fills or clears it):
## otherwise a job's alias would keep the old one. Every assignment in feel.gd and the jobs is looked
## for by its name.
func test_no_linked_member_is_assigned_whole() -> void:
	var sources: Array[String] = ["res://gameplay/feel/feel.gd"]
	for name: StringName in JOBS:
		sources.append((JOBS[name] as Script).resource_path)
	var linked: Dictionary = {}
	for name: StringName in JOBS:
		for member: StringName in (JOBS[name] as Script).get_script_constant_map()["LINKED"]:
			if member != &"feel" and not String(member).begins_with("_job_"):
				linked[member] = true
	var assign := RegEx.create_from_string("(?:^|[^\\w.])(?:feel\\.)?(\\w+)\\s*=[^=]")
	for path: String in sources:
		var text: String = FileAccess.get_file_as_string(path)
		var number: int = 0
		for line: String in text.split("\n"):
			number += 1
			var code: String = line.get_slice("#", 0)
			if code.strip_edges().begins_with("var ") or code.strip_edges().begins_with("static var ") or code.strip_edges().begins_with("const "):
				continue
			for found: RegExMatch in assign.search_all(code):
				var member: String = found.get_string(1)
				check(not linked.has(StringName(member)), "%s:%d assigns %s whole, which a job links" % [path, number, member])


## Nor do the tests and screenshots that reach into Feel put their own in a linked member's place
## (`set("_name", ...)`, `feel._name = ...`): the job would keep drawing from Feel's old one. A member
## they do replace is read through `feel` (`_flash_offset`).
func test_no_test_puts_its_own_in_a_linked_members_place() -> void:
	var linked: Array[String] = []
	for name: StringName in JOBS:
		for member: StringName in (JOBS[name] as Script).get_script_constant_map()["LINKED"]:
			if member != &"feel" and not String(member).begins_with("_job_"):
				linked.append(String(member))
	var files: Array[String] = []
	for folder: String in ["res://tests/gameplay/feel", "res://tests/screenshots", "res://tests/benchmark", "res://bench"]:
		for file: String in DirAccess.get_files_at(folder):
			if file.ends_with(".gd"):
				files.append(folder.path_join(file))
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		for member: String in linked:
			for put: String in ["set(\"%s\"" % member, "set(&\"%s\"" % member, ".%s = " % member]:
				check(not text.contains(put), "%s puts its own %s in Feel's place (%s), which a job links" % [path, member, put])


func test_feel_frees_its_jobs() -> void:
	var feel: Node = FeelScript.new()
	var jobs: Array[Object] = []
	for name: StringName in JOBS:
		jobs.append(feel.get(name))
	feel.free()
	for job in jobs:
		check(not is_instance_valid(job), "a job is freed with Feel")


## Every alias of every job is Feel's own: a write through it is seen by Feel (a packed array's
## write through a copy would not be).
func _check_linked(feel: Node, when: String) -> void:
	for name: StringName in JOBS:
		var job: Object = feel.get(name)
		var listed: Array = (JOBS[name] as Script).get_script_constant_map()["LINKED"]
		for member: StringName in listed:
			if member == &"feel":
				check(job.get(member) == feel, "%s: %s's feel is Feel" % [when, name])
				continue
			var own: Variant = feel.get(member)
			var alias: Variant = job.get(member)
			if own is Object or own is Dictionary or own is Array:
				check(is_same(own, alias), "%s: %s.%s is Feel's own" % [when, name, member])
				continue
			# A packed array: one more element through the alias, seen by Feel, then taken back.
			var size: int = own.size()
			alias.resize(size + 1)
			check(feel.get(member).size() == size + 1, "%s: %s.%s is Feel's own array, not a copy" % [when, name, member])
			alias.resize(size)
