class_name Health
extends ActorComponent
## Health (actors G4, docs/milestones/M2-actors.md, "The components"): how much an actor can take.
## `take(amount)` loses health, `heal(amount)` gains it back up to `max_health`; `protect(seconds)`
## makes it unhurtable for a while (a wizard who joins mid-run). At 0 it sends `depleted` once;
## the actor dies, or a Downed component (gameplay/player, G7) downs it instead.
##
## Nobody else keeps an actor's health: Combat calls this (G5). Until then the actor's hits and
## heals come as `damage_dealt` and `heal_dealt` with the actor as target, as they come to a
## wizard today (Combat still keeps an enemy's own count beside it, and frees it at 0).
##
## Signals are local (to the actor's own components and controller), never on the bus.

## The health changed (a hit, a heal, a reset): `health` of `max_health`.
signal changed(health: int, max_health: int)
## The health reached 0; `killer` is who landed the last hit (an event's player, or -1).
signal depleted(killer: int)

## Most health; an enemy's comes from its data (`EnemyBase.max_health`).
@export var max_health: int = 100

var health: int = 100

## Seconds left of `protect`.
var _protect_left: float = 0.0


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	health = max_health


func attach() -> void:
	if actor == null or actor.events == null:
		return
	if not actor.events.damage_dealt.is_connected(_on_damage_dealt):
		actor.events.damage_dealt.connect(_on_damage_dealt)
	if not actor.events.heal_dealt.is_connected(_on_heal_dealt):
		actor.events.heal_dealt.connect(_on_heal_dealt)


func detach() -> void:
	if actor == null or actor.events == null or not is_instance_valid(actor.events):
		return
	if actor.events.damage_dealt.is_connected(_on_damage_dealt):
		actor.events.damage_dealt.disconnect(_on_damage_dealt)
	if actor.events.heal_dealt.is_connected(_on_heal_dealt):
		actor.events.heal_dealt.disconnect(_on_heal_dealt)


## Counts the protection down (the actor calls it first in its step).
func step(delta: float) -> void:
	_protect_left = maxf(_protect_left - delta, 0.0)


## Lose `amount` (from `killer`, an event's player or -1). Ignored at 0 health, while protected,
## or for 0 or less. Returns true if it was applied; at 0 `depleted` follows.
func take(amount: int, killer: int = -1) -> bool:
	if health <= 0 or is_protected() or amount <= 0:
		return false
	health = maxi(health - amount, 0)
	changed.emit(health, max_health)
	if health == 0:
		_protect_left = 0.0
		depleted.emit(killer)
	return true


## Gain `amount`, up to `max_health`. Ignored at 0 health (a revive is the way back: `reset`).
## Returns true if any was added.
func heal(amount: int) -> bool:
	if health <= 0 or amount <= 0 or health >= max_health:
		return false
	health = mini(health + amount, max_health)
	changed.emit(health, max_health)
	return true


## Set the health to `amount` (a revive, a new run), at most `max_health`.
func reset(amount: int) -> void:
	health = clampi(amount, 0, max_health)
	changed.emit(health, max_health)


## Unhurtable for `seconds` (at least what is left). Nothing at 0 health.
func protect(seconds: float) -> void:
	if health > 0:
		_protect_left = maxf(_protect_left, seconds)


func is_protected() -> bool:
	return _protect_left > 0.0


## Seconds of protection left.
func protect_left() -> float:
	return _protect_left


func is_depleted() -> bool:
	return health <= 0


func _on_damage_dealt(player: int, target: Node, amount: int, _position: Vector2) -> void:
	if target == actor:
		take(amount, player)


func _on_heal_dealt(_player: int, target: Node, amount: int, _position: Vector2) -> void:
	if target == actor:
		heal(amount)
