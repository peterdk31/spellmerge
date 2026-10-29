extends "res://tests/support/suite.gd"
## Tests for the table of what a card does on a carrier (`CardRules`, rules R2): every behaviour
## and trigger event against every motion is "runs" or has a reason, the audit's silent cells
## (docs/milestones/M2-rules.md, "Card x carrier") are listed as wasted, and the compiler lists
## exactly what the table says, melee carriers included.
##
## godot --headless --path . --script res://tests/core/test_card_rules_table.gd

const SpellsScript := preload("res://core/spells/spells.gd")

## A registry stand-in with the same question as the real one.
class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _spells: Node
var _fake: FakeRegistry
var _staff: StaffBase


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_spells = own(SpellsScript.new())
	_spells.set("registry", _fake)
	_staff = StaffBase.new()
	_staff.id = &"test"
	_staff.slots = 6
	var bolt := FormBase.new()
	bolt.base_damage = 3
	bolt.speed = 300.0
	_put(bolt, &"payload_bolt")


func _put(card: SpellComponent, id: StringName) -> void:
	card.id = id
	card.display_name = String(id).capitalize()
	_fake.items[id] = card


func _motion_name(motion: int) -> String:
	return String(FormBase.Motion.keys()[motion])


func _carrier(motion: int) -> void:
	var form := FormBase.new()
	form.motion = motion as FormBase.Motion
	form.base_damage = 3
	form.speed = 300.0
	_put(form, &"carrier")


func _modifier(behaviour: int) -> void:
	var modifier := ModifierBase.new()
	modifier.behaviour = behaviour as ModifierBase.Behaviour
	modifier.behaviour_strength = 1.0
	_put(modifier, &"card")


func _trigger(event: int) -> void:
	var trigger := TriggerBase.new()
	trigger.event = event as TriggerBase.Event
	trigger.interval = 1.0
	_put(trigger, &"card")


func _compile(cards: Array[StringName]) -> CompiledStaff:
	return _spells.call("compile_staff", cards, _staff) as CompiledStaff


func test_every_cell_runs_or_gives_a_reason() -> void:
	for behaviour in ModifierBase.Behaviour.values():
		for motion in FormBase.Motion.values():
			var runs: bool = CardRules.behaviour_runs(behaviour, motion)
			var why: String = CardRules.behaviour_why_not(behaviour, motion)
			var where: String = "%s on %s" % [ModifierBase.Behaviour.keys()[behaviour], _motion_name(motion)]
			check_equal(why.is_empty(), runs, "%s: a reason exactly when it is wasted (%s)" % [where, why])
			if not runs:
				check(why.length() > 12 and not why.ends_with("."), "%s has a sentence fragment as its reason: '%s'" % [where, why])
	for event in TriggerBase.Event.values():
		for motion in FormBase.Motion.values():
			var runs: bool = CardRules.trigger_runs(event, motion)
			var why: String = CardRules.trigger_why_not(event, motion)
			check_equal(why.is_empty(), runs, "%s on %s: a reason exactly when it is wasted" % [TriggerBase.Event.keys()[event], _motion_name(motion)])


func test_the_audit_s_silent_cells_are_wasted() -> void:
	var B := ModifierBase.Behaviour
	var M := FormBase.Motion
	var wasted: Array = [
		[B.GROWTH, M.STILL], [B.STICKY, M.ORBIT], [B.LINGER, M.WALL], [B.GHOST, M.RAY], [B.SPIRAL, M.FISSURE],
		[B.MAGNET, M.RAY], [B.RELAY, M.RAY], [B.HEAVY, M.DASH], [B.CHAIN, M.TELEPORT], [B.SIPHON, M.RAIN],
		[B.POSSESS, M.DECOY], [B.SHIELD, M.FAMILIAR], [B.HOLD, M.DASH], [B.HOLD, M.RAIN], [B.HOLD, M.FISSURE],
		[B.RECOIL, M.TELEPORT], [B.BOUNCE, M.STILL], [B.BOUNCE, M.DASH], [B.MIRROR, M.HOOK], [B.MIRROR, M.RAIN],
		[B.BOUNCE, M.SWING], [B.GHOST, M.SLAM], [B.MAGNET, M.SWING], [B.RELAY, M.SLAM], [B.HOMING, M.SWING],
	]
	for cell: Array in wasted:
		check(not CardRules.behaviour_runs(cell[0], cell[1]), "%s on %s is wasted" % [B.keys()[cell[0]], _motion_name(cell[1])])
	var runs: Array = [
		[B.HEAVY, M.SWING], [B.HEAVY, M.SLAM], [B.CHAIN, M.SWING], [B.CHAIN, M.SLAM], [B.MIRROR, M.SWING],
		[B.MIRROR, M.SLAM], [B.SHIELD, M.RAY], [B.SHIELD, M.SLAM], [B.ECHO, M.DASH], [B.BLAST, M.RAIN],
		[B.BOUNCE, M.RAY], [B.GROWTH, M.HOOK], [B.MAGNET, M.WALL],
	]
	for cell: Array in runs:
		check(CardRules.behaviour_runs(cell[0], cell[1]), "%s on %s runs" % [B.keys()[cell[0]], _motion_name(cell[1])])


func test_the_triggers_that_need_what_a_carrier_lacks_are_wasted() -> void:
	var E := TriggerBase.Event
	var M := FormBase.Motion
	for cell: Array in [
		[E.TIMER, M.RAY], [E.HURT, M.FISSURE], [E.TIMER, M.DASH], [E.HURT, M.RAIN], [E.TIMER, M.DECOY],
		[E.HURT, M.FAMILIAR], [E.HIT, M.FAMILIAR], [E.KILL, M.DASH], [E.REACTION, M.RAIN], [E.HIT, M.TELEPORT],
		[E.BLOCK, M.DECOY], [E.WALL, M.DASH], [E.WALL, M.ORBIT], [E.WALL, M.SWING], [E.WALL, M.SLAM],
	]:
		check(not CardRules.trigger_runs(cell[0], cell[1]), "%s on %s is wasted" % [E.keys()[cell[0]], _motion_name(cell[1])])
	for cell: Array in [
		[E.HIT, M.SWING], [E.HIT, M.SLAM], [E.KILL, M.RAY], [E.WALL, M.RAY], [E.WALL, M.STRAIGHT],
		[E.TIMER, M.STRAIGHT], [E.CAST, M.DASH], [E.EXPIRE, M.RAIN], [E.BLOCK, M.DASH], [E.HURT, M.ORBIT],
	]:
		check(CardRules.trigger_runs(cell[0], cell[1]), "%s on %s runs" % [E.keys()[cell[0]], _motion_name(cell[1])])


func test_the_compiler_wastes_exactly_what_the_table_says() -> void:
	for motion in FormBase.Motion.values():
		_carrier(motion)
		for behaviour in ModifierBase.Behaviour.values():
			if behaviour == ModifierBase.Behaviour.NONE:
				continue
			# Shield and deflect also meet each other (a deflect first), tested with deflect.
			if behaviour == ModifierBase.Behaviour.DEFLECT or behaviour == ModifierBase.Behaviour.SHIELD:
				continue
			_modifier(behaviour)
			var staff: CompiledStaff = _compile([&"card", &"carrier"])
			var where: String = "%s on %s" % [ModifierBase.Behaviour.keys()[behaviour], _motion_name(motion)]
			var expected: bool = not CardRules.behaviour_runs(behaviour, motion)
			check_equal(staff.wasted.has(0), expected, "%s: wasted as the table says (%s)" % [where, staff.wasted])
			if expected:
				var reason: String = staff.wasted[0]
				check(reason.contains(CardRules.behaviour_why_not(behaviour, motion)), "%s: the reason is the table's: %s" % [where, reason])


func test_the_compiler_wastes_a_trigger_its_carrier_never_sets_off() -> void:
	# Two bolts after the carrier: a rain or a familiar takes the first as its own payload.
	var payload: Array[StringName] = [&"card", &"carrier", &"payload_bolt", &"payload_bolt"]
	for motion in FormBase.Motion.values():
		_carrier(motion)
		for event in TriggerBase.Event.values():
			_trigger(event)
			var staff: CompiledStaff = _compile(payload)
			var where: String = "%s on %s" % [TriggerBase.Event.keys()[event], _motion_name(motion)]
			check_equal(staff.wasted.has(0), not CardRules.trigger_runs(event, motion), "%s: wasted as the table says" % where)
			if staff.wasted.has(0):
				var spell: CompiledSpell = staff.casts[0].group.spells[0]
				check(spell.payload == null and spell.trigger_id == &"", "%s: no payload is held" % where)
				check(not staff.wasted.has(2), "%s: the card after it is read as itself, not wasted with it" % where)


func test_a_trigger_that_runs_is_unchanged() -> void:
	_carrier(FormBase.Motion.STRAIGHT)
	_trigger(TriggerBase.Event.HIT)
	var staff: CompiledStaff = _compile([&"card", &"carrier", &"payload_bolt"])
	check(staff.wasted.is_empty(), "nothing is wasted: %s" % staff.wasted)
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	check(spell.payload != null and spell.trigger_event == TriggerBase.Event.HIT, "the payload is held")
