class_name CarrierCaster
extends CarrierFallback
## The fallback carrier of a cast's own group (`&"caster"`, docs/CARRIERS.md): the modifiers and
## infusions left with no carrier after them land on the caster. It strikes round the caster's hand
## (`CarrierFallback`), and since it is on the caster (any actor, a wizard or an enemy) it meets the
## shots that reach it: a shield on it is the caster's barrier, a deflect turns the shots round the caster as it is cast.


func id() -> StringName:
	return &"caster"


func traits() -> int:
	return HITS | MEETS_SHOTS


## A cast on yourself (the owner, 2026-11-06: such a cast showed nothing): the staff swung upright,
## drawn in to the body and glowing a moment, then back.
const POSE: Array[Dictionary] = [
	{"phase": "after", "at": 0.06, "turn": -70.0, "push": -3.0, "stretch": -0.15, "ease": "out"},
	{"phase": "after", "at": 0.16, "turn": -80.0, "push": -3.0, "lift": 2.0, "glow": 0.7, "stretch": 0.1, "mood": "raised"},
	{"phase": "after", "at": 0.36},
]

func staff_pose() -> PackedFloat32Array:
	return FormBase.pack_pose(POSE)


## Its cast cue (content/cues/cast_self.tres): drawn in to the caster, not thrown out.
func cast_cue() -> StringName:
	return &"cast_self"


## A deflect turns the shots of other teams within its strike, or within MOVE_GUARD_REACH (a
## teleport's landing) when that is wider, before the strike.
func _before_strike(spell: CompiledSpell, tag: int, actor: int, at: Vector2, reach: float) -> void:
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) <= 0.0 or kit.projectiles == null:
		return
	var around: float = maxf(reach, SpellLimits.MOVE_GUARD_REACH)
	kit.guard(kit.projectiles.shots_on_segment(actor, at, at, around), actor, tag, true, 0, at, at, id())


## A shield on it is a barrier on the actor whose body cast it, a wizard or an enemy (a ring of
## copies, penta, is cast by points, which have none). After the strike, which reaches the caster and
## would spend it.
func _after_strike(spell: CompiledSpell, tag: int, actor: int, _at: Vector2) -> void:
	if kit.caster() == SpellRuntime.CASTER_BODY:
		kit.moves().shield_caster(spell, tag, actor, 0.0)
