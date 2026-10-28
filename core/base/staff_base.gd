class_name StaffBase
extends Resource
## A staff (docs/milestones/M2-staffs.md, "Staffs"): a row of card slots and the numbers of
## how it casts, and its look (living staffs H3, docs/milestones/M2-living-staffs.md): the head a
## player's floating body shows while it is on this staff, where its tip is, and the personality
## (face style and resting brows) that comes with it. Every player holds four, one per button. A staff is a `.tres` in its own
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
## Degrees a shot may leave off its line, either side, at random (seeded per cast); 0 aims true.
## The carriers of a multicast leave along one aim, so only this sets them apart.
@export var spread: float = 0.0

## The body while this staff is shown (a player's floating staff): a sheet of 48x48 frames, one
## column per direction (16, clockwise from pointing right), one row per ramp (the player
## colour, 0-3), the grip at (24, 27) of each frame. None: the body keeps its own look.
@export var head: Texture2D = null
## Pixels from the grip to where shots leave, along the aim; 0 keeps the actor's own reach.
@export var tip: float = 0.0
## The personality: the face's eye style and resting brows (gameplay/actor/face.gd, Face.Style and
## Face.Mood, in that order).
@export_enum("cheer", "eager", "sleepy", "stern", "stray", "stray_one") var face_style: int = 0
@export_enum("neutral", "raised", "angry", "furious", "worried") var resting_mood: int = 0


## The allowed range of each number field, as {field name: Vector2(min, max)}, both ends
## included, the same shape as `SpellComponent.ranges()`.
func ranges() -> Dictionary:
	return {
		"slots": Vector2(1, 64),
		"draw": Vector2(1, 4),
		"cast_delay": Vector2(0.0, 2.0),
		"recharge": Vector2(0.0, 5.0),
		"spread": Vector2(0.0, 45.0),
		"tip": Vector2(0.0, 32.0),
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
