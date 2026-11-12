extends "res://tests/support/suite.gd"
## The card rules check (rules R3, docs/milestones/M2-rules.md, rule 1 "works or wasted"): every
## card in content/spells/ on every carrier either changes what happens in the game or is listed
## by the compiler as wasted. Nothing does nothing silently.
##
## It keeps no list of cards or carriers (owner, 2026-10-29: "It should just auto discover new
## cards and carriers"). It asks the registry for every card: the forms are the carriers, and every
## modifier, trigger, infusion and multicast card is tried on each of them. A new card or carrier
## is checked the day it lands.
##
## A cell: compile the card on the carrier (`[card, carrier]`; a trigger gets a plain payload
## after its carrier). When
## the compiler lists the card as wasted: W. Otherwise the cast runs
## in a small world (tests/support/card_rules_world.gd: the real Spells, projectile manager, Combat,
## Entities and actor kit) and its trace (every hit with its whole profile, damage, statuses, moves,
## area hits, spawns, blocks, the shots' paths and sizes, the beams and swings, the actors' places
## and health) is compared with the same cast without the card. A different trace: ✓. The same: ✗,
## "`card` on `carrier` does nothing and is not listed as wasted", and the test fails.
##
## "Without the card": a trigger, an infusion or a multicast is left out. A modifier with a
## behaviour is swapped for a copy of itself with no behaviour, so its numbers (damage, speed,
## size) cancel out and the cell says whether the *behaviour* does something there (heavy's speed
## on a dash does not count as heavy working on a dash). A modifier of numbers only is left out.
##
## The scene: the wizard's hand at (0, 0), aiming along +x; a teammate behind it. What else stands
## there is chosen by what the card does (its `ModifierBase.Behaviour` or `TriggerBase.Event`, read
## from the enums), never by the card's id or the carrier's: homing gets a target off the line,
## bounce a wall, ghost a wall with a target behind it, shield and deflect an enemy that shoots at
## the wizard, on kill a target that dies, on hurt the wizard hurt or an enemy that shoots (a body of the carrier's own is hurt when it is: a decoy), orbit the open with what circles written down, on reaction a target with a
## status the carrier's infusion reacts with (see `behaviour_scenes` and `event_scenes`). How far
## along the line things stand is the carrier's reach, chosen by its `FormBase.carrier` (`reach`). A
## card whose behaviour or event has no scene yet fails with "no probe for ...", and a carrier
## that has none with "no reach for ...", so a new kind of card or carrier brings its
## probe in the same PR.
##
## The other way round (R4b): a W cell is also played with the card forced on, and fails with
## "`card` on `carrier` is listed as wasted but changes the cast" when that trace differs
## (slam was once wrongly listed, found by hand). The seam is one test-only switch,
## `StaffCompiler.keep_wasted`: with it the compiler keeps every card its waste table would drop
## (a behaviour, numbers, an infusion, a trigger that "never fires" and its payload), and the
## runtime, which does not read the table, alone decides what the card does. Both casts are
## compiled with it on. A wasted card's costs are no effect: a modifier of numbers only is compared
## with a copy of it that keeps only its costs (`_costs_of`: mana, a slower cast, less damage), a
## behaviour modifier with its plain copy as above.
##
## The Pulse card (docs/CARRIERS.md, "Pulse: a strike round what casts it"; props W9a) is a column of
## its own, as every form, and its carrier in a payload is three more, `on it`, `on its body` and
## `right there`, each played the way a staff reaches it. A modifier or an infusion on a Pulse is
## played with a card that changes nothing (`LAND`) in both casts, so the Pulse strikes with or without
## it (a bare Pulse strikes nothing). On it: the Pulse in the payload of `on hit` on a piercing shot that
## hits the target (`_bearer_prefix`): it pierces, so the shot that fired the payload flies on and
## the Pulse is round it. On its body: the payload of `on cast` on a shot (`_body_prefix`), which the
## wizard's body casts, so the Pulse is round that body (as a decoy's or a dashing wizard's payload's
## is; owner, 2026-11-06). Right there: the same as on it with a shot that does not pierce
## (`_point_prefix`), spent by its hit, so the payload is a point's. Both are cast at once in the
## enemy shooter's scene: its shots end on the target, so none comes near the wizard. Only modifiers
## and infusions are played on the three payload columns, so the triggers' and multicasts' cells
## there are `–`.
##
## It prints the matrix of every kind (✓ works, W wasted, ✗ silent no-op) so a PR shows coverage.
## Rule 2 (a card's effect survives a bounce, a jump, an echo, a payload) is not checked here yet.
##
## godot --headless --path . --script res://tests/core/test_card_rules.gd
##
## The runner plays it in six processes side by side (tests/support/suite.gd, "shards"):
# unit-test-shards: 6

const World := preload("res://tests/support/card_rules_world.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const WORKS: String = "✓"
const WASTED: String = "W"
const SILENT: String = "✗"
const NO_PROBE: String = "?"
## A card that is not played on a payload's Pulse column (a trigger, a multicast).
const NOT_THERE: String = "–"
## The card both casts of a modifier or an infusion on a Pulse have: a modifier with no behaviour and
## no numbers, so the Pulse strikes in both and it changes nothing else (put on the shelf).
const LAND: StringName = &"~land"

## The longest a cast runs (a familiar lives 8 s).
const LONGEST: float = 9.5
## Seconds a cast runs past its carrier's life.
const AFTER_LIFE: float = 1.5
## Where the teammate stands (behind the wizard, off every line).
const ALLY_AT: Vector2 = Vector2(-40.0, 40.0)
## How far behind the wizard the target behind it stands.
const BACK_AT: float = 30.0
## How far off the line the side target stands, and the second target off the first.
const SIDE: float = 30.0
const SECOND: float = 45.0
## How far from the target on the line the rest of a crowd stands.
const CROWD: float = 16.0
## Where the teammate stands that sends a shot through a carrier that opens a way through (a
## portal), the point on the aim line it aims at (a portal's mouth, a step ahead) and the step it
## casts at. It stands ahead and to the side, so its shot comes down into the mouth clear of the
## wizard's body, and out of the exit clear of the target off the line, unless the portal's cards
## turn it.
const COURIER_AT: Vector2 = Vector2(60.0, -60.0)
const COURIER_AIM: float = 24.0
const COURIER_STEP: int = 0
## How far behind the target on the line the enemy shooter stands.
const SHOOTER_BEHIND: float = 70.0
## The wizard casts when an enemy shot is this much further than its carrier's reach.
const SHOT_NEAR: float = 10.0
## The steps after which the wizard is hurt in the on-hurt scene.
const HURT_STEPS: Array[int] = [2, 20, 60]
## Staff spread in degrees, so a card that changes aim (sniper) has something to change.
const SPREAD: float = 4.0
## Print the first differing line of every ✓ cell (for checking a probe by hand).
const EXPLAIN: bool = false
## Only this carrier (for checking a probe by hand); empty for all.
const ONLY_FORM: String = ""
## How many tests the modifiers' matrix is split into (see `_modifier_part`).
const MODIFIER_PARTS: int = 6

var _registry: Node
var _shelf: World.Shelf
var _compiler: SpellsScript
var _staff: StaffBase
var _forms: Array[FormBase] = []
var _modifiers: Array[ModifierBase] = []
var _triggers: Array[TriggerBase] = []
var _elements: Array[ElementBase] = []
var _multicasts: Array[MulticastBase] = []
## The plain payload a trigger fires: the straight carrier with the most
## shots, so a fire shows wherever it happens.
var _payload: FormBase = null
## What the enemy shooter and the relay donor cast: the straight carrier of one shot that reaches
## furthest.
var _shot: FormBase = null
## What the `on it` column's payload is fired from in the enemy shooter's scene: the straight
## carrier of one shot that lives longest, so it flies on through the shooter's stream long enough
## to meet its shots (`_shot`, small and fast, passes them between two steps).
var _lasting: FormBase = null
## The Pulse card (the form whose carrier is `Carriers.PULSE`), played after a card on a Pulse column.
var _pulse: FormBase = null
## The matrix's columns: every form card, then a stand-in form for each Pulse in a payload (its
## `carrier` names it; not a card, never in a staff: the Pulse card is played there).
var _columns: Array[FormBase] = []
## What comes before the cards of the `on it` column (`on hit`, a pierce card, `_shot`; `_lasting`
## in the shooter's scene: `_bearer_shooter_prefix`) and of the `right there` column (`on hit`,
## `_shot`).
var _bearer_prefix: Array[StringName] = []
var _bearer_shooter_prefix: Array[StringName] = []
var _point_prefix: Array[StringName] = []
## What comes before the cards of the `on its body` column: `on cast`, `_shot`.
var _body_prefix: Array[StringName] = []
## The id of that column's stand-in form.
const BODY_COLUMN: StringName = &"on its body"
## True while a multicast is given one carrier only, not the ones it asks for: one that adds no
## carrier at all must change the cast or be wasted (owner, 2026-11-06).
var _one_carrier: bool = false
## Trace by scene key, for the casts without the card.
var _baselines: Dictionary = {}


func before_each() -> void:
	_registry = own(RegistryScript.new()) as Node
	_registry.call("scan")
	_shelf = own(World.Shelf.new()) as World.Shelf
	_shelf.base = _registry
	_compiler = own(SpellsScript.new()) as SpellsScript
	_compiler.registry = _shelf
	_staff = StaffBase.new()
	_staff.id = &"card_rules"
	_staff.slots = 16
	_staff.cooldown = 0.0
	_staff.spread = SPREAD
	_baselines.clear()
	_discover()


func _discover() -> void:
	_forms.clear()
	_modifiers.clear()
	_triggers.clear()
	_elements.clear()
	_multicasts.clear()
	for card: Resource in _registry.call("get_all", &"spells"):
		if card is FormBase:
			_forms.append(card as FormBase)
		elif card is ModifierBase:
			_modifiers.append(card as ModifierBase)
		elif card is TriggerBase:
			_triggers.append(card as TriggerBase)
		elif card is ElementBase:
			_elements.append(card as ElementBase)
		elif card is MulticastBase:
			_multicasts.append(card as MulticastBase)
	_payload = null
	_shot = null
	_lasting = null
	_pulse = null
	for form in _forms:
		if form.carrier == Carriers.PULSE:
			_pulse = form
		if form.carrier != &"atom":
			continue
		if _payload == null or form.shots > _payload.shots:
			_payload = form
		if form.shots == 1 and (_shot == null or form.speed * form.lifetime > _shot.speed * _shot.lifetime):
			_shot = form
		if form.shots == 1 and (_lasting == null or form.lifetime > _lasting.lifetime):
			_lasting = form
	_columns.assign(_forms)
	_bearer_prefix.clear()
	_body_prefix.clear()
	_bearer_shooter_prefix.clear()
	_point_prefix.clear()
	if _shot == null or _pulse == null:
		return
	var land := ModifierBase.new()
	land.id = LAND
	_shelf.extra[LAND] = land
	for trigger in _triggers:
		if trigger.event == TriggerBase.Event.HIT:
			_bearer_prefix.append(trigger.id)
			_point_prefix.append(trigger.id)
		elif trigger.event == TriggerBase.Event.CAST:
			_body_prefix.append(trigger.id)
	_body_prefix.append(_shot.id)
	for modifier in _modifiers:
		if modifier.behaviour == ModifierBase.Behaviour.NONE and modifier.extra_pierce > 0:
			_bearer_prefix.append(modifier.id)
			break
	_bearer_shooter_prefix.assign(_bearer_prefix)
	_bearer_prefix.append(_shot.id)
	_bearer_shooter_prefix.append(_lasting.id)
	_point_prefix.append(_shot.id)
	var on_it := FormBase.new()
	on_it.id = &"on it"
	on_it.carrier = Carriers.PULSE_BEARER
	on_it.speed = _shot.speed
	on_it.lifetime = _shot.lifetime
	_columns.append(on_it)
	var on_body := FormBase.new()
	on_body.id = BODY_COLUMN
	on_body.carrier = Carriers.PULSE_BEARER
	on_body.lifetime = _pulse.lifetime
	on_body.radius = _pulse.radius
	_columns.append(on_body)
	var there := FormBase.new()
	there.id = &"right there"
	there.carrier = Carriers.PULSE_POINT
	there.speed = _shot.speed
	there.lifetime = _shot.lifetime
	_columns.append(there)


# --- The probes --------------------------------------------------------------------------------

## The scenes, each a Dictionary of what stands there besides the wizard and its teammate (and
## `name`). Keys: `line` (a target on the aim line at the carrier's reach), `crowd` (three more
## round it, one just behind), `second` (one more near it, off the line), `side` (a target off the line only),
## `wall` (a wall across the line at that fraction of the reach), `behind` (a target just past that
## wall), `back` (a target behind the wizard, on the line), `shooter` (an enemy past the reach shooting along the line at the wizard all the time; the
## wizard casts once one of its shots is near),
## `donor` (the target on the line cast an infused shot just before), `weak` (that target dies of
## any one hit: WEAK_HEALTH), `status` (that target has a status the carrier's infusion reacts with), `hurt` (the
## wizard is hurt now and then), `repeat` (the wizard keeps casting whenever its staff is ready),
## `with` (a modifier of that behaviour joins both casts). `open` is nothing at all.
const LINE: Dictionary = {"name": "target", "line": true}
const OPEN: Dictionary = {"name": "open"}
const CROWD_AGAIN: Dictionary = {"name": "a crowd, cast again", "line": true, "crowd": true, "repeat": true}
## Nothing in the way, the staff pressed again now and then (`again`: at these steps; `on
## recast`), busy or not. Without the card the carrier holds its payload under a trigger that stays
## quiet here (`stand_in`: `on hurt`, and no one is hurt), so both staffs cast the same cycle and
## only the recast differs.
const OPEN_AGAIN: Dictionary = {"name": "open, pressed again", "again": [6, 9, 14, 22, 40, 70], "stand_in": TriggerBase.Event.HURT}
const SIDE_TARGET: Dictionary = {"name": "target off the line", "side": true}
## The same, cast again while it lasts: a zap is a chance (50% a body a shot), so one shot may
## pass the target without zapping it; a stream of them does not.
const SIDE_AGAIN: Dictionary = {"name": "target off the line, cast again", "side": true, "repeat": true}
const TWO_TARGETS: Dictionary = {"name": "two targets", "line": true, "second": true}
const SHOOTER: Dictionary = {"name": "enemy shooter", "shooter": true}
const WALL: Dictionary = {"name": "wall, target behind", "wall": 0.6, "back": true}
const BACK: Dictionary = {"name": "target behind", "back": true}
const WALL_TARGET: Dictionary = {"name": "target behind a wall", "wall": 0.4, "behind": true}
const DONOR: Dictionary = {"name": "infused target", "line": true, "donor": true}
const SHIELDED: Dictionary = {"name": "enemy shooter, shield", "shooter": true, "with": ModifierBase.Behaviour.SHIELD}
const WEAK: Dictionary = {"name": "target dies", "line": true, "weak": true}
## The weak target's health: any hit takes it, an atom's speck too.
const WEAK_HEALTH: float = 0.01
const HURT: Dictionary = {"name": "wizard hurt", "hurt": true}
const REACTING: Dictionary = {"name": "target with a status", "line": true, "status": true}
## Nothing in the way; every sample the trace also says which of the wizard's shots circle (their
## motion is the manager's orbit) and which way each beam points, so a carrier that circles or
## sweeps shows it (`circling`; Orbit, docs/milestones/carrier-modifiers.md Part 5).
const CIRCLING: Dictionary = {"name": "open, what circles", "circling": true}


## The scenes in which a modifier of `behaviour` shows what it does (it works when one of them
## shows a change), or [] when there is no probe for it yet.
static func behaviour_scenes(behaviour: int) -> Array[Dictionary]:
	match behaviour:
		ModifierBase.Behaviour.NONE:
			# Numbers: damage, pierce, size, speed and cooldown show on targets, a crowd and casts
			# made again; a longer or slower life in the open.
			return [CROWD_AGAIN, OPEN]
		ModifierBase.Behaviour.HOMING, ModifierBase.Behaviour.MAGNET:
			return [SIDE_TARGET]
		ModifierBase.Behaviour.ZAP:
			return [SIDE_TARGET, SIDE_AGAIN]
		ModifierBase.Behaviour.CHAIN:
			return [TWO_TARGETS]
		ModifierBase.Behaviour.SHIELD, ModifierBase.Behaviour.DEFLECT:
			return [SHOOTER]
		ModifierBase.Behaviour.BLAST, ModifierBase.Behaviour.ECHO, ModifierBase.Behaviour.HEAVY, ModifierBase.Behaviour.SIPHON, ModifierBase.Behaviour.STICKY, ModifierBase.Behaviour.POSSESS, ModifierBase.Behaviour.PULL, ModifierBase.Behaviour.PENTA, ModifierBase.Behaviour.SKYFALL:
			return [LINE]
		ModifierBase.Behaviour.HOLD:
			# A held carrier lives on, and a held Pulse strikes again: what stands on the line is struck.
			return [OPEN, LINE]
		ModifierBase.Behaviour.RECOIL, ModifierBase.Behaviour.LINGER, ModifierBase.Behaviour.SPIRAL, ModifierBase.Behaviour.GROWTH, ModifierBase.Behaviour.RETURN:
			return [OPEN]
		ModifierBase.Behaviour.MIRROR, ModifierBase.Behaviour.NOVA:
			# A nova is a mirror with eight ways: one of them goes behind.
			return [BACK]
		ModifierBase.Behaviour.BOUNCE:
			return [WALL]
		ModifierBase.Behaviour.GHOST:
			return [WALL_TARGET]
		ModifierBase.Behaviour.RELAY:
			return [DONOR]
		ModifierBase.Behaviour.ORBIT:
			return [CIRCLING]
	return []


## The scenes in which a trigger of `event` fires.
static func event_scenes(event: int) -> Array[Dictionary]:
	match event:
		TriggerBase.Event.HIT:
			return [LINE]
		TriggerBase.Event.EXPIRE, TriggerBase.Event.TIMER, TriggerBase.Event.CAST:
			return [OPEN]
		TriggerBase.Event.BLOCK:
			return [SHIELDED]
		TriggerBase.Event.KILL:
			return [WEAK]
		TriggerBase.Event.WALL:
			return [WALL]
		TriggerBase.Event.HURT:
			# The wizard hurt, or a carrier that is a body of its own (a decoy) shot at.
			return [HURT, SHOOTER]
		TriggerBase.Event.REACTION:
			return [REACTING]
		TriggerBase.Event.RECAST:
			return [OPEN_AGAIN]
	return []


## How far along the aim a carrier of `form` acts (where its target stands), by its carrier; -1
## when there is no rule for its carrier yet.
static func reach(form: FormBase) -> float:
	if form.id == BODY_COLUMN:
		# On its body: within its strike round the wizard's hand, as on you.
		return form.radius
	match form.carrier:
		&"atom", &"swap", Carriers.PULSE_BEARER, Carriers.PULSE_POINT:
			# On it and right there: where the shot that fires it hits (its stand-in has that shot's
			# numbers).
			return minf(form.speed * form.lifetime * 0.5, 90.0)
		Carriers.PULSE:
			# On you: within its strike round the wizard's hand.
			return form.radius
		&"beam":
			return minf(form.ray_length * 0.5, 90.0)
		&"swing":
			return form.ray_length * 0.75
		&"slam":
			# The ring's middle: it strikes `ray_length` ahead and grows to `radius`.
			return form.ray_length
		&"rune":
			return form.radius
		&"pool":
			# In the puddle: it spreads `ray_length` ahead.
			return form.ray_length
		&"wall":
			return SpellLimits.WALL_REACH
		&"dash":
			# On its way: a dash strikes what its body passes (rules R4c).
			return form.ray_length * 0.5
		&"teleport":
			# Where it lands: a teleport strikes what is there (rules R4c).
			return form.ray_length
		&"decoy":
			# Its body stands a step ahead (twice its size) and turns the shots near it as it appears:
			# a shot this near the wizard's hand when it is cast is near its body.
			return 30.0
		&"familiar":
			return 60.0
		&"portal":
			# Its exit: what stands there goes through to the mouth.
			return form.ray_length
	return -1.0


# --- The tests ---------------------------------------------------------------------------------

func test_it_finds_the_cards_and_carriers_itself() -> void:
	check(_forms.size() >= 2, "the registry has carriers (%d)" % _forms.size())
	check(not _modifiers.is_empty() and not _triggers.is_empty(), "and modifiers and triggers")
	check(_payload != null, "a straight carrier to fire as a payload")
	check(_shot != null, "a straight carrier of one shot for the enemy shooter")
	for form in _forms:
		check(reach(form) >= 0.0, "no reach for the carrier %s of `%s`: add it to `reach`" % [form.carrier, form.id])


func test_the_same_cast_writes_the_same_trace() -> void:
	# Without this a ✓ could be noise: every carrier, cast alike twice, in the busiest scenes.
	for form in _forms:
		var cards: Array[StringName] = [form.id]
		for scene: Dictionary in [CROWD_AGAIN, SHOOTER]:
			var seconds: float = minf(form.wind_up + form.lifetime + AFTER_LIFE, LONGEST)
			var first: PackedStringArray = _run(cards, form, scene, seconds)
			var second: PackedStringArray = _run(cards, form, scene, seconds)
			check(first == second, "`%s` in the scene %s writes another trace the second time: %s" % [form.id, scene["name"], _first_difference(first, second)])
			check(not first.is_empty(), "`%s` in the scene %s writes something" % [form.id, scene["name"]])


func test_forcing_keeps_every_wasted_card() -> void:
	# The seam of the W check: with `keep_wasted` nothing on a carrier is listed as wasted.
	var forced: int = 0
	for form in _forms:
		for modifier in _modifiers:
			var cards: Array[StringName] = [modifier.id, form.id]
			if not _compiler.compile_staff(cards, _staff).wasted.has(0):
				continue
			StaffCompiler.keep_wasted = true
			var kept: CompiledStaff = _compiler.compile_staff(cards, _staff)
			StaffCompiler.keep_wasted = false
			check(not kept.wasted.has(0), "`%s` on `%s` is kept when forced" % [modifier.id, form.id])
			check(kept.casts[0].group.spells[0].modifier_ids.has(modifier.id), "and rides on it")
			forced += 1
		for trigger in _triggers:
			var cards: Array[StringName] = [trigger.id, form.id, _payload.id]
			if not _compiler.compile_staff(cards, _staff).wasted.has(0):
				continue
			StaffCompiler.keep_wasted = true
			var kept: CompiledStaff = _compiler.compile_staff(cards, _staff)
			StaffCompiler.keep_wasted = false
			check(not kept.wasted.has(0), "`%s` on `%s` is kept when forced" % [trigger.id, form.id])
			forced += 1
	check(forced > 0, "some card is wasted somewhere (%d)" % forced)


# The modifiers are most of the matrix: they are played in MODIFIER_PARTS tests, so the runner can
# play them side by side (`unit-test-shards` at the top).
func test_every_modifier_works_or_is_wasted_on_every_carrier_1() -> void:
	_modifier_part(0)


func test_every_modifier_works_or_is_wasted_on_every_carrier_2() -> void:
	_modifier_part(1)


func test_every_modifier_works_or_is_wasted_on_every_carrier_3() -> void:
	_modifier_part(2)


func test_every_modifier_works_or_is_wasted_on_every_carrier_4() -> void:
	_modifier_part(3)


func test_every_modifier_works_or_is_wasted_on_every_carrier_5() -> void:
	_modifier_part(4)


func test_every_modifier_works_or_is_wasted_on_every_carrier_6() -> void:
	_modifier_part(5)


func test_every_trigger_works_or_is_wasted_on_every_carrier() -> void:
	var cards: Array[SpellComponent] = []
	cards.assign(_triggers)
	_matrix("Triggers", cards)


func test_every_infusion_works_or_is_wasted_on_every_carrier() -> void:
	var cards: Array[SpellComponent] = []
	cards.assign(_elements)
	_matrix("Infusions", cards)


func test_every_multicast_works_or_is_wasted_on_every_carrier() -> void:
	var cards: Array[SpellComponent] = []
	cards.assign(_multicasts)
	_matrix("Multicasts", cards)


func test_every_multicast_with_one_carrier_works_or_is_wasted_on_every_carrier() -> void:
	# A multicast that finds no carrier for its extra draws (`double · bolt` alone) adds none: it is
	# wasted unless it does something else (a burst repeats, a scatter turns the one it has).
	var cards: Array[SpellComponent] = []
	cards.assign(_multicasts)
	_one_carrier = true
	_matrix("Multicasts with one carrier", cards)
	_one_carrier = false


# --- The matrix --------------------------------------------------------------------------------

## The modifiers' part `part` (from 0) of MODIFIER_PARTS: every MODIFIER_PARTS-th modifier by id,
## from the `part`-th, played by `_play_modifiers`.
func _modifier_part(part: int) -> void:
	var sorted: Array[ModifierBase] = _modifiers.duplicate()
	sorted.sort_custom(func(a: ModifierBase, b: ModifierBase) -> bool: return String(a.id) < String(b.id))
	var cards: Array[SpellComponent] = []
	for i in sorted.size():
		if i % MODIFIER_PARTS == part:
			cards.append(sorted[i])
	check(_modifiers.size() >= MODIFIER_PARTS, "every part has modifiers (%d)" % _modifiers.size())
	_play_modifiers("Modifiers (part %d of %d)" % [part + 1, MODIFIER_PARTS], cards)


## Plays one part of the modifiers: the works-or-wasted matrix.
func _play_modifiers(title: String, cards: Array[SpellComponent]) -> void:
	_matrix(title, cards)


func _matrix(title: String, cards: Array[SpellComponent]) -> void:
	if _payload == null or _shot == null:
		return
	var started: int = Time.get_ticks_msec()
	var header: PackedStringArray = PackedStringArray(["", ""])
	for form in _columns:
		header.append(String(form.id))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("| %s |" % " | ".join(header.slice(1)))
	var rule: PackedStringArray = PackedStringArray()
	for n in header.size() - 1:
		rule.append("---")
	lines.append("| %s |" % " | ".join(rule))
	var silent: int = 0
	for card in cards:
		var row: PackedStringArray = PackedStringArray([String(card.id)])
		for form in _columns:
			var cell: String = NOT_THERE if _payload_pulse(form) and not _lands(card) else _cell(card, form)
			if cell == SILENT:
				silent += 1
			row.append(cell)
		lines.append("| %s |" % " | ".join(row))
	print("\n%s × carriers (%s works, %s wasted, %s silent no-op), %d ✗, %d ms:\n%s\n" % [title, WORKS, WASTED, SILENT, silent, Time.get_ticks_msec() - started, "\n".join(lines)])


## The cell of `card` on `form`: W, ✓ (some scene of its probe shows a change), ✗ (and a
## failure), or ? (no probe, a failure).
func _cell(card: SpellComponent, form: FormBase) -> String:
	var scenes: Array[Dictionary] = _scenes_of(card)
	if scenes.is_empty():
		check(false, "no probe for %s (the card `%s`): add a scene for it" % [_what(card), card.id])
		return NO_PROBE
	if reach(form) < 0.0 or (not ONLY_FORM.is_empty() and String(form.id) != ONLY_FORM):
		return NO_PROBE
	var names: PackedStringArray = PackedStringArray()
	for scene in scenes:
		names.append(scene["name"])
		var casts: Array = _casts(card, form, scene, false)
		var compiled: CompiledStaff = _compiler.compile_staff(casts[0], _staff)
		if compiled.wasted.has(int(casts[2])):
			# The other way round: forced on, a wasted card must still change nothing.
			for forced in scenes:
				if _changes(card, form, forced, true):
					check(false, "`%s` on `%s` is listed as wasted but changes the cast (scene: %s)" % [card.id, form.id, forced["name"]])
					break
			return WASTED
		if _changes(card, form, scene, false):
			return WORKS
	check(false, "`%s` on `%s` does nothing and is not listed as wasted (scene: %s)" % [card.id, form.id, "; ".join(names)])
	return SILENT


## True when the cast with `card` on `form` writes another trace in `scene` than the cast without
## it. `forced` compiles both with `StaffCompiler.keep_wasted`, so what the waste table would drop
## is kept and the runtime alone decides what it does.
func _changes(card: SpellComponent, form: FormBase, scene: Dictionary, forced: bool) -> bool:
	StaffCompiler.keep_wasted = forced
	var casts: Array = _casts(card, form, scene, forced)
	var with: Array[StringName] = casts[0]
	var without: Array[StringName] = casts[1]
	var seconds: float = minf(form.wind_up + form.lifetime + AFTER_LIFE, LONGEST)
	if scene.get("repeat", false):
		# Long enough for the second cast to land (its delay is every carrier's cooldown).
		var plain: CompiledStaff = _compiler.compile_staff(without, _staff)
		var delay: float = plain.casts[0].delay if not plain.is_empty() else 0.0
		seconds = minf(delay + form.wind_up + form.lifetime + AFTER_LIFE, LONGEST)
	var key: String = "%s|%s|%s|%s|%s" % [form.id, scene["name"], ",".join(PackedStringArray(without)), seconds, forced]
	var before: PackedStringArray
	if _baselines.has(key):
		before = _baselines[key]
	else:
		before = _run(without, form, scene, seconds)
		_baselines[key] = before
	var after: PackedStringArray = _run(with, form, scene, seconds, before)
	StaffCompiler.keep_wasted = false
	if after != before and EXPLAIN:
		print("%s on %s (%s%s): %s" % [card.id, form.id, scene["name"], ", forced" if forced else "", _first_difference(before, after)])
	return after != before


## The cards of the cast with `card` and of the same cast without it, and the slot of `card` in the
## first, as [with, without, slot]. `forced` (a wasted card forced on): a modifier of numbers only
## is swapped for a copy of its costs, so both casts pay them (a slower cast is no effect).
func _casts(card: SpellComponent, form: FormBase, scene: Dictionary, forced: bool) -> Array:
	var with: Array[StringName] = []
	var without: Array[StringName] = []
	var extra: Array[StringName] = _extra_cards(scene)
	if Carriers.is_pulse(form.carrier) and _lands(card):
		# The card lands with LAND and the scene's cards, and the Pulse card after them: round the
		# caster, round the shot that hit and flies on, or round the point where `on hit`'s shot was
		# spent.
		if form.id == BODY_COLUMN:
			with.append_array(_body_prefix)
			without.append_array(_body_prefix)
		elif form.carrier == Carriers.PULSE_BEARER:
			var prefix: Array[StringName] = _bearer_shooter_prefix if scene.get("shooter", false) else _bearer_prefix
			with.append_array(prefix)
			without.append_array(prefix)
		elif form.carrier == Carriers.PULSE_POINT:
			with.append_array(_point_prefix)
			without.append_array(_point_prefix)
		for cards: Array[StringName] in [with, without]:
			cards.append_array(extra)
			cards.append(LAND)
		var slot: int = with.size()
		with.append(card.id)
		var plain: StringName = _costs_of(card) if forced else _plain_of(card)
		if plain != &"":
			without.append(plain)
		with.append(_pulse.id)
		without.append(_pulse.id)
		return [with, without, slot]
	var tail: Array[StringName] = [form.id]
	if card is TriggerBase:
		with.append(card.id)
		with.append_array(extra)
		with.append_array(tail)
		with.append(_payload.id)
		if scene.has("stand_in"):
			for trigger in _triggers:
				if trigger.event == int(scene["stand_in"]):
					without.append(trigger.id)
					break
		without.append_array(extra)
		without.append_array(tail)
		without.append(_payload.id)
	elif card is MulticastBase:
		with.append(card.id)
		for n in 1 if _one_carrier else 1 + (card as MulticastBase).extra_draws:
			with.append_array(tail)
			without.append_array(tail)
	else:
		with.append(card.id)
		var plain: StringName = _costs_of(card) if forced else _plain_of(card)
		if plain != &"":
			without.append(plain)
		with.append_array(extra)
		without.append_array(extra)
		with.append_array(tail)
		without.append_array(tail)
	return [with, without, 0]


## True when `card` is played on a Pulse with LAND: a modifier or an infusion (a trigger or a multicast
## is played on the Pulse card's own column as on any form's).
static func _lands(card: SpellComponent) -> bool:
	return card is ModifierBase or card is ElementBase


## True when `form` is the stand-in of a Pulse in a payload (`on it`, `on its body`, `right there`).
static func _payload_pulse(form: FormBase) -> bool:
	return form.carrier == Carriers.PULSE_BEARER or form.carrier == Carriers.PULSE_POINT


func _scenes_of(card: SpellComponent) -> Array[Dictionary]:
	var scenes: Array[Dictionary] = []
	if card is ModifierBase:
		scenes.assign(behaviour_scenes((card as ModifierBase).behaviour))
	elif card is TriggerBase:
		scenes.assign(event_scenes((card as TriggerBase).event))
	elif card is ElementBase or card is MulticastBase:
		scenes.append(LINE)
	return scenes


func _what(card: SpellComponent) -> String:
	if card is ModifierBase:
		return "the behaviour %s" % ModifierBase.Behaviour.keys()[(card as ModifierBase).behaviour]
	if card is TriggerBase:
		return "the event %s" % TriggerBase.Event.keys()[(card as TriggerBase).event]
	return "the kind %s" % card.kind()


## The cards a scene adds to both casts: a modifier of the behaviour it asks for (`with`), the
## infusion that reacts with the target's status (`status`).
func _extra_cards(scene: Dictionary) -> Array[StringName]:
	var extra: Array[StringName] = []
	if scene.has("with"):
		for modifier in _modifiers:
			if modifier.behaviour == int(scene["with"]):
				extra.append(modifier.id)
				break
	if scene.get("status", false):
		var row: ReactionRow = _reaction()
		if row != null:
			extra.append(row.element_id)
	return extra


## The first reaction of the table whose infusion is a card.
func _reaction() -> ReactionRow:
	for row: ReactionRow in CombatScript.REACTIONS.rows:
		if _registry.call("get_resource", &"spells", row.element_id) != null:
			return row
	return null


## The id of the copy of `card` with no behaviour (put on the shelf), or &"" when leaving the card
## out is the same: a modifier of numbers only, or one whose numbers change nothing a cast shows.
func _plain_of(card: SpellComponent) -> StringName:
	var modifier := card as ModifierBase
	if modifier == null or modifier.behaviour == ModifierBase.Behaviour.NONE:
		return &""
	if is_equal_approx(modifier.damage_mult, 1.0) and is_equal_approx(modifier.speed_mult, 1.0) and is_equal_approx(modifier.radius_mult, 1.0) and modifier.shot_mult == 1 and modifier.extra_pierce == 0 and is_equal_approx(modifier.spread_mult, 1.0) and is_equal_approx(modifier.lifetime_mult, 1.0) and modifier.lifetime_base <= 0.0:
		return &""
	var id: StringName = StringName("%s~plain" % modifier.id)
	if not _shelf.extra.has(id):
		var plain := modifier.duplicate() as ModifierBase
		plain.id = id
		plain.behaviour = ModifierBase.Behaviour.NONE
		plain.behaviour_strength = 0.0
		plain.behaviour_reach = 0.0
		_shelf.extra[id] = plain
	return id


## For a wasted card forced on: the id of a copy of `card` that keeps only what it costs (more
## mana, a slower cast, less damage) for a modifier of numbers only; `_plain_of` for any other card.
func _costs_of(card: SpellComponent) -> StringName:
	var modifier := card as ModifierBase
	if modifier == null or modifier.behaviour != ModifierBase.Behaviour.NONE:
		return _plain_of(card)
	var id: StringName = StringName("%s~costs" % modifier.id)
	if not _shelf.extra.has(id):
		var costs := modifier.duplicate() as ModifierBase
		costs.id = id
		costs.damage_mult = minf(modifier.damage_mult, 1.0)
		costs.wind_down_mult = maxf(modifier.wind_down_mult, 1.0)
		costs.wind_up_mult = maxf(modifier.wind_up_mult, 1.0)
		costs.speed_mult = 1.0
		costs.radius_mult = 1.0
		costs.lifetime_mult = 1.0
		costs.spread_mult = 1.0
		costs.shot_mult = 1
		costs.extra_pierce = 0
		_shelf.extra[id] = costs
	return id


## Casts `cards` once (or for the whole run, `repeat`) in the scene for `form` and returns the trace,
## up to its first difference from `expect` (the whole trace when there is none).
func _run(cards: Array[StringName], form: FormBase, scene: Dictionary, seconds: float, expect: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var world: World = _make_world()
	# Stop at the first difference: the cell is ✓ then.
	world.expect = expect
	var r: float = reach(form)
	world.add_wizard(cards)
	world.add_ally(ALLY_AT)
	# On it and right there are cast where `on hit`'s shot hits: always a target on the line for it.
	if scene.get("line", false) or _cast_by_a_hit(form):
		var donor: Array[StringName] = []
		if scene.get("donor", false):
			for element in _elements:
				if element.status_id != &"":
					donor = [element.id, _shot.id]
					break
			# Its own cast flies off up into a wall.
			world.add_wall(Rect2(-480.0, -160.0, 960.0, 8.0))
		# A weak target has 0.01 health: any hit kills it, a speck's too (an atom's 0.3).
		var target: Node2D = world.add_enemy(&"A", Vector2(r, 0.0), WEAK_HEALTH if scene.get("weak", false) else World.HEALTH, donor, Vector2.UP)
		if scene.get("status", false):
			var row: ReactionRow = _reaction()
			if row != null:
				world.combat.apply_status(world.table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY), target, row.status_id, 30.0, 1.0)
	if scene.get("back", false):
		world.add_enemy(&"K", Vector2(-BACK_AT, 0.0))
	if scene.get("crowd", false):
		world.add_enemy(&"C", Vector2(r + CROWD, 0.0))
		world.add_enemy(&"D", Vector2(r, CROWD))
		world.add_enemy(&"F", Vector2(r, -CROWD))
	if scene.get("second", false):
		world.add_enemy(&"B", Vector2(r, SECOND))
	if scene.get("side", false):
		world.add_enemy(&"S", Vector2(r, SIDE))
	if scene.has("wall"):
		var x: float = r * float(scene["wall"])
		world.add_wall(Rect2(x, -80.0, 8.0, 160.0))
		if scene.get("behind", false):
			world.add_enemy(&"G", Vector2(r + 8.0, 0.0))
	if scene.get("shooter", false):
		var shot: Array[StringName] = [_shot.id]
		world.add_enemy(&"E", Vector2(r + SHOOTER_BEHIND, 0.0), World.HEALTH, shot, Vector2.LEFT, true)
	if Carriers.of(form.carrier).has(CarrierTraits.GATES):
		# A carrier that opens a way through (a portal) acts on what goes through it: a teammate
		# sends a plain shot into it a moment after the cast.
		var shot: Array[StringName] = [_shot.id]
		world.add_courier(COURIER_AT, shot, COURIER_AT.direction_to(Vector2(COURIER_AIM, 0.0)), COURIER_STEP)
	if scene.get("hurt", false):
		for step in HURT_STEPS:
			world.hurt_wizard_at(step, 1)
	if scene.get("shooter", false) and _cast_by_a_hit(form):
		# On it and right there: the shooter's shots end on the target their shot hits, so none comes
		# near the wizard; cast at once, the shot that hit flies on through them.
		world.press()
	elif scene.get("shooter", false):
		# A carrier that leans back first (a swing) is cast that much sooner.
		world.press_when_shot_within(r + SHOT_NEAR + form.wind_up * _shot.speed)
	elif scene.get("donor", false):
		# The donor casts first, so a carrier that hits at once finds what it cast.
		world.at_step[2] = [world.press]
	else:
		world.press(scene.get("repeat", false))
	for step: int in scene.get("again", []):
		world.press_at(step)
	if scene.get("circling", false):
		var watch: Callable = _watch_circling.bind(world)
		for step in range(0, int(ceilf(seconds / World.STEP)), World.SAMPLE_EVERY):
			if not world.at_step.has(step):
				world.at_step[step] = []
			(world.at_step[step] as Array).append(watch)
	world.run(seconds, 0.0 if not scene.get("repeat", false) else seconds)
	var trace: PackedStringArray = world.trace
	world.free_all()
	return trace


## The `circling` scene's lines: each of the wizard's shots that circles (its motion is the
## manager's orbit), and the way each beam points, in whole degrees.
func _watch_circling(world: World) -> void:
	var projectiles: World.ProjectilesScript = world.projectiles
	for slot in projectiles._high:
		if projectiles.is_alive(slot) and projectiles.get_actor_of(slot) == world.wizard.id and projectiles._motion[slot] == World.ProjectilesScript.MOTION_ORBIT:
			world._put("circling %s" % world._node(projectiles.get_tag_of(slot)))
	var beams: CarrierBeam = CarrierBeam.of(world.spells)
	for at in beams.beam_slots():
		if beams.beam_on(at) and beams.beam_point_count(at) >= 2:
			var way: Vector2 = beams.beam_point(at, 1) - beams.beam_point(at, 0)
			world._put("beam %s points %d" % [world._who(beams.beam_caster(at)), roundi(rad_to_deg(DMath.angle(way)))])


## True for the columns whose payload a shot's hit fires (on it, right there): a target always
## stands on the line for that shot.
static func _cast_by_a_hit(form: FormBase) -> bool:
	return form.id != BODY_COLUMN and _payload_pulse(form)


## The world a cast runs in.
func _make_world() -> World:
	return World.new(root, _shelf, _staff)


static func _first_difference(a: PackedStringArray, b: PackedStringArray) -> String:
	for n in mini(a.size(), b.size()):
		if a[n] != b[n]:
			return "line %d: '%s' / '%s'" % [n, a[n], b[n]]
	return "lengths %d / %d" % [a.size(), b.size()]
