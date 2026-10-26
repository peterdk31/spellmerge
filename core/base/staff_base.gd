class_name StaffBase
extends Resource
## A staff (docs/milestones/M2-staffs.md, "Staffs"): a row of card slots and the numbers of
## how it casts. Every wizard holds four, one per button. A staff is a `.tres` in its own
## folder under `content/wizard/staffs/`; the registry finds it under `wizard` by `id`.
## Which cards sit in the slots is the player's, not the staff's: a staff is shared,
## read-only data, like a card.

## Unique name, also the folder name.
@export var id: StringName = &""
## Name shown in the builder.
@export var display_name: String = ""
## Number of card slots.
@export var slots: int = 4
## Carriers one cast wants (the group size before multicast cards add to it).
@export var draw: int = 1
## Seconds added to the delay of every cast.
@export var cast_delay: float = 0.1
## Seconds added when the staff has read all its cards and starts over.
@export var recharge: float = 0.5
## Degrees of random spread on every shot (0 is a true aim).
@export var spread: float = 0.0


## The allowed range of each number field, as {field name: Vector2(min, max)}, both ends
## included, the same shape as `SpellComponent.ranges()`.
func ranges() -> Dictionary:
	return {
		"slots": Vector2(1, 64),
		"draw": Vector2(1, 4),
		"cast_delay": Vector2(0.0, 2.0),
		"recharge": Vector2(0.0, 5.0),
		"spread": Vector2(0.0, 45.0),
	}


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
