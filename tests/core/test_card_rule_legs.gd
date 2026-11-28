extends "res://tests/support/suite.gd"
## Card rules, rule 2 (docs/milestones/M2-rules.md, "The general rules"): nothing takes a card
## away. A card's effect survives a bounce, a chain jump, an echo and a payload firing: the second
## leg still shows it. Hand-written probes, one a behaviour and leg, on the bolt (the owner,
## 2026-11-27: hand-written probes, the bolt only; the rule 1 matrix, tests/core/test_card_rules.gd,
## covers every carrier).
##
## Each probe casts the card's staff and the same staff without the card in the card rules world
## (tests/support/card_rules_world.gd) and reads the hits of the second leg from the trace: a hit
## after the first wall (a bounce), on the second target (a chain jump), the second hit (an echo),
## or the parent's hits after its payload fired. The card shows there (its element on the hit, a
## harder knockback, a target it reaches only by its homing) and not without it, so a
## leg that dropped the card fails, whatever the first leg did.
const World := preload("res://tests/support/card_rules_world.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## Seconds a probe runs: every leg's shot has hit or ended by then.
const SECONDS: float = 3.0
## The spell node of the cast's own carrier, the parent of a payload (the trace's `wizard/n0`).
const PARENT: String = "wizard/n0"
## The wall a bounce meets, this far ahead of the hand.
const WALL_AHEAD: float = 40.0
## The aim of a bounce's cast: down and to the right, so the bolt comes back past the wizard.
const BOUNCE_AIM: Vector2 = Vector2(0.8944272, 0.4472136)
## On the bounced bolt's way back: from where it meets the wall (40, 20) on along (-2, 1).
const BOUNCED: Dictionary = {&"T": Vector2(-60.0, 70.0)}
## The step a late target stands at: after the bolt has met the wall (about step 6), so a card that
## steers (homing) has nothing to turn toward on the first leg.
const LATE_STEP: int = 12

var _registry: Node
var _shelf: World.Shelf
var _staff: StaffBase


func before_each() -> void:
	_registry = own(RegistryScript.new()) as Node
	_registry.call("scan")
	_shelf = own(World.Shelf.new()) as World.Shelf
	_shelf.base = _registry
	_staff = StaffBase.new()
	_staff.id = &"card_rule_legs"
	_staff.slots = 16
	_staff.cooldown = 0.0
	_staff.spread = 0.0


# --- A bounce ---------------------------------------------------------------------------------
# The bolt is cast down and to the right at a wall just ahead and comes back down and to the left
# past the wizard; the target stands on that way back, behind the wizard, so only the leg after
# the bounce can reach it.

func test_an_infusion_survives_a_bounce() -> void:
	var with: Array[Dictionary] = _hits_after_wall([&"bounce", &"fire", &"bolt"], BOUNCED)
	var without: Array[Dictionary] = _hits_after_wall([&"bounce", &"bolt"], BOUNCED)
	check(_hit_on(with, &"T"), "the bounced bolt hits the target behind (%s)" % [with])
	check(_has_element(with, &"T", &"fire"), "and still burns after the bounce: %s" % [with])
	check(not _has_element(without, &"T", &"fire"), "(without fire it does not: %s)" % [without])


func test_heavy_survives_a_bounce() -> void:
	var with: Array[Dictionary] = _hits_after_wall([&"bounce", &"heavy", &"bolt"], BOUNCED)
	var without: Array[Dictionary] = _hits_after_wall([&"bounce", &"bolt"], BOUNCED)
	check(_hit_on(with, &"T") and _hit_on(without, &"T"), "both bounced bolts hit the target behind (%s / %s)" % [with, without])
	check(_knockback(with, &"T") > _knockback(without, &"T"), "heavy still knocks harder after the bounce (%d against %d)" % [_knockback(with, &"T"), _knockback(without, &"T")])


func test_homing_survives_a_bounce() -> void:
	# Off the way back, and standing only once the bolt has bounced: the bounced bolt reaches it
	# only by homing on the second leg.
	var target: Dictionary = {&"T": Vector2(-150.0, 40.0)}
	var with: Array[Dictionary] = _hits_after_wall([&"bounce", &"homing", &"bolt"], {}, target)
	var without: Array[Dictionary] = _hits_after_wall([&"bounce", &"bolt"], {}, target)
	check(not _hit_on(without, &"T"), "a plain bounced bolt misses the target off its line (%s)" % [without])
	check(_hit_on(with, &"T"), "a homing one still homes after the bounce and hits it: %s" % [with])


# --- A chain jump ---------------------------------------------------------------------------------
# The bolt hits A on its line and jumps to B; what B is hit with is the jump's.

func test_an_infusion_survives_a_chain_jump() -> void:
	var with: Array[Dictionary] = _cast([&"chain", &"fire", &"bolt"], _chain_scene())
	var without: Array[Dictionary] = _cast([&"chain", &"bolt"], _chain_scene())
	check(_hit_on(with, &"B"), "the jump hits B (%s)" % [with])
	check(_has_element(with, &"B", &"fire"), "with fire still on it: %s" % [with])
	check(not _has_element(without, &"B", &"fire"), "(without fire, no fire on B: %s)" % [without])


func test_heavy_survives_a_chain_jump() -> void:
	var with: Array[Dictionary] = _cast([&"chain", &"heavy", &"bolt"], _chain_scene())
	var without: Array[Dictionary] = _cast([&"chain", &"bolt"], _chain_scene())
	check(_hit_on(with, &"B") and _hit_on(without, &"B"), "both jumps hit B (%s / %s)" % [with, without])
	check(_knockback(with, &"B") > _knockback(without, &"B"), "heavy still knocks harder on the jump (%d against %d)" % [_knockback(with, &"B"), _knockback(without, &"B")])


# --- An echo ---------------------------------------------------------------------------------------
# The cast fires again a moment later at half damage: its hit is the one on the target with less
# damage than the first (`_echo_of`), so a second hit of the first leg is never taken for it.

func test_an_infusion_survives_an_echo() -> void:
	var echo: Dictionary = _echo_of(_hits_on([&"echo", &"fire", &"bolt"], &"A"))
	var plain: Dictionary = _echo_of(_hits_on([&"echo", &"bolt"], &"A"))
	check(not echo.is_empty() and not plain.is_empty(), "the bolt's echo hits A, at less damage (%s / %s)" % [echo, plain])
	check(not echo.is_empty() and (echo["elements"] as PackedStringArray).has("fire"), "the echo still burns: %s" % [echo])
	check(plain.is_empty() or not (plain["elements"] as PackedStringArray).has("fire"), "(a plain echo does not: %s)" % [plain])


func test_heavy_survives_an_echo() -> void:
	var echo: Dictionary = _echo_of(_hits_on([&"echo", &"heavy", &"bolt"], &"A"))
	var plain: Dictionary = _echo_of(_hits_on([&"echo", &"bolt"], &"A"))
	check(not echo.is_empty() and not plain.is_empty(), "both echoes hit A, at less damage (%s / %s)" % [echo, plain])
	if not echo.is_empty() and not plain.is_empty():
		check(int(echo["knockback"]) > int(plain["knockback"]), "the echo of a heavy bolt still knocks harder (%d against %d)" % [echo["knockback"], plain["knockback"]])


# --- A payload firing -------------------------------------------------------------------------------
# A piercing bolt with `on hit` fires its payload (a plain bolt) at A and flies on; what it does
# after is the parent's, with its own cards. Only the parent's hits are read (its spell node,
# `PARENT`): the payload's own bolt may hit B too.

func test_an_infusion_survives_a_payload_firing() -> void:
	var scene: Dictionary = {&"A": Vector2(60.0, 0.0), &"B": Vector2(130.0, 0.0)}
	var with: Array[Dictionary] = _parent_hits(_cast([&"fire", &"pierce", &"on_hit", &"bolt", &"bolt"], scene))
	var without: Array[Dictionary] = _parent_hits(_cast([&"pierce", &"on_hit", &"bolt", &"bolt"], scene))
	check(_hit_on(with, &"A"), "the parent hits A, where its payload fires (%s)" % [with])
	check(_hit_on(with, &"B"), "the parent flies on and hits B (%s)" % [with])
	check(_has_element(with, &"B", &"fire"), "still burning after its payload fired: %s" % [with])
	check(not _has_element(without, &"B", &"fire"), "(without fire, nothing burns B: %s)" % [without])


func test_homing_survives_a_payload_firing() -> void:
	# A on the line, clear of the wizard; B off the line past it: the parent reaches B only by
	# homing on after its payload fired at A.
	var scene: Dictionary = {&"A": Vector2(40.0, 0.0), &"B": Vector2(150.0, 45.0)}
	var with: Array[Dictionary] = _parent_hits(_cast([&"homing", &"pierce", &"on_hit", &"bolt", &"bolt"], scene))
	var without: Array[Dictionary] = _parent_hits(_cast([&"pierce", &"on_hit", &"bolt", &"bolt"], scene))
	check(_hit_on(with, &"A"), "the parent hits A first (%s)" % [with])
	check(not _hit_on(without, &"B"), "without homing, nothing reaches B off the line (%s)" % [without])
	check(_hit_on(with, &"B"), "with it, the parent still homes on after its payload and hits B: %s" % [with])


# --- The probes' world ------------------------------------------------------------------------------

## A on the bolt's line, B below it, in a chain jump's reach.
static func _chain_scene() -> Dictionary:
	return {&"A": Vector2(60.0, 0.0), &"B": Vector2(60.0, 45.0)}


## Every hit of the wizard's cast of `cards` with `enemies` (label to place) standing, and walls
## where `wall_ahead` asks (a wall across the line that far ahead, cast at it along BOUNCE_AIM; 0
## for none), and `late` standing at LATE_STEP, in order:
## {target, node, step, profile, damage, knockback, elements, after_wall}.
func _cast(cards: Array[StringName], enemies: Dictionary, wall_ahead: float = 0.0, late: Dictionary = {}) -> Array[Dictionary]:
	var world := World.new(root, _shelf, _staff)
	world.add_wizard(cards)
	if wall_ahead > 0.0:
		world.brain.aim = BOUNCE_AIM
	for label: StringName in enemies:
		world.add_enemy(label, enemies[label] as Vector2)
	if wall_ahead > 0.0:
		world.add_wall(Rect2(wall_ahead, -120.0, 8.0, 240.0))
	for label: StringName in late:
		world.at_step[LATE_STEP] = [world.add_enemy.bind(label, late[label] as Vector2)]
	world.press()
	world.run(SECONDS)
	var hits: Array[Dictionary] = []
	var walled: bool = false
	for line: String in world.trace:
		var words: PackedStringArray = line.split(" ")
		if words.size() > 2 and words[1] == "wall" and words[2] == "wizard":
			walled = true
		elif words.size() > 4 and words[1] == "hit" and words[2] == "wizard":
			hits.append(_hit_of(line, words, walled))
	world.free_all()
	return hits


## One `hit` line of the trace (card_rules_world.gd `_listen`: "<step> hit <caster> <node> <target>
## at <x,y> [d.. h.. s.. k.. <kind> <elements> <statuses>]") as a dictionary.
static func _hit_of(line: String, words: PackedStringArray, walled: bool) -> Dictionary:
	# (`split` keeps empty fields: an empty kind or no elements still leave them at their index.
	# A hit with no profile is written `[none]`: `profile` false, which every probe refuses.)
	var fields: PackedStringArray = line.get_slice("[", 1).trim_suffix("]").split(" ")
	var known: bool = fields.size() >= 6 and fields[0].begins_with("d")
	var damage: int = fields[0].trim_prefix("d").to_int() if known else 0
	var knockback: int = fields[3].trim_prefix("k").to_int() if known else 0
	var elements: PackedStringArray = fields[5].split(",", false) if known else PackedStringArray()
	return {"target": StringName(words[4]), "node": words[3], "step": words[0].to_int(), "profile": known, "damage": damage, "knockback": knockback, "elements": elements, "after_wall": walled}


## The hits of the cast's own carrier (`PARENT`), not of a payload it fired.
static func _parent_hits(hits: Array[Dictionary]) -> Array[Dictionary]:
	var own_hits: Array[Dictionary] = []
	for hit: Dictionary in hits:
		if hit["node"] == PARENT:
			own_hits.append(hit)
	return own_hits


## The echo's hit among `hits` on one target: the first after the first hit with less damage than
## it (an echo hits at SpellLimits.ECHO_DAMAGE); empty when there is none.
static func _echo_of(hits: Array[Dictionary]) -> Dictionary:
	if hits.is_empty():
		return {}
	for hit: Dictionary in hits.slice(1):
		if hit["profile"] and int(hit["damage"]) < int(hits[0]["damage"]):
			return hit
	return {}


## The hits after the bolt met the wall just ahead (the leg after the bounce).
func _hits_after_wall(cards: Array[StringName], enemies: Dictionary, late: Dictionary = {}) -> Array[Dictionary]:
	var after: Array[Dictionary] = []
	for hit: Dictionary in _cast(cards, enemies, WALL_AHEAD, late):
		if hit["after_wall"]:
			after.append(hit)
	return after


## The hits on `label`, one target on the bolt's line, in order.
func _hits_on(cards: Array[StringName], label: StringName) -> Array[Dictionary]:
	var on: Array[Dictionary] = []
	for hit: Dictionary in _cast(cards, {label: Vector2(60.0, 0.0)}):
		if hit["target"] == label:
			on.append(hit)
	return on


static func _hit_on(hits: Array[Dictionary], label: StringName) -> bool:
	for hit: Dictionary in hits:
		if hit["target"] == label and hit["profile"]:
			return true
	return false


static func _has_element(hits: Array[Dictionary], label: StringName, element: StringName) -> bool:
	for hit: Dictionary in hits:
		if hit["target"] == label and (hit["elements"] as PackedStringArray).has(String(element)):
			return true
	return false


## The hardest knockback `label` took (-1 when no hit with a profile reached it, so a lost profile
## never reads as a softer hit).
static func _knockback(hits: Array[Dictionary], label: StringName) -> int:
	var most: int = -1
	for hit: Dictionary in hits:
		if hit["target"] == label and hit["profile"]:
			most = maxi(most, int(hit["knockback"]))
	return most
