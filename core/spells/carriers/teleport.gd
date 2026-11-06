class_name CarrierTeleport
extends CarrierMove
## Blinks its caster `ray_length` along the aim, stopping before walls, and strikes the bodies where
## it lands (`&"teleport"`). With homing it blinks to a target instead: one picked at random among
## those within its homing reach, any way round (`CarrierKit.pick_target`), landing at its edge, where
## its landing strike reaches it; with none in reach it does not blink (owner, 2026-11-06).


func id() -> StringName:
	return &"teleport"


func traits() -> int:
	return HITS | REACHES | STEERS | INSTANT_HOMING | MOVES_CASTER | MEETS_SHOTS


## Its landing strikes the body that lands too, so it deals no damage (the card's `base_damage` 0):
## its hits carry only what else they do (an infusion's status, a push, an `on hit`).
func deals_damage() -> bool:
	return false


## It strikes what is where it landed (rules R4c): each body within SpellLimits.LAND_REACH
## (`Spells._strike_round`), the one that moved too (a teleport deals no damage of its own), and
## with `deflect` turns the shots within MOVE_GUARD_REACH.
func on_move_end(spell: CompiledSpell, tag: int, actor: int, at: Vector2, heading: Vector2) -> void:
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0:
		kit.turn_shots_round(actor, tag, at, SpellLimits.MOVE_GUARD_REACH, id())
	kit.strike_round(spell, tag, actor, at, heading, SpellLimits.LAND_REACH, spell.echo_hit if kit.is_echo(spell) else null)


## A homing teleport goes to a target in its homing reach of what it moves (`from`, the body's
## anchor), landing with that at the target's edge (LAND_CLEARANCE short of it), so its landing
## strike, round where the body lands, reaches the target; nothing in reach: it teleports in place
## (owner, 2026-11-06: distance 0, so the cast, its landing strike and its payloads still happen
## where it stands). One without homing goes its way and distance.
func _aim_move(spell: CompiledSpell, _tag: int, actor: int, origin: Vector2, from: Vector2, way: Vector2, distance: float) -> Vector3:
	if spell.homing_range > 0.0:
		var goal: Vector2 = kit.pick_target(actor, from, spell.homing_range)
		distance = 0.0
		if goal.is_finite():
			if not goal.is_equal_approx(from):
				way = from.direction_to(goal)
			distance = maxf(from.distance_to(goal) - kit.projectiles.homing_target_radius - SpellLimits.LAND_CLEARANCE, 0.0)
	# Where it leaves shows now, as it is aimed (a teleport is over at once); where it lands shows at
	# its end point (`carrier_ended`, `CasterMoves.end`).
	if kit.events != null:
		kit.events.form_shown.emit(actor, spell.form_id, origin, way, distance, spell.tint, spell.look)
	return Vector3(way.x, way.y, distance)


func _move_body(_spell: CompiledSpell, tag: int, _actor: int, body: int, _origin: Vector2, _way: Vector2, offset: Vector2, _seconds: float, _chain: int, _prev: int) -> void:
	kit.events.caster_move_requested.emit(body, &"teleport", offset, 0.0, tag)
