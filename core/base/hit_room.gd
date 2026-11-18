class_name HitRoom
extends RefCounted
## What a body can still take, Combat's answer to `hit_room_asked` (hit batch A2,
## docs/milestones/hit-batch.md, "A body's room, asked once a body"): the projectile manager merges
## a step's shot hits and sends them after its hit pass, so a body killed by the first of them would
## otherwise take the rest of the pass's shots too, and those shots would be spent on a dead body.
## Combat, which owns health and damage, fills it at once, so the manager never calls Combat; the
## damage of one hit of a spell is the other half (`HitDamage`, `hit_damage_asked`).
##
## One is made once by the asker and filled again at each ask (`clear`), so an ask allocates nothing.

## Whether hits take any health from the body: false for one down, dying, depleted, protected or
## invincible, a plain body at 0, or one Combat does not know (its room is then unknown: never dead).
var known: bool = false
## Health the body has left (INF while not `known`).
var health: float = INF
## Whether it is hexed, and the hex's power (each hit's damage grows by `hex` percent).
var hexed: bool = false
var hex: float = 0.0
## Its barrier's charges (0 for none), each taking a hit whole, and the spell (tag) the barrier lets
## through (0: none; a Barrier card's, `Combat.give_barrier`).
var charges: int = 0
var spares: int = 0


func clear() -> void:
	known = false
	health = INF
	hexed = false
	hex = 0.0
	charges = 0
	spares = 0
