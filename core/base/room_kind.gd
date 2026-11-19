class_name RoomKind
extends Resource
## A kind of room a run's map places (run generation RG1, docs/milestones/run-generation.md, "The
## model"): what a room of that kind is for the game, how it is filled and what ends it. One file
## per kind, `content/room_kinds/<id>.tres`, found by the registry under `room_kinds`; a room template
## says which kinds it can host (`RoomBase.kinds`) and a run's map rules where each kind may stand
## (`KindRule`). Today: `fight`, `boss`, `start` (a biome's start room) and connected biomes CB11's
## special rooms (`reward`, `shop`, `fountain`, `treasure`, `secret`, `challenge`). A new kind is a
## new file, and a new way of filling or of entering is engine work (one more of `FILLS` or `DOORS`,
## and the behaviour it names), never a change to the generator.

## How a room of the kind is filled: an enemy budget spent on the biome's enemy pool (`RunContent.enemy_pool`).
const FILL_ENEMIES: StringName = &"enemies"
## How a room of the kind is filled: one boss of the biome's boss pool (`RunContent.boss_pool`).
const FILL_BOSS: StringName = &"boss"
## How a room of the kind is filled: with nothing, a safe room (a biome's start room, connected
## biomes CB5; a reward room, a treasure room and a secret room, CB11, whose clear on entering rolls
## each player's reward from the kind's `rewards`).
const FILL_NONE: StringName = &"none"
## How a room of the kind is filled: as `FILL_ENEMIES`, every enemy an elite (a challenge room,
## connected biomes CB11, decision 23: more health, one extra card from the biome's
## `MapRules.elite_cards`, an outline).
const FILL_ELITES: StringName = &"elites"
## How a room of the kind is filled: a shop's shelf (decision 19), one of each item rolled from the
## kind's `shelf` table, each bought (A) by the first wizard at it with its price in their own coins
## (the Rewards area's; coins are an inventory item).
const FILL_SHOP: StringName = &"shop"
## How a room of the kind is filled: a fountain (decision 20), a shared pool of healing that every
## hurt wizard standing in it draws on until it runs dry (the Rewards area's).
const FILL_FOUNTAIN: StringName = &"fountain"
## Every way of filling the game knows.
const FILLS: Array[StringName] = [FILL_ENEMIES, FILL_BOSS, FILL_NONE, FILL_ELITES, FILL_SHOP, FILL_FOUNTAIN]
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
## By a key door (a treasure room, connected biomes CB11, decision 21): shut until a wizard holding
## its key comes to it (the key is dropped on the way to it: in the room its bridge hangs off, as that
## room is cleared); then it opens for everyone.
const DOOR_KEY: StringName = &"key"
## By cracked rock (a secret room, CB11, decision 22): shut until an element rolled for the room (its
## crack's tint) touches the floor at the rock; then it breaks open for everyone.
const DOOR_SECRET: StringName = &"secret"
## Not a kind's door: the name the view is told the portal home by (`gather_door_shown`, CB7).
const DOOR_PORTAL_HOME: StringName = &"portal"
## Every way in the game knows.
const DOORS: Array[StringName] = [DOOR_NONE, DOOR_GATHER, DOOR_GATE, DOOR_KEY, DOOR_SECRET]
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
## The reward table (`RewardTable` id, content/rewards) a room of the kind rolls each player's reward
## from as it is cleared (connected biomes CB11; decision 16, rule 3): a fight's `clear`, the boss's
## `boss`, a reward room's `reward`. Empty: its clear rewards nobody (the start room, a shop).
@export var rewards: StringName = &""
## A shop's shelf (`FILL_SHOP`): the reward table its items are rolled from, each line's `price` what
## it costs. Read for no other fill.
@export var shelf: StringName = &""
## Its rewards are of one type (the owner's ask of 2026-11-19, `RewardType`): decided from its
## `rewards` table as the biome is made, told at its mouths and on the held map, and every wizard's
## roll there made among items of it. A reward room's; every other kind's rewards are of any type.
@export var typed_rewards: bool = false

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
## its seals' runes glow in (empty: the spark's), and that its room's own light is tinted toward
## (`light_tint`; CB12b).
@export var light: StringName = &""
## How far a room of the kind's own light takes on its light's colour (connected biomes CB12b): 0 not
## at all, 1 wholly. Its dark and every light falling in it lean toward the light's base shade by this
## share (the spell light's apply pass, `gameplay/feel/room_tints.gd`); read only while dynamic
## lighting is on.
@export_range(0.0, LIGHT_TINT_MOST, 0.01) var light_tint: float = 0.0
## Its air motes (connected biomes CB12b): what drifts in a room of the kind's air besides its
## template's (`RoomBase.air`), given off over that room alone (`gameplay/feel/kind_air.gd`), as a
## room's air is (its `rate` for every `RoomBase.AIR_AREA` of the room in view). Null: none.
@export var air_motes: MoteSource = null
## Its symbol (connected biomes CB9): what a bridge's mouth into a room of the kind tells of what lies
## behind it, and what the held map shows on the room. A picture of SYMBOL_SIDE rows of SYMBOL_SIDE
## pixels as text, a row a line: `#` its light's lit shade, `+` its base shade, `.` none (drawn with a
## dark edge round its pixels). Empty: nothing is told (a room meant to be found, a secret one).
@export_multiline var symbol: String = ""

## The most `light_tint` may be: a room keeps its own colours under its kind's light.
const LIGHT_TINT_MOST: float = 0.5
## A symbol's side, in pixels.
const SYMBOL_SIDE: int = 7
## A symbol pixel's values (`symbol_pixels`).
const SYMBOL_NONE: int = 0
const SYMBOL_BASE: int = 1
const SYMBOL_LIT: int = 2


## True when a room of the kind is filled with enemies, elites or not (a fight, a challenge room).
func fills_with_enemies() -> bool:
	return fill == FILL_ENEMIES or fill == FILL_ELITES


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
	if fill == FILL_SHOP and shelf == &"":
		found.append("%s: a shop names no shelf table (shelf)." % id)
	if light != &"" and (not Palette.has(light) or Palette.OWNED.has(light)):
		found.append("%s: light '%s' is not a palette material the world may use." % [id, light])
	if light_tint < 0.0 or light_tint > LIGHT_TINT_MOST:
		found.append("%s: light_tint %.2f is outside 0 to %.2f." % [id, light_tint, LIGHT_TINT_MOST])
	for problem in RoomBase.problems_of_air(air_motes):
		found.append("%s's air motes: %s" % [id, problem])
	if music != null:
		found.append_array(music.problems(String(id)))
	if symbol_problem() != "":
		found.append(symbol_problem())
	return found
