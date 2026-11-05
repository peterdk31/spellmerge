extends "res://tests/support/suite.gd"
## A crowd of shots on one body (the sandbox storm, 2026-11-02): a hit that repeats the last one
## Feel gave its flash, hold and sound (the same actor, attacker and kind, with no physics frame
## and no Feel step between) does not do them again; its spray and shake still come. Any of
## those differing, the hit is a hit of its own.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_feel_repeat_hits.gd

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const WizardStandIn := preload("res://tests/gameplay/feel/fixtures/wizard_stand_in.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const FIRST_WIZARD_ID: int = 4
const SOUND: StringName = &"hit_sound"
const STEP: float = 0.0625


class AskingRegistry:
	extends RegistryScript
	## The sound ids Feel asked for, one per sound it would play.
	var asked: Array[StringName] = []

	func get_sound(id: StringName) -> AudioStream:
		asked.append(id)
		return null


var bus: EventsScript
var feel: FeelScript
var registry: AskingRegistry
var actors: ActorSeats.ActorsScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	registry = own(AskingRegistry.new()) as AskingRegistry
	# The cues (a hit's spray is the cue `hit`, S6 2).
	registry.scan()
	feel = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = SOUND
	feel.events = bus
	feel.registry = registry
	actors = own(ActorSeats.table(4, FIRST_WIZARD_ID)) as ActorSeats.ActorsScript
	feel.actors = actors
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)


func _wizard(index: int) -> Actor:
	var wizard: Actor = own(WizardStandIn.new()) as Actor
	wizard.id = FIRST_WIZARD_ID + index
	actors.set_node(wizard.id, wizard)
	root.add_child(wizard)
	return wizard


## What combat sends for one hit: its kind, then the damage.
func _hit(by: int, target: Node, kind: StringName = &"shot") -> void:
	bus.hit_landed.emit(by, target, 5, Vector2.ZERO, kind, -1)
	bus.damage_dealt.emit(by, target, 5, Vector2(4.0, 0.0))


func test_a_repeat_hit_is_not_heard_again_but_still_sprays() -> void:
	var target: Actor = _wizard(1)
	var by: int = FIRST_WIZARD_ID
	_hit(by, target)
	check_equal(registry.asked.size(), 1, "the first hit is heard")
	var sprays: int = feel.flashes_of(FeelScript.KIND_PUFF) + feel.flashes_of(FeelScript.KIND_SPRAY)
	var shake: float = feel.trauma()
	for i in 5:
		_hit(by, target)
	check_equal(registry.asked.size(), 1, "five more by the same attacker in the same frame are not")
	check_equal(feel.flashes_of(FeelScript.KIND_PUFF) + feel.flashes_of(FeelScript.KIND_SPRAY), sprays + 5, "each still sprays")
	check(feel.trauma() >= shake, "and still shakes")


func test_another_attacker_kind_or_step_is_a_hit_of_its_own() -> void:
	var target: Actor = _wizard(1)
	var by: int = FIRST_WIZARD_ID
	_hit(by, target)
	_hit(FIRST_WIZARD_ID + 2, target)
	check_equal(registry.asked.size(), 2, "another attacker is heard")
	_hit(by, target, &"burst")
	check_equal(registry.asked.size(), 3, "another kind is heard")
	feel.step(STEP)
	_hit(by, target, &"burst")
	check_equal(registry.asked.size(), 4, "after Feel stepped the same hit is heard again")
	_hit(by, _wizard(3))
	check_equal(registry.asked.size(), 5, "another body is heard")


## Feel keeps the `Actors` autoload once found (performance, 2026-11-02: every hit asks for it),
## and finds the table again when another takes its place.
func test_the_actor_table_is_kept_while_it_is_there() -> void:
	feel.actors = null
	var auto: ActorSeats.ActorsScript = ActorSeats.autoload()
	check(auto != null, "the tests run with the autoload")
	check(feel._actor_table() == auto, "the autoload")
	check(feel._actor_table() == auto, "and again, kept")
	var index: int = auto.get_index()
	root.remove_child(auto)
	var other: ActorSeats.ActorsScript = ActorSeats.table()
	other.name = "Actors"
	root.add_child(other)
	check(feel._actor_table() == other, "a table that took its place")
	root.remove_child(other)
	other.free()
	check(feel._actor_table() == null, "none while there is none")
	root.add_child(auto)
	root.move_child(auto, index)
	check(feel._actor_table() == auto, "the autoload once it is back")
