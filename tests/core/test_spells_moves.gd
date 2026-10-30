extends "res://tests/support/suite.gd"
## Tests for the moves, areas and refunds of the staffs (B2d): teleport, pull, swap and recoil ask
## the player and ai to move through the events (the way and the distance); the end of a dash, a
## teleport or a pull whose hit spent its shot is the carrier's end point (blast, on expire); blast asks combat for an area hit where a shot or beam
## ends; siphon refunds mana per hit. It runs a real projectile manager and event bus, stepped by
## hand, with cards built in code.
##
## godot --headless --path . --script res://tests/core/test_spells_moves.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _fake: FakeRegistry
var _spells: SpellsScript
var _mgr: ManagerScript
var _bus: EventsScript
## Every caster_move_requested as [player, mode, move, seconds, tag].
var _moves: Array = []
## Every target_move_requested as [player, target, to].
var _target_moves: Array = []
## Every blast (its `cue_shown`) as [player, position, radius].
var _areas: Array = []
## Every mana_refund_requested as [player, amount].
var _refunds: Array = []


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	# Four wizards seated 0-3 at actor ids 0-3, as the tests name their casters.
	_mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_mgr, _bus)
	_mgr.set_anchor(0, Vector2.ZERO)
	_moves.clear()
	_target_moves.clear()
	_areas.clear()
	_refunds.clear()
	_bus.caster_move_requested.connect(func(player: int, mode: StringName, to: Vector2, seconds: float, tag: int) -> void:
		_moves.append([player, mode, to, seconds, tag]))
	_bus.target_move_requested.connect(func(player: int, target: Node, to: Vector2) -> void:
		_target_moves.append([player, target, to]))
	_bus.cue_shown.connect(func(player: int, _cue: StringName, at: Vector2, _direction: Vector2, radius: float, _tint: Color, _look: int) -> void: _areas.append([player, at, radius]))
	_bus.mana_refund_requested.connect(func(player: int, amount: float) -> void:
		_refunds.append([player, amount]))
	var bolt: FormBase = _form(&"bolt", 300.0, 1.0)
	bolt.base_damage = 10
	var teleport: FormBase = _form(&"teleport", 400.0, 0.25)
	teleport.carrier = &"teleport"
	var dash: FormBase = _form(&"dash", 400.0, 0.2)
	dash.carrier = &"dash"
	_modifier(&"pull", ModifierBase.Behaviour.PULL, 1.0)
	var swap: FormBase = _form(&"swap", 300.0, 1.0)
	swap.carrier = &"swap"
	var beam: FormBase = _form(&"beam", 0.0, 0.2)
	beam.carrier = &"beam"
	beam.ray_length = 200.0
	beam.radius = 6.0
	_modifier(&"blast", ModifierBase.Behaviour.BLAST, 30.0)
	_modifier(&"recoil", ModifierBase.Behaviour.RECOIL, 20.0)
	_modifier(&"siphon", ModifierBase.Behaviour.SIPHON, 2.0)
	_modifier(&"mirror", ModifierBase.Behaviour.MIRROR, 1.0)
	_modifier(&"chain", ModifierBase.Behaviour.CHAIN, 1.0)
	var piercing := ModifierBase.new()
	piercing.extra_pierce = 2
	_put(piercing, &"pierce")
	var wall: FormBase = _form(&"wall", 0.0, 0.5)
	wall.carrier = &"wall"
	wall.shots = 3
	wall.spread = 10.0
	wall.radius = 4.0
	_trigger(&"on_expire", TriggerBase.Event.EXPIRE)
	var spark: FormBase = _form(&"spark", 100.0, 1.0)
	spark.base_damage = 3


func _put(component: SpellComponent, id: StringName) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = 1
	_fake.items[id] = component


func _form(id: StringName, speed: float, lifetime: float) -> FormBase:
	var form := FormBase.new()
	form.base_damage = 5
	form.speed = speed
	form.lifetime = lifetime
	form.mana_cost = 2.0
	_put(form, id)
	return form


func _modifier(id: StringName, behaviour: ModifierBase.Behaviour, strength: float) -> void:
	var modifier := ModifierBase.new()
	modifier.behaviour = behaviour
	modifier.behaviour_strength = strength
	_put(modifier, id)


func _trigger(id: StringName, event: TriggerBase.Event) -> TriggerBase:
	var trigger := TriggerBase.new()
	trigger.event = event
	_put(trigger, id)
	return trigger


func _build(player: int, cards: Array[StringName]) -> int:
	StaffKit.build(_spells, player, 0, cards)
	return _spells.current_tag(player, 0, 0)


func _target(position: Vector2) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, 10.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
	return node


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


func _cast(player: int = 0) -> float:
	return _spells.cast_staff(player, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)


func test_teleport_asks_for_a_blink_along_the_aim() -> void:
	var tag: int = _build(0, [&"teleport"])
	check(_cast() >= 0.0, "the cast went through")
	check_equal(_moves.size(), 1, "one move asked for")
	check(_moves.size() == 1 and _moves[0][1] == &"teleport" and _moves[0][2].is_equal_approx(Vector2(100, 0)) and _moves[0][4] == tag, "a blink of speed x lifetime: %s" % [_moves])
	check_equal(_mgr.get_count(), 0, "no shot leaves the caster")


func test_a_blast_teleport_explodes_on_arrival() -> void:
	var tag: int = _build(0, [&"blast", &"teleport"])
	_cast()
	check_equal(_areas.size(), 0, "nothing before the player has arrived")
	_bus.caster_move_finished.emit(0, &"teleport", Vector2(90, 5), tag)
	check_equal(_areas.size(), 1, "one explosion")
	check(_areas.size() == 1 and _areas[0][1].is_equal_approx(Vector2(90, 5)) and is_equal_approx(_areas[0][2], 30.0), "where the wizard arrived, as wide as the blast: %s" % [_areas])


func test_an_on_expire_teleport_fires_its_payload_on_arrival() -> void:
	var tag: int = _build(0, [&"on_expire", &"teleport", &"spark"])
	_cast()
	check_equal(_mgr.get_count(), 0, "nothing yet")
	_bus.caster_move_finished.emit(0, &"teleport", Vector2(90, 5), tag)
	check_equal(_mgr.get_count(), 1, "the payload left the arrival point")
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot):
			check(_mgr.get_position_of(slot).is_equal_approx(Vector2(90, 5)), "from the arrival")
			check(_mgr.get_velocity_of(slot).normalized().is_equal_approx(Vector2.RIGHT), "along the blink")


func test_a_dash_ends_with_its_blast_too() -> void:
	var tag: int = _build(0, [&"blast", &"dash"])
	_cast()
	_bus.caster_move_finished.emit(0, &"dash", Vector2(70, 0), tag)
	check_equal(_areas.size(), 1, "the dash explodes where it stops")


func test_a_move_that_ended_for_another_player_or_mode_is_ignored() -> void:
	var tag: int = _build(0, [&"blast", &"teleport"])
	_cast()
	_bus.caster_move_finished.emit(1, &"teleport", Vector2(90, 0), tag)
	_bus.caster_move_finished.emit(0, &"recoil", Vector2(90, 0), tag)
	_bus.caster_move_finished.emit(0, &"teleport", Vector2.INF, tag)
	_bus.caster_move_finished.emit(0, &"teleport", Vector2(90, 0), 0)
	check_equal(_areas.size(), 0, "none of them is the end of this teleport")


func test_a_move_of_a_forgotten_build_does_nothing() -> void:
	var tag: int = _build(0, [&"blast", &"teleport"])
	_cast()
	_build(0, [&"bolt"])
	for i in SpellLimits.GENERATIONS:
		_build(0, [&"bolt"])
	_bus.caster_move_finished.emit(0, &"teleport", Vector2(90, 0), tag)
	check_equal(_areas.size(), 0, "its tag means nothing any more")


func test_pull_pulls_the_caster_to_where_it_hits() -> void:
	var tag: int = _build(0, [&"pull", &"bolt"])
	_target(Vector2(60, 0))
	_cast()
	_tick(30)
	check_equal(_moves.size(), 1, "one pull")
	check(_moves.size() == 1 and _moves[0][1] == &"pull" and absf(_moves[0][2].x - 50.0) < 12.0 and _moves[0][4] == tag, "to the hit point: %s" % [_moves])
	check(_moves.size() == 1 and is_equal_approx(_moves[0][3], SpellLimits.PULL_SECONDS), "over the pull's time")


func test_a_pull_that_misses_pulls_nothing() -> void:
	_build(0, [&"blast", &"pull", &"bolt"])
	_cast()
	_tick(90)
	check_equal(_moves.size(), 0, "no pull")
	# Every carrier blasts at its end point (rules R1d): a pulling shot that misses, where it ended.
	check_equal(_areas.size(), 1, "one blast, where the shot ended")


func test_a_blast_pull_explodes_on_arrival_not_at_the_hit() -> void:
	var tag: int = _build(0, [&"blast", &"pull", &"bolt"])
	_target(Vector2(60, 0))
	_cast()
	_tick(30)
	check_equal(_areas.size(), 0, "not where the shot struck")
	_bus.caster_move_finished.emit(0, &"pull", Vector2(45, 0), tag)
	check(_areas.size() == 1 and _areas[0][1].is_equal_approx(Vector2(45, 0)), "where the wizard arrived: %s" % [_areas])


func test_swap_trades_places_with_the_target() -> void:
	_mgr.set_anchor(0, Vector2(-10, 4))
	var tag: int = _build(0, [&"swap"])
	var enemy: Node2D = _target(Vector2(60, 0))
	_spells.cast_staff(0, 0, Vector2(-10, 4), Vector2.RIGHT, 100.0)
	_tick(30)
	check_equal(_target_moves.size(), 1, "the target is moved")
	check(_target_moves.size() == 1 and _target_moves[0][1] == enemy and _target_moves[0][2].is_equal_approx(Vector2(-10, 4)), "to where the caster stood: %s" % [_target_moves])
	check(_moves.size() == 1 and _moves[0][1] == &"swap" and _moves[0][2].is_equal_approx(Vector2(70, -4)) and _moves[0][4] == tag, "and the caster to the target (the way from its anchor): %s" % [_moves])


func test_a_swap_with_no_caster_place_moves_nobody() -> void:
	_mgr.clear_anchor(0)
	_build(0, [&"swap"])
	_target(Vector2(60, 0))
	_cast()
	_tick(30)
	check_equal(_target_moves.size() + _moves.size(), 0, "without knowing where the caster is, nothing is traded")


func test_recoil_pushes_the_caster_back() -> void:
	var tag: int = _build(0, [&"recoil", &"bolt"])
	_cast()
	check_equal(_moves.size(), 1, "one push")
	check(_moves.size() == 1 and _moves[0][1] == &"recoil" and _moves[0][2].is_equal_approx(Vector2(-20, 0)) and _moves[0][4] == tag, "against the aim by its strength: %s" % [_moves])
	check_equal(_mgr.get_count(), 1, "the bolt still flew")


func test_mirror_cancels_the_recoil() -> void:
	_build(0, [&"mirror", &"recoil", &"bolt"])
	_cast()
	check_equal(_moves.size(), 2, "a push each way")
	var sum: Vector2 = Vector2.ZERO
	for move in _moves:
		sum += move[2]
	check(sum.is_zero_approx(), "they cancel: %s" % [_moves])


func test_a_payload_does_not_recoil_the_caster() -> void:
	_build(0, [&"recoil", &"on_expire", &"bolt", &"spark"])
	_cast()
	_tick(90)
	var pushes: int = 0
	for move in _moves:
		if move[1] == &"recoil":
			pushes += 1
	check_equal(pushes, 1, "only the cast's own firing pushes")


func test_a_blast_shot_explodes_where_it_hits() -> void:
	var tag: int = _build(0, [&"blast", &"bolt"])
	_target(Vector2(60, 0))
	_cast()
	_tick(30)
	check_equal(_areas.size(), 1, "one explosion")
	check(_areas.size() == 1 and absf(_areas[0][1].x - 50.0) < 12.0 and is_equal_approx(_areas[0][2], 30.0), "at the hit: %s" % [_areas])


func test_a_blast_shot_explodes_where_it_expires() -> void:
	_build(0, [&"blast", &"bolt"])
	_cast()
	_tick(90)
	check_equal(_areas.size(), 1, "one explosion at its end")
	check(_areas.size() == 1 and _areas[0][1].x > 200.0, "far out: %s" % [_areas])


func test_a_blast_beam_explodes_at_its_end() -> void:
	_build(0, [&"blast", &"beam"])
	_cast()
	check_equal(_areas.size(), 0, "nothing while the beam is on")
	_tick(30)
	check_equal(_areas.size(), 1, "one explosion when its life is over")
	check(_areas.size() == 1 and absf(_areas[0][1].x - 200.0) < 1.0, "at the end of the beam: %s" % [_areas])


func test_a_shot_without_blast_asks_for_no_area_hit() -> void:
	_build(0, [&"bolt"])
	_target(Vector2(60, 0))
	_cast()
	_tick(30)
	check_equal(_areas.size(), 0, "a plain hit is no area")


func test_siphon_refunds_mana_for_each_hit() -> void:
	_build(0, [&"siphon", &"beam"])
	_target(Vector2(60, 0))
	_cast()
	check_equal(_refunds, [[0, 2.0]], "the beam's hit paid back its strength")


func test_siphon_refunds_mana_for_a_shot_hit() -> void:
	_build(0, [&"siphon", &"bolt"])
	_target(Vector2(60, 0))
	_cast()
	_tick(30)
	check_equal(_refunds, [[0, 2.0]], "the bolt's hit paid back its strength")


func test_a_miss_refunds_nothing() -> void:
	_build(0, [&"siphon", &"bolt"])
	_cast()
	_tick(90)
	check_equal(_refunds.size(), 0, "no hit, no mana")


func test_a_piercing_shot_does_not_blast_at_a_hit_it_survives() -> void:
	_build(0, [&"blast", &"pierce", &"bolt"])
	_target(Vector2(60, 0))
	_cast()
	_tick(30)
	check_equal(_areas.size(), 0, "still flying: no explosion at the hit")
	_tick(60)
	check_equal(_areas.size(), 1, "one explosion where it finally expires")


func test_a_chain_shot_blasts_where_each_jump_ends() -> void:
	_build(0, [&"blast", &"chain", &"bolt"])
	_target(Vector2(60, 0))
	_target(Vector2(60, 40))
	_cast()
	_tick(60)
	# The bolt's hit jumps on, and so does its blast's hit on the same body (rules R4 F2): the jump
	# shot and the jump of the blast each blast where they end.
	check_equal(_areas.size(), 3, "the bolt, its jump shot and its blast's jump: %s" % [_areas])


func test_a_wall_blasts_once_when_it_expires() -> void:
	_build(0, [&"blast", &"wall"])
	_cast()
	_tick(60)
	check_equal(_areas.size(), 1, "one wall, one explosion (rules R4 F6)")


func test_the_move_heading_is_the_last_asked_move() -> void:
	var tag: int = _build(0, [&"on_expire", &"teleport", &"spark"])
	_cast()
	_tick(120)
	check(_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.UP, 100.0) >= 0.0, "the second cast went off")
	_bus.caster_move_finished.emit(0, &"teleport", Vector2(90, 5), tag)
	var seen: int = 0
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot):
			seen += 1
			check(_mgr.get_velocity_of(slot).normalized().is_equal_approx(Vector2.UP), "the later move's heading wins")
	check(seen > 0, "the payload left")


func test_a_pull_works_for_player_two() -> void:
	_mgr.set_anchor(2, Vector2(0, 100))
	var tag: int = _build(2, [&"on_expire", &"pull", &"bolt", &"spark"])
	_target(Vector2(60, 100))
	_spells.cast_staff(2, 0, Vector2(0, 100), Vector2.RIGHT, 100.0)
	_tick(30)
	check(_moves.size() == 1 and _moves[0][0] == 2 and _moves[0][1] == &"pull" and _moves[0][4] == tag, "the pull is player 2's: %s" % [_moves])
	_bus.caster_move_finished.emit(2, &"pull", Vector2(45, 100), tag)
	var found: bool = false
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot) and SpellTag.caster_of(_mgr.get_tag_of(slot)) == 2 and _mgr.get_position_of(slot).is_equal_approx(Vector2(45, 100)):
			found = true
	check(found, "its payload is player 2's and leaves the arrival point")


## Regression (rules R4a): a hook with pierce left fired `on expire` at the arrival and again
## where the shot ended. Its end is the shot's: the end of its flight (a pulling shot's now).
func test_a_piercing_pull_ends_once_where_its_shot_ends() -> void:
	var tag: int = _build(0, [&"on_expire", &"pierce", &"pull", &"bolt", &"spark"])
	var spark: int = _spells.current_tag(0, 0, 1)
	_target(Vector2(60, 0))
	_cast()
	_tick(30)
	check(_moves.size() == 1 and _moves[0][1] == &"pull", "the hit pulls: %s" % [_moves])
	_bus.caster_move_finished.emit(0, &"pull", Vector2(45, 0), tag)
	check_equal(_spells.live_shots(spark), 0, "nothing goes off where the caster arrives")
	_tick(35)
	check_equal(_spells.live_shots(spark), 1, "the payload goes off once, where the shot ended")


func test_a_swap_reads_the_casters_own_anchor() -> void:
	_mgr.set_anchor(0, Vector2(-500, 0))
	_mgr.set_anchor(3, Vector2(-10, 4))
	_build(3, [&"swap"])
	var enemy: Node2D = _target(Vector2(60, 0))
	_spells.cast_staff(3, 0, Vector2(-10, 4), Vector2.RIGHT, 100.0)
	_tick(30)
	check(_target_moves.size() == 1 and _target_moves[0][0] == 3 and _target_moves[0][1] == enemy and _target_moves[0][2].is_equal_approx(Vector2(-10, 4)), "player 3's place, not player 0's: %s" % [_target_moves])


func test_a_teleport_of_player_three_ignores_other_players_arrivals() -> void:
	var tag: int = _build(3, [&"on_expire", &"teleport", &"spark"])
	_spells.cast_staff(3, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)
	check(_moves.size() == 1 and _moves[0][0] == 3 and _moves[0][1] == &"teleport", "asked for player 3: %s" % [_moves])
	_bus.caster_move_finished.emit(0, &"teleport", Vector2(90, 0), tag)
	check_equal(_mgr.get_count(), 0, "another player's arrival fires nothing")
	_bus.caster_move_finished.emit(3, &"teleport", Vector2(90, 0), tag)
	check_equal(_mgr.get_count(), 1, "its own does")


# --- Fixed move distances and the payload's caster (owner, 2026-10-27) ------------------------

## A dash card that moves a fixed 48 px at 240 px/s, a teleport that blinks 64 px, a timer
## trigger that fires once after 0.25 s, an orbit, and faster (speed x1.5).
func _distance_cards() -> void:
	var short: FormBase = _form(&"short", 240.0, 0.25)
	short.carrier = &"dash"
	short.ray_length = 48.0
	var blink: FormBase = _form(&"blink", 400.0, 0.25)
	blink.carrier = &"teleport"
	blink.ray_length = 64.0
	var timer: TriggerBase = _trigger(&"timer", TriggerBase.Event.TIMER)
	timer.interval = 0.25
	var orbit: FormBase = _form(&"ring", 3.0, 1.0)
	orbit.carrier = &"orbit"
	orbit.orbit_radius = 20.0
	var faster := ModifierBase.new()
	faster.speed_mult = 1.5
	_put(faster, &"faster")
	var homing := ModifierBase.new()
	homing.behaviour = ModifierBase.Behaviour.HOMING
	homing.behaviour_strength = 3.0
	homing.behaviour_reach = 160.0
	_put(homing, &"homing")


## The live shots that are not `slot`.
func _others(slot: int) -> Array[int]:
	var out: Array[int] = []
	for at in _mgr.get_cap():
		if at != slot and _mgr.is_alive(at):
			out.append(at)
	return out


func test_a_dash_moves_its_card_distance_and_faster_only_makes_it_sooner() -> void:
	_distance_cards()
	_build(0, [&"short"])
	_cast(0)
	check_equal(_moves.size(), 1, "one move")
	check(_moves[0][2].is_equal_approx(Vector2(48.0, 0.0)), "48 px, the card's distance: %s" % _moves[0][2])
	check(is_equal_approx(_moves[0][3], 0.2), "at 240 px/s it takes 0.2 s: %s" % _moves[0][3])
	_mgr.set_anchor(1, Vector2.ZERO)
	_build(1, [&"faster", &"short"])
	_cast(1)
	check_equal(_moves.size(), 2, "a second move")
	check(_moves[1][2].is_equal_approx(Vector2(48.0, 0.0)), "faster goes no farther: %s" % _moves[1][2])
	check(is_equal_approx(_moves[1][3], 0.2 / 1.5), "it gets there sooner: %s" % _moves[1][3])


func test_a_dash_is_drawn_where_its_caster_goes() -> void:
	# The owner (2026-10-28): the dash look went another way than the wizard. Its streaks and cards
	# are a trail that follows the caster's anchor for the dash's time.
	_distance_cards()
	_build(0, [&"short"])
	_cast(0)
	check_equal(_mgr.get_trail_count(), 1, "the dash opens a trail on its caster")
	_mgr.set_anchor(0, Vector2(0.0, 30.0))
	for i in 4:
		_mgr.step(1.0 / 60.0)
	check(_mgr.get_trail_point(0, 0).y > 20.0, "which follows the wizard, wherever it goes")
	_build(0, [&"blink"])
	_cast(0)
	check_equal(_mgr.get_trail_count(), 1, "a teleport opens none")


func test_a_dash_keeps_its_own_way_when_its_move_ends_another_dash() -> void:
	# A dash's request to move may end another dash at once (here wizard 1's, when wizard 0 asks):
	# that end fires its `on expire` payload, a dash too, before the new one is drawn. The dash
	# carrier once kept the way of the move it was launching on itself, so the payload's launch
	# wrote its own way over the new dash's.
	_distance_cards()
	_mgr.set_anchor(1, Vector2.ZERO)
	var first: int = _build(1, [&"on_expire", &"short", &"short"])
	_build(0, [&"short"])
	var shown: Array[Vector2] = []
	var ended: Array[bool] = [false]
	_bus.form_shown.connect(func(caster: int, form: StringName, _origin: Vector2, direction: Vector2, _length: float, _tint: Color, _look: int) -> void:
		if form == &"dash" and caster == 0:
			shown.append(direction))
	_bus.caster_move_requested.connect(func(player: int, _mode: StringName, _to: Vector2, _seconds: float, _tag: int) -> void:
		if player == 0 and not ended[0]:
			ended[0] = true
			_bus.caster_move_finished.emit(1, &"dash", Vector2(48.0, 0.0), first))
	_spells.cast_staff(1, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)
	check(_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.DOWN, 100.0) >= 0.0, "wizard 0's dash is cast")
	check(ended[0], "and it ended wizard 1's on the way")
	check(shown.size() == 1 and shown[0].is_equal_approx(Vector2.DOWN), "wizard 0's dash is drawn along its own way, down: %s" % [shown])


func test_a_teleport_blinks_its_card_distance() -> void:
	_distance_cards()
	_build(0, [&"blink"])
	_cast(0)
	check(_moves.size() == 1 and _moves[0][1] == &"teleport" and _moves[0][2].is_equal_approx(Vector2(64.0, 0.0)), "64 px, the card's distance: %s" % [_moves])


func test_a_dash_in_a_payload_moves_the_shot_that_fired_it_not_the_wizard() -> void:
	_distance_cards()
	_build(0, [&"timer", &"bolt", &"short"])
	_cast(0)
	var bolt: int = _others(-1)[0]
	_tick(60)
	check_equal(_moves.size(), 0, "the wizard is not asked to move")
	check(_mgr.is_alive(bolt), "the bolt still flies")
	# One second at 300 px/s, plus 48 px for each of the timer's three fires (every 0.25 s).
	check(absf(_mgr.get_position_of(bolt).x - (300.0 + 3.0 * 48.0)) < 6.0, "the bolt dashed 48 px three times: %s" % _mgr.get_position_of(bolt))


func test_a_homing_dash_tells_the_wizard_how_to_turn_and_a_plain_one_does_not() -> void:
	_distance_cards()
	_build(0, [&"homing", &"short"])
	_cast(0)
	var homing: Homing = CarrierDash.of(_spells).move_homing(0)
	check(is_equal_approx(homing.turn, 3.0) and is_equal_approx(homing.reach, 160.0), "the card's turn rate and reach: %s, %s" % [homing.turn, homing.reach])
	_mgr.set_anchor(1, Vector2.ZERO)
	_build(1, [&"short"])
	_cast(1)
	check(not CarrierDash.of(_spells).move_homing(1).homes(), "a plain dash does not home")
	_build(0, [&"short"])
	_tick(30)
	_cast(0)
	check(not CarrierDash.of(_spells).move_homing(0).homes(), "nor does the next plain dash of the same wizard")


func test_a_homing_teleport_bends_its_way_toward_a_target_and_blinks_its_distance() -> void:
	_distance_cards()
	# Further than the blink's 64 px: it turns toward the target and keeps its distance.
	var target := _target(Vector2(100.0, 50.0))
	_build(0, [&"homing", &"blink"])
	_cast(0)
	check_equal(_moves.size(), 1, "one move")
	var to: Vector2 = _moves[0][2]
	check(to.y > 1.0, "bent toward the target, off the aim: %s" % to)
	check(is_equal_approx(to.length(), 64.0), "still its card's distance: %s" % to.length())
	check(absf(to.angle_to(target.global_position)) < 0.01, "straight at it: %s" % to)


func test_a_homing_teleport_lands_at_the_edge_of_a_target_within_its_distance() -> void:
	_distance_cards()
	var target := _target(Vector2(40.0, 10.0))
	_build(0, [&"homing", &"blink"])
	_cast(0)
	var to: Vector2 = _moves[0][2]
	var want: float = target.global_position.length() - 10.0 - SpellLimits.LAND_CLEARANCE
	check(absf(to.length() - want) < 0.01, "it stops at the target's edge, not past it: %s px, want %s" % [to.length(), want])
	check(absf(to.angle_to(target.global_position)) < 0.01, "straight at it")


func test_a_chain_of_homing_teleports_hops_on_to_another_enemy() -> void:
	_distance_cards()
	# The second enemy is out of reach from the start, and in reach from beside the first.
	var first := _target(Vector2(50.0, 0.0))
	var second := _target(Vector2(190.0, 30.0))
	# Each cast picks with its own seed; every one must go on to the second.
	for cast in 8:
		_moves.clear()
		var tag: int = _build(0, [&"homing", &"on_expire", &"blink", &"homing", &"blink"])
		var cost: float = _cast(0)
		check(cost != SpellsScript.REFUSED and _moves.size() == 1, "cast %d: one hop asked for (cost %s, %d moves)" % [cast, cost, _moves.size()])
		if _moves.size() != 1:
			return
		var landed: Vector2 = _moves[0][2]
		check(landed.is_equal_approx(Vector2(50.0 - 10.0 - SpellLimits.LAND_CLEARANCE, 0.0)), "the first hop lands beside the first enemy: %s" % landed)
		_bus.caster_move_finished.emit(0, &"teleport", landed, tag)
		check_equal(_moves.size(), 2, "its payload teleports again from where it landed")
		# A move carries its way and distance (rules R4 F1).
		var hop: Vector2 = _moves[1][2]
		check(hop.length() > 1.0 and absf(hop.angle_to(second.global_position - landed)) < 0.01, "cast %d: on toward the other enemy, though the first is nearer: %s" % [cast, hop])
		check(first.global_position.distance_to(landed + hop) > 20.0, "not staying at the first")
		# Past the cast's delay (two blinks), so the next cast goes out.
		_tick(90)


func test_a_homing_teleport_hops_back_to_a_lone_enemy() -> void:
	_distance_cards()
	var lone := _target(Vector2(50.0, 0.0))
	var tag: int = _build(0, [&"homing", &"on_expire", &"blink", &"homing", &"blink"])
	_cast(0)
	var landed: Vector2 = _moves[0][2]
	_bus.caster_move_finished.emit(0, &"teleport", landed, tag)
	check_equal(_moves.size(), 2, "a second hop")
	check(_moves[1][2].length() < 0.01, "with nobody else in reach it stays on the one enemy: %s" % _moves[1][2])
	check(lone != null, "the enemy is there")


func test_a_homing_dash_in_a_payload_turns_the_shot_toward_a_target() -> void:
	_distance_cards()
	_target(Vector2(160.0, 50.0))
	_build(0, [&"timer", &"bolt", &"homing", &"short"])
	_cast(0)
	var bolt: int = _others(-1)[0]
	_tick(20)
	check(_mgr.is_alive(bolt), "the bolt still flies")
	check(_mgr.get_position_of(bolt).y > 1.0, "its dash turned it toward the target: %s" % _mgr.get_position_of(bolt))


func test_a_payload_whose_shot_is_gone_dashes_the_wizard_to_its_point() -> void:
	# Rules R4 F1: a point cannot move, so its wizard dashes there (before, nothing moved).
	_distance_cards()
	_build(0, [&"on_expire", &"bolt", &"short"])
	_cast(0)
	_tick(90)
	check(_moves.size() == 1 and _moves[0][1] == &"dash" and _moves[0][2].x > 250.0, "the wizard dashes to where the bolt ended: %s" % [_moves])


func test_an_orbit_in_a_payload_circles_the_shot_that_fired_it() -> void:
	_distance_cards()
	_build(0, [&"timer", &"bolt", &"ring"])
	_cast(0)
	var bolt: int = _others(-1)[0]
	_tick(30)
	var ring: Array[int] = _others(bolt)
	check_equal(ring.size(), 1, "the orbit is out")
	_tick(10)
	check(_mgr.is_alive(ring[0]) and absf(_mgr.get_position_of(ring[0]).distance_to(_mgr.get_position_of(bolt)) - 20.0) < 6.0, "it circles the bolt as it flies: %s from %s" % [_mgr.get_position_of(ring[0]), _mgr.get_position_of(bolt)])
	check(_mgr.get_position_of(ring[0]).length() > 60.0, "not the wizard")


func test_an_orbit_in_a_payload_whose_shot_is_gone_circles_where_it_ended() -> void:
	_distance_cards()
	_build(0, [&"on_expire", &"bolt", &"ring"])
	_cast(0)
	_tick(62)
	var ring: Array[int] = _others(-1)
	check_equal(ring.size(), 1, "the orbit is out where the bolt ended")
	_tick(20)
	check(_mgr.is_alive(ring[0]) and absf(_mgr.get_position_of(ring[0]).distance_to(Vector2(300.0, 0.0)) - 20.0) < 8.0, "it circles the end point: %s" % _mgr.get_position_of(ring[0]))


func test_recoil_in_a_payload_pushes_the_shot_that_fired_it() -> void:
	_distance_cards()
	_build(0, [&"timer", &"bolt", &"recoil", &"spark"])
	_cast(0)
	var bolt: int = _others(-1)[0]
	_tick(60)
	check_equal(_moves.size(), 0, "the wizard is not pushed")
	check(_mgr.is_alive(bolt) and _mgr.get_position_of(bolt).x < 300.0 - 10.0, "the bolt was pushed back: %s" % _mgr.get_position_of(bolt))


func test_mirror_cancels_the_recoil_of_a_payload_too() -> void:
	# Rules R1e: the two pushes on the shot add up and cancel, as the wizard's do; the second
	# replaced the first before, and the bolt was pushed forward at every fire.
	_distance_cards()
	_build(0, [&"timer", &"bolt", &"mirror", &"recoil", &"spark"])
	_cast(0)
	var bolt: int = _others(-1)[0]
	_tick(50)
	check_equal(_moves.size(), 0, "the wizard is not pushed")
	check(_mgr.is_alive(bolt), "the bolt still flies")
	check(absf(_mgr.get_position_of(bolt).x - 250.0) < 1.0, "the pushes cancel: the bolt flew its own way only: %s" % _mgr.get_position_of(bolt))


func test_a_pull_after_a_recoil_on_a_shot_gets_both_moves() -> void:
	# Rules R1e: the hook ran in place of the recoil before, so the shot lost what was left of its
	# push back. Player 0's payload has recoil, player 1's the same without it.
	_distance_cards()
	_form(&"quick_bolt", 900.0, 1.0)
	_mgr.set_anchor(1, Vector2(0.0, 100.0))
	_target(Vector2(130.0, 0.0))
	_target(Vector2(130.0, 100.0))
	_build(0, [&"timer", &"pierce", &"bolt", &"recoil", &"pull", &"quick_bolt"])
	_build(1, [&"timer", &"pierce", &"bolt", &"pull", &"quick_bolt"])
	_cast(0)
	var pushed: int = _others(-1)[0]
	_spells.cast_staff(1, 0, Vector2(0.0, 100.0), Vector2.RIGHT, 100.0)
	var plain: int = _others(pushed)[0]
	# The timer fires at 0.25 s; the pull bolt hits before the push is over, and both are over before
	# the next fire.
	_tick(29)
	check(_mgr.is_alive(pushed) and _mgr.is_alive(plain), "both bolts still fly")
	var behind: float = _mgr.get_position_of(plain).x - _mgr.get_position_of(pushed).x
	check(behind > 3.0 and behind < 20.0, "the rest of the push after the pull still moves it back: %s px behind" % behind)
