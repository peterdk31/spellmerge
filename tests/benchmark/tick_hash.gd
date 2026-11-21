extends "res://tests/bots/playtest.gd"
## The simulation's tick, measured and fingerprinted over a whole biome played by bots (the
## performance pass of 2026-11-21, round C): the bots' playtest (`tests/bots/playtest.gd`, its
## arguments the same), and on top of it
##  - `--hash-every=N`: the whole game's state hash (`SimHash.whole` of `Tick.state_areas()`) every N
##    ticks from the hub on, each written as a line `tick hash` to `--hash-out=PATH` (default
##    `user://tick_hash.txt`), so two checkouts' runs of the same seed and players are compared line
##    by line (`diff`): a change that keeps the game exactly the same leaves the file the same;
##  - `--profile-steps`: each of the Tick's steps timed from a second into the run on, the biome's lay left out (`Tick.profile_steps`), printed
##    as `BENCH: tick steps` (ms a tick, the largest first), with the ticks run.
## Hashing costs far more than a tick, so a timed run hashes nothing (pass one or the other).
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/benchmark/tick_hash.gd -- --players=2 --seed=11 --sturdy --hash-every=1 --hash-out=/tmp/a.txt
##   godot --headless --fixed-fps 60 --path . --script res://tests/benchmark/tick_hash.gd -- --players=1 --seed=11 --sturdy --profile-steps

const TickScript := preload("res://core/sim/tick.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const PROJECTILE_PARTS: PackedStringArray = ["refresh", "common", "before", "hits", "kernel", "handbacks", "past budget", "after"]

var _hash_every: int = 0
var _hash_out: String = "user://tick_hash.txt"
var _profile: bool = false
var _hashes: PackedStringArray = PackedStringArray()
var _tick: TickScript = null
var _ticks_profiled: int = 0
var _projectiles: Node = null
## The projectile manager's parts (its `step_profile`, its last step's), summed after every tick.
var _projectile_sums: PackedInt64Array = PackedInt64Array()


func take() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hash-every="):
			_hash_every = maxi(arg.trim_prefix("--hash-every=").to_int(), 1)
		elif arg.begins_with("--hash-out="):
			_hash_out = arg.trim_prefix("--hash-out=")
		elif arg == "--profile-steps":
			_profile = true
	_tick = root.get_node("Tick") as TickScript
	if _hash_every > 0:
		_tick.ticked.connect(_on_ticked)
	if _profile:
		_tick.ticked.connect(_on_ticked_profiled)
	await super()
	if _hash_every > 0:
		var file := FileAccess.open(_hash_out, FileAccess.WRITE)
		if file != null:
			file.store_string("\n".join(_hashes) + "\n")
		print("BENCH: tick hash: %d hashes, every %d ticks, to %s" % [_hashes.size(), _hash_every, ProjectSettings.globalize_path(_hash_out)])
	if _profile:
		_report_steps()


## Timing starts a second into the run, so the biome's lay (a loading screen's, once) is left out.
func _on_ticked_profiled() -> void:
	if not _run_started or _ticks - _run_tick < 60:
		return
	if _ticks_profiled == 0 and _tick.step_profile.is_empty():
		_tick.profile_steps(Time.get_ticks_usec)
		_projectiles = root.get_node_or_null("Projectiles")
		if _projectiles != null:
			var parts := PackedInt64Array()
			parts.resize(ProjectileManagerScript.PROF_PARTS)
			_projectiles.set(&"step_profile", parts)
			_projectiles.set(&"profile_clock", Time.get_ticks_usec)
			_projectile_sums.resize(ProjectileManagerScript.PROF_PARTS)
		return
	_ticks_profiled += 1
	if _projectiles != null:
		var prof: PackedInt64Array = _projectiles.get(&"step_profile")
		for i in mini(prof.size(), _projectile_sums.size()):
			_projectile_sums[i] += prof[i]


func _on_ticked() -> void:
	var at: int = _tick.count
	if at % _hash_every != 0:
		return
	var walk := StateWalk.new()
	var whole: int = SimHash.whole(SimHash.areas(_tick.state_areas(), walk))
	_hashes.append("%d %d %d" % [_ticks, at, whole])


## The Tick's steps, ms a tick over the ticks profiled, the largest first.
func _report_steps() -> void:
	var names: PackedStringArray = _tick.step_names()
	var rows: Array = []
	var total: int = 0
	for i in mini(names.size(), _tick.step_profile.size()):
		rows.append([_tick.step_profile[i], names[i]])
		total += _tick.step_profile[i]
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var ticks: float = float(maxi(_ticks_profiled, 1))
	var parts := PackedStringArray()
	for row: Array in rows:
		parts.append("%s %.3f" % [row[1], float(row[0]) / ticks / 1000.0])
	var shots := PackedStringArray()
	for i in _projectile_sums.size():
		shots.append("%s %.3f" % [PROJECTILE_PARTS[i] if i < PROJECTILE_PARTS.size() else str(i), float(_projectile_sums[i]) / ticks / 1000.0])
	print("BENCH: tick projectile parts (ms a tick): %s" % ", ".join(shots))
	print("BENCH: tick steps (ms a tick over %d ticks, total %.3f): %s" % [_ticks_profiled, float(total) / ticks / 1000.0, ", ".join(parts)])
