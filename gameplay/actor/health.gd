class_name Health
extends ActorComponent
## Health (actors G4, docs/milestones/M2-actors.md, "The components"): how much an actor can take,
## in points that may be parts of a point (an atom's speck takes 0.3; owner, 2026-10-30).
## `take(amount)` loses health, `heal(amount)` gains it back up to `max_health`; `protect(seconds)`
## makes it unhurtable for a while (a wizard who joins mid-run). At 0 it sends `depleted` once;
## the actor dies, or a Downed component (gameplay/player, G7) downs it instead.
##
## Nobody else keeps an actor's health: Combat calls `take` and `heal` (actors G5), and the
## events it sends after (`damage_dealt`, `heal_dealt`) are for the rest of the game, not for this.
##
## Signals are local (to the actor's own components and controller), never on the bus.

## The health changed (a hit, a heal, a reset): `health` of `max_health`.
signal changed(health: float, max_health: float)
## The health reached 0; `killer` is who landed the last hit (an event's player, or -1).
signal depleted(killer: int)

## Most health; an enemy's comes from its data (`EnemyBase.max_health`).
@export var max_health: float = 100.0

var health: float = 100.0

## True from a `protect` until its time has run out: the actor steps Health only then (read only).
var protecting: bool = false

## True while hits take nothing (a prop no hit hurts, `PropBase.invincible`). Unlike
## `protect`, the hit still lands: Combat sends it, pushes and flashes the body; only the health
## stays as it was, so it is never depleted by a hit.
var invincible: bool = false

## Seconds left of `protect`.
var _protect_left: float = 0.0

## Health below this after a hit is none: the float sums of many specks never leave a crumb.
const EMPTY: float = 0.0001


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	health = max_health


## Counts the protection down (the actor calls it first in its step, while `protecting`).
func step(delta: float) -> void:
	_protect_left = maxf(_protect_left - delta, 0.0)
	protecting = _protect_left > 0.0


## Lose `amount` (from `killer`, an event's player or -1). Ignored at 0 health, while protected or
## `invincible`, or for 0 or less. Returns true if it was applied; at 0 `depleted` follows.
func take(amount: float, killer: int = -1) -> bool:
	if health <= 0.0 or is_protected() or invincible or amount <= 0.0:
		return false
	health = maxf(health - amount, 0.0)
	if health < EMPTY:
		health = 0.0
	changed.emit(health, max_health)
	if health == 0.0:
		_protect_left = 0.0
		depleted.emit(killer)
	return true


## Lose `amount` whatever protects it (hub rework HR-H2: a fall's cost, `Combat.take_fall`, which is
## no hit), as `take` would: at 0, `depleted` from `killer`. Nothing at 0 already or for 0 or less.
func lose(amount: float, killer: int = -1) -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if health < EMPTY:
		health = 0.0
	changed.emit(health, max_health)
	if health == 0.0:
		_protect_left = 0.0
		protecting = false
		depleted.emit(killer)


## Lose everything at once, whatever protects it (hub rework HR-H2: a fall a body does not come
## back from, `Combat.die_of_fall`): at 0, `depleted` from `killer`. Nothing at 0 already.
func empty(killer: int = -1) -> void:
	if health <= 0.0:
		return
	health = 0.0
	_protect_left = 0.0
	protecting = false
	changed.emit(health, max_health)
	depleted.emit(killer)


## Gain `amount`, up to `max_health`. Ignored at 0 health (a revive is the way back: `reset`).
## Returns true if any was added.
func heal(amount: float) -> bool:
	if health <= 0.0 or amount <= 0.0 or health >= max_health:
		return false
	health = minf(health + amount, max_health)
	changed.emit(health, max_health)
	return true


## Raise `max_health` by `more` and the health by as much, unless it is at 0 (a reward of more
## health, connected biomes CB10: Combat calls it). Nothing for `more` not above 0.
func grow(more: float) -> void:
	if not (more > 0.0) or not is_finite(more):
		return
	max_health += more
	if health > 0.0:
		health = minf(health + more, max_health)
	changed.emit(health, max_health)


## Set the health to `amount` (a revive, a new run), at most `max_health`.
func reset(amount: float) -> void:
	health = clampf(amount, 0.0, max_health)
	changed.emit(health, max_health)


## Make `most` the most health, the health keeping its share of it (boss plan OB13: a player joining
## or leaving changes a boss's most and current health by the same share). Ignored for a most that is
## not above 0; at 0 health it stays 0.
func rescale(most: float) -> void:
	if not (most > 0.0) or not is_finite(most) or most == max_health:
		return
	health = clampf(health * most / max_health, 0.0, most) if max_health > 0.0 else most
	max_health = most
	changed.emit(health, max_health)


## Unhurtable for `seconds` (at least what is left). Nothing at 0 health, and nothing for a still
## body (props W2, `Actor.is_still`): its step, which counts a protection down, never runs.
func protect(seconds: float) -> void:
	if actor != null and actor.is_still():
		return
	if health > 0.0:
		_protect_left = maxf(_protect_left, seconds)
		protecting = _protect_left > 0.0


func is_protected() -> bool:
	return _protect_left > 0.0


## Seconds of protection left.
func protect_left() -> float:
	return _protect_left


func is_depleted() -> bool:
	return health <= 0.0


## Full and not protected (props W2: what the actor's `rest_leaf` adds is the health itself and
## `invincible`).
func at_rest() -> bool:
	return health == max_health and _protect_left == 0.0 and not protecting
