extends Node
## What a prop costs the simulation before props exist (props W1, docs/milestones/props.md): props
## will be actors with no controller, so this stands N stand-ins in the real hub and times what
## the game pays for them. A stand-in (`prop_stand_in.tscn`, its data `prop_stand_in.tres`) is a
## barrel-to-be: an `Actor` with Health, a Hurtbox and a Caster holding two staffs of
## `fire` + `blast` (one with a one-second wind-up, the fuse), and no controller, no Mover and no
## look, standing still and never hit.
##
## For each count (0, 300, 1,000 by default) it prints `BENCH: props N:` lines:
## - **tick:** the Tick's own `run` (every area's step and every body's), timed tick by tick over
##   TICKS ticks with the Tick's physics process off (this runner calls it), average and p95;
## - **state hash:** HASH_PASSES hashes of every area the Tick names, as the stress run times them
##   (core/sim/README.md, "The hash"), the bodies' part, and spread over HASH_SLICES ticks;
## - **snapshot:** taking one (`Snapshot.take`), the objects it holds, writing it back into the same
##   world (every body matched), and writing it back with the stand-ins gone (each made again, as
##   a machine joining the hub would).
## The differences between the counts are what the props cost; W2 runs it again after its changes
## (a still body is not stepped, an untouched one hashes as a few values).
##
## Started by `prop_cost.gd`. Prints `PROP COST OK` and quits 0, or `PROP COST FAILED` and 1 (the
## hub did not start, a snapshot named problems, or the log has an error).

const BotScript := preload("res://tests/bots/bot.gd")
const ErrorLogScript := preload("res://tests/smoke/error_log.gd")
const TickScript := preload("res://core/sim/tick.gd")
const StandIn: EnemyBase = preload("res://tests/benchmark/prop_stand_in.tres")

const GROUP: StringName = &"prop_stand_in"
## The stand-ins' counts, in turn (`--counts=0,300,1000`).
const COUNTS: Array[int] = [0, 300, 1000]
## Ticks run before timing, and timed.
const WARM_UP: int = 30
const TICKS: int = 300
const HASH_PASSES: int = 5
const HASH_SLICES: int = 60
const SNAPSHOT_PASSES: int = 3
## Passes of the per-part timing (`_time_parts`).
const PART_PASSES: int = 20
## Ticks of the per-step timing (`_time_areas`).
const AREA_TICKS: int = 100
## Frames to wait for the hub, at most.
const WAIT_FRAMES: int = 600
## Where the stand-ins stand: a grid round the wizard, this far apart.
const SPACING: float = 12.0

var counts: Array[int] = COUNTS.duplicate()

var _log: Logger = ErrorLogScript.new()
var _logging: bool = false
var _tick: TickScript = null
var _flow: Node = null
var _bot: BotScript = null
var _failures: Array[String] = []


func _ready() -> void:
	OS.add_logger(_log)
	_logging = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--counts="):
			counts.clear()
			for part in arg.trim_prefix("--counts=").split(","):
				counts.append(part.to_int())
	var root: Window = get_tree().root
	_tick = root.get_node_or_null("Tick") as TickScript
	_flow = root.get_node_or_null("Flow")
	var events: Node = root.get_node_or_null("Events")
	var input: Node = root.get_node_or_null("PlayerInput")
	var projectiles: Node = root.get_node_or_null("Projectiles")
	if _tick == null or _flow == null or events == null or input == null:
		_finish(["the Tick, Flow, Events and PlayerInput autoloads must exist"])
		return
	if projectiles != null:
		print("BENCH: native module %s" % ("on" if projectiles.call(&"is_native") else "off"))
	_bot = BotScript.new()
	if not _bot.join(0, BotScript.Mode.IDLER, input, _flow):
		_finish(["the bot could not take its virtual device"])
		return
	events.emit_signal("hub_requested", 0)
	_run.call_deferred()


func _exit_tree() -> void:
	if _logging:
		_logging = false
		OS.remove_logger(_log)


func _run() -> void:
	var waited: int = 0
	while _flow.get("world") == null or _flow.call("get_wizard", 0) == null:
		waited += 1
		if waited > WAIT_FRAMES:
			_finish(["the hub did not start"])
			return
		await get_tree().physics_frame
	# Settle: the loading screen's work and the first ticks are out of the timings.
	for i in 30:
		await get_tree().physics_frame
	# From here this runner runs the ticks itself, so each one is timed alone.
	_tick.set_physics_process(false)
	for count in counts:
		_stand(count)
		_measure(count)
		_clear()
	_tick.set_physics_process(true)
	_finish(_failures)


## Stand `count` stand-ins on a grid round the first wizard.
func _stand(count: int) -> void:
	var world := _flow.get("world") as Node2D
	var wizard := _flow.call("get_wizard", 0) as Node2D
	var middle: Vector2 = wizard.global_position if wizard != null else Vector2.ZERO
	var side: int = maxi(1, ceili(sqrt(float(count))))
	for i in count:
		var body := StandIn.scene.instantiate() as Actor
		body.data = StandIn
		var cell := Vector2(float(i % side), float(i / side)) - Vector2(side, side) * 0.5
		body.position = middle + Vector2(0.0, 80.0) + cell * SPACING
		world.add_child(body)
	for i in WARM_UP:
		_tick.run(TickScript.DT)


## Free every stand-in (those made again by a snapshot too).
func _clear() -> void:
	for node in get_tree().get_nodes_in_group(GROUP):
		node.free()
	_tick.run(TickScript.DT)


func _measure(count: int) -> void:
	var bodies: int = get_tree().get_nodes_in_group(GROUP).size()
	print("BENCH: props %d: %d stand-ins in the hub (an actor with Health, a Hurtbox and a Caster of two staffs; no controller, no Mover)" % [count, bodies])
	_time_ticks(count)
	_time_hash(count)
	_time_snapshot(count)


func _time_ticks(count: int) -> void:
	var times: Array[int] = []
	for i in TICKS:
		var start: int = Time.get_ticks_usec()
		_tick.run(TickScript.DT)
		times.append(Time.get_ticks_usec() - start)
	times.sort()
	var total: int = 0
	for t in times:
		total += t
	print("BENCH: props %d: tick avg %.3f ms p95 %.3f ms max %.3f ms over %d ticks" % [count, float(total) / float(TICKS) / 1000.0, float(times[int(TICKS * 0.95)]) / 1000.0, float(times[-1]) / 1000.0, TICKS])
	_time_parts(count)


## Where a stand-in's tick goes: one pass over the stand-ins of each part the Tick runs for a body
## (`Actor.step`, and in it the Caster's and the Hurtbox's step; `Actor.move`), outside the tick.
## The stand-ins stand still and are never hit, so a pass leaves them as they were.
func _time_parts(count: int) -> void:
	if count == 0:
		return
	var stand_ins: Array[Actor] = []
	for node in get_tree().get_nodes_in_group(GROUP):
		stand_ins.append(node as Actor)
	var parts: Dictionary[String, int] = {"tick_step": 0, "step": 0, "caster.step": 0, "hurtbox.step": 0, "move": 0}
	var still: int = 0
	for body in stand_ins:
		if body.actors.is_still(body.id):
			still += 1
	for pass_index in PART_PASSES:
		var start: int = Time.get_ticks_usec()
		for body in stand_ins:
			body.tick_step(TickScript.DT)
		parts["tick_step"] += Time.get_ticks_usec() - start
		start = Time.get_ticks_usec()
		for body in stand_ins:
			body.step(TickScript.DT)
		parts["step"] += Time.get_ticks_usec() - start
		start = Time.get_ticks_usec()
		for body in stand_ins:
			body.caster.step(TickScript.DT)
		parts["caster.step"] += Time.get_ticks_usec() - start
		start = Time.get_ticks_usec()
		for body in stand_ins:
			body.hurtbox.step()
		parts["hurtbox.step"] += Time.get_ticks_usec() - start
		start = Time.get_ticks_usec()
		for body in stand_ins:
			body.move(TickScript.DT)
		parts["move"] += Time.get_ticks_usec() - start
	var shown: Array[String] = []
	for key: String in parts:
		shown.append("%s %.3f ms (%.1f us a body)" % [key, float(parts[key]) / PART_PASSES / 1000.0, float(parts[key]) / PART_PASSES / float(stand_ins.size())])
	print("BENCH: props %d: %d of %d stand-ins still (the Tick skips them); a pass over the stand-ins, stepped by hand: %s" % [count, still, stand_ins.size(), ", ".join(shown)])
	_time_areas(count)


## The tick's steps one by one, in its order (`Tick._order`: each area's step, and the bodies'),
## over AREA_TICKS ticks run here as the Tick runs them (its frames and clock aside): where the
## rest of a stand-in's cost is, beside its own step.
func _time_areas(count: int) -> void:
	_tick.call(&"_build_order")
	var order: Array = _tick.get(&"_order")
	var spent: Dictionary[String, int] = {}
	for t in AREA_TICKS:
		for step: SimArea.Step in order:
			var start: int = Time.get_ticks_usec()
			if step.key == TickScript.BODIES:
				_tick.call(&"_step_bodies", TickScript.DT)
			elif step.call.is_valid():
				step.call.call(TickScript.DT)
			var name: String = String(step.key)
			spent[name] = spent.get(name, 0) + Time.get_ticks_usec() - start
		_tick.sim.tick += 1
	var keys: Array = spent.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return spent[a] > spent[b])
	var shown: Array[String] = []
	for key: String in keys.slice(0, 6):
		shown.append("%s %.3f" % [key, float(spent[key]) / AREA_TICKS / 1000.0])
	print("BENCH: props %d: the tick's costliest steps (ms a tick): %s" % [count, ", ".join(shown)])


func _time_hash(count: int) -> void:
	var total: int = 0
	var body_total: int = 0
	var areas: int = 0
	var problems: PackedStringArray = PackedStringArray()
	var by_area: Dictionary[String, int] = {}
	for i in HASH_PASSES:
		var start: int = Time.get_ticks_usec()
		# An area with parts as its parts (Spells' casters, props W3), as `SimHash.areas` takes it.
		var named: Dictionary = SimHash.parted(_tick.state_areas())
		areas = named.size()
		var walk := StateWalk.new()
		walk.with_paths = false
		var hashes: Dictionary[String, int] = {}
		for name: String in named:
			var area_start: int = Time.get_ticks_usec()
			hashes[name] = SimHash.area(walk, name, named[name] as Object)
			if name.begins_with(SimHash.BODY_PREFIX):
				body_total += Time.get_ticks_usec() - area_start
			else:
				var key: String = _area_of(name, named[name] as Object)
				by_area[key] = by_area.get(key, 0) + Time.get_ticks_usec() - area_start
		SimHash.whole(hashes)
		problems = walk.problems
		total += Time.get_ticks_usec() - start
	var part_total: int = 0
	var part_most: int = 0
	for slice in HASH_SLICES:
		var part_start: int = Time.get_ticks_usec()
		var part_walk := StateWalk.new()
		part_walk.with_paths = false
		SimHash.areas(SimHash.slice(_tick.state_areas(), slice, HASH_SLICES), part_walk)
		var took: int = Time.get_ticks_usec() - part_start
		part_total += took
		part_most = maxi(part_most, took)
	print("BENCH: props %d: state hash avg %.2f ms (bodies %.2f ms) over %d areas; spread over %d ticks avg %.3f ms max %.3f ms a tick; %d problems" % [count, float(total) / HASH_PASSES / 1000.0, float(body_total) / HASH_PASSES / 1000.0, areas, HASH_SLICES, float(part_total) / HASH_SLICES / 1000.0, float(part_most) / 1000.0, problems.size()])
	var keys: Array = by_area.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return by_area[a] > by_area[b])
	var shown: Array[String] = []
	for key: String in keys.slice(0, 5):
		shown.append("%s %.2f" % [key, float(by_area[key]) / HASH_PASSES / 1000.0])
	print("BENCH: props %d: state hash, the costliest areas but the bodies (ms): %s" % [count, ", ".join(shown)])
	for problem in problems.slice(0, 5):
		_failures.append("props %d: state hash problem: %s" % [count, problem])


func _time_snapshot(count: int) -> void:
	var root: Window = get_tree().root
	var take_total: int = 0
	var snapshot: Snapshot = null
	for i in SNAPSHOT_PASSES:
		var start: int = Time.get_ticks_usec()
		snapshot = Snapshot.take(_tick.state_areas(), root)
		take_total += Time.get_ticks_usec() - start
	for problem in snapshot.problems.slice(0, 5):
		_failures.append("props %d: snapshot problem: %s" % [count, problem])
	var objects: int = 0
	for name: String in snapshot.areas:
		objects += _objects_in(snapshot.areas[name])
	# Written back into the same world: every body is there and matched.
	var start_same: int = Time.get_ticks_usec()
	var same_problems: PackedStringArray = snapshot.restore(_tick.state_areas(), root)
	var same: int = Time.get_ticks_usec() - start_same
	# Written back with the stand-ins gone: each is made again, as on a machine joining the hub.
	for node in get_tree().get_nodes_in_group(GROUP):
		node.free()
	var start_made: int = Time.get_ticks_usec()
	var made_problems: PackedStringArray = snapshot.restore(_tick.state_areas(), root)
	var made: int = Time.get_ticks_usec() - start_made
	for problem in (same_problems + made_problems).slice(0, 5):
		_failures.append("props %d: restore problem: %s" % [count, problem])
	var back: int = get_tree().get_nodes_in_group(GROUP).size()
	if back != count:
		_failures.append("props %d: the restore made %d stand-ins again" % [count, back])
	print("BENCH: props %d: snapshot take avg %.2f ms, %d bodies, %d objects; restore into the same world %.2f ms, with the stand-ins made again %.2f ms" % [count, float(take_total) / SNAPSHOT_PASSES / 1000.0, snapshot.bodies.size(), objects, float(same) / 1000.0, float(made) / 1000.0])


## What a hashed area is counted as: an area's parts ("Spells 7", `SimHash.Part`) together as
## "Spells parts", anything else by its name.
static func _area_of(name: String, object: Object) -> String:
	if object is SimHash.Part and (object as SimHash.Part).id >= 0:
		return name.substr(0, name.rfind(" ")) + " parts"
	return name


## The objects a snapshot's value holds (`Snapshot.Obj`), counted through its lists and tables:
## the snapshot's size in objects.
static func _objects_in(value: Variant) -> int:
	if value is Snapshot.Obj:
		var n: int = 1
		for inner: Variant in (value as Snapshot.Obj).values:
			n += _objects_in(inner)
		for inner: Variant in (value as Snapshot.Obj).added:
			n += _objects_in(inner)
		return n
	if value is Snapshot.List:
		var n: int = 0
		for inner: Variant in (value as Snapshot.List).items:
			n += _objects_in(inner)
		return n
	if value is Snapshot.Table:
		var n: int = 0
		for inner: Variant in (value as Snapshot.Table).values:
			n += _objects_in(inner)
		return n
	return 0


func _finish(failed: Array[String]) -> void:
	if _bot != null:
		_bot.leave()
	var found: Array[String] = failed.duplicate()
	var lines: Array[String] = _log.call("get_lines")
	for line in lines:
		found.append("the log has an error: " + line.trim_prefix("ERROR:").strip_edges())
	if _logging:
		_logging = false
		OS.remove_logger(_log)
	if found.is_empty():
		print("PROP COST OK: %s stand-ins measured" % ", ".join(counts.map(func(c: int) -> String: return str(c))))
		get_tree().quit(0)
	else:
		for reason in found:
			printerr("PROP COST FAILED: " + reason)
		get_tree().quit(1)
