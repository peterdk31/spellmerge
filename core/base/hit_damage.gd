class_name HitDamage
extends RefCounted
## The damage one hit of a spell deals before the body's hex, Combat's answer to `hit_damage_asked`
## (hit batch A2, docs/milestones/hit-batch.md): its profile's damage times its caster's power, 0
## for a heal or a spell that deals none. The body's half is `HitRoom`.
##
## One is made once by the asker and filled again at each ask (`clear`), so an ask allocates nothing.

var damage: float = 0.0


func clear() -> void:
	damage = 0.0
