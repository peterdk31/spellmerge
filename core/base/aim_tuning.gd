class_name AimTuning
extends Resource
## How well the enemies aim, as one tuning of the whole game (enemy aim, the owner 2026-11-19): a
## balance resource, `content/enemies/profiles/aim_tuning.tres`, read by the AI (`AIBrain.aim`). Each
## profile (`AIProfile`) has its own `lead` (0: aim where the target is; 1: where a shot meets it)
## and `accuracy` (its aim error: up to `AIBrain.AIM_ERROR` × (1 − accuracy) radians either side, drawn
## once a cast, seeded); this scales both:
##
## - by **depth** (the room's depth level, `Actor.room_level`: the run's per-depth scaling alone, its
##   scale with one player, connected biomes CB5, set by Difficulty as the enemy stands): at level 1 (a biome's start room, or out of
##   a run) an enemy leads by `start_lead` of its profile's lead and errs `start_error` times its
##   profile's error; at `sharp_level` or deeper, as its profile says; in between, a straight line.
## - for an **elite** (connected biomes CB11): `elite_sharpness` more of the way to sharp.
## - by the **global knobs** `lead_scale` and `error_scale`, on top of everything (1: as above).
##
## Only an enemy's aim is tuned (a brain that `warns()`): a test bot aims as its profile says. An
## enemy's AI possessing a wizard reads the wizard's body (level 1, no elite): its sloppiest. The
## level is by depth only (the owner, 2026-11-19): more players never make an enemy aim better.
## Pure numbers, the same on every machine.

## The lead at level 1, a share of the profile's (1: no change with depth).
@export_range(0.0, 1.0, 0.01) var start_lead: float = 0.3
## The aim error at level 1, times the profile's (1: no change with depth).
@export_range(1.0, 8.0, 0.05) var start_error: float = 3.0
## The room level at which an enemy aims as its profile says (above 1).
@export_range(1.01, 8.0, 0.01) var sharp_level: float = 1.5
## How much nearer sharp an elite is (0-1 of the way).
@export_range(0.0, 1.0, 0.01) var elite_sharpness: float = 0.5
## The global knob on every enemy's lead (0: none leads; the lead is held to 0-1).
@export_range(0.0, 4.0, 0.01) var lead_scale: float = 1.0
## The global knob on every enemy's aim error (0: none errs).
@export_range(0.0, 8.0, 0.01) var error_scale: float = 1.0


## How sharp an enemy aims in a room of `level`, 0 (as at level 1) to 1 (as its profile says),
## `elite` nearer 1.
func sharpness(level: float, elite: bool) -> float:
	var sharp: float = clampf((level - 1.0) / (sharp_level - 1.0), 0.0, 1.0) if is_finite(level) else 0.0
	if elite:
		sharp += (1.0 - sharp) * elite_sharpness
	return sharp


## The lead of a profile leading by `lead`, `sharp` sharp (`sharpness`), 0-1.
func lead_for(lead: float, sharp: float) -> float:
	return clampf(lead * lerpf(start_lead, 1.0, sharp) * lead_scale, 0.0, 1.0)


## What is wrong with the numbers, one line each (`tests/gameplay/ai/test_ai_aim.gd` checks the file).
func problems(what: String) -> PackedStringArray:
	var found := PackedStringArray()
	for row: Array in [[&"start_lead", 0.0, 1.0], [&"start_error", 1.0, 8.0], [&"elite_sharpness", 0.0, 1.0], [&"lead_scale", 0.0, 4.0], [&"error_scale", 0.0, 8.0]]:
		var value: float = float(get(row[0]))
		if not (value >= float(row[1]) and value <= float(row[2])):
			found.append("%s: %s %s; %s to %s." % [what, row[0], value, row[1], row[2]])
	if not (sharp_level > 1.0 and sharp_level <= 8.0):
		found.append("%s: sharp_level %s; above 1, at most 8." % [what, sharp_level])
	return found


## The factor on a profile's aim error, `sharp` sharp (`sharpness`).
func error_for(sharp: float) -> float:
	return lerpf(start_error, 1.0, sharp) * error_scale
