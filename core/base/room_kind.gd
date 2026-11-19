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

## Unique name of the kind, also its file name; room templates and kind rules name it by this.
@export var id: StringName = &""
## Its name for people (an exit shows what lies behind it, the run's map); empty: its id in words.
@export var display_name: String = ""
## How a room of the kind is filled (one of `FILLS`).
@export var fill: StringName = FILL_ENEMIES
## What ends a room of the kind (one of `ENDS`).
@export var ends: StringName = END_ENEMIES_DOWN


## Its name for people: `display_name`, else its id in words.
func shown_name() -> String:
	return display_name if display_name != "" else String(id).capitalize()


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
	return found
