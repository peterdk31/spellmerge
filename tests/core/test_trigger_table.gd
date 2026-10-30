extends "res://tests/support/suite.gd"
## The compiler lists triggers that cannot fire (rules R2b, docs/milestones/M2-rules.md):
## `StaffCompiler.trigger_runs` over every event x every carrier, with a reason wherever it
## cannot; a trigger that never fires on its carrier is wasted with its reason, and the payload it
## would cast is still read (the reading order does not change) but wasted and not attached.
## Cards are built in code.
##
## godot --headless --path . --script res://tests/core/test_trigger_table.gd

const E := TriggerBase.Event

## The table as the runtime runs it today (core/spells/spells.gd): event -> the carriers it can
## fire on. Every carrier not listed is wasted. A change here is a change of the rules: say so in
## M2-rules.md ("Triggers" under "Card x carrier") and docs/DECISIONS.md.
const SHOTS: Array = [&"bolt", &"rune", &"orbit", &"hook", &"swap", &"wall"]
## What is over at once: no timer ticks and nothing hears a hurt on it (rules R4d).
const AT_ONCE: Array = [&"slam", &"teleport"]
const HITTERS: Array = [&"bolt", &"rune", &"orbit", &"hook", &"swap", &"wall", &"beam", &"swing", &"slam", &"rain", &"dash", &"teleport"]

var _items: Dictionary = {}
var _compiler: StaffCompiler
var _staff: StaffBase


func before_each() -> void:
	_items = {}
	_compiler = StaffCompiler.new(func(id: StringName) -> SpellComponent: return _items.get(id))
	_staff = StaffBase.new()
	_staff.slots = 12
	_staff.cast_delay = 0.0
	_staff.recharge = 0.0
	for carrier: StringName in Carriers.ids():
		var form := FormBase.new()
		form.carrier = carrier
		form.mana_cost = 2.0
		form.cooldown = 0.25
		_put(form, carrier)
	for event: int in E.size():
		var trigger := TriggerBase.new()
		trigger.event = event as TriggerBase.Event
		trigger.interval = 0.5
		_put(trigger, StringName("on_" + String(E.keys()[event]).to_lower()))
	for behaviour: int in [ModifierBase.Behaviour.SHIELD, ModifierBase.Behaviour.DEFLECT, ModifierBase.Behaviour.BLAST, ModifierBase.Behaviour.GHOST, ModifierBase.Behaviour.RELAY]:
		var modifier := ModifierBase.new()
		modifier.behaviour = behaviour as ModifierBase.Behaviour
		modifier.behaviour_strength = 1.0
		_put(modifier, StringName(String(ModifierBase.Behaviour.keys()[behaviour]).to_lower()))
	var fire := ElementBase.new()
	fire.status_id = &"burn"
	_put(fire, &"fire")


func _put(card: SpellComponent, id: StringName) -> void:
	card.id = id
	card.display_name = String(id).capitalize()
	_items[id] = card


func _compile(cards: Array[StringName]) -> CompiledStaff:
	return _compiler.compile(cards, _staff)


func _expected(event: int, motion: StringName) -> bool:
	match event:
		E.HIT:
			return HITTERS.has(motion)
		E.TIMER, E.HURT:
			return not AT_ONCE.has(motion)
		E.BLOCK:
			# Wherever a shield or deflect runs: not on a rain or familiar (rules R4g: a decoy guards).
			return motion != &"rain" and motion != &"familiar"
		E.WALL:
			return [&"bolt", &"hook", &"swap", &"beam"].has(motion)
	return true


func test_every_event_on_every_carrier_runs_or_says_why() -> void:
	for event: int in E.size():
		for motion: StringName in Carriers.ids():
			var cell: String = "%s on %s" % [E.keys()[event], motion]
			var runs: bool = StaffCompiler.trigger_runs(event, motion)
			var why: String = StaffCompiler.trigger_why_not(event, motion)
			check_equal(runs, _expected(event, motion), "%s runs as the runtime does" % cell)
			check_equal(why.is_empty(), runs, "%s has a reason exactly when it cannot run (%s)" % [cell, why])


func test_a_timer_on_a_slam_is_wasted_with_its_payload() -> void:
	var built: CompiledStaff = _compile([&"on_timer", &"slam", &"bolt"])
	var cast: CompiledCast = built.casts[0]
	check(str(built.wasted.get(0, "")).contains("over at once"), "the timer is wasted with its reason: %s" % built.wasted)
	check(str(built.wasted.get(2, "")).begins_with("Nothing casts it"), "its payload is wasted too: %s" % built.wasted)
	check(not built.wasted.has(1), "the slam still casts")
	check_equal(cast.slots, PackedInt32Array([0, 1, 2]), "the payload is read in this cast, as when it fires")
	check(cast.group.spells[0].payload == null, "no payload hangs on the slam")
	check_equal(cast.group.spells[0].trigger_id, &"", "nor a trigger")
	check(not cast.targets.has(0) and not cast.targets.has(2), "nothing is attached")
	check_equal(cast.mana, 2.0, "the wasted payload costs no mana")
	check_equal(cast.delay, 0.25, "nor time")


func test_the_same_cards_read_alike_whether_the_trigger_fires_or_not() -> void:
	var fires: CompiledStaff = _compile([&"on_hit", &"bolt", &"bolt", &"bolt"])
	var never: CompiledStaff = _compile([&"on_hit", &"decoy", &"bolt", &"bolt"])
	check_equal(fires.casts.size(), never.casts.size(), "as many casts")
	for n in fires.casts.size():
		check_equal(never.casts[n].slots, fires.casts[n].slots, "cast %d reads the same slots" % n)
	check(str(never.wasted.get(0, "")).contains("a decoy hits nothing"), "on hit on a decoy says why: %s" % never.wasted)
	check(never.wasted.has(2) and not never.wasted.has(3), "the payload is wasted, the next cast is not")


func test_wasted_cells_say_why() -> void:
	var cells: Array = [
		[&"on_hit", &"decoy", "a decoy hits nothing"],
		[&"on_wall", &"rain", "never meets a wall"],
		[&"on_wall", &"dash", "it stops before walls"],
		[&"on_wall", &"orbit", "an orbit passes through walls"],
		[&"on_wall", &"rune", "never meets a wall"],
		[&"on_wall", &"swing", "a swing's sweep never meets a wall"],
		[&"on_hurt", &"slam", "over at once"],
		[&"on_hurt", &"teleport", "over at once"],
		[&"on_timer", &"slam", "over at once"],
		[&"on_timer", &"teleport", "over at once"],
		[&"on_block", &"rain", "nothing on it can block"],
		[&"on_kill", &"decoy", "without a blast"],
		[&"on_reaction", &"familiar", "without a blast"],
	]
	for cell: Array in cells:
		var cards: Array[StringName] = [cell[0], cell[1], &"bolt"]
		if cell[1] == &"rain":
			# A rain reads a payload of its own first.
			cards.append(&"bolt")
		var built: CompiledStaff = _compile(cards)
		var why: String = str(built.wasted.get(0, ""))
		check(why.contains(String(cell[2])), "%s on %s is wasted: %s" % [cell[0], cell[1], why])


func test_triggers_that_fire_are_not_wasted() -> void:
	var cells: Array = [
		[&"on_hit", &"bolt"], [&"on_timer", &"bolt"], [&"on_hurt", &"orbit"], [&"on_timer", &"wall"],
		[&"on_hit", &"beam"], [&"on_hit", &"swing"], [&"on_wall", &"beam"], [&"on_wall", &"hook"],
		[&"on_expire", &"rain"], [&"on_hit", &"rain"], [&"on_expire", &"decoy"], [&"on_cast", &"dash"], [&"on_kill", &"slam"],
		[&"on_timer", &"beam"], [&"on_timer", &"rain"], [&"on_timer", &"dash"], [&"on_timer", &"swing"],
		[&"on_hurt", &"beam"], [&"on_hurt", &"decoy"], [&"on_hurt", &"dash"], [&"on_hurt", &"rain"],
	]
	for cell: Array in cells:
		var cards: Array[StringName] = [cell[0], cell[1], &"bolt"]
		if cell[1] == &"rain":
			cards.append(&"bolt")
		var built: CompiledStaff = _compile(cards)
		check(built.wasted.is_empty(), "%s on %s fires: %s" % [cell[0], cell[1], built.wasted])
		var spell: CompiledSpell = built.casts[0].group.spells[0]
		check(spell.payload != null and not spell.payload.is_empty(), "%s on %s carries its payload" % [cell[0], cell[1]])


func test_the_cards_an_event_needs() -> void:
	# A block needs a shield or deflect; a dash's barrier blocks too.
	check(_compile([&"on_block", &"bolt", &"bolt"]).wasted.has(0), "on block on a bare bolt is wasted")
	check(_compile([&"on_block", &"shield", &"bolt", &"bolt"]).wasted.is_empty(), "with a shield it fires")
	check(_compile([&"on_block", &"deflect", &"swing", &"bolt"]).wasted.is_empty(), "with a deflect on a swing it fires")
	check(_compile([&"on_block", &"shield", &"dash", &"bolt"]).wasted.is_empty(), "a dash's barrier blocks")
	# A kill or reaction of a carrier that hits nothing itself comes from its blast.
	check(_compile([&"on_kill", &"rain", &"bolt", &"bolt"]).wasted.is_empty(), "a rain kills by its own strike")
	check(_compile([&"on_kill", &"blast", &"decoy", &"bolt"]).wasted.is_empty(), "a decoy with a blast can kill")
	check(_compile([&"on_kill", &"blast", &"dash", &"bolt"]).wasted.is_empty(), "so can a dash with a blast")
	# A reaction needs an element on the hit.
	var bare: String = str(_compile([&"on_reaction", &"bolt", &"bolt"]).wasted.get(0, ""))
	check(bare.contains("without an infusion"), "on reaction on a bare bolt says why: %s" % bare)
	check(_compile([&"on_reaction", &"fire", &"bolt", &"bolt"]).wasted.is_empty(), "with fire it fires")
	check(_compile([&"on_reaction", &"relay", &"bolt", &"bolt"]).wasted.is_empty(), "relay takes on elements")
	# A ghost shot flies through walls.
	var ghost: String = str(_compile([&"on_wall", &"ghost", &"bolt", &"bolt"]).wasted.get(0, ""))
	check(ghost.contains("passes through walls"), "on wall on a ghost bolt says why: %s" % ghost)
	# So does a ghost beam (rules R4f).
	var ghost_line: String = str(_compile([&"on_wall", &"ghost", &"beam", &"bolt"]).wasted.get(0, ""))
	check(ghost_line.contains("passes through walls"), "on wall on a ghost beam says why: %s" % ghost_line)
	check(not _compile([&"on_wall", &"beam", &"bolt"]).wasted.has(0), "a plain beam meets walls")
