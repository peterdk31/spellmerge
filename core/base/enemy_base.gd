class_name EnemyBase
extends Resource
## An enemy: its body's numbers, its scene, its staffs, how it plays them and a boss's phases.
## M3 extends it with player-count scaling.

## Unique name of the enemy, also its folder name; the registry finds it by this.
@export var id: StringName = &""
## True for content shown in the free web demo.
@export var demo: bool = false
@export var max_health: float = 1.0
## Pixels per second.
@export var move_speed: float = 0.0
## Damage a player takes from touching the enemy.
@export var contact_damage: int = 0
@export var scene: PackedScene
## True for a boss: its death stops the whole game for a moment (Feel); other kills hold only the
## bodies in them.
@export var boss: bool = false

## The body's scale (1: as drawn); a boss is bigger.
@export var size: float = 1.0

# Enemy AI (docs/milestones/M2-enemy-ai.md, "The enemy's data"): an enemy holds 1-4 staffs of
# player cards and casts them like a wizard, paying each staff's own mana. The AI reads what each
# staff casts next (`CastSense`), so a new enemy type is a sprite and staffs, with no code. Without
# a staff it only chases and hurts by touch.

## Its staffs, one per button (at most 4); empty for an enemy that only chases.
@export var staffs: Array[StaffCards] = []
## How it plays them (null: `AIProfile.fallback()`).
@export var profile: AIProfile = null
## A boss's phases, in order (empty: one phase).
@export var phases: Array[EnemyPhase] = []

## The most staffs an enemy may hold (the staff buttons).
const MAX_STAFFS: int = 4


## True when it holds at least one staff with a card.
func has_staffs() -> bool:
	for entry: StaffCards in staffs:
		if entry != null and entry.staff != null and not entry.cards.is_empty():
			return true
	return false


## The profile it plays by.
func profile_or_fallback() -> AIProfile:
	return profile if profile != null else AIProfile.fallback()


## What is wrong with the enemy's data, one line each (empty when it is fine): too many staffs,
## a staff entry's problems, a phase without a condition or with too many staffs.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if staffs.size() > MAX_STAFFS:
		found.append("%s has %d staffs; at most %d." % [id, staffs.size(), MAX_STAFFS])
	for at in staffs.size():
		if staffs[at] == null:
			found.append("%s: staff %d is empty." % [id, at])
			continue
		for line: String in staffs[at].problems():
			found.append("%s: staff %d: %s" % [id, at, line])
	for at in phases.size():
		var phase: EnemyPhase = phases[at]
		if phase == null:
			found.append("%s: phase %d is empty." % [id, at])
			continue
		if not phase.has_condition():
			found.append("%s: phase %d has no condition (health_below or after_seconds)." % [id, at])
		if phase.staffs.size() > MAX_STAFFS:
			found.append("%s: phase %d has %d staffs; at most %d." % [id, at, phase.staffs.size(), MAX_STAFFS])
		for k in phase.staffs.size():
			if phase.staffs[k] == null:
				found.append("%s: phase %d staff %d is empty." % [id, at, k])
				continue
			for line: String in phase.staffs[k].problems():
				found.append("%s: phase %d staff %d: %s" % [id, at, k, line])
	return found
