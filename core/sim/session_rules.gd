class_name SessionRules
extends RefCounted
## The settings that change the game (online-ready N11, docs/milestones/online-ready.md): what a
## run plays by, the same on every machine that plays it. A run takes them at its start
## (`Tick.begin_run`: `sim.rules`, handed to the areas by `take_rules` before they are renewed), and
## a replay carries them in its header (core/sim/replay.gd), so a run plays the same on a machine
## whose own settings are others. Offline a run takes this machine's (`machine()`): its defaults,
## and the pause menu's "Max shots". Settings that only change the look (the mote and particle
## budgets, effect slots, shake, light) stay this machine's, outside the simulation's state.
##
## - `shot_cap`: the most shots alive at once (`ProjectileManager.set_cap`; at the cap the oldest
##   shot of the richest budget drops). The "Max shots" setting; a change in a run is a command
##   (`shot_cap_requested`), applied at the next tick and recorded with it.
## - `horde_alive`: the most horde enemies alive at once (`Horde.max_alive`), lower on the web.
## - `hit_work`: the hit-test work one projectile step may do (`ProjectileManager.work_per_step`;
##   past it the rest of the shots are tested in the next step). Only benchmarks change it.
## - `fire_shots`: the shots one budget's trigger fires may make in one step
##   (`Spells.fire_shots_per_step`; past it a fire waits for the next step). Only benchmarks change it.
##
## While a replay records or plays (`Frames.record`, `Frames.play`) its rules are dealt to the runs
## it starts (`begin`, as `SimSeed` deals its seeds); otherwise a run takes a copy of this machine's.
## Online (later), the host's rules apply to everyone, capped at what the weakest machine allows.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## The most horde enemies alive at once on the desktop and on the web (horde H1b; a crowd past it
## waits off screen). The web's is lower so its frame holds (gameplay/horde/horde.gd).
const HORDE_ALIVE_DESKTOP: int = 225
const HORDE_ALIVE_WEB: int = 150
## The ranges a replay's header is held to (the decoder refuses any other value).
const MAX_SHOT_CAP: int = 1 << 20
const MAX_HORDE_ALIVE: int = 1 << 16
const MAX_WORK: int = 0x7fffffff
## The header's bytes: four 32-bit numbers.
const BYTES: int = 16

var shot_cap: int = ManagerScript.DEFAULT_CAP_DESKTOP
var horde_alive: int = HORDE_ALIVE_DESKTOP
var hit_work: int = ManagerScript.WORK_PER_STEP
var fire_shots: int = SpellLimits.FIRE_SHOTS_PER_STEP

## Not state: this machine's rules, and the rules a replay deals (`begin`); a test's switch.
const DERIVED: Array[StringName] = [&"_machine", &"_dealt"]

## This machine's rules (`machine`), made on first use from its defaults.
static var _machine: SessionRules = null
## The rules of the replay that records or plays, else null.
static var _dealt: SessionRules = null


## The defaults of this platform: the web's lower shot cap and horde.
static func defaults() -> SessionRules:
	var made := SessionRules.new()
	if OS.has_feature("web"):
		made.shot_cap = ManagerScript.DEFAULT_CAP_WEB
		made.horde_alive = HORDE_ALIVE_WEB
	return made


## This machine's rules, which a run takes when no replay deals any: its defaults, changed by its
## settings (the Tick hears the "Max shots" setting, `projectile_cap_changed`) and by benchmarks.
static func machine() -> SessionRules:
	if _machine == null:
		_machine = defaults()
	return _machine


## This machine's rules back to its defaults (each test starts so, tests/support/suite.gd).
static func reset_machine() -> void:
	_machine = defaults()


## The rules a run starting now takes: a copy of the replay's while one records or plays, else of
## this machine's.
static func for_run() -> SessionRules:
	return (_dealt if _dealt != null else machine()).copy()


## Deal `rules` to every run until `end` (a replay records or plays).
static func begin(rules: SessionRules) -> void:
	_dealt = rules.copy() if rules != null else null


## Runs take this machine's rules again.
static func end() -> void:
	_dealt = null


func copy() -> SessionRules:
	var made := SessionRules.new()
	made.shot_cap = shot_cap
	made.horde_alive = horde_alive
	made.hit_work = hit_work
	made.fire_shots = fire_shots
	return made


func equals(other: SessionRules) -> bool:
	return other != null and shot_cap == other.shot_cap and horde_alive == other.horde_alive and hit_work == other.hit_work and fire_shots == other.fire_shots


## Append the rules to `out` (BYTES bytes, a replay's header).
func encode_into(out: PackedByteArray) -> void:
	var at: int = out.size()
	out.resize(at + BYTES)
	out.encode_u32(at, shot_cap)
	out.encode_u32(at + 4, horde_alive)
	out.encode_u32(at + 8, hit_work)
	out.encode_u32(at + 12, fire_shots)


## Read the rules from `bytes` at `at` (BYTES bytes): "" when every value is in range, else why
## not (and nothing is changed).
func decode_at(bytes: PackedByteArray, at: int) -> String:
	if at < 0 or at + BYTES > bytes.size():
		return "the rules are cut short"
	var cap: int = bytes.decode_u32(at)
	var alive: int = bytes.decode_u32(at + 4)
	var work: int = bytes.decode_u32(at + 8)
	var fires: int = bytes.decode_u32(at + 12)
	if cap < 1 or cap > MAX_SHOT_CAP:
		return "shot cap %d" % cap
	if alive < 1 or alive > MAX_HORDE_ALIVE:
		return "horde cap %d" % alive
	if work < 1 or work > MAX_WORK:
		return "hit work %d" % work
	if fires > MAX_WORK:
		return "fire shots %d" % fires
	shot_cap = cap
	horde_alive = alive
	hit_work = work
	fire_shots = fires
	return ""


func _to_string() -> String:
	return "SessionRules(shots %d, horde %d, hit work %d, fire shots %d)" % [shot_cap, horde_alive, hit_work, fire_shots]
