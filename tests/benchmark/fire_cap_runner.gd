extends Node
## Measures what the per-step fire pacing (`Spells.fire_shots_per_step`, `SpellLimits.FIRE_SHOTS_PER_STEP`:
## the shots trigger fires may make in a step; a fire past it waits for the next) costs and saves: four seats cast trigger-heavy staffs of the real cards at a crowd that never
## dies, with eight enemy casters on the shared budget, in a walled room, and the runner steps the
## projectile manager and the spell runtime by hand. For each projectile cap (web 500, desktop
## 3,000) and each budget in FIRE_CAPS it prints one `BENCH:` line: the step time (the manager's
## and the runtime's step together; average, p95, max), the payloads fired and made to wait per
## step, and the shots in flight. Triggers have no per-shot count and nothing is dropped (owner,
## 2026-10-29), so the pacing is all that spreads a cascade over steps. It gates nothing.
##
## The staffs (the worst of what a player can build today, all at once):
##  - seat 0: a split nova whose every hit fires a split bolt,
##  - seat 1: a beam that bounces twice and fires a nova at every wall it meets,
##  - seat 2: an orbit whose timer fires a split nova every half second,
##  - seat 3: a doubly piercing bolt whose hits fire a split bolt whose hits fire a nova,
##  - eight enemies (one shared budget): a nova whose hits fire a bolt.
## The crowd never dies (no Combat here), so `on hit` cascades never run out of targets; kills,
## reactions and hurts are not part of it.
##
## Then what one fire costs (`_burst`): a nova split three times, cast in the middle of the crowd
## so most of its shots hit in the same few steps, with `on hit` and a payload (a bolt, a split
## bolt, a nova) and without, unpaced and at the default pacing; the difference over those steps,
## per payload fired, is the cost of a fire and of the shots it made, and the worst step says what
## the pacing saves. Native numbers:
## a web build runs the same GDScript several times slower.
##
## godot --headless --path . --script res://tests/benchmark/fire_cap.gd

const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const StaffKit := preload("res://tests/support/staff_kit.gd")

const DT: float = 1.0 / 60.0
const ROOM: Vector2 = Vector2(640.0, 360.0)
const WALL: float = 16.0
const PLAYERS: int = 4
const ENEMY_CASTERS: int = 8
const CROWD: int = 100
const CROWD_CENTER: Vector2 = Vector2(430.0, 180.0)
## Steps before measuring, and measured.
const WARM_UP: int = 120
const MEASURE: int = 600
## The pacing budgets tried (shots a step); the last is as good as none.
const FIRE_CAPS: Array[int] = [64, 128, 256, 512, 1024, 1000000]
const SHOT_CAPS: Array[int] = [ManagerScript.DEFAULT_CAP_WEB, ManagerScript.DEFAULT_CAP_DESKTOP]
const SEAT_STAFFS: Array[Array] = [
	[&"split", &"on_hit", &"nova", &"split", &"bolt"],
	[&"bounce", &"bounce", &"on_wall", &"beam", &"nova"],
	[&"timer", &"orbit", &"split", &"nova"],
	[&"pierce", &"pierce", &"on_hit", &"bolt", &"split", &"on_hit", &"bolt", &"nova"],
]
const ENEMY_STAFF: Array[StringName] = [&"on_hit", &"nova", &"bolt"]
## The burst: its carrier, and the payloads timed.
const BURST_CARRIER: Array[StringName] = [&"split", &"split", &"split", &"nova"]
const BURST_PAYLOADS: Dictionary = {
	"a bolt": [&"bolt"],
	"a split bolt": [&"split", &"bolt"],
	"a nova": [&"nova"],
}
## Steps timed after a burst's cast, and bursts averaged.
const BURST_STEPS: int = 30
const BURSTS: int = 10

var _bus: EventsScript
var _mgr: ManagerScript
var _spells: SpellsScript
var _actors: ActorSeats.ActorsScript
var _seats: PackedInt32Array = PackedInt32Array()
var _enemies: PackedInt32Array = PackedInt32Array()
var _targets: Array[Node2D] = []
var _failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	var registry: Node = get_tree().root.get_node_or_null(^"Registry")
	if registry == null:
		_finish(["the Registry autoload is missing"])
		return
	for shots in SHOT_CAPS:
		for cap in FIRE_CAPS:
			_run(registry, shots, cap)
	for shots in SHOT_CAPS:
		for budget in [SpellLimits.FIRE_SHOTS_PER_STEP, 1000000]:
			for payload: String in BURST_PAYLOADS:
				_burst(registry, shots, payload, budget)
	_teardown()
	_finish(_failures)


func _finish(failed: Array[String]) -> void:
	if failed.is_empty():
		print("FIRE CAP OK")
		get_tree().quit(0)
	else:
		for reason in failed:
			printerr("FIRE CAP FAILED: " + reason)
		get_tree().quit(1)


func _teardown() -> void:
	for target in _targets:
		if is_instance_valid(target):
			target.free()
	_targets.clear()
	for node: Node in [_spells, _mgr, _bus, _actors]:
		if node != null and is_instance_valid(node):
			node.free()
	_spells = null
	_mgr = null
	_bus = null
	_actors = null


## A fresh scene: the room, the crowd, the casters, the runtime with `fire_cap`.
func _open(registry: Node, shot_cap: int, fire_cap: int) -> void:
	_teardown()
	_bus = EventsScript.new()
	_mgr = ManagerScript.new()
	_actors = ActorSeats.ActorsScript.new()
	_seats = ActorSeats.seat_wizards(_actors, PLAYERS)
	_enemies = PackedInt32Array()
	for i in ENEMY_CASTERS:
		_enemies.append(ActorSeats.enemy(_actors))
	_mgr.actors = _actors
	_mgr.events = _bus
	_mgr.set_cap(shot_cap)
	_mgr.set_bounds(Rect2(Vector2.ZERO, ROOM))
	_mgr.set_walls([
		Rect2(0.0, 0.0, ROOM.x, WALL), Rect2(0.0, ROOM.y - WALL, ROOM.x, WALL),
		Rect2(0.0, 0.0, WALL, ROOM.y), Rect2(ROOM.x - WALL, 0.0, WALL, ROOM.y),
		Rect2(250.0, 60.0, 24.0, 24.0), Rect2(250.0, 276.0, 24.0, 24.0),
	] as Array[Rect2])
	_spells = SpellsScript.new()
	_spells.registry = registry
	_spells.bind(_mgr, _bus)
	_spells.fire_shots_per_step = fire_cap
	for i in CROWD:
		var node := Node2D.new()
		get_tree().root.add_child(node)
		node.global_position = CROWD_CENTER + Vector2(float(i % 10) - 4.5, float(i / 10) - 4.5) * 14.0
		_mgr.add_target(node, 6.0, ManagerScript.LAYER_ENEMY)
		_targets.append(node)


func _run(registry: Node, shot_cap: int, fire_cap: int) -> void:
	_open(registry, shot_cap, fire_cap)
	for seat in PLAYERS:
		var cards: Array[StringName] = []
		cards.assign(SEAT_STAFFS[seat])
		StaffKit.build(_spells, _seats[seat], 0, cards)
	for actor in _enemies:
		StaffKit.build(_spells, actor, 0, ENEMY_STAFF)
	var times := PackedInt32Array()
	var fires := PackedInt32Array()
	var drops := PackedInt32Array()
	var shots_sum: int = 0
	for n in WARM_UP + MEASURE:
		_cast_all()
		var made: int = _spells.fires_made
		var dropped: int = _spells.fires_waited
		var start: int = Time.get_ticks_usec()
		_mgr.step(DT)
		_spells.step(DT)
		var took: int = Time.get_ticks_usec() - start
		if n >= WARM_UP:
			times.append(took)
			fires.append(_spells.fires_made - made)
			drops.append(_spells.fires_waited - dropped)
			shots_sum += _mgr.get_count()
	times.sort()
	var total: int = 0
	for t in times:
		total += t
	var fired: int = 0
	var most: int = 0
	for f in fires:
		fired += f
		most = maxi(most, f)
	var dropped_total: int = 0
	for d in drops:
		dropped_total += d
	var steps: float = float(MEASURE)
	print("BENCH: fire cap %s, shot cap %d: step avg %.2f ms p95 %.2f ms max %.2f ms; fires per step avg %.1f max %d; made to wait per step avg %.1f (%.0f%%); shots avg %.0f" % [
		"none" if fire_cap >= 1000000 else str(fire_cap) + " shots", shot_cap,
		float(total) / steps / 1000.0, float(times[int(steps * 0.95)]) / 1000.0, float(times[times.size() - 1]) / 1000.0,
		float(fired) / steps, most, float(dropped_total) / steps,
		100.0 * float(dropped_total) / maxf(1.0, float(fired + dropped_total)), float(shots_sum) / steps])
	if fired == 0:
		_failures.append("fire cap %d, shot cap %d: nothing fired" % [fire_cap, shot_cap])


## Every caster casts its staff whenever it is ready, from the crowd's edge (a nova is a short
## burst) and aimed at it; the seats hold aim, so a beam follows it.
func _cast_all() -> void:
	for seat in PLAYERS:
		var actor: int = _seats[seat]
		var origin: Vector2 = Vector2(345.0, 110.0 + 46.0 * seat)
		var way: Vector2 = origin.direction_to(CROWD_CENTER + Vector2(0.0, 40.0 * (seat - 1.5)))
		_mgr.set_anchor(actor, origin)
		_spells.set_aim(actor, origin, way)
		_spells.cast_staff(actor, 0, origin, way, 1.0e9)
	for i in _enemies.size():
		var actor: int = _enemies[i]
		var origin: Vector2 = Vector2(515.0, 100.0 + 22.0 * i)
		_mgr.set_anchor(actor, origin)
		_spells.cast_staff(actor, 0, origin, origin.direction_to(CROWD_CENTER), 1.0e9)


## The cost of a fire with `payload`: BURSTS bursts with the trigger and as many without, each in
## a fresh scene, timed over BURST_STEPS steps from the cast.
func _burst(registry: Node, shot_cap: int, payload: String, budget: int) -> void:
	var fired: Array[StringName] = [&"on_hit"]
	fired.append_array(BURST_CARRIER)
	for card: StringName in BURST_PAYLOADS[payload]:
		fired.append(card)
	var plain: Array[StringName] = []
	plain.assign(BURST_CARRIER)
	var with_usec: int = 0
	var without_usec: int = 0
	var fires: int = 0
	var shots_made: int = 0
	var peak: int = 0
	var worst_with: int = 0
	var worst_without: int = 0
	for n in BURSTS:
		var timed: Array[int] = _burst_once(registry, shot_cap, fired, budget)
		with_usec += timed[0]
		fires += timed[1]
		shots_made += timed[2]
		peak = maxi(peak, timed[3])
		worst_with = maxi(worst_with, timed[4])
		var control: Array[int] = _burst_once(registry, shot_cap, plain, budget)
		without_usec += control[0]
		worst_without = maxi(worst_without, control[4])
	if fires == 0:
		_failures.append("burst with %s, shot cap %d, pacing %d: nothing fired" % [payload, shot_cap, budget])
		return
	var extra: float = float(with_usec - without_usec)
	print("BENCH: fire cost, %s, shot cap %d, pacing %s: %.1f fires a burst, at most %d in one step, %.0f shots in flight at most; %.2f ms with, %.2f ms without over %d steps (worst step %.2f ms with, %.2f ms without); %.1f us per fire (%.0f fires per ms)" % [
		payload, shot_cap, "none" if budget >= 1000000 else str(budget) + " shots", float(fires) / BURSTS, peak, float(shots_made) / BURSTS,
		float(with_usec) / BURSTS / 1000.0, float(without_usec) / BURSTS / 1000.0, BURST_STEPS,
		float(worst_with) / 1000.0, float(worst_without) / 1000.0,
		extra / float(fires), 1000.0 * float(fires) / maxf(1.0, extra)])


## One burst of `cards` from the middle of the crowd: [usec over BURST_STEPS steps, fires, most
## shots alive at once, most fires in one step, the longest step in usec].
func _burst_once(registry: Node, shot_cap: int, cards: Array[StringName], budget: int) -> Array[int]:
	_open(registry, shot_cap, budget)
	StaffKit.build(_spells, _seats[0], 0, cards)
	_mgr.set_anchor(_seats[0], CROWD_CENTER)
	_spells.cast_staff(_seats[0], 0, CROWD_CENTER, Vector2.RIGHT, 1.0e9)
	var usec: int = 0
	var most: int = 0
	var peak: int = 0
	var worst: int = 0
	for n in BURST_STEPS:
		var made: int = _spells.fires_made
		var start: int = Time.get_ticks_usec()
		_mgr.step(DT)
		_spells.step(DT)
		var took: int = Time.get_ticks_usec() - start
		usec += took
		worst = maxi(worst, took)
		most = maxi(most, _mgr.get_count())
		peak = maxi(peak, _spells.fires_made - made)
	return [usec, _spells.fires_made, most, peak, worst]
