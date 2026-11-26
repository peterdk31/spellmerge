extends "res://tests/support/suite.gd"
## The spell runtime's jobs (core/README.md, "The spell runtime"): each job script works on the
## runtime's arrays through members of its own of the same names, aliases of the runtime's, so a
## job's alias that is not the runtime's own array (never linked, or left on an array the runtime no
## longer holds) reads and writes the wrong rows in silence. These check that every member a job
## declares is linked, that each alias is the runtime's own array (a write through it is the
## runtime's), that a snapshot's restore and a run's start link them again, that no job aliases a
## member the runtime replaces whole, and that the runtime frees its jobs with itself.

const RuntimeScript := preload("res://core/spells/spells.gd")

## The runtime's members that hold its jobs, by the job's script.
const JOBS: Dictionary[StringName, Script] = {
	&"_job_views": preload("res://core/spells/spell_views.gd"),
	&"_job_generations": preload("res://core/spells/spell_generations.gd"),
	&"_job_casts": preload("res://core/spells/spell_casts.gd"),
	&"_job_launches": preload("res://core/spells/spell_launches.gd"),
	&"_job_fires": preload("res://core/spells/spell_fires.gd"),
	&"_job_strikes": preload("res://core/spells/spell_strikes.gd"),
	&"_job_lasting": preload("res://core/spells/spell_lasting.gd"),
	&"_job_zaps": preload("res://core/spells/spell_zaps.gd"),
	&"_job_hits": preload("res://core/spells/spell_hits.gd"),
}


func test_every_job_is_the_runtimes_and_named_in_its_derived() -> void:
	var runtime: Node = RuntimeScript.new()
	var derived: Array = RuntimeScript.DERIVED
	for name: StringName in JOBS:
		var job: Object = runtime.get(name)
		check(job != null and job.get_script() == JOBS[name], "the runtime's %s is a %s" % [name, JOBS[name].resource_path])
		check(derived.has(name), "the runtime lists %s in DERIVED (a job holds no state)" % name)
	runtime.free()


func test_every_member_of_a_job_is_linked() -> void:
	for name: StringName in JOBS:
		var script: Script = JOBS[name]
		var listed: Array = (script as Script).get_script_constant_map()["DERIVED"]
		for info: Dictionary in script.get_script_property_list():
			if int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			check(listed.has(StringName(info["name"])), "%s: %s is in DERIVED, so `link` sets it from the runtime" % [script.resource_path, info["name"]])


func test_each_alias_is_the_runtimes_own_array() -> void:
	var runtime: Node = RuntimeScript.new()
	_check_linked(runtime, "made")
	runtime.free()


## A snapshot's restore and a run's renew replace the runtime's arrays by others: the jobs follow.
func test_the_jobs_follow_arrays_put_in_place_of_the_runtimes() -> void:
	var runtime: Node = RuntimeScript.new()
	var other := PackedInt64Array()
	other.resize((runtime.get(&"_rec_seq") as PackedInt64Array).size())
	runtime.set(&"_rec_seq", other)
	runtime.set(&"_profiles", {})
	runtime.call(&"rebuild_derived")
	_check_linked(runtime, "after rebuild_derived")
	var renewed := PackedInt32Array()
	renewed.resize((runtime.get(&"_lc_trigger") as PackedInt32Array).size())
	runtime.set(&"_lc_trigger", renewed)
	runtime.call(&"begin_run")
	_check_linked(runtime, "after begin_run")
	runtime.free()


## The jump ring (`_jq_*`) is replaced whole when it grows (`SpellFires._grow_jumps`): a job reads
## it through `rt`, never an alias that the growth would leave on the old ring.
func test_no_job_aliases_the_jump_ring() -> void:
	for name: StringName in JOBS:
		var listed: Array = (JOBS[name] as Script).get_script_constant_map()["DERIVED"]
		for member: StringName in listed:
			check(not String(member).begins_with("_jq_"), "%s aliases %s, which the runtime replaces when the ring grows" % [JOBS[name].resource_path, member])


func test_the_runtime_frees_its_jobs() -> void:
	var runtime: Node = RuntimeScript.new()
	var jobs: Array[Object] = []
	for name: StringName in JOBS:
		jobs.append(runtime.get(name))
	runtime.free()
	for job in jobs:
		check(not is_instance_valid(job), "a job is freed with its runtime")


## Every alias of every job is the runtime's own: a write through it is seen by the runtime (a
## packed array's write through a copy would not be).
func _check_linked(runtime: Node, when: String) -> void:
	for name: StringName in JOBS:
		var job: Object = runtime.get(name)
		var listed: Array = (JOBS[name] as Script).get_script_constant_map()["DERIVED"]
		for member: StringName in listed:
			if member == &"rt":
				check(job.get(member) == runtime, "%s: %s's rt is the runtime" % [when, name])
				continue
			var own: Variant = runtime.get(member)
			var alias: Variant = job.get(member)
			if own is Object or own is Dictionary or own is Array:
				check(is_same(own, alias), "%s: %s.%s is the runtime's own" % [when, name, member])
				continue
			# A packed array: one more element through the alias, seen by the runtime, then taken back.
			var size: int = own.size()
			alias.resize(size + 1)
			check(runtime.get(member).size() == size + 1, "%s: %s.%s is the runtime's own array, not a copy" % [when, name, member])
			alias.resize(size)
