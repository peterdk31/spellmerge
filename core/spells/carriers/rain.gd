class_name CarrierRain
extends Carrier
## Strikes the aim point after `lifetime` seconds and drops its payload there (`&"rain"`).
## Homing places it on a target near the point; held, it falls again and again.


func id() -> StringName:
	return &"rain"


## What draws its look: no look of its own (cues, or a body that is not the card's).
func look_drawer() -> int:
	return LOOK_NONE


func traits() -> int:
	return HITS | LASTS | REACHES | STEERS | SPEED | SHOTS | REPEATS_HELD | CARRIES_PAYLOAD | HOLDS_STAFF


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
		var along: Vector2 = DMath.rotated(heading, kit.fan_angle(n, spell.shots, spell))
		var point: Vector2 = _homed_place(spell, actor, origin, kit.projectiles.clip_to_walls(origin, origin + along * reach))
		var group: CompiledGroup = spell.own_payload if spell.own_payload != null else CompiledGroup.new()
		var launch: SpellRuntime.PendingLaunch = kit.delay(spell.lifetime, group, null, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), point, along, null, false)
		launch.landing = spell
		launch.echoed = kit.is_echo(spell)
		kit.live_join(spell, tag, SpellRuntime.LC_POINT, -1, 0, false, spell.lifetime, point, along)
		placed += 1
		if kit.events != null:
			kit.events.form_shown.emit(actor, &"rain", point, along, spell.lifetime, spell.tint, spell.look)
	return placed


## A rain lands (`Spells._run_pending`, when its waiting launch is due): it strikes every body within its splash (`SpellLimits.RAIN_SPLASH`, or its size
## when that is larger) with its own hit and cards (an echo's at half), then its `blast` goes off,
## its payload falls (a group, so a burst repeats it), then its own `on expire` trigger fires, all
## at the aim point (its end point, rules R1d and R4g).
func land(spell: CompiledSpell, group: CompiledGroup, actor: int, staff: int, generation: int, point: Vector2, heading: Vector2, echoed: bool = false) -> void:
	var tag: int = SpellTag.make(actor, staff, spell.node, generation)
	var splash: float = maxf(spell.radius, SpellLimits.RAIN_SPLASH)
	if kit.events != null:
		kit.events.carrier_ended.emit(actor, spell.form_id, point, heading, splash, spell.tint, spell.look)
	kit.strike_round(spell, tag, actor, point, heading, splash, spell.echo_hit if echoed else null)
	kit.blast(spell, tag, actor, point)
	if group != null and not group.is_empty():
		kit.fire(group, actor, staff, generation, point, heading, null, SpellRuntime.CASTER_POINT)
	for trigger in spell.triggers:
		if trigger.event == TriggerBase.Event.EXPIRE:
			kit.fire(trigger.payload, actor, staff, generation, point, heading, null, SpellRuntime.CASTER_POINT)


## Where a carrier placed at `point` ahead of its caster at `origin` (a rain) goes when it
## homes (rules R4i): onto a target within its homing reach of the point, a random one, any way
## round (`CarrierKit.pick_target`), stopped at a wall on the way; else `point`.
func _homed_place(spell: CompiledSpell, actor: int, origin: Vector2, point: Vector2) -> Vector2:
	if spell.homing_range <= 0.0:
		return point
	var goal: Vector2 = kit.pick_target(actor, point, spell.homing_range)
	return point if not goal.is_finite() else kit.projectiles.clip_to_walls(origin, goal)
