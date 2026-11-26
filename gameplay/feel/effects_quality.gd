extends RefCounted
## How much the screen's effects cost (the owner's one pass, 2026-11-22; docs/milestones/connected-biomes.md,
## "One pass"): one row of numbers a level, so the quality setting ("Effects")
## turns every effect down by choosing a row, and nothing else knows how ("Effects", `EffectsSetting` in
## core/settings: Low, Medium and High a row each, Auto a row chosen by the frames' times,
## `effects_auto.gd`; the owner's choice of 2026-11-21). The spectacle reads it
## (`Spectacle.set_effects_quality`) and hands each number to the effect it names; whether an effect
## is drawn at all stays its own setting ("Dynamic lighting", "Shadows", "Fog", "Ambient particles").
## View only.

enum Level { LOW, MEDIUM, HIGH }

## The level the game draws at unless told (the look the owner chose).
const DEFAULT_LEVEL: Level = Level.HIGH
## The rows: the light's cell (world px, one of LightGrid.CELLS) and whether it is smoothed between the
## cells' middles; the mist's layers of billows (1 to 3); the share of the air's motes given off (the
## rooms', the kinds' and the void's); the share of the floor's motes (a flat cover kind's: sparks
## over live water, steam's wisps) and whether its ripples, twinkles and wisps play (the floor's look,
## docs/milestones/floor-look.md: none of either at Low).
const ROWS: Dictionary[Level, Dictionary] = {
	Level.LOW: {&"light_cell": 16.0, &"light_smooth": true, &"mist_billows": 1, &"air_share": 0.5, &"floor_motes": 0.0, &"floor_shimmer": false},
	Level.MEDIUM: {&"light_cell": 8.0, &"light_smooth": true, &"mist_billows": 2, &"air_share": 0.75, &"floor_motes": 0.5, &"floor_shimmer": true},
	Level.HIGH: {&"light_cell": 8.0, &"light_smooth": true, &"mist_billows": 3, &"air_share": 1.0, &"floor_motes": 1.0, &"floor_shimmer": true},
}

## The level and its row's numbers (`_init`). Read only.
var level: Level = DEFAULT_LEVEL
var light_cell: float = 0.0
var light_smooth: bool = false
var mist_billows: int = 0
var air_share: float = 0.0
var floor_motes: float = 0.0
var floor_shimmer: bool = false


## The level a step cheaper than `at` (LOW stays LOW), and a step dearer (HIGH stays HIGH).
static func lower(at: Level) -> Level:
	return maxi(int(at) - 1, int(Level.LOW)) as Level


static func higher(at: Level) -> Level:
	return mini(int(at) + 1, int(Level.HIGH)) as Level


## The row the "Effects" setting's fixed `mode` names (`EffectsSetting`: LOW, MEDIUM, HIGH; AUTO's row is
## the watcher's, `effects_auto.gd`, and HIGH until it has watched).
static func of_setting(mode: int) -> Level:
	match mode:
		EffectsSetting.LOW:
			return Level.LOW
		EffectsSetting.MEDIUM:
			return Level.MEDIUM
	return Level.HIGH


## The "Effects" setting's word for `at` (`EffectsSetting.LOW`, MEDIUM, HIGH): what the menu shows
## Auto drawing.
static func setting_of(at: Level) -> int:
	match at:
		Level.LOW:
			return EffectsSetting.LOW
		Level.MEDIUM:
			return EffectsSetting.MEDIUM
	return EffectsSetting.HIGH


func _init(at: Level = DEFAULT_LEVEL) -> void:
	level = at if ROWS.has(at) else DEFAULT_LEVEL
	var row: Dictionary = ROWS[level]
	light_cell = row[&"light_cell"]
	light_smooth = row[&"light_smooth"]
	mist_billows = row[&"mist_billows"]
	air_share = row[&"air_share"]
	floor_motes = row[&"floor_motes"]
	floor_shimmer = row[&"floor_shimmer"]
