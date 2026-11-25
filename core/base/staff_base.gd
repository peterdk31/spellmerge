class_name StaffBase
extends Resource
## A staff (docs/milestones/M2-staffs.md, "Staffs"): a row of card slots and the numbers of
## how it casts, and its look (living staffs H3, docs/milestones/M2-living-staffs.md): the head a
## player's floating body shows while it is on this staff, where its tip is, and the personality
## (face style and resting brows) that comes with it. Every player holds four, one per button. A staff is a `.tres` in its own
## folder under `content/wizard/staffs/`; the registry finds it under `wizard` by `id`.
## Which cards sit in the slots is the player's, not the staff's: a staff is shared,
## read-only data, like a card. The mana a staff holds now is its holder's (`Caster.mana_of`);
## the staff sets the pool's size and regen.

## Unique name, also the folder name.
@export var id: StringName = &""
## Name shown in the builder.
@export var display_name: String = ""
## Number of card slots.
@export var slots: int = 4
## Carriers one cast wants (the group size before multicast cards add to it).
@export var draw: int = 1
## Seconds every cast of this staff winds up before it leaves, on top of its cards' (an enemy's
## telegraph; docs/milestones/cast-timing.md).
@export var wind_up: float = 0.0
## The cue a cast of this staff plays while it winds up (`CueBase`, content/cues; props W6: a
## barrel's fuse), in place of its carrier card's `wind_cue`; empty: the card's (a tree's slam staff
## winds up with the slam's).
@export var wind_cue: StringName = &""
## Cues of this staff's own moments (boss plan OB15; `CueBase`, content/cues; empty: none), each
## played besides what its cards show, so a boss's Sweep sounds as only it does while the dash card
## stays everyone's: `cast_cue` as a cast of it leaves (`cast_left`: from where the caster holds it,
## along its aim), `move_cue` as each move of it sets off (`carrier_shown` of a carrier that runs its
## caster along, `CarrierTraits.MOVES_ALONG`: a dash, a payload's dash too; its `held` parts last
## until that move ends, `carrier_ended`, as a `stream` part does) and `wall_cue` where a
## move of it is stopped by a wall (`caster_move_finished` walled, boss plan OB12). Feel plays them
## (drawn only).
@export var cast_cue: StringName = &""
@export var move_cue: StringName = &""
@export var wall_cue: StringName = &""
## Seconds the staff waits after the last cast of its cycle, after that cast's wind-down, before
## it starts over (docs/milestones/cast-timing.md).
@export var cooldown: float = 0.5
## Seconds a body that enters play holding this staff waits before its first cast of it (boss plan
## OB14: the Big Sweep is not a boss's first move); 0: ready at once. A boss's phase's staffs start
## ready whatever this is (`Caster.replace_staffs`).
@export var first_wait: float = 0.0
## Degrees a shot may leave off its line, either side, at random (seeded per cast); 0 aims true.
## The carriers of a multicast leave along one aim, so only this sets them apart.
@export var spread: float = 0.0
## The staff's own mana pool, full when its holder enters play, and the mana it gets back a
## second (owner, 2026-11-01: every staff has its own pool; a cast of this staff pays from it
## alone, its sustained cards hold part of it, siphon on its shots refills it).
@export var max_mana: float = 100.0
@export var mana_regen: float = 10.0

## The body while this staff is shown (a player's floating staff): a sheet of 48x48 frames, one
## column per direction (16, clockwise from pointing right), one row per ramp (the player
## colour, 0-3), the grip at (24, 27) of each frame. A sheet drawn at 2x detail (`head@2x.png`,
## ArtDetail) has 96x96 frames, the grip at (48, 54), and is drawn at half its size. None: the body
## keeps its own look.
@export var head: Texture2D = null
## Pixels from the grip to where shots leave, along the aim; 0 keeps the actor's own reach.
@export var tip: float = 0.0
## Pixels the drawn staff runs on behind the grip, against the aim, to its lower end (every head
## sheet's shaft today: 9-10 px). A moment over the whole staff (the swap's cue, S6 item 9) covers
## it from there to the tip.
@export var butt: float = 10.0
## The personality: the face's eye style and resting brows (gameplay/actor/face.gd, Face.Style and
## Face.Mood, in that order).
@export_enum("cheer", "eager", "sleepy", "stern", "stray", "stray_one") var face_style: int = 0
@export_enum("neutral", "raised", "angry", "furious", "worried") var resting_mood: int = 0
## Face sheets of its own (`FaceArt`, in its folder), worn while it is shown, in place of the shared
## eyes' `face_style` row and brows (a head redrawn at 2x detail wears eyes drawn as finely: the
## curl's). None: the shared sheets. Its `face_style` still sets the face's habits.
@export var face: FaceArt = null

## Drawn only (core/sim/README.md, "Steps"): a staff made in the game is walked with the state, and its
## face sheets are no part of it (the state hash and snapshots never read them).
const VIEW: Array[StringName] = [&"face"]


## The name shown: its own, else its id (items I6: a staff lying on the ground).
func shown_name() -> String:
	return display_name if display_name != "" else String(id)


## The allowed range of each number field, as {field name: Vector2(min, max)}, both ends
## included, the same shape as `SpellComponent.ranges()`.
func ranges() -> Dictionary:
	return {
		"slots": Vector2(1, 64),
		"draw": Vector2(1, 4),
		"wind_up": Vector2(0.0, 2.0),
		"cooldown": Vector2(0.0, 30.0),
		"first_wait": Vector2(0.0, 60.0),
		"spread": Vector2(0.0, 45.0),
		"tip": Vector2(0.0, 32.0),
		"max_mana": Vector2(0.0, 1000000.0),
		"mana_regen": Vector2(0.0, 1000000.0),
	}


## Which way each number of `ranges()` is better (items I7: the inventory's arrows between two
## staffs): 1 when more is better, -1 when less is, 0 when neither (a look, not a strength).
## `tests/core/test_staff_base.gd` checks it names every number `ranges()` does.
const BETTER: Dictionary = {
	"slots": 1, "draw": 1, "wind_up": -1, "cooldown": -1, "first_wait": -1, "spread": -1, "tip": 0, "max_mana": 1, "mana_regen": 1,
}


## Whether staff `other`'s `field` (one of `ranges()`) is better than this staff's: 1 better, -1
## worse, 0 the same or neither way (`BETTER`).
func compared(other: StaffBase, field: String) -> int:
	var a: float = float(get(field))
	var b: float = float(other.get(field))
	if is_equal_approx(a, b):
		return 0
	return int(BETTER.get(field, 0)) * (1 if b > a else -1)


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
