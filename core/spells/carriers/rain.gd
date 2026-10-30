class_name CarrierRain
extends Carrier
## Strikes the aim point after `lifetime` seconds and drops its payload there (`&"rain"`).
## Homing places it on a target near the point; held, it falls again and again.


## Modifier cards that do nothing on a rain, with the sentence the builder shows after
## "<Card> does nothing on a Rain: ". Every card not listed does something here.
const DOES_NOTHING: Dictionary = {
	B.SHIELD: "it blocks shots that touch the carrier or guards the caster on a move, and a rain strikes once where it lands",
	B.BOUNCE: "it turns a shot or a beam at walls, and a rain strikes once where it lands",
	B.LINGER: "it only changes a moving shot, and a rain strikes once where it lands",
	B.STICKY: "it only changes a moving shot, and a rain strikes once where it lands",
	B.MAGNET: "it needs a shot or a beam that stays in the world, and a rain strikes once where it lands",
	B.GHOST: "it only takes a flying shot or a line through walls, and a rain strikes once where it lands",
	B.SPIRAL: "it only changes a moving shot, and a rain strikes once where it lands",
	B.GROWTH: "it grows a shot in the world or a beam, and a rain strikes once where it lands",
	B.RETURN: "it does not fly out",
	B.ARC: "it is not a shot that stays in the air",
	B.DEFLECT: "it touches no shots",
}
## Trigger cards that never go off on a rain, with the sentence the builder shows.
const NEVER_FIRES: Dictionary = {
	E.BLOCK: "nothing on it can block a shot",
	E.WALL: "a rain falls from above and never meets a wall",
}


func id() -> StringName:
	return &"rain"


func noun() -> String:
	return "rain"


func what() -> String:
	return "a rain strikes once where it lands"


func traits() -> int:
	return HITS | LASTS | REACHES | STEERS | SPEED | SHOTS | REPEATS_HELD | CARRIES_PAYLOAD | HOLDS_STAFF


func does_nothing() -> Dictionary:
	return DOES_NOTHING


func never_fires() -> Dictionary:
	return NEVER_FIRES


func hit_kind() -> StringName:
	return &"ray"



func reach_of(spell: CompiledSpell) -> float:
	return spell.ray_length if spell.ray_length > 0.0 else SpellLimits.RAIN_REACH


## Rain: for each of its shots, a cue at the aim point and a launch of its payload there after
## its `lifetime`. The aim point is `ray_length` (or `SpellLimits.RAIN_REACH`) along the shot's
## heading, stopped at a wall; homing moves it onto a target near it (`_homed_place`). Returns
## how many were set. A held rain falls again and again (`_repeats`).
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, _source: Node, _lifetime: float, _chain: int, _prev: int) -> int:
	var reach: float = spell.ray_length if spell.ray_length > 0.0 else SpellLimits.RAIN_REACH
	var placed: int = 0
	for n in spell.shots:
		var along: Vector2 = heading.rotated(rt._fan_angle(n, spell.shots, spell))
		var point: Vector2 = _homed_place(spell, actor, tag + n, origin, rt.projectiles.clip_to_walls(origin, origin + along * reach))
		var group: CompiledGroup = spell.own_payload if spell.own_payload != null else CompiledGroup.new()
		var launch: SpellRuntime.PendingLaunch = rt._delay(spell.lifetime, group, null, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), point, along, null, false)
		launch.landing = spell
		launch.echoed = rt._echo_spell == spell
		rt._lc_join(spell, tag, SpellRuntime.LC_POINT, -1, 0, false, spell.lifetime, point, along)
		placed += 1
		if rt.events != null:
			rt.events.form_shown.emit(actor, &"rain", point, along, spell.lifetime, spell.tint, spell.look)
	return placed


## A rain lands (`Spells._run_pending`, when its waiting launch is due): it strikes every body within its splash (`SpellLimits.RAIN_SPLASH`, or its size
## when that is larger) with its own hit and cards (an echo's at half), then its `blast` goes off,
## its payload falls (a group, so a burst repeats it), then its own `on expire` trigger fires, all
## at the aim point (its end point, rules R1d and R4g).
func land(spell: CompiledSpell, group: CompiledGroup, actor: int, staff: int, generation: int, point: Vector2, heading: Vector2, echoed: bool = false) -> void:
	var tag: int = SpellTag.make(actor, staff, spell.node, generation)
	_strike_round(spell, tag, actor, point, heading, maxf(spell.radius, SpellLimits.RAIN_SPLASH), spell.echo_hit if echoed else null)
	rt._blast(spell, tag, actor, point)
	if group != null and not group.is_empty():
		rt._fire(group, actor, staff, generation, point, heading, null, SpellRuntime.CASTER_POINT)
	if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
		rt._fire(spell.payload, actor, staff, generation, point, heading, null, SpellRuntime.CASTER_POINT)


## The carrier `spell` with `tag` strikes every body within `reach` of `at` at once, outward from
## `at`, with `hit` (null: its own) as a ray (`_ray_begin`) that `_on_hit` reads, so the
## whole hit goes with it: infusions, heavy, chain, siphon, possess and `on hit` (a slam's ring
## strikes the same way as it grows). The bodies are copied first: what a hit sets off can sweep.
func _strike_round(spell: CompiledSpell, tag: int, actor: int, at: Vector2, way: Vector2, reach: float, hit: HitProfile) -> void:
	var found: int = rt.projectiles.sweep(actor, at, way, 1, -PI, PI, reach, SpellRuntime.HITS)
	if found == 0:
		return
	var struck: Array[Node] = []
	for i in found:
		struck.append(rt.projectiles.sweep_nodes[i])
	var ray: RayHit = rt._ray_begin(tag, rt._ray.dir, spell.chain_jumps, 0, hit, -1)
	for node in struck:
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var body: Vector2 = (node as Node2D).global_position
		ray.dir = at.direction_to(body) if not at.is_equal_approx(body) else way
		rt.projectiles.strike(actor, node, at, ray.dir, tag, &"rain")
	rt._ray_end()
	rt._cast_jumps()


## Where a carrier placed at `point` ahead of its caster at `origin` (a rain) goes when it
## homes (rules R4i): onto a target within its homing reach of the point, picked as a homing
## shot picks one (`homing_point`, any way round), stopped at a wall on the way; else `point`.
func _homed_place(spell: CompiledSpell, actor: int, tag: int, origin: Vector2, point: Vector2) -> Vector2:
	if spell.homing_range <= 0.0:
		return point
	var goal: Vector2 = rt.projectiles.homing_point(actor, point, Vector2.RIGHT, PI, SpellRuntime.ProjectilesScript.ACTOR_LAYERS, spell.homing_range, 0, hash(Vector3i(actor, tag, roundi(rt._clock * 1000.0))))
	return point if not goal.is_finite() else rt.projectiles.clip_to_walls(origin, goal)
