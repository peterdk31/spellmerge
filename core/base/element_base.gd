class_name ElementBase
extends SpellComponent
## An element (fire, frost, storm, void): what a hit does besides damage. A spell has at
## most one; without one it deals plain arcane damage. Reactions between elements are
## not listed here but in `content/spells/reactions.tres` (a ReactionTable), so a new
## element needs no change in the others.

## The status a hit puts on its target, for example &"burn". `gameplay/combat` knows the
## statuses; an unknown id is a validator error.
@export var status_id: StringName = &""
## Seconds the status lasts.
@export var status_duration: float = 0.0
## How strong the status is (burn damage per second, slow share, ...), read by combat.
@export var status_strength: float = 0.0
## Factor on the spell's damage.
@export var damage_scale: float = 1.0
## Shot tint, a colour from the palette in docs/STYLE.md.
@export var tint: Color = Color.WHITE
## A hit of this element heals wizards instead of hurting them (mend); enemies take a tenth of
## the damage, at least 1.
@export var heals: bool = false

# --- Look (staffs B6a) ----------------------------------------------------------------

## The particles this card makes its shots give off: a LOOK_* kind of `core/projectiles` (0
## none, 1 embers, 2 frost flecks ... see the LOOK_* constants in
## `core/projectiles/projectile_manager.gd`). A shot gives off the kinds of all its infusions
## and modifiers, mixed at random from its tail; two cards with the same kind add nothing more.
@export var look_layer: int = 0


func kind() -> StringName:
	return &"element"


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"status_duration": Vector2(0.0, 30.0),
		"status_strength": Vector2(0.0, 100.0),
		"damage_scale": Vector2(0.1, 4.0),
		"look_layer": Vector2(0.0, 21.0),
	})
	return limits
