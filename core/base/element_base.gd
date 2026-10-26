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
## The silhouette, animation and trail of the element's shots, so they read without
## colour: 0 the plain sprite, 1 flame, 2 star, 3 zigzag, 4 ring, 5 forked arc (the SHAPE_* constants
## of `core/projectiles`). Fire is 1, frost 2, storm 3, void 4, lightning 5.
@export var shape: int = 0


func kind() -> StringName:
	return &"element"


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"status_duration": Vector2(0.0, 30.0),
		"status_strength": Vector2(0.0, 100.0),
		"damage_scale": Vector2(0.1, 4.0),
		"shape": Vector2(0.0, 5.0),
	})
	return limits
