class_name BossIntro
extends Resource
## A boss's intro (docs/milestones/boss-intro.md, rule 1): the screen-wide overlay before its fight,
## as data. A sub-resource of the boss's `.tres` (`EnemyBase.boss_intro`; null: no intro, the
## entrance banner as before). Flow stops the game on the room's tick for it (`BossIntroHold`), the
## HUD draws it and Feel plays its cues; none of them names a boss, so a second boss with an intro
## needs only this data (rule 9).
##
## The timeline's moments are constants here, so the HUD and Feel time the same moments without
## naming each other (rule 1). They are the HUD's frame (real time), never the game's: only the pages
## and the end are the game's (rule 2).

## The side of one portrait frame, in pixels (drawn at 2×).
const FRAME: int = 96
## The portrait's frames, left to right in its sheet.
const REST: int = 0
const MEAN: int = 1
const EYES: int = 2
const FRAMES: int = 3
## The most lines a boss says (decision 3: the boss alone speaks).
const MAX_LINES: int = 3
## The shared reveal cue (content/cues, boss plan OB15), for a boss with no reveal cue of its own.
const SHARED_REVEAL_CUE: StringName = &"boss_intro"

## Seconds from the open: the bars start sliding in (the room shown a moment first).
const LEAD: float = 0.4
## The bars are in and the slash and the portrait come.
const SLASH_AT: float = 0.7
## The silhouette holds; its eyes light up and the dark cue plays.
const DARK_AT: float = 1.2
## The reveal: the flash, the mean pose, the name and the reveal cue.
const REVEAL_AT: float = 1.9
## Seconds between the name's letters slamming in.
const LETTER_GAP: float = 0.04
## The dialog (or "Fight") shows.
const LINES_AT: float = 2.9
## Characters a second a line types out at.
const TYPE_RATE: float = 30.0
## The reveal's flash, in frames of the HUD.
const FLASH_FRAMES: int = 2
## The reveal's shake, in pixels, and the seconds it settles within.
const SHAKE: float = 4.0
const SHAKE_TIME: float = 0.3

## A sheet of FRAMES frames of FRAME×FRAME in the boss's folder: rest (the silhouette's shape),
## mean (the reveal) and eyes (only the pixels that light up in the dark).
@export var portrait: Texture2D = null
## What the boss says, a page each: at most MAX_LINES of at most `StoryValidator.MAX_SPEECH_CHARS`
## (the story check, `Registry.validate_story`). Empty: one page, "Fight".
@export var lines: Array[String] = []
## A palette ramp of docs/STYLE.md (`Palette`): the slash, the rim, the glint, the name's shadow.
@export var accent: StringName = &""
## The cue played at the silhouette (DARK_AT), the boss's own; empty: none.
@export var dark_cue: StringName = &""
## The cue played at the reveal (REVEAL_AT), the boss's own; empty: the shared SHARED_REVEAL_CUE.
@export var reveal_cue: StringName = &""


## How many pages the intro has: a line each, or one ("Fight") with none.
func pages() -> int:
	return maxi(lines.size(), 1)


## The cue the reveal plays: its own, else the shared one.
func reveal_cue_or_shared() -> StringName:
	return reveal_cue if reveal_cue != &"" else SHARED_REVEAL_CUE


## What is wrong with the intro of `owner`, one line each (empty when it is fine): no portrait or one
## not FRAMES frames of FRAME wide and FRAME high, more than MAX_LINES lines, an accent that is no
## palette ramp, and, given `known_cue` (a cue id to whether the game has it: the registry's), a cue
## it does not know. The lines' words are the story check's (`StoryValidator.check_speech`).
func problems(owner: String, known_cue: Callable = Callable()) -> PackedStringArray:
	var found := PackedStringArray()
	if portrait == null:
		found.append("%s: its intro has no portrait" % owner)
	else:
		var size: Vector2i = Vector2i(portrait.get_width(), portrait.get_height())
		if size != Vector2i(FRAME * FRAMES, FRAME):
			found.append("%s: its intro's portrait is %dx%d; %d frames of %dx%d (%dx%d)" % [owner, size.x, size.y, FRAMES, FRAME, FRAME, FRAME * FRAMES, FRAME])
	if lines.size() > MAX_LINES:
		found.append("%s: its intro has %d lines; at most %d" % [owner, lines.size(), MAX_LINES])
	if not Palette.has(accent):
		found.append("%s: its intro's accent '%s' is no palette ramp (%s)" % [owner, accent, ", ".join(PackedStringArray(Palette.MATERIALS.keys()))])
	if known_cue.is_valid():
		for cue: StringName in [dark_cue, reveal_cue_or_shared()]:
			if cue != &"" and not known_cue.call(cue):
				found.append("%s: its intro's cue '%s' is no cue (content/cues)" % [owner, cue])
	return found
