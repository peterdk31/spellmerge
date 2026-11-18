class_name ArrivalStyle
extends Resource
## How an enemy arrives (arrival styles, docs/milestones/arrival-styles.md): the look of a body coming
## into a room as data a biome or an enemy names, as a card names its behaviour. One folder a style,
## `content/arrivals/<id>/`: its `.tres` (its `id` is the folder's name), its art if any, and an
## `assets.json` for that art; the registry finds it under `arrivals`, so a new style is a new folder
## and no list is edited (content/arrivals/README.md is the guide).
##
## A style is the numbers of one arrival: how long it lasts, where its stages hand over, the frames
## each stage of the mark is drawn in, the mark's colours and art, and the cue played as the body
## starts to move. What the body does is its `motion`, one of `MOTIONS`: a name here, and code in
## Feel (`ArriveLook.MOTIONS`, gameplay/feel/arrive_motions/; a test holds the two lists together),
## as a card's behaviour is a row of `ModifierBase.RULES` and the kit that runs it.
##
## The simulation knows only a style's `seconds` (the body can't be hurt and can't act for so long)
## and its id; everything else is drawn (gameplay/feel/arrive_look.gd). Today every body arrives as
## `rise` (content/arrivals/rise/); which style a body gets is AS2 (`pick`, to come).
##
## `DEFAULT` is `rise`'s numbers, kept here for when no style is found (the `rise` folder deleted, an
## id another machine does not have): a test holds them to content/arrivals/rise/rise.tres. A field's
## default is its number in `DEFAULT`, so a style file only writes what it changes.

## The registry's folder of the styles (content/arrivals), which Flow and Feel find them in.
const FOLDER: StringName = &"arrivals"
## The motions a style may name: the kinds of motion Feel draws (`ArriveLook.MOTIONS` has code for
## each). `rise`: out of the floor, through the mark (enemy arrivals EA2's look).
const MOTIONS: Array[StringName] = [&"rise"]
## `rise`'s numbers: every field's default, and the style drawn when none is found.
const DEFAULT: Dictionary[String, Variant] = {
	"id": &"rise",
	"motion": &"rise",
	"seconds": 0.8,
	"mark_end": 0.4,
	"close_from": 0.92,
	"mark_frames": 4,
	"close_frames": 3,
	"colours": &"floor",
	"cue": &"enemy_arrive",
}
## The frame rate a stage's frames are checked at (`problems`): each frame shows for one frame at
## least. A stage is drawn in `MIN_FRAMES` frames at least (docs/STYLE.md, "Smooth").
const CHECK_FPS: float = 60.0
const MIN_FRAMES: int = 3
## The least and most seconds an arrival lasts. The length is how long a body can't be hurt, and
## content/ is open to contributors, so it is bounded above too.
const MIN_SECONDS: float = 0.3
const MAX_SECONDS: float = 2.0
## The `colours` that takes the room's floor's (`RoomBase.floor_colors`), as a floor mark's `floor`.
const FLOOR: StringName = &"floor"

## The style's id, which the registry keys it by; its folder's name.
@export var id: StringName = &""
## The kind of motion (one of `MOTIONS`).
@export var motion: StringName = DEFAULT["motion"]
## How long the arrival lasts, in seconds (`MIN_SECONDS` to `MAX_SECONDS`): the simulation's one
## number of it (the body can't be hurt and can't act for this long).
@export_range(0.3, 2.0, 0.01) var seconds: float = DEFAULT["seconds"]
## Where the mark stage ends and the motion begins, as a share of the arrival.
@export_range(0.0, 1.0, 0.01) var mark_end: float = DEFAULT["mark_end"]
## Where the mark starts to close, as a share of the arrival (after `mark_end`).
@export_range(0.0, 1.0, 0.01) var close_from: float = DEFAULT["close_from"]
## The frames the mark grows in (from a dot to the footprint's width), and closes in.
@export_range(3, 16) var mark_frames: int = DEFAULT["mark_frames"]
@export_range(3, 16) var close_frames: int = DEFAULT["close_frames"]
## The mark's look: none for the ring drawn in its colours (today's look), or an art strip played
## over the mark stage (arrival styles AS4, to come: until then a strip is a problem, so a style
## never names art it does not show).
@export var mark_strip: Texture2D = null
## Where the mark's colours come from: `floor` (the room's floor's, today's ring) or a material of
## the game's palette by name (`Palette`; never a player's nor Blight, docs/STYLE.md). Read by the
## look from AS3 on; every style today is `floor`'s.
@export var colours: StringName = DEFAULT["colours"]
## The cue played as the body starts to move (content/cues): its dust and sound. Empty: none.
@export var cue: StringName = DEFAULT["cue"]
## The biomes it is the arrival of (`RoomBase.biome`, as an enemy names its `biomes`). No two styles
## name one biome (`all_problems`). Empty: no biome's (`rise`, the default, is every other biome's).
@export var biomes: Array[StringName] = []


## A style of `DEFAULT`'s numbers, made now: what is drawn when no style is found.
static func from_default() -> ArrivalStyle:
	var style := ArrivalStyle.new()
	style.id = DEFAULT["id"]
	return style


## The time the mark grows in and the mark closes in, at `CHECK_FPS`, in frames.
func mark_stage_frames() -> float:
	return mark_end * seconds * CHECK_FPS


func close_stage_frames() -> float:
	return (1.0 - close_from) * seconds * CHECK_FPS


## What is wrong with it, one line each (empty when it is fine): an id that is not its folder's name
## (a style read from a file), a motion `MOTIONS` does not have, `seconds` outside `MIN_SECONDS` to
## `MAX_SECONDS`, shares out of order (0 < `mark_end` < `close_from` < 1), a stage shorter than its
## frames at `CHECK_FPS` or drawn in fewer than `MIN_FRAMES`, colours that are neither the floor's
## nor a world material of the palette, a mark strip (not drawn before AS4), a biome named twice, and
## given `known_cue` (a cue id to whether the game has it: the registry's), a cue it does not know.
func problems(known_cue: Callable = Callable()) -> PackedStringArray:
	var found := PackedStringArray()
	var name: String = String(id) if id != &"" else resource_path
	if id == &"":
		found.append("%s: it has no id." % name)
	elif resource_path.begins_with("res://") and resource_path.get_base_dir().get_file() != String(id):
		found.append("%s: its id '%s' is not its folder's name ('%s')." % [resource_path, id, resource_path.get_base_dir().get_file()])
	if not MOTIONS.has(motion):
		found.append("%s: motion '%s' is none of %s." % [name, motion, MOTIONS])
	if not (seconds >= MIN_SECONDS and seconds <= MAX_SECONDS):
		found.append("%s: seconds is %s; %s to %s." % [name, seconds, MIN_SECONDS, MAX_SECONDS])
	if not (mark_end > 0.0 and mark_end < close_from and close_from < 1.0):
		found.append("%s: the shares are out of order (mark_end %s, close_from %s); 0 < mark_end < close_from < 1." % [name, mark_end, close_from])
	else:
		# The motion's stage holds the close's, so a close long enough is a motion long enough.
		_check_stage(found, name, "the mark's", mark_frames, mark_stage_frames(), "mark_frames")
		_check_stage(found, name, "the close's", close_frames, close_stage_frames(), "close_frames")
	if colours != FLOOR:
		for line: String in Palette.world_problems([colours] as Array[StringName], "%s: colours" % name):
			found.append(line + "; or 'floor'.")
	if mark_strip != null:
		found.append("%s: it names a mark strip, which is not drawn yet (arrival styles AS4)." % name)
	for at in biomes.size():
		if biomes.find(biomes[at]) != at:
			found.append("%s: it names the biome '%s' twice." % [name, biomes[at]])
	if known_cue.is_valid() and cue != &"" and not known_cue.call(cue):
		found.append("%s: its cue '%s' is no cue (content/cues)." % [name, cue])
	return found


## A stage of `frames` frames drawn over `has` frames at `CHECK_FPS`: a line in `found` when it has
## fewer than `MIN_FRAMES` frames, or is too short to show each.
static func _check_stage(found: PackedStringArray, name: String, stage: String, frames: int, has: float, field: String) -> void:
	if frames < MIN_FRAMES:
		found.append("%s: %s is %d; %d at least (docs/STYLE.md, \"Smooth\")." % [name, field, frames, MIN_FRAMES])
	elif has < float(frames):
		found.append("%s: %s stage lasts %.1f frames at %d fps, too short for its %d; make the arrival longer or the stage wider." % [name, stage, has, roundi(CHECK_FPS), frames])


## What is wrong with `styles` (every style the game has), one line each: each style's own
## `problems(known_cue)`, and two styles that name one biome (no style may win a biome silently by
## the order they are read in).
static func all_problems(styles: Array[ArrivalStyle], known_cue: Callable = Callable()) -> PackedStringArray:
	var found := PackedStringArray()
	var biome_of: Dictionary[StringName, StringName] = {}
	for style in styles:
		found.append_array(style.problems(known_cue))
		for biome: StringName in style.biomes:
			if biome_of.has(biome) and biome_of[biome] != style.id:
				found.append("%s and %s both name the biome '%s'; one style a biome." % [biome_of[biome], style.id, biome])
			else:
				biome_of[biome] = style.id
	return found
