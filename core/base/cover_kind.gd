@tool
class_name CoverKind
extends Resource
## A kind of ground cover (ground cover GC2, docs/milestones/ground-cover.md, rules 1 and 3): grass,
## moss, cobwebs. One content folder each (`content/cover/<id>/`: this `.tres`, its tuft frames, its
## `assets.json`, its test), found by the registry's folder `cover`. What it looks like and what it
## does are its data alone: where it grows by itself (`biomes` and the fill numbers, read by
## `CoverLayout.of`), its tufts (`sheet`), and its states, shaped like a prop's (`PropStates`): each a
## look, an effect on a body standing in it, a spread, and its triggers to the next state. A new kind
## of cover is new files; a new kind of trigger is engine work (`CoverTrigger.When`).
##
## Read-only shared data, like a card: the cover area keeps each cell's state as its own (GC5).

## Unique name of the kind, also its folder's; the registry and a room's fields find it by this.
@export var id: StringName = &""
## Its name for people; empty: its id in words.
@export var display_name: String = ""

@export_group("Fill")
## The biomes whose rooms it fills by itself (`RoomBase.biome`: &"crypt", &"hub"). Empty: it grows
## only where a room's field puts it (`CoverField`).
@export var biomes: Array[StringName] = []
## The share of the open floor's cells that start a clump of it (0-1).
@export_range(0.0, 1.0, 0.005) var fill_density: float = 0.05
## The most a clump reaches from its middle, in cells (`CoverLayout.CELL`); each clump's own reach is
## between half of it and all of it.
@export_range(0, 8) var clump_size: int = 2
## How many cells it keeps from a wall when it fills (0: up to the wall, never under it).
@export_range(0, 8) var wall_gap: int = 1
## How many cells it keeps from a door, a spawn or a placement when it fills (0: up to their own cell,
## never on it).
@export_range(0, 8) var keep_gap: int = 1
## True: it is the floor's own cover (the floor's first slice, docs/milestones/floor.md): the layout's
## last pass gives it every cell no other source took that is not under a wall or a hole, a door's, a
## spawn's and a placement's cell too, in every room, filled or not (`CoverLayout._lay_floor`; the
## first such kind in id order). Its rest is bare floor.
@export var fills_floor: bool = false

@export_group("Look")
## How it is drawn: in tufts from its `sheet` (grass, cobwebs), or flat, one joined surface a room
## drawn from its states' `flat_*` looks with no sheet (the floor's water and ice; Feel's
## `cover_flat.gdshader`).
enum Look { TUFTS, FLAT }
@export var look: Look = Look.TUFTS
## Its tuft frames, side by side (Feel's batch, GC3; the editor's preview).
@export var sheet: Texture2D
## The size of one tuft frame in the sheet, in pixels.
@export var frame_size: Vector2i = Vector2i(16, 16)
## How many tufts a covered cell holds (scattered by `CoverLayout.hash4` of the cell, GC3).
@export_range(1, 8) var tufts_per_cell: int = 3
## How far its tufts sway in the wind at a state's full `sway`, in pixels at their tips.
@export var sway: float = 1.0
## How long a cell of it walked through lies flat after the last body left it, then how long it
## takes to spring back, in seconds of Feel's clock (GC4, look only: Feel's `Cover.flatness`).
@export_range(0.0, 30.0, 0.1) var trample_hold: float = 0.6
@export_range(0.1, 30.0, 0.1) var trample_spring: float = 1.5

@export_group("")
## Its states; the first is the one every cell of it starts in (at rest).
@export var states: Array[CoverState] = []


## Its name for people: `display_name`, else its id in words.
func shown_name() -> String:
	return display_name if display_name != "" else String(id).capitalize()


## True when it fills rooms of `biome` by itself (never a room of no biome).
func fills(biome: StringName) -> bool:
	return biome != &"" and biomes.has(biome)


## The index of the state named `state_id`, -1 for none.
func state_at(state_id: StringName) -> int:
	for at in states.size():
		if states[at] != null and states[at].state_id == state_id:
			return at
	return -1


## How many frames its sheet holds side by side (0 with no sheet).
func frame_count() -> int:
	if sheet == null or frame_size.x <= 0:
		return 0
	return int(sheet.get_width()) / frame_size.x


## What is wrong with it, one line each (empty when it is fine), given the elements and statuses the
## game knows (`known`: &"element", &"status", each a PackedStringArray; a kind left out is not
## checked): no id, no state, a state with no name or a name twice, a state drawing a frame its sheet
## lacks, a status with no time between two, a spread with no element or no chance, a trigger's
## problems.
func problems(known: Dictionary = {}) -> PackedStringArray:
	var found := PackedStringArray()
	var owner: String = String(id) if id != &"" else (resource_path if resource_path != "" else "a cover kind")
	if id == &"":
		found.append("%s has no id." % owner)
	if states.is_empty():
		found.append("%s has no state." % owner)
	var ids := PackedStringArray()
	for at in states.size():
		var state: CoverState = states[at]
		if state == null:
			found.append("%s: state %d is empty." % [owner, at])
			continue
		if state.state_id == &"":
			found.append("%s: state %d has no state_id." % [owner, at])
		elif ids.has(String(state.state_id)):
			found.append("%s: two states are named '%s'." % [owner, state.state_id])
		ids.append(String(state.state_id))
	var frames: int = frame_count()
	var statuses: PackedStringArray = known.get(&"status", PackedStringArray())
	var elements: PackedStringArray = known.get(&"element", PackedStringArray())
	for state in states:
		if state == null:
			continue
		var named: String = "%s: %s" % [owner, state.state_id]
		if sheet != null:
			for frame in state.frames:
				var last: int = frame + maxi(state.animation_frames, 1) - 1
				if frame < 0 or last >= frames:
					found.append("%s draws frame %d, which its sheet (%d frames) lacks." % [named, last if frame >= 0 else frame, frames])
			if state.animation_frames < 1 or state.animation_frames > 16:
				found.append("%s plays %d frames a tuft; 1 to 16." % [named, state.animation_frames])
			if state.animation_fps < 1 or state.animation_fps > 127:
				found.append("%s plays %d frames a second; 1 to 127 (Feel's shader)." % [named, state.animation_fps])
			for frame in state.trampled_frames:
				if frame < 0 or frame >= frames:
					found.append("%s draws frame %d trampled, which its sheet (%d frames) lacks." % [named, frame, frames])
		if look == Look.FLAT:
			if state.flat_material != &"" and not Palette.has(state.flat_material):
				found.append("%s is drawn in '%s', which is no material of the palette." % [named, state.flat_material])
			if state.flat_under != &"" and not Palette.has(state.flat_under):
				found.append("%s is drawn over '%s', which is no material of the palette." % [named, state.flat_under])
			if state.flat_spark != &"" and not Palette.has(state.flat_spark):
				found.append("%s sparks in '%s', which is no material of the palette." % [named, state.flat_spark])
			if state.flat_glow != &"" and not Palette.has(state.flat_glow):
				found.append("%s glows in '%s', which is no material of the palette." % [named, state.flat_glow])
			if state.flat_trace != &"" and not Palette.has(state.flat_trace):
				found.append("%s leaves a mark of '%s', which is no material of the palette." % [named, state.flat_trace])
			if state.flat_glow != &"" and state.flat_glow_strength <= 0.0:
				found.append("%s glows in '%s' at no strength (flat_glow_strength)." % [named, state.flat_glow])
		if state.strike_element != &"" and state.strike_damage <= 0.0:
			found.append("%s strikes %s for no damage (strike_damage)." % [named, state.strike_element])
		if state.strike_element != &"" and not elements.is_empty() and not elements.has(String(state.strike_element)):
			found.append("%s strikes with '%s', which is no element the game knows." % [named, state.strike_element])
		if state.status != &"":
			if state.status_every <= 0.0:
				found.append("%s gives %s with no time between two (status_every)." % [named, state.status])
			if not statuses.is_empty() and not statuses.has(String(state.status)):
				found.append("%s gives '%s', which is no status the game knows." % [named, state.status])
		if state.spreads != &"" and state.spread_chance <= 0.0:
			found.append("%s spreads %s with no chance (spread_chance)." % [named, state.spreads])
		if state.spreads == &"" and state.spread_chance > 0.0:
			found.append("%s has a spread chance but spreads no element (spreads)." % named)
		if state.spreads != &"" and not elements.is_empty() and not elements.has(String(state.spreads)):
			found.append("%s spreads '%s', which is no element the game knows." % [named, state.spreads])
		for k in state.triggers.size():
			var row: CoverTrigger = state.triggers[k]
			if row == null:
				found.append("%s: trigger %d is empty." % [named, k])
				continue
			for line: String in row.problems(ids, elements):
				found.append("%s: %s" % [named, line])
	return found
