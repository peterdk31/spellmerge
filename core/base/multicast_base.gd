class_name MulticastBase
extends SpellComponent
## A multicast card (double, triple, scatter, burst): pulls more carriers into the group being
## read, or fires the group more than once (docs/milestones/M2-staffs.md, "Reading a staff").
## Like every card it is a `.tres` in its own folder, here under `content/spells/multicasts/`.

## How the carriers of the group leave the caster.
enum Mode {
	## All together, each along the aim (or its own fan).
	TOGETHER,
	## Each in a random direction, seeded per cast so a replay is the same.
	SCATTER,
	## The whole group fires `repeats` times, `repeat_interval` seconds apart.
	BURST,
}

## Carriers the group wants on top of its own one (double 1, triple 2, scatter 2, burst 0).
@export var extra_draws: int = 1
@export var mode: Mode = Mode.TOGETHER
## BURST only: how often the group fires in all.
@export var repeats: int = 1
## BURST only: seconds between two firings of the group.
@export var repeat_interval: float = 0.0
## Mana this card adds to the cast.
@export var mana_cost: float = 0.0
## Seconds this card adds to the cast's delay.
@export var cooldown: float = 0.0


func kind() -> StringName:
	return &"multicast"


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"extra_draws": Vector2(0, 4),
		"mode": Vector2(0, Mode.size() - 1),
		"repeats": Vector2(1, 8),
		"repeat_interval": Vector2(0.0, 1.0),
		"mana_cost": Vector2(0.0, 100.0),
		"cooldown": Vector2(0.0, 2.0),
	})
	return limits
