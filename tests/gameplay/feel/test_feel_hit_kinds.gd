extends "res://tests/support/suite.gd"
## Hit kinds in gameplay/feel (staffs B3): every kind of hit has a default stop, shake and sound,
## a wizard hit by their own spell gets a ring of its own on the frame of the hit, a heal shows a
## soft green ring with no stop and no shake, and a wizard downed by their own spell is told so.
## Feel only reacts: none of this changes damage.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const WizardStandIn := preload("res://tests/gameplay/feel/fixtures/wizard_stand_in.gd")

## The stand-in wizards' actor ids are their seat plus this, apart from the seats, so a test sees
## that a self-hit is told by the actor id (hits are keyed by caster, actors G3b).
const FIRST_WIZARD_ID: int = 4


## What combat tells Feel about a downed wizard.
class FakeCombat:
	extends Node
	var note: String = ""
	var wizard: Node2D = null

	func downed_note(_index: int) -> String:
		return note

	func wizard_of(_index: int) -> Node2D:
		return wizard


var bus: EventsScript
var feel: FeelScript
var preset: FeelPresetScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	preset = FeelPresetScript.new()
	preset.hit_sound = &""
	preset.death_sound = &""
	preset.downed_sound = &""
	preset.self_hit_sound = &""
	preset.heal_sound = &""
	feel.events = bus
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)


func _enemy() -> Node2D:
	var enemy: Node2D = own(Node2D.new()) as Node2D
	root.add_child(enemy)
	return enemy


func _wizard(index: int) -> Node2D:
	var wizard: Node2D = own(WizardStandIn.new()) as Node2D
	wizard.set("index", index)
	wizard.set("actor_id", FIRST_WIZARD_ID + index)
	root.add_child(wizard)
	return wizard


## What combat sends for one hit: its kind, then the damage.
func _hit(player: int, target: Node, kind: StringName) -> void:
	bus.hit_landed.emit(player, target, 5, Vector2.ZERO, kind)
	bus.damage_dealt.emit(player, target, 5, Vector2.ZERO)


func test_a_burst_stops_the_game_longer_and_shakes_harder_than_a_shot() -> void:
	_hit(0, _enemy(), &"shot")
	var shot_stop: float = feel.stop_left
	var shot_shake: float = feel.trauma()
	check(shot_stop > 0.0 and shot_shake > 0.0, "a shot stops and shakes")
	feel.stop_left = 0.0
	feel.rest_left = 0.0
	feel._trauma = 0.0
	_hit(0, _enemy(), &"burst")
	check(feel.stop_left > shot_stop, "a burst stops longer")
	check(feel.trauma() > shot_shake, "and shakes harder")


func test_damage_over_time_neither_stops_nor_shakes() -> void:
	_hit(0, _enemy(), &"status")
	check_equal(feel.stop_left, 0.0, "no stop")
	check_equal(feel.trauma(), 0.0, "no shake")


func test_a_beam_is_gentler_than_a_shot() -> void:
	_hit(0, _enemy(), &"ray")
	check(feel.stop_left > 0.0 and feel.stop_left < preset.hit_stop_seconds, "a shorter stop")


func test_a_hit_with_no_kind_feels_like_a_shot() -> void:
	bus.damage_dealt.emit(0, _enemy(), 5, Vector2.ZERO)
	check_equal(feel.stop_left, preset.hit_stop_seconds, "the old default")


func test_a_stale_kind_is_not_applied_to_a_later_hit() -> void:
	var other: Node2D = _enemy()
	bus.hit_landed.emit(0, other, 5, Vector2.ZERO, &"burst")
	bus.damage_dealt.emit(0, _enemy(), 5, Vector2.ZERO)
	check_equal(feel.stop_left, preset.hit_stop_seconds, "the kind belongs to the target it was sent for")


func test_a_wizard_hit_by_their_own_spell_gets_a_ring() -> void:
	var wizard: Node2D = _wizard(1)
	var before: int = feel.effects_of(FeelScript.KIND_RING_OUT)
	_hit(FIRST_WIZARD_ID + 1, wizard, &"shot")
	check(feel.effects_of(FeelScript.KIND_RING_OUT) > before, "a ring on the hit's frame")


func test_a_wizard_hit_by_another_player_or_an_enemy_gets_no_self_ring() -> void:
	var wizard: Node2D = _wizard(1)
	var before: int = feel.effects_of(FeelScript.KIND_RING_OUT)
	_hit(FIRST_WIZARD_ID + 2, wizard, &"shot")
	_hit(-1, wizard, &"shot")
	_hit(1, wizard, &"shot")  # the seat's number is not the wizard's caster
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT), before, "only a self-hit has the ring")


func test_a_self_inflicted_burn_tick_gets_no_ring() -> void:
	var wizard: Node2D = _wizard(1)
	var before: int = feel.effects_of(FeelScript.KIND_RING_OUT)
	_hit(FIRST_WIZARD_ID + 1, wizard, &"status")
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT), before, "a burn tick is not a hit: no self-hit ring")


func test_a_heal_shows_a_ring_without_stop_or_shake() -> void:
	var wizard: Node2D = _wizard(0)
	var before: int = feel.effects_of(FeelScript.KIND_RING_OUT)
	bus.heal_dealt.emit(1, wizard, 5, Vector2(10.0, 10.0))
	check(feel.effects_of(FeelScript.KIND_RING_OUT) > before, "a ring")
	check_equal(feel.stop_left, 0.0, "no stop")
	check_equal(feel.trauma(), 0.0, "no shake")


func test_a_wizard_downed_by_their_own_spell_is_told_so() -> void:
	var wizard: Node2D = _wizard(0)
	var fake := own(FakeCombat.new()) as FakeCombat
	fake.note = "downed by your own Blast"
	fake.wizard = wizard
	feel.combat = fake
	bus.player_downed.emit(0)
	check_equal(feel.live_labels(), 1, "a note rises over the wizard")


func test_no_note_when_an_enemy_downed_the_wizard() -> void:
	var fake := own(FakeCombat.new()) as FakeCombat
	fake.wizard = _wizard(0)
	feel.combat = fake
	bus.player_downed.emit(0)
	check_equal(feel.live_labels(), 0, "an empty note shows nothing")


func test_the_note_fades_away() -> void:
	var fake := own(FakeCombat.new()) as FakeCombat
	fake.note = "downed by your own Blast"
	fake.wizard = _wizard(0)
	feel.combat = fake
	bus.player_downed.emit(0)
	for i in 80:
		feel.step(0.0625)
	check_equal(feel.live_labels(), 0, "gone after its seconds")
