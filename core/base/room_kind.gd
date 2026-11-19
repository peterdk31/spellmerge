class_name RoomKind
extends Resource
## A kind of room a run's map places (run generation RG1, docs/milestones/run-generation.md, "The
## model"): what a room of that kind is for the game, how it is filled and what ends it. One file
## per kind, `content/room_kinds/<id>.tres`, found by the registry under `room_kinds`; a room template
## says which kinds it can host (`RoomBase.kinds`) and a run's map rules where each kind may stand
## (`KindRule`). Today: `fight`, `boss` and `start` (a biome's start room). A new kind (a reward room) is a new file, and a new way of
## filling is engine work (one more of `FILLS`, and the behaviour it names), never a change to the
## generator.

## How a room of the kind is filled: an enemy budget spent on the biome's enemy pool (`RunContent.enemy_pool`).
const FILL_ENEMIES: StringName = &"enemies"
## How a room of the kind is filled: one boss of the biome's boss pool (`RunContent.boss_pool`).
const FILL_BOSS: StringName = &"boss"
## How a room of the kind is filled: with nothing, a safe room (a biome's start room, connected
## biomes CB5; the special rooms' fills come with CB11).
const FILL_NONE: StringName = &"none"
## Every way of filling the game knows.
const FILLS: Array[StringName] = [FILL_ENEMIES, FILL_BOSS, FILL_NONE]
## What ends a room of the kind: every enemy in it down.
const END_ENEMIES_DOWN: StringName = &"enemies_down"
## Every way of ending the game knows.
const ENDS: Array[StringName] = [END_ENEMIES_DOWN]
## How a room of the kind is entered in a biome (connected biomes CB7, decisions 23 and 25): freely
## (none: its mouths open as any room's).
const DOOR_NONE: StringName = &""
## By a gather door (a challenge room, decision 23): its mouths stay shut until every standing wizard
## is at one of them (on its bridge); then it opens and they come in together, onto its player spawns.
const DOOR_GATHER: StringName = &"gather"
## By the gate (the boss's room, decision 25): a gather door that also stays shut while any sealed
## fight holds a wizard, downed or standing; when it opens everyone comes, downed or far away.
const DOOR_GATE: StringName = &"gate"
## Not a kind's door: the name the view is told the portal home by (`gather_door_shown`, CB7).
const DOOR_PORTAL_HOME: StringName = &"portal"
## Every way in the game knows.
const DOORS: Array[StringName] = [DOOR_NONE, DOOR_GATHER, DOOR_GATE]
## The layout metadata a biome's laid room may carry its kind's id under (`room_built`'s layout;
## connected biomes CB12): what the view reads a room's kind by. Without it the view takes the first
## kind its template hosts (`RoomBase.kinds`).
const LAYOUT_META: StringName = &"room_kind"

## Unique name of the kind, also its file name; room templates and kind rules name it by this.
@export var id: StringName = &""
## Its name for people (an exit shows what lies behind it, the run's map); empty: its id in words.
@export var display_name: String = ""
## How a room of the kind is filled (one of `FILLS`).
@export var fill: StringName = FILL_ENEMIES
## What ends a room of the kind (one of `ENDS`).
@export var ends: StringName = END_ENEMIES_DOWN
## How a room of the kind is entered in a biome (one of `DOORS`; connected biomes CB7). A row run
## reads none of it.
@export var door: StringName = DOOR_NONE
## True when a room of the kind, cleared, opens the portal home (connected biomes CB7, decision 7):
## a gather door in it that ends the run, back to the hub, once every standing wizard is in it.
@export var portal_home: bool = false

@export_group("Look and sound")
## What a room of the kind brings to how it looks and sounds (connected biomes CB12, decision 30;
## drawn and heard only, nothing in the game reads it). Each is optional: unset, the room's own.
## Its air: the bed and accents heard while the music follows a room of the kind, in place of the
## room's own (`RoomBase.ambience`).
@export var air: Ambience = null
## Its music: played while the music follows a room of the kind, in place of the room's own
## (`RoomBase.music`; a living boss's still comes first).
@export var music: MusicTrack = null
## Its light: the palette material (docs/STYLE.md) the mouths into a room of the kind shimmer in, and
## its seals' runes glow in (empty: the spark's).
@export var light: StringName = &""
## Its symbol (connected biomes CB9): what a bridge's mouth into a room of the kind tells of what lies
## behind it, and what the held map shows on the room. A picture of SYMBOL_SIDE rows of SYMBOL_SIDE
## pixels as text, a row a line: `#` its light's lit shade, `+` its base shade, `.` none (drawn with a
## dark edge round it). Empty: nothing is told (a room meant to be found, a secret one).
@export_multiline var symbol: String = ""

## A symbol's side, in pixels.
const SYMBOL_SIDE: int = 7
## A symbol pixel's values (`symbol_pixels`).
const SYMBOL_NONE: int = 0
const SYMBOL_BASE: int = 1
const SYMBOL_LIT: int = 2


## Its name for people: `display_name`, else its id in words.
func shown_name() -> String:
	return display_name if display_name != "" else String(id).capitalize()


## The symbol's pixels, row by row (SYMBOL_SIDE × SYMBOL_SIDE of SYMBOL_NONE, SYMBOL_BASE, SYMBOL_LIT),
## or empty when it has none or it is not a whole picture (`problems` says why).
func symbol_pixels() -> PackedByteArray:
	var out := PackedByteArray()
	if symbol_problem() != "" or symbol.strip_edges() == "":
		return out
	for line in symbol.strip_edges().split("\n"):
		for at in SYMBOL_SIDE:
			var pixel: String = line.strip_edges()[at]
			out.append(SYMBOL_LIT if pixel == "#" else (SYMBOL_BASE if pixel == "+" else SYMBOL_NONE))
	return out


## What is wrong with the symbol (empty: nothing, or no symbol): not SYMBOL_SIDE rows of SYMBOL_SIDE
## pixels, or a pixel none of `#`, `+` and `.`.
func symbol_problem() -> String:
	var text: String = symbol.strip_edges()
	if text == "":
		return ""
	var lines: PackedStringArray = text.split("\n")
	if lines.size() != SYMBOL_SIDE:
		return "%s: its symbol has %d rows, not %d." % [id, lines.size(), SYMBOL_SIDE]
	for line in lines:
		var row: String = line.strip_edges()
		if row.length() != SYMBOL_SIDE:
			return "%s: a row of its symbol is %d pixels, not %d." % [id, row.length(), SYMBOL_SIDE]
		for pixel in row:
			if pixel != "#" and pixel != "+" and pixel != ".":
				return "%s: its symbol has '%s', none of #, + and ." % [id, pixel]
	return ""


## What is wrong with the kind, one line each (empty when it is fine): no id, a fill or an end the
## game does not know.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if id == &"":
		found.append("A room kind has no id.")
	if not FILLS.has(fill):
		found.append("%s: fill '%s' is none of %s." % [id, fill, FILLS])
	if not ENDS.has(ends):
		found.append("%s: ends '%s' is none of %s." % [id, ends, ENDS])
	if not DOORS.has(door):
		found.append("%s: door '%s' is none of %s." % [id, door, DOORS])
	if light != &"" and (not Palette.has(light) or Palette.OWNED.has(light)):
		found.append("%s: light '%s' is not a palette material the world may use." % [id, light])
	if music != null:
		found.append_array(music.problems(String(id)))
	if symbol_problem() != "":
		found.append(symbol_problem())
	return found
