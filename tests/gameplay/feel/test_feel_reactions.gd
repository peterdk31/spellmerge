extends "res://tests/support/suite.gd"
## Feel hears `reaction_triggered` (M2 part 8): a flash, the reaction's name rising and a
## sound by id, the same for every player, silent when the sound is missing, and never more
## than the fixed pools hold.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_feel_reactions.gd

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const STEP: float = 0.0625


class AskingRegistry:
	extends RegistryScript
	## The sound ids feel asked for.
	var asked: Array[StringName] = []

	func get_sound(id: StringName) -> AudioStream:
		asked.append(id)
		return null


var _bus: EventsScript
var _feel: FeelScript
var _registry: AskingRegistry


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_registry = own(AskingRegistry.new()) as AskingRegistry
	_feel = own(FeelScript.new()) as FeelScript
	_feel.events = _bus
	_feel.registry = _registry
	_feel.drive_engine = false
	_feel.preset = FeelPresetScript.new()
	root.add_child(_feel)


func test_a_reaction_shows_a_flash_and_a_name() -> void:
	_bus.reaction_triggered.emit(0, &"shatter", Vector2(10.0, 20.0))
	check_equal(_feel.effects_of(FeelScript.KIND_PUFF), 1, "a puff")
	check_equal(_feel.effects_of(FeelScript.KIND_RING_OUT), 1, "and a ring")
	check_equal(_feel.live_labels(), 1, "one name")
	check_equal(_feel.get_child_count() > 0, true, "feel owns them")


func test_the_name_and_flash_end_by_themselves() -> void:
	_bus.reaction_triggered.emit(1, &"rift", Vector2.ZERO)
	for i in 40:
		_feel.step(STEP)
	check_equal(_feel.live_effects(), 0, "the puff and ring are gone")
	check_equal(_feel.live_labels(), 0, "the name is gone")


func test_the_sound_is_asked_by_reaction_id() -> void:
	_bus.reaction_triggered.emit(2, &"thaw", Vector2.ZERO)
	check_equal(_registry.asked.has(&"reaction_thaw"), true, "reaction_thaw was asked for")


func test_every_player_gets_the_same_reaction() -> void:
	for player in 4:
		_bus.reaction_triggered.emit(player, &"flare", Vector2(float(player) * 30.0, 0.0))
	check_equal(_feel.live_labels(), 4, "four names")
	_feel.step(STEP)
	check_equal(_feel.live_labels(), 4, "and they stay for a moment")


func test_a_crowd_of_reactions_stays_inside_the_pools() -> void:
	for i in 60:
		_bus.reaction_triggered.emit(i % 4, &"kindle", Vector2(float(i), 0.0))
	check(_feel.live_labels() <= FeelScript.REACTION_SLOTS, "labels are capped")
	check(_feel.live_effects() <= _feel.effect_slots, "effects stay inside the slots")


func test_an_unknown_reaction_still_shows_and_a_missing_sound_is_silent() -> void:
	_bus.reaction_triggered.emit(0, &"brand_new", Vector2.ZERO)
	check_equal(_feel.effects_of(FeelScript.KIND_PUFF) + _feel.effects_of(FeelScript.KIND_RING_OUT), 2, "a puff and a ring in the default colour")
	check_equal(_feel.live_labels(), 1, "and its name")


func test_a_reaction_does_not_touch_combat_events() -> void:
	var seen: Array = []
	_bus.damage_dealt.connect(func(_p: int, _t: Node, _a: int, _at: Vector2) -> void: seen.append(1))
	_bus.reaction_triggered.emit(0, &"shatter", Vector2.ZERO)
	check(seen.is_empty(), "feel sends no damage")


func test_the_same_reaction_on_the_same_spot_shows_one_name_and_one_sound() -> void:
	for i in 5:
		_bus.reaction_triggered.emit(0, &"flare", Vector2(10.0, 10.0))
		_feel.step(STEP * 0.5)
	check_equal(_feel.live_labels(), 1, "one name, not five")
	check_equal(_registry.asked.count(&"reaction_flare"), 1, "one sound inside the repeat time")
	for i in 10:
		_feel.step(STEP)
	_bus.reaction_triggered.emit(0, &"flare", Vector2(10.0, 10.0))
	check_equal(_registry.asked.count(&"reaction_flare"), 2, "and the sound comes back later")


func test_the_reactions_have_colours_that_differ_at_a_glance() -> void:
	var preset: FeelPresetScript = FeelPresetScript.new()
	var ids: Array = preset.reaction_colors.keys()
	var table: ReactionTable = load("res://content/spells/reactions.tres") as ReactionTable
	var wanted: Array[StringName] = [&"discharge"]
	for row: ReactionRow in table.rows:
		if not wanted.has(row.reaction_id):
			wanted.append(row.reaction_id)
	for id: StringName in wanted:
		check(ids.has(id), "%s has a colour" % id)
	for id: StringName in ids:
		check(wanted.has(id), "%s is a reaction that exists" % id)
	for id: StringName in ids:
		var colour: Color = preset.reaction_colors[id] as Color
		check(maxf(colour.r, maxf(colour.g, colour.b)) >= 0.6, "%s is bright enough for the dark floor" % id)
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			var one: Color = preset.reaction_colors[ids[a]] as Color
			var other: Color = preset.reaction_colors[ids[b]] as Color
			var apart: float = Vector3(one.r - other.r, one.g - other.g, one.b - other.b).length()
			check(apart >= 0.45, "%s and %s are far apart in colour (%.2f)" % [ids[a], ids[b], apart])


func test_a_discharge_asks_for_its_sound_and_the_new_reactions_for_theirs() -> void:
	for id: StringName in [&"discharge", &"overload", &"superconduct"]:
		_bus.reaction_triggered.emit(0, id, Vector2.ZERO)
		check_equal(_registry.asked.has(StringName("reaction_" + String(id))), true, "reaction_%s was asked for" % id)
		check(_feel.preset.reaction_colors.has(id), "%s has a colour of its own" % id)


func test_a_discharge_arc_shows_a_jagged_line_between_both_ends_and_fades() -> void:
	var from := Vector2(10.0, 10.0)
	var to := Vector2(90.0, 10.0)
	_bus.discharge_arc.emit(0, from, to)
	check_equal(_feel.live_arcs(), 1, "one arc")
	var arc: Dictionary = _feel.effect_info(FeelScript.KIND_ARC)
	check_equal(arc["at"], from, "it starts at the struck enemy")
	check((arc["dir"] as Vector2).is_equal_approx(Vector2.RIGHT), "toward the zapped one")
	check_equal(arc["zoom"], 20, "as long as the gap: 80 px is 20 steps of 4 (the shader jags it)")
	check_equal(arc["core"], _feel.preset.reaction_colors[&"discharge"], "in the discharge's colour")
	check((arc["look"] as int) & FeelScript.EXACT != 0, "exactly that colour")
	for i in 20:
		_feel.step(STEP)
	check_equal(_feel.live_arcs(), 0, "the arc ends by itself")


func test_a_crowd_of_arcs_stays_inside_the_slots() -> void:
	_feel.set_effect_slots(EffectSlots.MIN)
	for i in 100:
		_bus.discharge_arc.emit(i % 4, Vector2.ZERO, Vector2(20.0 + float(i), 5.0))
	check_equal(_feel.live_arcs(), _feel.effect_slots, "arcs fill the slots, no more")
	var before: int = _feel.live_arcs()
	_bus.discharge_arc.emit(0, Vector2(3.0, 3.0), Vector2(3.0, 3.0))
	check_equal(_feel.live_arcs(), before, "an arc of no length shows nothing")


func test_a_reaction_keeps_its_own_colour_exactly() -> void:
	_bus.reaction_triggered.emit(0, &"rift", Vector2(5.0, 5.0))
	var want: Color = _feel.preset.reaction_colors[&"rift"] as Color
	for kind: int in [FeelScript.KIND_PUFF, FeelScript.KIND_RING_OUT]:
		var shown: Dictionary = _feel.effect_info(kind)
		check_equal(shown["core"], want, "kind %d is in the reaction's colour" % kind)
		check((shown["look"] as int) & FeelScript.EXACT != 0, "kind %d takes it exactly, not the nearest palette ramp" % kind)


