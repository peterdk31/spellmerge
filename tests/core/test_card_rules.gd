extends "res://tests/support/suite.gd"
## The card rules check (rules R3, docs/milestones/M2-rules.md, rule 1 "works or wasted"): every
## card in content/spells/ on every carrier either changes what happens in the game or is listed
## by the compiler as wasted, with a reason. Nothing does nothing silently.
##
## It keeps no list of cards or carriers (owner, 2026-10-29: "It should just auto discover new
## cards and carriers"). It asks the registry for every card: the forms are the carriers, and every
## modifier, trigger, infusion and multicast card is tried on each of them. A new card or carrier
## is checked the day it lands.
##
## A cell: compile the card on the carrier (`[card, carrier]`; a trigger gets a plain payload
## after its carrier, a carrier that reads its own payload, rain and familiar, gets one too). When
## the compiler lists the card as wasted, its reason must not be empty: W. Otherwise the cast runs
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
## the wizard, on kill a target that dies, on hurt the wizard hurt, on reaction a target with a
## status the carrier's infusion reacts with (see `behaviour_scenes` and `event_scenes`). How far
## along the line things stand is the carrier's reach, chosen by its `FormBase.carrier` (`reach`). A
## card whose behaviour or event has no scene yet fails with "no probe for ...", and a carrier
## whose motion has none with "no reach for ...", so a new kind of card or carrier brings its
## probe in the same PR.
##
## The other way round (R4b): a W cell is also played with the card forced on, and fails with
## "`card` on `carrier` is listed as wasted (reason) but changes the cast" when that trace differs
## (slam was once wrongly listed, found by hand). The seam is one test-only switch,
## `StaffCompiler.keep_wasted`: with it the compiler keeps every card its waste table would drop
## (a behaviour, numbers, an infusion, a trigger that "never fires" and its payload), and the
## runtime, which does not read the table, alone decides what the card does. Both casts are
## compiled with it on. A wasted card's costs are no effect: a modifier of numbers only is compared
## with a copy of it that keeps only its costs (`_costs_of`: mana, a slower cast, less damage), a
## behaviour modifier with its plain copy as above.
##
## It prints the matrix of every kind (✓ works, W wasted, ✗ silent no-op) so a PR shows coverage.
## Rule 2 (a card's effect survives a bounce, a jump, an echo, a payload) is not checked here yet.
##
## godot --headless --path . --script res://tests/core/test_card_rules.gd

const World := preload("res://tests/support/card_rules_world.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const WORKS: String = "✓"
const WASTED: String = "W"
const SILENT: String = "✗"
const NO_PROBE: String = "?"

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

var _registry: Node
var _shelf: World.Shelf
var _compiler: SpellsScript
var _staff: StaffBase
var _forms: Array[FormBase] = []
var _modifiers: Array[ModifierBase] = []
var _triggers: Array[TriggerBase] = []
var _elements: Array[ElementBase] = []
var _multicasts: Array[MulticastBase] = []
## The plain payload a trigger (and a rain or familiar) fires: the straight carrier with the most
## shots, so a fire shows wherever it happens.
var _payload: FormBase = null
## What the enemy shooter and the relay donor cast: the straight carrier of one shot that reaches
## furthest.
var _shot: FormBase = null
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
	_staff.cast_delay = 0.0
	_staff.recharge = 0.0
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
	for form in _forms:
		if form.carrier != &"bolt":
			continue
		if _payload == null or form.shots > _payload.shots:
			_payload = form
		if form.shots == 1 and (_shot == null or form.speed * form.lifetime > _shot.speed * _shot.lifetime):
			_shot = form


# --- The probes --------------------------------------------------------------------------------

## The scenes, each a Dictionary of what stands there besides the wizard and its teammate (and
## `name`). Keys: `line` (a target on the aim line at the carrier's reach), `crowd` (three more
## round it, one just behind), `second` (one more near it, off the line), `side` (a target off the line only),
## `wall` (a wall across the line at that fraction of the reach), `behind` (a target just past that
## wall), `back` (a target behind the wizard, on the line), `shooter` (an enemy past the reach shooting along the line at the wizard all the time; the
## wizard casts once one of its shots is near),
## `donor` (the target on the line cast an infused shot just before), `weak` (that target dies of
## one hit), `status` (that target has a status the carrier's infusion reacts with), `hurt` (the
## wizard is hurt now and then), `repeat` (the wizard keeps casting whenever its staff is ready),
## `with` (a modifier of that behaviour joins both casts). `open` is nothing at all.
const LINE: Dictionary = {"name": "target", "line": true}
const OPEN: Dictionary = {"name": "open"}
const CROWD_AGAIN: Dictionary = {"name": "a crowd, cast again", "line": true, "crowd": true, "repeat": true}
const SIDE_TARGET: Dictionary = {"name": "target off the line", "side": true}
const TWO_TARGETS: Dictionary = {"name": "two targets", "line": true, "second": true}
const SHOOTER: Dictionary = {"name": "enemy shooter", "shooter": true}
const WALL: Dictionary = {"name": "wall, target behind", "wall": 0.6, "back": true}
const BACK: Dictionary = {"name": "target behind", "back": true}
const WALL_TARGET: Dictionary = {"name": "target behind a wall", "wall": 0.4, "behind": true}
const DONOR: Dictionary = {"name": "infused target", "line": true, "donor": true}
const SHIELDED: Dictionary = {"name": "enemy shooter, shield", "shooter": true, "with": ModifierBase.Behaviour.SHIELD}
const WEAK: Dictionary = {"name": "target dies", "line": true, "weak": true}
const HURT: Dictionary = {"name": "wizard hurt", "hurt": true}
const REACTING: Dictionary = {"name": "target with a status", "line": true, "status": true}


## The scenes in which a modifier of `behaviour` shows what it does (it works when one of them
## shows a change), or [] when there is no probe for it yet.
static func behaviour_scenes(behaviour: int) -> Array[Dictionary]:
	match behaviour:
		ModifierBase.Behaviour.NONE:
			# Numbers: damage, pierce, size, speed and cooldown show on targets, a crowd and casts
			# made again; a longer or slower life in the open.
			return [CROWD_AGAIN, OPEN]
		ModifierBase.Behaviour.HOMING, ModifierBase.Behaviour.MAGNET, ModifierBase.Behaviour.ARC:
			return [SIDE_TARGET]
		ModifierBase.Behaviour.CHAIN:
			return [TWO_TARGETS]
		ModifierBase.Behaviour.SHIELD, ModifierBase.Behaviour.DEFLECT:
			return [SHOOTER]
		ModifierBase.Behaviour.BLAST, ModifierBase.Behaviour.ECHO, ModifierBase.Behaviour.HEAVY, ModifierBase.Behaviour.SIPHON, ModifierBase.Behaviour.STICKY, ModifierBase.Behaviour.POSSESS:
			return [LINE]
		ModifierBase.Behaviour.HOLD, ModifierBase.Behaviour.RECOIL, ModifierBase.Behaviour.LINGER, ModifierBase.Behaviour.SPIRAL, ModifierBase.Behaviour.GROWTH, ModifierBase.Behaviour.RETURN:
			return [OPEN]
		ModifierBase.Behaviour.MIRROR:
			return [BACK]
		ModifierBase.Behaviour.BOUNCE:
			return [WALL]
		ModifierBase.Behaviour.GHOST:
			return [WALL_TARGET]
		ModifierBase.Behaviour.RELAY:
			return [DONOR]
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
			return [HURT]
		TriggerBase.Event.REACTION:
			return [REACTING]
	return []


## How far along the aim a carrier of `form` acts (where its target stands), by its carrier; -1
## when there is no rule for its carrier yet.
static func reach(form: FormBase) -> float:
	match form.carrier:
		&"bolt", &"hook", &"swap":
			return minf(form.speed * form.lifetime * 0.5, 90.0)
		&"beam":
			return minf(form.ray_length * 0.5, 90.0)
		&"swing":
			return form.ray_length * 0.75
		&"slam":
			# The ring's middle: it strikes `ray_length` ahead and grows to `radius`.
			return form.ray_length
		&"rune":
			return form.radius
		&"orbit":
			return form.orbit_radius
		&"wall":
			return SpellLimits.WALL_REACH
		&"rain":
			return form.ray_length if form.ray_length > 0.0 else SpellLimits.RAIN_REACH
		&"dash":
			# On its way: a dash strikes what its body passes (rules R4c).
			return form.ray_length * 0.5
		&"teleport":
			# Where it lands: a teleport strikes what is there (rules R4c).
			return form.ray_length
		&"decoy", &"familiar":
			return 60.0
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
		if form.carries_payload():
			cards.append(_payload.id)
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
			if form.carries_payload():
				cards.insert(2, _payload.id)
			if not _compiler.compile_staff(cards, _staff).wasted.has(0):
				continue
			StaffCompiler.keep_wasted = true
			var kept: CompiledStaff = _compiler.compile_staff(cards, _staff)
			StaffCompiler.keep_wasted = false
			check(not kept.wasted.has(0), "`%s` on `%s` is kept when forced" % [trigger.id, form.id])
			forced += 1
	check(forced > 0, "some card is wasted somewhere (%d)" % forced)


func test_every_modifier_works_or_is_wasted_on_every_carrier() -> void:
	var cards: Array[SpellComponent] = []
	cards.assign(_modifiers)
	_matrix("Modifiers", cards)


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


# --- The matrix --------------------------------------------------------------------------------

func _matrix(title: String, cards: Array[SpellComponent]) -> void:
	if _payload == null or _shot == null:
		return
	var started: int = Time.get_ticks_msec()
	var header: PackedStringArray = PackedStringArray(["", ""])
	for form in _forms:
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
		for form in _forms:
			var cell: String = _cell(card, form)
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
		var compiled: CompiledStaff = _compiler.compile_staff(_casts(card, form, scene, false)[0], _staff)
		if compiled.wasted.has(0):
			var why: String = String(compiled.wasted[0]).strip_edges()
			check(not why.is_empty(), "`%s` on `%s` is wasted with no reason" % [card.id, form.id])
			# The other way round: forced on, a wasted card must still change nothing.
			for forced in scenes:
				if _changes(card, form, forced, true):
					check(false, "`%s` on `%s` is listed as wasted (%s) but changes the cast (scene: %s)" % [card.id, form.id, why, forced["name"]])
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


## The cards of the cast with `card` and of the same cast without it, as [with, without]. `forced`
## (a wasted card forced on): a modifier of numbers only is swapped for a copy of its costs, so
## both casts pay them (a slower cast is no effect).
func _casts(card: SpellComponent, form: FormBase, scene: Dictionary, forced: bool) -> Array:
	var tail: Array[StringName] = [form.id]
	if form.carries_payload():
		tail.append(_payload.id)
	var with: Array[StringName] = []
	var without: Array[StringName] = []
	var extra: Array[StringName] = _extra_cards(scene)
	if card is TriggerBase:
		with.append(card.id)
		with.append_array(extra)
		with.append_array(tail)
		with.append(_payload.id)
		without.append_array(extra)
		without.append_array(tail)
		without.append(_payload.id)
	elif card is MulticastBase:
		with.append(card.id)
		for n in 1 + (card as MulticastBase).extra_draws:
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
	return [with, without]


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
	if is_equal_approx(modifier.damage_mult, 1.0) and is_equal_approx(modifier.speed_mult, 1.0) and is_equal_approx(modifier.radius_mult, 1.0) and modifier.shot_mult == 1 and modifier.extra_pierce == 0 and is_equal_approx(modifier.spread_mult, 1.0) and is_equal_approx(modifier.lifetime_mult, 1.0):
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
		costs.cooldown_mult = maxf(modifier.cooldown_mult, 1.0)
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
	var world := World.new(root, _shelf, _staff)
	# Stop at the first difference: the cell is ✓ then.
	world.expect = expect
	var r: float = reach(form)
	world.add_wizard(cards)
	world.add_ally(ALLY_AT)
	if scene.get("line", false):
		var donor: Array[StringName] = []
		if scene.get("donor", false):
			for element in _elements:
				if element.status_id != &"":
					donor = [element.id, _shot.id]
					break
			# Its own cast flies off up into a wall.
			world.add_wall(Rect2(-480.0, -160.0, 960.0, 8.0))
		var target: Actor = world.add_enemy(&"A", Vector2(r, 0.0), 1 if scene.get("weak", false) else World.HEALTH, donor, Vector2.UP)
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
	if scene.get("hurt", false):
		for step in HURT_STEPS:
			world.hurt_wizard_at(step, 1)
	if scene.get("shooter", false):
		# A carrier that leans back first (a swing) is cast that much sooner.
		world.press_when_shot_within(r + SHOT_NEAR + form.wind_up * _shot.speed)
	elif scene.get("donor", false):
		# The donor casts first, so a carrier that hits at once finds what it cast.
		world.at_step[2] = [world.press]
	else:
		world.press(scene.get("repeat", false))
	world.run(seconds, 0.0 if not scene.get("repeat", false) else seconds)
	var trace: PackedStringArray = world.trace
	world.free_all()
	return trace


static func _first_difference(a: PackedStringArray, b: PackedStringArray) -> String:
	for n in mini(a.size(), b.size()):
		if a[n] != b[n]:
			return "line %d: '%s' / '%s'" % [n, a[n], b[n]]
	return "lengths %d / %d" % [a.size(), b.size()]
