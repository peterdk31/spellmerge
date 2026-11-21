extends "res://tests/benchmark/biome_frames_runner.gd"
## The frames of a run as it is played, not stressed (the owner's report of 2026-11-21: "I'm
## noticing worse performance in the game now"): the biome frames' crypt biome of seed 11, its
## measures and its `BENCH:` lines (biome_frames_runner.gd), with the load a room walked through
## or fought in has, not the stress crowd and the shot cap: 1 to 4 players, no filler shots.
##
## Each at the desktop's defaults, and the one wizard's also at the web's ("web": the web build's
## mote ring, `MoteCap.DEFAULT_WEB`, and shot cap), where the owner plays:
##  - **1p near**: one wizard standing in a fight room with no foe, the camera at its own zoom (the
##    room, the void round it and the rooms not yet entered on screen);
##  - **1p far**: one wizard fighting a few foes round it, the camera zoomed out to hold them
##    (close foes, #872: down to 0.5, four times the area);
##  - **Np together** (2 to 4): the party in one fight room among a few foes, one picture;
##  - **Np apart dynamic / equal**: each wizard in a fight room of its own with a few foes, the
##    split screen in each mode.
##
## Started by `play_frames.gd` (it needs a window: a GPU, or `xvfb-run`, where llvmpipe draws).

const PLAY_SEED: int = 11
## The foes a room's fight holds (each room the wizards stand in gets its share of these).
const FOES_A_ROOM: int = 12


func _init() -> void:
	super()
	rows = play_rows()
	scenarios = []
	for index in rows.size():
		scenarios.append(index)
	result_word = "PLAY FRAMES"


## Every scenario: one wizard near and far, then 2 to 4 players together and apart in each split.
static func play_rows() -> Array[Dictionary]:
	var cap: int = ProjectileManagerScript.DEFAULT_CAP_DESKTOP
	var out: Array[Dictionary] = []
	out.append(_row("1p near web", 1, 0, true, "together", SplitScreenSetting.DYNAMIC, ProjectileManagerScript.DEFAULT_CAP_WEB, MoteCap.DEFAULT_WEB))
	out.append(_row("1p far web", 1, FOES_A_ROOM, false, "together", SplitScreenSetting.DYNAMIC, ProjectileManagerScript.DEFAULT_CAP_WEB, MoteCap.DEFAULT_WEB))
	out.append(_row("1p near", 1, 0, true, "together", SplitScreenSetting.DYNAMIC, cap))
	out.append(_row("1p far", 1, FOES_A_ROOM, false, "together", SplitScreenSetting.DYNAMIC, cap))
	for players: int in [2, 3, 4]:
		out.append(_row("%dp together" % players, players, FOES_A_ROOM, false, "together", SplitScreenSetting.DYNAMIC, cap))
		out.append(_row("%dp apart dynamic" % players, players, FOES_A_ROOM * players, false, "apart", SplitScreenSetting.DYNAMIC, cap))
		out.append(_row("%dp apart equal" % players, players, FOES_A_ROOM * players, false, "apart", SplitScreenSetting.EQUAL, cap))
	return out


static func _row(label: String, players: int, enemies: int, idle: bool, spread: String, split: int, cap: int, motes: int = MoteCap.DEFAULT_DESKTOP) -> Dictionary:
	return {"label": label, "players": players, "enemies": enemies, "shots": cap, "fill": 0, "idle": idle, "seed": PLAY_SEED, "spread": spread, "split": split, "motes": motes}


## The scenario's mote ring (the "Particles" setting) taken before its run starts.
func _start_play(scenario: Dictionary) -> void:
	if _feel != null and _feel.has_method(&"set_mote_cap"):
		var taken: int = int(_feel.call(&"set_mote_cap", int(scenario.get("motes", MoteCap.DEFAULT_DESKTOP))))
		print("BENCH: play frames %s: mote ring %d rows" % [scenario["label"], taken])
	super(scenario)
