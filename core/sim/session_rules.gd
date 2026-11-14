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
## - `hit_work`: the hit-test work one projectile step may do (`ProjectileManager.work_per_step`;
##   past it the rest of the shots are tested in the next step). Only benchmarks change it.
## - `fire_shots`: the shots one budget's trigger fires may make in one step
##   (`Spells.fire_shots_per_step`; past it a fire waits for the next step). Only benchmarks change it.
## - `bag_staffs`, `bag_cards`, `bag_relics`, `bag_potions`: the capacity of each bag of an
##   inventory, in copies (items I4, docs/milestones/items.md; one rule per `ItemKinds.BAGS`
##   entry, named `bag_` and the bag's name). 0, the default: no limit. An inventory takes its
##   bags' at its start (`bag_capacity`); meta progression raises them later.
##
## A run takes them from the frames service (`Frames.next_run_rules`): the replay's while one
## records or plays (its header), otherwise a copy of this machine's. Online (later), the host's
## rules apply to everyone, capped at what the weakest machine allows.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## The ranges a replay's header is held to (the decoder refuses any other value).
const MAX_SHOT_CAP: int = 1 << 20
const MAX_WORK: int = 0x7fffffff
const MAX_BAG: int = 0xffff
## A bag with no limit, as `bag_capacity` answers (the rule's 0).
const NO_LIMIT: int = -1
## What a bag's rule is named: this and the bag's name.
const BAG_RULE: String = "bag_"
## Every rule, in a replay header's order: its member, its name in a decoder's message, and the
## range a header may hold. A new rule is a member and a row here (and its default); copying,
## comparing, encoding and decoding follow (tests/core/test_session_rules.gd checks each member is
## a row).
const FIELDS: Array = [
	[&"shot_cap", "shot cap", 1, MAX_SHOT_CAP],
	[&"hit_work", "hit work", 1, MAX_WORK],
	[&"fire_shots", "fire shots", 0, MAX_WORK],
	[&"bag_staffs", "staff bag", 0, MAX_BAG],
	[&"bag_cards", "card bag", 0, MAX_BAG],
	[&"bag_relics", "relic bag", 0, MAX_BAG],
	[&"bag_potions", "potion bag", 0, MAX_BAG],
]
## The header's bytes: a 32-bit number for each of FIELDS.
const BYTES: int = 28

var shot_cap: int = ManagerScript.DEFAULT_CAP_DESKTOP
var hit_work: int = ManagerScript.WORK_PER_STEP
var fire_shots: int = SpellLimits.FIRE_SHOTS_PER_STEP
var bag_staffs: int = 0
var bag_cards: int = 0
var bag_relics: int = 0
var bag_potions: int = 0

## Not state: this machine's rules.
const DERIVED: Array[StringName] = [&"_machine"]

## This machine's rules (`machine`), made on first use from its defaults: its settings, as the
## saved settings are this machine's. Nothing but the frames service reads them for a run.
static var _machine: SessionRules = null


## The defaults of this platform: the web's lower shot cap.
static func defaults() -> SessionRules:
	var made := SessionRules.new()
	if OS.has_feature("web"):
		made.shot_cap = ManagerScript.DEFAULT_CAP_WEB
	return made


## This machine's rules, which a run takes when no replay deals any: its defaults, changed by its
## settings (the frames service hears the "Max shots" setting, `projectile_cap_changed`) and by
## benchmarks.
static func machine() -> SessionRules:
	if _machine == null:
		_machine = defaults()
	return _machine


## This machine's rules back to its defaults (each test starts so, tests/support/suite.gd).
static func reset_machine() -> void:
	_machine = defaults()


func copy() -> SessionRules:
	var made := SessionRules.new()
	for field: Array in FIELDS:
		made.set(field[0], get(field[0]))
	return made


func equals(other: SessionRules) -> bool:
	if other == null:
		return false
	for field: Array in FIELDS:
		if get(field[0]) != other.get(field[0]):
			return false
	return true


## The capacity of the bag `bag` in copies, or NO_LIMIT (its rule is 0, or no rule names it).
func bag_capacity(bag: StringName) -> int:
	for field: Array in FIELDS:
		if field[0] == StringName(BAG_RULE + bag):
			var copies: int = get(field[0])
			return copies if copies > 0 else NO_LIMIT
	return NO_LIMIT


## Append the rules to `out` (BYTES bytes, a replay's header): each of FIELDS as 32 bits, in order.
func encode_into(out: PackedByteArray) -> void:
	var at: int = out.size()
	out.resize(at + BYTES)
	for field: Array in FIELDS:
		out.encode_u32(at, get(field[0]) as int)
		at += 4


## Read the rules from `bytes` at `at` (BYTES bytes): "" when every value is in its range, else why
## not (and nothing is changed).
func decode_at(bytes: PackedByteArray, at: int) -> String:
	if at < 0 or at + BYTES > bytes.size():
		return "the rules are cut short"
	var values := PackedInt64Array()
	for field: Array in FIELDS:
		var value: int = bytes.decode_u32(at)
		at += 4
		if value < (field[2] as int) or value > (field[3] as int):
			return "%s %d" % [field[1], value]
		values.append(value)
	for i in FIELDS.size():
		set(FIELDS[i][0], values[i])
	return ""


func _to_string() -> String:
	var parts := PackedStringArray()
	for field: Array in FIELDS:
		parts.append("%s %d" % [field[1], get(field[0]) as int])
	return "SessionRules(%s)" % ", ".join(parts)
