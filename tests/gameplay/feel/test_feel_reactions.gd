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
	check_equal(_feel.live_flashes(), 1, "one flash")
	check_equal(_feel.live_labels(), 1, "one name")
	check_equal(_feel.get_child_count() > 0, true, "feel owns them")


func test_the_name_and_flash_end_by_themselves() -> void:
	_bus.reaction_triggered.emit(1, &"rift", Vector2.ZERO)
	for i in 40:
		_feel.step(STEP)
	check_equal(_feel.live_flashes(), 0, "the flash is gone")
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
	check(_feel.live_flashes() <= FeelScript.REACTION_SLOTS, "flashes are capped")
	var particles: int = 0
	for child in _feel.get_children():
		var burst := child as CPUParticles2D
		if burst != null and burst.emitting:
			particles += burst.amount
	check(particles <= FeelScript.PARTICLE_LIMIT, "particles stay under the limit")


func test_an_unknown_reaction_still_shows_and_a_missing_sound_is_silent() -> void:
	_bus.reaction_triggered.emit(0, &"brand_new", Vector2.ZERO)
	check_equal(_feel.live_flashes(), 1, "a flash in the default colour")
	check_equal(_feel.live_labels(), 1, "and its name")


func test_a_reaction_does_not_touch_combat_events() -> void:
	var seen: Array = []
	_bus.damage_dealt.connect(func(_p: int, _t: Node, _a: int, _at: Vector2) -> void: seen.append(1))
	_bus.reaction_triggered.emit(0, &"shatter", Vector2.ZERO)
	check(seen.is_empty(), "feel sends no damage")
