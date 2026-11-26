extends "res://tests/support/suite.gd"
## The projectile manager's jobs (core/README.md, "The projectile manager"): each job script works on
## the manager's arrays through members of its own of the same names, aliases of the manager's, so
## a job's alias that is not the manager's own array (never linked, or left on an array the manager
## no longer holds) reads and writes the wrong shots in silence. These check that every member a job
## declares is linked, that each alias is the manager's own array (a write through it is the
## manager's), that a snapshot's restore and a run's start link them again, and that the manager
## frees its jobs with itself.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## The manager's members that hold its jobs, by the job's script.
const JOBS: Dictionary[StringName, Script] = {
	&"_job_rows": preload("res://core/projectiles/projectile_rows.gd"),
	&"_job_targets": preload("res://core/projectiles/projectile_targets.gd"),
	&"_job_moves": preload("res://core/projectiles/projectile_moves.gd"),
	&"_job_hits": preload("res://core/projectiles/projectile_hits.gd"),
	&"_job_walls": preload("res://core/projectiles/projectile_walls.gd"),
	&"_job_guards": preload("res://core/projectiles/projectile_guards.gd"),
	&"_job_places": preload("res://core/projectiles/projectile_places.gd"),
	&"_job_rays": preload("res://core/projectiles/projectile_rays.gd"),
	&"_job_batches": preload("res://core/projectiles/projectile_batches.gd"),
	&"_job_draw": preload("res://core/projectiles/projectile_draw.gd"),
}


func test_every_job_is_the_managers_and_named_in_its_derived() -> void:
	var manager: Node = ManagerScript.new()
	var derived: Array = ManagerScript.DERIVED
	for name: StringName in JOBS:
		var job: Object = manager.get(name)
		check(job != null and job.get_script() == JOBS[name], "the manager's %s is a %s" % [name, JOBS[name].resource_path])
		check(derived.has(name), "the manager lists %s in DERIVED (a job holds no state)" % name)
	manager.free()


func test_every_member_of_a_job_is_linked() -> void:
	for name: StringName in JOBS:
		var script: Script = JOBS[name]
		var listed: Array = (script as Script).get_script_constant_map()["DERIVED"]
		for info: Dictionary in script.get_script_property_list():
			if int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			check(listed.has(StringName(info["name"])), "%s: %s is in DERIVED, so `link` sets it from the manager" % [script.resource_path, info["name"]])


func test_each_alias_is_the_managers_own_array() -> void:
	var manager: Node = ManagerScript.new()
	_check_linked(manager, "made")
	manager.free()


## A snapshot's restore and a run's renew replace the manager's arrays by others: the jobs follow.
func test_the_jobs_follow_arrays_put_in_place_of_the_managers() -> void:
	var manager: Node = ManagerScript.new()
	var cap: int = manager.call(&"get_cap")
	var other := PackedVector2Array()
	other.resize(cap)
	manager.set(&"_pos", other)
	manager.call(&"rebuild_derived")
	_check_linked(manager, "after rebuild_derived")
	var renewed := PackedByteArray()
	renewed.resize(cap)
	manager.set(&"_alive", renewed)
	manager.call(&"begin_run")
	_check_linked(manager, "after begin_run")
	manager.free()


func test_the_manager_frees_its_jobs() -> void:
	var manager: Node = ManagerScript.new()
	var jobs: Array[Object] = []
	for name: StringName in JOBS:
		jobs.append(manager.get(name))
	manager.free()
	for job in jobs:
		check(not is_instance_valid(job), "a job is freed with its manager")


## Every alias of every job is the manager's own: a write through it is seen by the manager (a
## packed array's write through a copy would not be).
func _check_linked(manager: Node, when: String) -> void:
	for name: StringName in JOBS:
		var job: Object = manager.get(name)
		var listed: Array = (JOBS[name] as Script).get_script_constant_map()["DERIVED"]
		for member: StringName in listed:
			if member == &"pm":
				check(job.get(member) == manager, "%s: %s's pm is the manager" % [when, name])
				continue
			var own: Variant = manager.get(member)
			var alias: Variant = job.get(member)
			if own is Object or own is Dictionary or own is Array:
				check(is_same(own, alias), "%s: %s.%s is the manager's own" % [when, name, member])
				continue
			# A packed array: one more element through the alias, seen by the manager, then taken back.
			var size: int = own.size()
			alias.resize(size + 1)
			check(manager.get(member).size() == size + 1, "%s: %s.%s is the manager's own array, not a copy" % [when, name, member])
			alias.resize(size)
