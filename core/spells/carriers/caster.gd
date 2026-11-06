class_name CarrierCaster
extends CarrierBearer
## The fallback carrier of a cast's own group (`&"caster"`, docs/CARRIERS.md): the modifiers and
## infusions left with no carrier after them land on the caster. It strikes round the caster's hand
## (`CarrierFallback`), and since it is on the caster (any actor, a wizard or an enemy) it meets the
## shots that reach it: a shield on it is the caster's barrier, a deflect turns the shots round the
## caster as it is cast. The same rule as a payload's cards landing on the body that fired it
## (`CarrierBearer`), with a look of its own: a cast on yourself.


func id() -> StringName:
	return &"caster"


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
## teleport's landing) when that is wider, before the strike: round the caster, and round each
## point of a ring of copies (penta), which strike there too.
func _before_strike(spell: CompiledSpell, tag: int, actor: int, at: Vector2, reach: float) -> void:
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0 and kit.projectiles != null:
		kit.turn_shots_round(actor, tag, at, reach, id())
