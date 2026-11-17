class_name HitRoom
extends RefCounted
## How much a body can still take, the answer to `hit_room_asked` (performance prototype,
## 2026-11-17): the projectile manager merges a step's shot hits (`ProjectileManager.merge_hits`) and
## sends them after its hit pass, so a body killed by the first of them would otherwise take the
## rest of the pass's shots too, and those shots would be spent on a dead body. Combat, which owns
## health and damage, fills it at once, so the manager never calls Combat.
##
## One is made once by the asker and filled again at each ask (`clear`), so an ask allocates nothing.

## Health the body has left (INF: it cannot be told, or cannot be killed by hits).
var health: float = INF
## The damage one hit of the spell asked about deals it (0: none, a heal).
var damage: float = 0.0
## The charges of its barrier that spell's hits meet: each takes one hit whole, no damage.
var charges: int = 0


func clear() -> void:
	health = INF
	damage = 0.0
	charges = 0
