extends "res://tests/support/suite.gd"
## The compiler lists triggers that cannot fire (rules R2b, docs/milestones/M2-rules.md):
## `Carrier.fires` over every event x every carrier; a trigger that never fires on its
## carrier is wasted, and the payload it
## would cast is still read (the reading order does not change) but wasted and not attached.
## Cards are built in code.
##
## godot --headless --path . --script res://tests/core/test_trigger_table.gd

const E := TriggerBase.Event

## The table as the runtime runs it today (core/spells/spells.gd): event -> the carriers it can
## fire on. Every carrier not listed is wasted. A change here is a change of the rules: say so in
## M2-rules.md ("Triggers" under "Card x carrier") and docs/DECISIONS.md.
const SHOTS: Array = [&"atom", &"rune", &"swap", &"wall", &"pool"]
## What is over at once: no timer ticks, nothing hears a hurt on it (rules R4d) and nothing is left
## for a recast.
const AT_ONCE: Array = [&"slam", &"teleport"]

var _items: Dictionary = {}
var _compiler: StaffCompiler
var _staff: StaffBase


func before_each() -> void:
	_items = {}
	_compiler = StaffCompiler.new(func(id: StringName) -> SpellComponent: return _items.get(id))
	_staff = StaffBase.new()
	_staff.slots = 12
	_staff.cooldown = 0.0
	for carrier: StringName in Carriers.ids():
		var form := CarrierCard.new()
		form.carrier = carrier
		form.mana_cost = 2.0
		form.wind_down = 0.25
		_put(form, carrier)
	for event: int in E.size():
		var trigger := TriggerBase.new()
		trigger.event = event as TriggerBase.Event
		trigger.wind_up = 0.5
		_put(trigger, StringName("on_" + String(E.keys()[event]).to_lower()))
	for behaviour: int in [ModifierBase.Behaviour.SHIELD, ModifierBase.Behaviour.DEFLECT, ModifierBase.Behaviour.BLAST, ModifierBase.Behaviour.GHOST, ModifierBase.Behaviour.RELAY, ModifierBase.Behaviour.ORBIT]:
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


func _expected(event: int, carrier: StringName) -> bool:
	match event:
		E.TIMER, E.HURT, E.RECAST:
			return not AT_ONCE.has(carrier)
		E.BLOCK:
			# Wherever a shield or deflect runs: not on a familiar (a decoy has a barrier), nor a
			# portal, which passes every shot on (owner, 2026-11-05).
			return carrier != &"familiar" and carrier != &"portal"
		E.WALL:
			return [&"atom", &"swap", &"beam"].has(carrier)
	return true


func test_every_event_on_every_carrier_runs_as_the_runtime_does() -> void:
	for event: int in E.size():
		for carrier: StringName in Carriers.ids():
			var cell: String = "%s on %s" % [E.keys()[event], carrier]
			check_equal(Carriers.of(carrier).fires(event), _expected(event, carrier), "%s runs as the runtime does" % cell)


func test_a_timer_on_a_slam_is_wasted_with_its_payload() -> void:
	var built: CompiledStaff = _compile([&"on_timer", &"slam", &"atom"])
	var cast: CompiledCast = built.casts[0]
	check(built.wasted.has(0), "the timer is wasted: %s" % built.wasted)
	check(built.wasted.has(2), "its payload is wasted too: %s" % built.wasted)
	check(not built.wasted.has(1), "the slam still casts")
	check_equal(cast.slots, PackedInt32Array([0, 1, 2]), "the payload is read in this cast, as when it fires")
	check(cast.group.spells[0].payload == null, "no payload hangs on the slam")
	check_equal(cast.group.spells[0].trigger_id, &"", "nor a trigger")
	check(not cast.targets.has(0) and not cast.targets.has(2), "nothing is attached")
	check_equal(cast.mana, 2.0, "the wasted payload costs no mana")
	check_equal(cast.delay, 0.25, "nor time")


func test_the_same_cards_read_alike_whether_the_trigger_fires_or_not() -> void:
	var fires: CompiledStaff = _compile([&"on_hit", &"atom", &"atom", &"atom"])
	var never: CompiledStaff = _compile([&"on_hit", &"decoy", &"atom", &"atom"])
	check_equal(fires.casts.size(), never.casts.size(), "as many casts")
	for n in fires.casts.size():
		check_equal(never.casts[n].slots, fires.casts[n].slots, "cast %d reads the same slots" % n)
	check(never.wasted.has(0), "on hit on a decoy is wasted: %s" % never.wasted)
	check(never.wasted.has(2) and not never.wasted.has(3), "the payload is wasted, the next cast is not")


func test_triggers_that_never_fire_are_wasted() -> void:
	var cells: Array = [
		[&"on_hit", &"decoy"],
		[&"on_wall", &"dash"],
		[&"on_wall", &"rune"],
		[&"on_wall", &"swing"],
		[&"on_hurt", &"slam"],
		[&"on_hurt", &"teleport"],
		[&"on_timer", &"slam"],
		[&"on_timer", &"teleport"],
		[&"on_block", &"familiar"],
		[&"on_kill", &"decoy"],
		[&"on_reaction", &"familiar"],
	]
	for cell: Array in cells:
		var cards: Array[StringName] = [cell[0], cell[1], &"atom"]
		var built: CompiledStaff = _compile(cards)
		check(built.wasted.has(0), "%s on %s is wasted: %s" % [cell[0], cell[1], built.wasted])


func test_triggers_that_fire_are_not_wasted() -> void:
	var cells: Array = [
		[&"on_hit", &"atom"], [&"on_timer", &"atom"], [&"on_hurt", &"rune"], [&"on_timer", &"wall"],
		[&"on_hit", &"beam"], [&"on_hit", &"swing"], [&"on_wall", &"beam"], [&"on_wall", &"swap"],
		[&"on_expire", &"decoy"], [&"on_cast", &"dash"], [&"on_kill", &"slam"],
		[&"on_timer", &"beam"], [&"on_timer", &"dash"], [&"on_timer", &"swing"],
		[&"on_hurt", &"beam"], [&"on_hurt", &"decoy"], [&"on_hurt", &"dash"],
	]
	for cell: Array in cells:
		var cards: Array[StringName] = [cell[0], cell[1], &"atom"]
		var built: CompiledStaff = _compile(cards)
		check(built.wasted.is_empty(), "%s on %s fires: %s" % [cell[0], cell[1], built.wasted])
		var spell: CompiledSpell = built.casts[0].group.spells[0]
		check(spell.payload != null and not spell.payload.is_empty(), "%s on %s carries its payload" % [cell[0], cell[1]])


func test_the_cards_an_event_needs() -> void:
	# A block needs a shield or deflect; a dash's barrier blocks too.
	check(_compile([&"on_block", &"atom", &"atom"]).wasted.has(0), "on block on a bare bolt is wasted")
	check(_compile([&"on_block", &"shield", &"atom", &"atom"]).wasted.is_empty(), "with a shield it fires")
	check(_compile([&"on_block", &"deflect", &"swing", &"atom"]).wasted.is_empty(), "with a deflect on a swing it fires")
	check(_compile([&"on_block", &"shield", &"dash", &"atom"]).wasted.is_empty(), "a dash's barrier blocks")
	# A hit, kill or reaction of a carrier that hits nothing itself comes from its blast (rules R4 F2).
	check(_compile([&"on_hit", &"blast", &"decoy", &"atom"]).wasted.is_empty(), "a decoy with a blast hits")
	check(_compile([&"on_hit", &"decoy", &"atom", &"atom"]).wasted.has(0), "without one it does not")
	check(_compile([&"on_kill", &"blast", &"decoy", &"atom"]).wasted.is_empty(), "a decoy with a blast can kill")
	check(_compile([&"on_kill", &"blast", &"dash", &"atom"]).wasted.is_empty(), "so can a dash with a blast")
	# A reaction needs an element on the hit.
	check(_compile([&"on_reaction", &"atom", &"atom"]).wasted.has(0), "on reaction on a bare bolt is wasted")
	check(_compile([&"on_reaction", &"fire", &"atom", &"atom"]).wasted.is_empty(), "with fire it fires")
	check(_compile([&"on_reaction", &"relay", &"atom", &"atom"]).wasted.is_empty(), "relay takes on elements")
	# A ghost shot flies through walls.
	check(_compile([&"on_wall", &"ghost", &"atom", &"atom"]).wasted.has(0), "on wall on a ghost bolt is wasted")
	# So does a ghost beam (rules R4f).
	check(_compile([&"on_wall", &"ghost", &"beam", &"atom"]).wasted.has(0), "on wall on a ghost beam is wasted")
	check(not _compile([&"on_wall", &"beam", &"atom"]).wasted.has(0), "a plain beam meets walls")
	# A circling shot is a shot (Orbit, docs/milestones/carrier-modifiers.md Part 5): room walls end
	# it, so on wall fires on it, and on hurt fires while it circles.
	check(not _compile([&"on_wall", &"orbit", &"atom", &"atom"]).wasted.has(0), "on wall on a circling shot fires")
	check(_compile([&"on_wall", &"orbit", &"ghost", &"atom", &"atom"]).wasted.has(0), "a ghost one passes the walls")
	check(not _compile([&"on_hurt", &"orbit", &"atom", &"atom"]).wasted.has(0), "on hurt on a circling shot fires")
