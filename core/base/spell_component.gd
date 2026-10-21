class_name SpellComponent
extends Resource
## One spell component (M2): a form, an element, a modifier or a trigger. A spell is
## built from them as form -> element -> modifiers -> trigger, and the trigger holds
## one more spell (docs/milestones/M2-spell-system.md). A component is a `.tres` on
## one of the four subclasses, in its own folder under `content/spells/<kind>s/`.
##
## Components are shared, read-only data: the spell runtime (`core/spells`, M2 part 5)
## compiles them into per-player spells. Only `content/spells/`, `core/base/` and
## `core/spells/` read these fields; players and bots never do.
##
## Each subclass lists the allowed range of its numbers in `ranges()`, and
## `range_problems()` reports what is outside them, so the content validator (M2 part 9)
## and a contributor's agent get the same answer.

## Unique name of the component across all four kinds, also its folder name; the
## registry finds it by this under `spells`.
@export var id: StringName = &""
## True for content shown in the free web demo.
@export var demo: bool = false
## Name shown in the builder, for example "Frost". Original names only.
@export var display_name: String = ""
## What the component costs from the spell's complexity budget (1-4).
@export var complexity: int = 1
## The 16x16 icon shown in the builder.
@export var icon: Texture2D

## The smallest and largest allowed complexity of one component.
const COMPLEXITY_MIN: int = 1
const COMPLEXITY_MAX: int = 4


## The kind of component: &"form", &"element", &"modifier" or &"trigger". The builder
## uses it to filter the bag by slot.
func kind() -> StringName:
	return &""


## The allowed range of each number field, as {field name: Vector2(min, max)}, both ends
## included. Subclasses add their own fields to the base ones.
func ranges() -> Dictionary:
	return {"complexity": Vector2(COMPLEXITY_MIN, COMPLEXITY_MAX)}


## One line per field whose value is outside ranges(), as "field: value is outside
## [min, max]". Empty when every number is in range.
func range_problems() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var limits: Dictionary = ranges()
	for field: String in limits:
		var bounds: Vector2 = limits[field]
		var value: float = float(get(field))
		if value < bounds.x or value > bounds.y:
			problems.append("%s: %s is outside [%s, %s]" % [field, str(get(field)), str(bounds.x), str(bounds.y)])
	return problems
