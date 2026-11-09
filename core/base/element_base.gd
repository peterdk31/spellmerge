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

## The particles this card makes its shots give off, by name (`LookNames`: `embers`, `flecks`,
## `curl` ...; empty for none). A shot gives off the looks of all its infusions and modifiers,
## mixed at random from its tail; two cards with the same look add nothing more.
@export var look_id: StringName = &""
## `look_id` as its number, the LOOK_* kind of `core/projectiles` the engine reads (0 for none).
var look_layer: int:
	get:
		return LookNames.layer_of(look_id)
	set(value):
		look_id = LookNames.name_of(value)

## The places in `status_look()`.
const STATUS_LOOK_STATUS: int = 0
const STATUS_LOOK_TINT: int = 1
const STATUS_LOOK_LAYER: int = 2
const STATUS_LOOK_CARD: int = 3


func kind() -> StringName:
	return &"element"


## How a status it puts on is shown, for looks (`gameplay/feel`, which reads no spell field; spell
## spectacle 2, S6 item 11): [status_id, tint, look_layer, id] (`STATUS_LOOK_*`). A new Array each
## call.
func status_look() -> Array:
	return [status_id, tint, look_layer, id]


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"status_duration": Vector2(0.0, 30.0),
		"status_strength": Vector2(0.0, 100.0),
		"damage_scale": Vector2(0.1, 4.0),
	})
	return limits


## The range problems, and a look name that is no look.
func range_problems() -> PackedStringArray:
	var problems: PackedStringArray = super()
	if look_id != &"" and LookNames.layer_of(look_id) == 0:
		problems.append("look_id: %s is not a look (%s)" % [look_id, ", ".join(LookNames.NAMES.slice(1))])
	return problems
