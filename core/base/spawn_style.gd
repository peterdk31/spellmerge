class_name SpawnStyle
extends Resource
## How an enemy spawns in (spawn styles, docs/milestones/spawn-styles.md): the look of a body coming
## into a room as data a biome or an enemy names, as a card names its behaviour. One folder a style,
## `content/spawn_styles/<id>/`: its `.tres` (its `id` is the folder's name), its art if any, and an
## `assets.json` for that art; the registry finds it under `spawn_styles`, so a new style is a new folder
## and no list is edited (content/spawn_styles/README.md is the guide).
##
## A style is the numbers of one spawn: how long it lasts, where its stages hand over, the frames
## each stage of the mark is drawn in, the mark's colours and art, and the cue played as the body
## starts to move. What the body does is its `motion`, one of `MOTIONS`: a name here, and code in
## Feel (`SpawnLook.MOTIONS`, gameplay/feel/spawn_motions/; a test holds the two lists together),
## as a card's behaviour is a row of `ModifierBase.RULES` and the kit that runs it.
##
## The simulation knows only a style's `seconds` (the body can't be hurt and can't act for so long)
## and its id; everything else is drawn (gameplay/feel/spawn_look.gd). Which style a body gets is
## `pick` (spawn styles AS2): the enemy's own, else its room's biome's, else `rise`. Flow picks it as it
## stands the body and hands the actor its seconds and id (`Actor.spawn`).
##
## `DEFAULT` is `rise`'s numbers, kept here for when no style is found (the `rise` folder deleted, an
## id another machine does not have): a test holds them to content/spawn_styles/rise/rise.tres. A field's
## default is its number in `DEFAULT`, so a style file only writes what it changes.

const RegistryScript := preload("res://core/registry/registry.gd")

## The registry's folder of the styles (content/spawn_styles), which Flow and Feel find them in.
const FOLDER: StringName = &"spawn_styles"
## The motions a style may name: the kinds of motion Feel draws (`SpawnLook.MOTIONS` has code for
## each). `rise`: out of the floor, through the mark (enemy spawning EA2's look); `materialize`: built
## up out of light, row by row behind a scan line (spawn styles AS3).
const MOTIONS: Array[StringName] = [&"rise", &"materialize"]
## The least frames each motion's stage (`mark_end` to the end) must last at `CHECK_FPS` to draw all
## its stages in `MIN_FRAMES` frames each (`problems`): the motion's own (`least_frames()` of its code in
## gameplay/feel/spawn_motions/; a test holds the two together).
const MOTION_FRAMES: Dictionary[StringName, int] = {&"rise": 3, &"materialize": 17}
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
	"cue": &"enemy_spawn",
}
## The frame rate a stage's frames are checked at (`problems`): each frame shows for one frame at
## least. A stage is drawn in `MIN_FRAMES` frames at least (docs/STYLE.md, "Smooth").
const CHECK_FPS: float = 60.0
const MIN_FRAMES: int = 3
## The least and most seconds a spawn lasts. The length is how long a body can't be hurt, and
## content/ is open to contributors, so it is bounded above too.
const MIN_SECONDS: float = 0.3
const MAX_SECONDS: float = 2.0
## The `colours` that takes the room's floor's (`RoomBase.floor_colors`), as a floor mark's `floor`.
const FLOOR: StringName = &"floor"

## The style's id, which the registry keys it by; its folder's name.
@export var id: StringName = &""
## The kind of motion (one of `MOTIONS`).
@export var motion: StringName = DEFAULT["motion"]
## How long the spawn lasts, in seconds (`MIN_SECONDS` to `MAX_SECONDS`): the simulation's one
## number of it (the body can't be hurt and can't act for this long).
@export_range(0.3, 2.0, 0.01) var seconds: float = DEFAULT["seconds"]
## Where the mark stage ends and the motion begins, as a share of the spawn.
@export_range(0.0, 1.0, 0.01) var mark_end: float = DEFAULT["mark_end"]
## Where the mark starts to close, as a share of the spawn (after `mark_end`).
@export_range(0.0, 1.0, 0.01) var close_from: float = DEFAULT["close_from"]
## The frames the mark grows in (from a dot to the footprint's width), and closes in.
@export_range(3, 16) var mark_frames: int = DEFAULT["mark_frames"]
@export_range(3, 16) var close_frames: int = DEFAULT["close_frames"]
## The mark's look: none for the ring drawn in its colours (today's look), or an art strip played
## over the mark stage (spawn styles AS4, to come: until then a strip is a problem, so a style
## never names art it does not show).
@export var mark_strip: Texture2D = null
## Where the mark's colours come from: `floor` (the room's floor's, today's ring) or a material of
## the game's palette by name (`Palette`; never a player's nor Blight, docs/STYLE.md): the mark's
## shades (its rim the light one) and `materialize`'s scan line (its light shade).
@export var colours: StringName = DEFAULT["colours"]
## The cue played as the body starts to move (content/cues): its dust and sound. Empty: none.
@export var cue: StringName = DEFAULT["cue"]
## The biomes it is the spawn of (`RoomBase.biome`, as an enemy names its `biomes`). No two styles
## name one biome (`all_problems`). Empty: no biome's (`rise`, the default, is every other biome's).
@export var biomes: Array[StringName] = []


## The style an enemy of `enemy` spawns in in, in a room of biome `biome`, from `registry`'s styles
## (spawn styles AS2): the enemy's own (`EnemyBase.spawn_style`), else the first style by id that
## names `biome` (`all_problems` makes it the only one), else `rise`, else (no `rise` found: its folder
## deleted, or no registry) a style of `DEFAULT`'s numbers. An id the registry does not have (the
## enemy's own, or a biome's style named wrong) is passed over, never an error: the content's tests
## name it. Pure: it reads the registry and the data, and never names Feel, so Flow picking a style
## does not tie Flow to the look.
static func pick(registry: RegistryScript, enemy: EnemyBase, biome: StringName) -> SpawnStyle:
	if registry != null:
		if enemy != null and enemy.spawn_style != &"":
			var own := registry.get_resource(FOLDER, enemy.spawn_style) as SpawnStyle
			if own != null:
				return own
		if biome != &"":
			for item: Resource in registry.get_all(FOLDER):
				var style := item as SpawnStyle
				if style != null and style.biomes.has(biome):
					return style
		var rise := registry.get_resource(FOLDER, DEFAULT["id"]) as SpawnStyle
		if rise != null:
			return rise
	return from_default()


## A style of `DEFAULT`'s numbers, made now: what is drawn when no style is found.
static func from_default() -> SpawnStyle:
	var style := SpawnStyle.new()
	style.id = DEFAULT["id"]
	return style


## The time the mark grows in and the mark closes in, at `CHECK_FPS`, in frames.
func mark_stage_frames() -> float:
	return mark_end * seconds * CHECK_FPS


func close_stage_frames() -> float:
	return (1.0 - close_from) * seconds * CHECK_FPS


## The time the motion is drawn in (from `mark_end` to the end), at `CHECK_FPS`, in frames.
func motion_stage_frames() -> float:
	return (1.0 - mark_end) * seconds * CHECK_FPS


## What is wrong with it, one line each (empty when it is fine): an id that is not its folder's name
## (a style read from a file), a motion `MOTIONS` does not have, `seconds` outside `MIN_SECONDS` to
## `MAX_SECONDS`, shares out of order (0 < `mark_end` < `close_from` < 1), a stage shorter than its
## frames at `CHECK_FPS` or drawn in fewer than `MIN_FRAMES`, a motion's stage shorter than its
## motion needs (`MOTION_FRAMES`), colours that are neither the floor's
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
		_check_stage(found, name, "the mark's", mark_frames, mark_stage_frames(), "mark_frames")
		_check_stage(found, name, "the close's", close_frames, close_stage_frames(), "close_frames")
		var least: int = MOTION_FRAMES.get(motion, 0)
		if MOTIONS.has(motion) and motion_stage_frames() < float(least):
			found.append("%s: the motion's stage lasts %.1f frames at %d fps; %s needs %d to draw its stages; make the spawn longer or mark_end earlier." % [name, motion_stage_frames(), roundi(CHECK_FPS), motion, least])
	if colours != FLOOR:
		for line: String in Palette.world_problems([colours] as Array[StringName], "%s: colours" % name):
			found.append(line + "; or 'floor'.")
	if mark_strip != null:
		found.append("%s: it names a mark strip, which is not drawn yet (spawn styles AS4)." % name)
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
		found.append("%s: %s stage lasts %.1f frames at %d fps, too short for its %d; make the spawn longer or the stage wider." % [name, stage, has, roundi(CHECK_FPS), frames])


## What is wrong with `styles` (every style the game has), one line each: each style's own
## `problems(known_cue)`, and two styles that name one biome (no style may win a biome silently by
## the order they are read in).
static func all_problems(styles: Array[SpawnStyle], known_cue: Callable = Callable()) -> PackedStringArray:
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
