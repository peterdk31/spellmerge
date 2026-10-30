extends "res://tests/support/suite.gd"
## The compiler lists triggers that cannot fire (rules R2b, docs/milestones/M2-rules.md):
## `StaffCompiler.trigger_runs` over every event x every carrier motion, with a reason wherever it
## cannot; a trigger that never fires on its carrier is wasted with its reason, and the payload it
## would cast is still read (the reading order does not change) but wasted and not attached.
## Cards are built in code.
##
## godot --headless --path . --script res://tests/core/test_trigger_table.gd

const E := TriggerBase.Event
const M := FormBase.Motion

## The table as the runtime runs it today (core/spells/spells.gd): event -> the motions it can
## fire on. Every motion not listed is wasted. A change here is a change of the rules: say so in
## M2-rules.md ("Triggers" under "Card x carrier") and docs/DECISIONS.md.
const SHOTS: Array = [M.STRAIGHT, M.STILL, M.ORBIT, M.HOOK, M.SWAP, M.WALL]
## What is over at once: no timer ticks and nothing hears a hurt on it (rules R4d).
const AT_ONCE: Array = [M.SLAM, M.TELEPORT]
const HITTERS: Array = [M.STRAIGHT, M.STILL, M.ORBIT, M.HOOK, M.SWAP, M.WALL, M.RAY, M.SWING, M.SLAM, M.RAIN]

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
	for motion: int in M.size():
		var form := FormBase.new()
		form.motion = motion as FormBase.Motion
		form.mana_cost = 2.0
		form.cooldown = 0.25
		_put(form, StringName(String(M.keys()[motion]).to_lower()))
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


func _expected(event: int, motion: int) -> bool:
	match event:
		E.HIT:
			return HITTERS.has(motion)
		E.TIMER, E.HURT:
			return not AT_ONCE.has(motion)
		E.BLOCK:
			# Wherever a shield or deflect runs: not on a rain or familiar (rules R4g: a decoy guards).
			return motion != M.RAIN and motion != M.FAMILIAR
		E.WALL:
			return [M.STRAIGHT, M.HOOK, M.SWAP, M.RAY].has(motion)
	return true


func test_every_event_on_every_carrier_runs_or_says_why() -> void:
	for event: int in E.size():
		for motion: int in M.size():
			var cell: String = "%s on %s" % [E.keys()[event], M.keys()[motion]]
			var runs: bool = StaffCompiler.trigger_runs(event, motion as FormBase.Motion)
			var why: String = StaffCompiler.trigger_why_not(event, motion as FormBase.Motion)
			check_equal(runs, _expected(event, motion), "%s runs as the runtime does" % cell)
			check_equal(why.is_empty(), runs, "%s has a reason exactly when it cannot run (%s)" % [cell, why])


func test_a_timer_on_a_slam_is_wasted_with_its_payload() -> void:
	var built: CompiledStaff = _compile([&"on_timer", &"slam", &"straight"])
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
	var fires: CompiledStaff = _compile([&"on_hit", &"straight", &"straight", &"straight"])
	var never: CompiledStaff = _compile([&"on_hit", &"decoy", &"straight", &"straight"])
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
		[&"on_wall", &"still", "never meets a wall"],
		[&"on_wall", &"swing", "a swing's sweep never meets a wall"],
		[&"on_hurt", &"slam", "over at once"],
		[&"on_hurt", &"teleport", "over at once"],
		[&"on_timer", &"slam", "over at once"],
		[&"on_timer", &"teleport", "over at once"],
		[&"on_block", &"rain", "nothing on it can block"],
		[&"on_kill", &"teleport", "without a blast"],
		[&"on_reaction", &"familiar", "without a blast"],
	]
	for cell: Array in cells:
		var cards: Array[StringName] = [cell[0], cell[1], &"straight"]
		if cell[1] == &"rain" or cell[1] == &"familiar":
			# A rain and a familiar read a payload of their own first.
			cards.append(&"straight")
		var built: CompiledStaff = _compile(cards)
		var why: String = str(built.wasted.get(0, ""))
		check(why.contains(String(cell[2])), "%s on %s is wasted: %s" % [cell[0], cell[1], why])


func test_triggers_that_fire_are_not_wasted() -> void:
	var cells: Array = [
		[&"on_hit", &"straight"], [&"on_timer", &"straight"], [&"on_hurt", &"orbit"], [&"on_timer", &"wall"],
		[&"on_hit", &"ray"], [&"on_hit", &"swing"], [&"on_wall", &"ray"], [&"on_wall", &"hook"],
		[&"on_expire", &"rain"], [&"on_hit", &"rain"], [&"on_expire", &"decoy"], [&"on_cast", &"dash"], [&"on_kill", &"slam"],
		[&"on_timer", &"ray"], [&"on_timer", &"rain"], [&"on_timer", &"dash"], [&"on_timer", &"swing"],
		[&"on_hurt", &"ray"], [&"on_hurt", &"decoy"], [&"on_hurt", &"dash"], [&"on_hurt", &"rain"],
	]
	for cell: Array in cells:
		var cards: Array[StringName] = [cell[0], cell[1], &"straight"]
		if cell[1] == &"rain":
			cards.append(&"straight")
		var built: CompiledStaff = _compile(cards)
		check(built.wasted.is_empty(), "%s on %s fires: %s" % [cell[0], cell[1], built.wasted])
		var spell: CompiledSpell = built.casts[0].group.spells[0]
		check(spell.payload != null and not spell.payload.is_empty(), "%s on %s carries its payload" % [cell[0], cell[1]])


func test_the_cards_an_event_needs() -> void:
	# A block needs a shield or deflect; a dash's barrier blocks too.
	check(_compile([&"on_block", &"straight", &"straight"]).wasted.has(0), "on block on a bare bolt is wasted")
	check(_compile([&"on_block", &"shield", &"straight", &"straight"]).wasted.is_empty(), "with a shield it fires")
	check(_compile([&"on_block", &"deflect", &"swing", &"straight"]).wasted.is_empty(), "with a deflect on a swing it fires")
	check(_compile([&"on_block", &"shield", &"dash", &"straight"]).wasted.is_empty(), "a dash's barrier blocks")
	# A kill or reaction of a carrier that hits nothing itself comes from its blast.
	check(_compile([&"on_kill", &"rain", &"straight", &"straight"]).wasted.is_empty(), "a rain kills by its own strike")
	check(_compile([&"on_kill", &"blast", &"decoy", &"straight"]).wasted.is_empty(), "a decoy with a blast can kill")
	check(_compile([&"on_kill", &"blast", &"dash", &"straight"]).wasted.is_empty(), "so can a dash with a blast")
	# A reaction needs an element on the hit.
	var bare: String = str(_compile([&"on_reaction", &"straight", &"straight"]).wasted.get(0, ""))
	check(bare.contains("without an infusion"), "on reaction on a bare bolt says why: %s" % bare)
	check(_compile([&"on_reaction", &"fire", &"straight", &"straight"]).wasted.is_empty(), "with fire it fires")
	check(_compile([&"on_reaction", &"relay", &"straight", &"straight"]).wasted.is_empty(), "relay takes on elements")
	# A ghost shot flies through walls.
	var ghost: String = str(_compile([&"on_wall", &"ghost", &"straight", &"straight"]).wasted.get(0, ""))
	check(ghost.contains("passes through walls"), "on wall on a ghost bolt says why: %s" % ghost)
	# So does a ghost beam (rules R4f).
	var ghost_line: String = str(_compile([&"on_wall", &"ghost", &"ray", &"straight"]).wasted.get(0, ""))
	check(ghost_line.contains("passes through walls"), "on wall on a ghost beam says why: %s" % ghost_line)
	check(not _compile([&"on_wall", &"ray", &"straight"]).wasted.has(0), "a plain beam meets walls")
