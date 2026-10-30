extends "res://tests/support/suite.gd"
## Tests for the payload and line carriers of the staffs (B2c): rain drops its payload on the aim
## point after a delay, familiar and decoy ask for entities a step ahead and end through the events
## (a familiar casts what its triggers give it, rules R4 F3),
## wall is one solid still shot (a short-lived wall across the aim, rules R4 F6). It runs a real
## projectile manager and event bus, stepped by hand, with cards built in code.
##
## godot --headless --path . --script res://tests/core/test_spells_payload_carriers.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

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
## Every projectile_hit as [player, target, position, tag].
var _hits: Array = []
## Every entity_spawn_requested as [player, kind, position, seconds, tag, caster].
var _spawns: Array = []
## Every entity_end_requested as [player, tag].
var _end_requests: Array = []
## Every blast (its `cue_shown`) as [player, position, radius].
var _areas: Array = []
## Every form_shown as [player, form, origin, direction, length].
var _shown: Array = []
## Every cue_shown as [player, at, size, cue].
var _explosions: Array = []


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_mgr, _bus)
	_hits.clear()
	_spawns.clear()
	_end_requests.clear()
	_areas.clear()
	_shown.clear()
	_explosions.clear()
	_bus.cue_shown.connect(func(player: int, cue: StringName, at: Vector2, _direction: Vector2, size: float, _tint: Color, _look: int) -> void:
		_explosions.append([player, at, size, cue]))
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int) -> void:
		_hits.append([player, target, at, tag]))
	_bus.entity_spawn_requested.connect(func(player: int, kind: StringName, at: Vector2, seconds: float, tag: int, caster: int) -> void:
		_spawns.append([player, kind, at, seconds, tag, caster]))
	_bus.entity_end_requested.connect(func(player: int, tag: int) -> void:
		_end_requests.append([player, tag]))
	_bus.cue_shown.connect(func(player: int, _cue: StringName, at: Vector2, _direction: Vector2, radius: float, _tint: Color, _look: int) -> void: _areas.append([player, at, radius]))
	_bus.form_shown.connect(func(player: int, form: StringName, at: Vector2, direction: Vector2, length: float, _tint: Color, _look: int) -> void:
		_shown.append([player, form, at, direction, length]))
	var bolt: FormBase = _form(&"bolt", 300.0, 1.0)
	bolt.base_damage = 10
	var rain: FormBase = _form(&"rain", 0.0, 0.5)
	rain.motion = FormBase.Motion.RAIN
	var familiar: FormBase = _form(&"familiar", 0.0, 6.0)
	familiar.motion = FormBase.Motion.FAMILIAR
	familiar.radius = 5.0
	var decoy: FormBase = _form(&"decoy", 0.0, 4.0)
	decoy.motion = FormBase.Motion.DECOY
	decoy.radius = 8.0
	var rune: FormBase = _form(&"rune", 0.0, 3.0)
	rune.motion = FormBase.Motion.STILL
	rune.radius = 7.0
	var wall: FormBase = _form(&"wall", 0.0, 3.0)
	wall.motion = FormBase.Motion.WALL
	wall.shots = 3
	wall.spread = 10.0
	wall.radius = 4.0
	var beam: FormBase = _form(&"beam", 0.0, 0.2)
	beam.motion = FormBase.Motion.RAY
	beam.ray_length = 300.0
	beam.radius = 6.0
	_modifier(&"hold", ModifierBase.Behaviour.HOLD, 1.0)
	_modifier(&"shield", ModifierBase.Behaviour.SHIELD, 2.0)
	_modifier(&"blast", ModifierBase.Behaviour.BLAST, 30.0).cue = &"blast"
	# A barrel's blast: the same behaviour, naming another cue.
	_modifier(&"barrel", ModifierBase.Behaviour.BLAST, 30.0).cue = &"fireball"
	_modifier(&"mirror", ModifierBase.Behaviour.MIRROR, 1.0)
	_modifier(&"echo", ModifierBase.Behaviour.ECHO, 0.2)
	_trigger(&"on_expire", TriggerBase.Event.EXPIRE)
	_trigger(&"on_hit", TriggerBase.Event.HIT)
	_trigger(&"timer", TriggerBase.Event.TIMER).interval = 0.5
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


func _modifier(id: StringName, behaviour: ModifierBase.Behaviour, strength: float) -> ModifierBase:
	var modifier := ModifierBase.new()
	modifier.behaviour = behaviour
	modifier.behaviour_strength = strength
	_put(modifier, id)
	return modifier


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


## Positions of the live shots, in slot order.
func _positions() -> Array[Vector2]:
	var found: Array[Vector2] = []
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot):
			found.append(_mgr.get_position_of(slot))
	return found


func test_rain_drops_its_payload_on_the_aim_point_after_its_delay() -> void:
	_build(0, [&"rain", &"bolt"])
	check_equal(_cast(), 4.0, "rain and its payload cost both carriers")
	check_equal(_mgr.get_count(), 0, "nothing flies at the cast")
	_tick(20)
	check_equal(_mgr.get_count(), 0, "nothing falls before the delay is over")
	_tick(12)
	var found: Array[Vector2] = _positions()
	check_equal(found.size(), 1, "the payload fell")
	check(found.size() == 1 and found[0].x > SpellLimits.RAIN_REACH - 20.0 and absf(found[0].y) < 1.0, "on the aim point: %s" % [found])


func test_rain_shows_where_and_when() -> void:
	_build(0, [&"rain", &"bolt"])
	_cast()
	check_equal(_shown.size(), 1, "one cue")
	check(_shown.size() == 1 and _shown[0][1] == &"rain" and is_equal_approx(_shown[0][4], 0.5), "a rain cue that says how long it takes")
	check(_shown.size() == 1 and is_equal_approx(_shown[0][2].x, SpellLimits.RAIN_REACH), "at the aim point")


func test_rain_stops_at_a_wall() -> void:
	_mgr.set_walls([Rect2(60.0, -50.0, 20.0, 100.0)])
	_build(0, [&"rain", &"bolt"])
	_cast()
	check(_shown.size() == 1 and _shown[0][2].x < 60.0, "the aim point is in front of the wall")


func test_rain_is_dropped_when_the_staff_is_rebuilt() -> void:
	_build(0, [&"rain", &"bolt"])
	_cast()
	_build(0, [&"bolt"])
	_tick(60)
	check_equal(_mgr.get_count(), 0, "the old build's rain never fell")


func test_a_dropped_rains_timer_ends_with_its_landing() -> void:
	# Rules R4 F3 (from #478): the rebuild drops the landing, and the rain's clock with it.
	(_fake.items[&"rain"] as FormBase).lifetime = 2.0
	_build(0, [&"timer", &"rain", &"bolt", &"bolt"])
	_cast()
	_tick(40)
	check_equal(_mgr.get_count(), 1, "its timer ticks while it falls")
	# Its bolt in the air keeps the old build known, as any shot of it does.
	_build(0, [&"bolt"])
	_tick(90)
	check_equal(_mgr.get_count(), 0, "after the rebuild its timer casts no more (its last bolt is gone)")


func test_rain_fires_its_own_on_expire_trigger_as_it_lands() -> void:
	_build(0, [&"on_expire", &"rain", &"bolt", &"bolt"])
	_cast()
	_tick(40)
	check_equal(_mgr.get_count(), 2, "its payload and the trigger's payload both fell")


func test_a_rain_with_nothing_after_it_does_nothing() -> void:
	_build(0, [&"rain"])
	_cast()
	_tick(60)
	check_equal(_mgr.get_count(), 0, "no payload, no shots")


func test_a_rain_strikes_what_is_under_it_as_it_lands() -> void:
	# Rules R4g: the rain hits with its own hit and cards where it lands, then drops its payload.
	var under: Node2D = _target(Vector2(SpellLimits.RAIN_REACH, 0.0))
	_target(Vector2(SpellLimits.RAIN_REACH + 40.0, 0.0))
	var tag: int = _build(0, [&"rain"])
	_cast()
	_tick(20)
	check(_hits.is_empty(), "nothing before it lands")
	_tick(20)
	check_equal(_hits.size(), 1, "one body under it is struck")
	check(_hits.size() == 1 and _hits[0][1] == under and _hits[0][3] == tag, "the one on the aim point, by the rain itself")


func test_a_landing_rain_fires_its_on_hit() -> void:
	_target(Vector2(SpellLimits.RAIN_REACH, 0.0))
	_build(0, [&"on_hit", &"rain", &"bolt"])
	_cast()
	_tick(31)
	check_equal(_mgr.get_count(), 1, "its on-hit payload left from the target")


func test_an_echoed_rain_strikes_at_half() -> void:
	_target(Vector2(SpellLimits.RAIN_REACH, 0.0))
	var damage: Array[int] = []
	_bus.projectile_hit.connect(func(_player: int, _target_hit: Node, _at: Vector2, tag: int) -> void:
		damage.append(_spells.hit_profile(tag).damage))
	_build(0, [&"echo", &"rain"])
	_cast()
	_tick(90)
	check_equal(damage.size(), 2, "the rain and its echo strike")
	check(damage.size() == 2 and damage[1] < damage[0], "the echo at half: %s" % [damage])


func test_a_mirrored_rain_lands_through_the_caster() -> void:
	_build(0, [&"mirror", &"rain", &"bolt"])
	_cast()
	check_equal(_shown.size(), 2, "two cues")
	check(_shown.size() == 2 and is_equal_approx(_shown[1][2].x, -SpellLimits.RAIN_REACH), "the second behind the caster: %s" % [_shown])


func test_a_mirrored_wall_stands_behind() -> void:
	_build(0, [&"mirror", &"wall"])
	_cast()
	var ahead: int = 0
	var behind: int = 0
	for at in _positions():
		if is_equal_approx(at.x, SpellLimits.WALL_REACH):
			ahead += 1
		elif is_equal_approx(at.x, -SpellLimits.WALL_REACH):
			behind += 1
	check_equal([ahead, behind], [1, 1], "a wall ahead and one behind")
	check(_blocked(Vector2(0.0, 5.0), Vector2(60.0, 5.0)) and _blocked(Vector2(0.0, 5.0), Vector2(-60.0, 5.0)), "both are solid")


func test_a_mirrored_decoy_is_a_second_decoy() -> void:
	_build(0, [&"mirror", &"decoy"])
	_cast()
	check_equal(_spawns.size(), 2, "two decoys")


func test_a_decoy_and_a_familiar_appear_a_step_ahead_and_a_mirror_puts_its_copy_behind() -> void:
	# Rules R4 F3: what a caster places appears twice its size ahead along the aim.
	for card: StringName in [&"decoy", &"familiar"]:
		_spawns.clear()
		_spells.clear()
		_build(0, [&"mirror", card])
		_cast()
		var step: float = (_fake.items[card] as FormBase).radius * 2.0
		check(_spawns.size() == 2 and (_spawns[0][2] as Vector2).is_equal_approx(Vector2(step, 0.0)), "the %s ahead: %s" % [card, _spawns])
		check(_spawns.size() == 2 and (_spawns[1][2] as Vector2).is_equal_approx(Vector2(-step, 0.0)), "its mirror's behind: %s" % [_spawns])


func test_a_lone_rune_appears_a_step_ahead() -> void:
	_build(0, [&"rune"])
	_cast()
	var found: Array[Vector2] = _positions()
	check(found.size() == 1 and found[0].is_equal_approx(Vector2(14.0, 0.0)), "twice its size ahead: %s" % [found])


func test_a_mirrored_rune_is_placed_behind() -> void:
	_build(0, [&"mirror", &"rune"])
	_cast()
	var found: Array[Vector2] = _positions()
	check(found.size() == 2 and found[0].distance_to(-found[1]) < 0.01 and absf(absf(found[0].x) - 14.0) < 0.01, "one ahead, one behind: %s" % [found])


func test_rain_payload_counts_as_live_until_it_ends() -> void:
	var tag: int = _build(0, [&"rain", &"bolt"])
	_cast()
	_tick(40)
	check_equal(_spells.live_shots(tag + (1 << SpellTag.NODE_SHIFT)), 1, "the payload's shot is counted under its own node")


func _rain_cues() -> int:
	var count: int = 0
	for shown: Array in _shown:
		if shown[1] == &"rain":
			count += 1
	return count


func test_a_held_rain_keeps_falling_until_switched_off() -> void:
	# Rules R4e (owner, 2026-10-29): a held rain used to fall once.
	_form(&"stone", 0.0, 10.0)
	_build(0, [&"hold", &"rain", &"stone"])
	var mana: float = _cast()
	check(_spells.is_holding(0, 0), "a held rain is on")
	check_equal(_spells.reserved_mana(0), mana, "and reserves its cast")
	check_equal(_rain_cues(), 1, "one rain at the cast")
	_tick(32)
	check_equal(_mgr.get_count(), 1, "the first fell after its own delay")
	check_equal(_rain_cues(), 2, "and the next began as it fell")
	_tick(30)
	check_equal(_mgr.get_count(), 2, "the second fell a lifetime later")
	check_equal(_rain_cues(), 3, "a third is on its way")
	check(_spells.is_holding(0, 0), "still on between two falls")
	check_equal(_cast(), 0.0, "the next press switches it off")
	check(not _spells.is_holding(0, 0), "off")
	check_equal(_spells.reserved_mana(0), 0.0, "its mana is free")
	_tick(60)
	check_equal(_rain_cues(), 3, "no new rain")
	check_equal(_mgr.get_count(), 2, "and the third never fell")


func test_familiar_asks_for_an_entity() -> void:
	var tag: int = _build(0, [&"familiar", &"bolt"])
	_cast()
	check_equal(_spawns.size(), 1, "one entity asked for")
	check(_spawns.size() == 1 and _spawns[0][1] == &"familiar" and is_equal_approx(_spawns[0][3], 6.0) and _spawns[0][4] == tag, "a familiar for its lifetime, under the carrier's tag: %s" % [_spawns])
	check_equal(_mgr.get_count(), 0, "no shot leaves the caster")
	check_equal(_spells.live_shots(tag), 1, "the entity keeps its build alive")


func test_a_familiar_casts_nothing_of_its_own() -> void:
	# Rules R4 F3: no built-in payload; the bolt after it is the staff's next cast.
	_build(0, [&"familiar", &"bolt"])
	_cast()
	_tick(120)
	check_equal(_mgr.get_count(), 0, "a familiar with no trigger casts nothing")


func test_a_familiar_casts_what_its_timer_gives_it() -> void:
	var tag: int = _build(0, [&"timer", &"familiar", &"bolt"])
	_cast()
	_tick(31)
	var found: Array[Vector2] = _positions()
	check_equal(found.size(), 1, "its timer cast a bolt after the interval")
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot):
			check(_mgr.get_velocity_of(slot).normalized().is_equal_approx(Vector2.RIGHT), "along the aim it was cast with")
			check_equal(SpellTag.node_of(_mgr.get_tag_of(slot)), SpellTag.node_of(tag) + 1, "the timer's payload, under its own node")
	_tick(30)
	check_equal(_mgr.get_count(), 2, "and again every tick")


func test_entity_events_for_another_player_are_ignored() -> void:
	var tag: int = _build(0, [&"familiar", &"bolt"])
	_cast()
	_bus.entity_ended.emit(1, &"familiar", Vector2.ZERO, tag)
	check_equal(_spells.live_shots(tag), 1, "player 1 cannot end player 0's familiar")


func test_a_familiar_stops_casting_when_it_ends() -> void:
	var tag: int = _build(0, [&"timer", &"familiar", &"bolt"])
	_cast()
	_bus.entity_ended.emit(0, &"familiar", Vector2.ZERO, tag)
	_tick(60)
	check_equal(_mgr.get_count(), 0, "it is gone")
	check_equal(_spells.live_shots(tag), 0, "and no longer counted")


func test_a_familiar_outlives_a_rebuild_of_its_staff() -> void:
	var tag: int = _build(0, [&"timer", &"familiar", &"bolt"])
	_cast()
	_build(0, [&"bolt"])
	_tick(31)
	check_equal(_mgr.get_count(), 1, "the old familiar still casts what it was built with")
	_mgr.clear()
	_bus.entity_ended.emit(0, &"familiar", Vector2.ZERO, tag)
	check(_spells.profile(tag) == null, "the old build is forgotten once its familiar is gone")


func test_a_held_familiar_stays_until_the_staff_is_cast_again() -> void:
	var tag: int = _build(0, [&"hold", &"familiar", &"bolt"])
	_cast()
	check(_spawns.size() == 1 and is_inf(_spawns[0][3]), "it lasts until it is ended")
	check(_spells.is_holding(0, 0), "the staff is holding")
	_tick(90)
	check_equal(_cast(), 0.0, "the next press switches it off")
	check_equal(_end_requests, [[0, tag]], "and asks ai to end the familiar")
	_bus.entity_ended.emit(0, &"familiar", Vector2.ZERO, tag)
	check(not _spells.is_holding(0, 0), "no longer holding once it has ended")


func test_a_rebuild_ends_a_held_familiar() -> void:
	var tag: int = _build(0, [&"hold", &"familiar", &"bolt"])
	_cast()
	_build(0, [&"bolt"])
	check_equal(_end_requests, [[0, tag]], "editing the staff ends it")


func test_a_revoked_build_ends_its_familiars() -> void:
	var tag: int = _build(0, [&"familiar", &"bolt"])
	_cast()
	for i in SpellLimits.GENERATIONS:
		_build(0, [&"bolt"])
	check_equal(_end_requests, [[0, tag]], "the revoked build's familiar is told to end")
	_bus.entity_ended.emit(0, &"familiar", Vector2.ZERO, tag)
	check_equal(_spells.live_shots(tag), 0, "and its late answer changes nothing")


func test_decoy_asks_for_an_entity() -> void:
	var tag: int = _build(0, [&"decoy"])
	_cast()
	check(_spawns.size() == 1 and _spawns[0][1] == &"decoy" and is_equal_approx(_spawns[0][3], 4.0) and _spawns[0][4] == tag, "a decoy for its lifetime: %s" % [_spawns])


func test_a_decoy_fires_its_on_expire_payload_where_it_ends() -> void:
	var tag: int = _build(0, [&"on_expire", &"decoy", &"bolt"])
	_cast()
	check_equal(_mgr.get_count(), 0, "nothing while it stands")
	_bus.entity_ended.emit(0, &"decoy", Vector2(50, 20), tag)
	var found: Array[Vector2] = _positions()
	check(found.size() == 1 and found[0].is_equal_approx(Vector2(50, 20)), "the payload starts at its end point: %s" % [found])


func test_a_blast_decoy_explodes_where_it_ends() -> void:
	var tag: int = _build(0, [&"blast", &"decoy"])
	_cast()
	_bus.entity_ended.emit(0, &"decoy", Vector2(50, 20), tag)
	check_equal(_areas.size(), 1, "one area hit")
	check(_areas.size() == 1 and _areas[0][1].is_equal_approx(Vector2(50, 20)) and is_equal_approx(_areas[0][2], 30.0), "at the end point, as wide as the blast: %s" % [_areas])


func test_a_blast_shows_its_explosion_where_it_goes_off() -> void:
	var tag: int = _build(0, [&"blast", &"decoy"])
	_cast()
	_bus.entity_ended.emit(0, &"decoy", Vector2(50, 20), tag)
	check(_explosions.size() == 1 and _explosions[0][1].is_equal_approx(Vector2(50, 20)) and is_equal_approx(_explosions[0][2], 30.0), "one explosion at the area hit, as wide: %s" % [_explosions])
	check(_explosions.size() == 1 and _explosions[0][0] == 0 and _explosions[0][3] == &"blast", "of its caster, in blast's style")


func test_a_blast_plays_the_cue_its_card_names_the_first_in_slot_order() -> void:
	var tag: int = _build(0, [&"barrel", &"decoy"])
	_cast()
	_bus.entity_ended.emit(0, &"decoy", Vector2(50, 20), tag)
	check(_explosions.size() == 1 and _explosions[0][3] == &"fireball", "the barrel card's cue: %s" % [_explosions])
	_explosions.clear()
	tag = _build(1, [&"barrel", &"blast", &"decoy"])
	_cast(1)
	_bus.entity_ended.emit(1, &"decoy", Vector2(50, 20), tag)
	check(_explosions.size() == 1 and _explosions[0][3] == &"fireball", "two blast cards: the first's cue: %s" % [_explosions])
	_explosions.clear()
	_build(2, [&"blast", &"barrel"])
	_cast(2)
	check(_explosions.size() == 1 and _explosions[0][3] == &"blast", "fallen back on the caster, the first's too: %s" % [_explosions])


func test_the_shipped_blast_card_names_the_blast_cue() -> void:
	var card: ModifierBase = load("res://content/spells/modifiers/blast/blast.tres") as ModifierBase
	check_equal(card.cue, &"blast", "blast.tres says which cue it plays")


func test_a_lone_blast_explodes_on_its_caster_and_a_decoy_without_one_does_not() -> void:
	_build(0, [&"blast"])
	_cast()
	check_equal(_explosions.size(), 1, "blast alone falls back on the caster and explodes there")
	check(_areas.size() == 1 and _explosions.size() == 1 and _explosions[0][1].is_equal_approx(_areas[0][1]), "where its area hit is")
	_explosions.clear()
	var tag: int = _build(0, [&"decoy"])
	_cast()
	_bus.entity_ended.emit(0, &"decoy", Vector2(50, 20), tag)
	check_equal(_explosions.size(), 0, "nothing explodes without a blast")


func test_a_decoy_ending_twice_counts_once() -> void:
	var tag: int = _build(0, [&"blast", &"decoy"])
	_cast()
	_bus.entity_ended.emit(0, &"decoy", Vector2.ZERO, tag)
	_bus.entity_ended.emit(0, &"decoy", Vector2.ZERO, tag)
	check_equal(_areas.size(), 1, "the second answer is ignored")


## True when the segment `from`-`to` meets a wall.
func _blocked(from: Vector2, to: Vector2) -> bool:
	return _mgr.clip_to_walls(from, to) != to


func test_wall_is_one_solid_row_across_the_aim() -> void:
	_build(0, [&"wall"])
	_cast()
	var found: Array[Vector2] = _positions()
	check_equal(found, [Vector2(SpellLimits.WALL_REACH, 0.0)] as Array[Vector2], "one body, ahead of the caster")
	# Three stones 10 px apart, 4 px round: the row reaches 14 px either side of its middle.
	for y: float in [-12.0, 0.0, 12.0]:
		check(_blocked(Vector2(0.0, y), Vector2(60.0, y)), "a line across it at y %s meets it" % y)
	check(not _blocked(Vector2(0.0, 30.0), Vector2(60.0, 30.0)), "one well beside it does not")
	_tick(30)
	check_equal(_mgr.get_count(), 1, "it stands")
	check(_blocked(Vector2(0.0, 0.0), Vector2(60.0, 0.0)), "and is still solid")
	_tick(180)
	check_equal(_mgr.get_count(), 0, "its life over, it is gone")
	check(not _blocked(Vector2(0.0, 0.0), Vector2(60.0, 0.0)), "and so is its wall")


func test_wall_follows_the_aim() -> void:
	_build(0, [&"wall"])
	_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.DOWN, 100.0)
	check_equal(_positions(), [Vector2(0.0, SpellLimits.WALL_REACH)] as Array[Vector2], "below the caster")
	check(_blocked(Vector2(-12.0, 0.0), Vector2(-12.0, 60.0)) and _blocked(Vector2(12.0, 0.0), Vector2(12.0, 60.0)), "a horizontal row")
	check(not _blocked(Vector2(0.0, 0.0), Vector2(0.0, 15.0)), "short of it the way is open")


func test_a_shield_wall_blocks_enemy_shots() -> void:
	_build(0, [&"shield", &"wall"])
	_cast()
	var charged: int = 0
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot) and _mgr.get_shield_of(slot) == 2:
			charged += 1
	check_equal(charged, 1, "the wall carries the shield's charges")


func test_a_shot_ends_on_the_wall_and_a_ghost_passes() -> void:
	_build(0, [&"wall"])
	_cast()
	var plain: int = _mgr.spawn(9, Vector2(80.0, 8.0), Vector2(-300.0, 0.0), 2.0, 2.0, ManagerScript.LAYER_PLAYER)
	var ghost: int = _mgr.spawn(9, Vector2(80.0, -8.0), Vector2(-300.0, 0.0), 2.0, 2.0, ManagerScript.LAYER_PLAYER)
	_mgr.set_ghost(ghost)
	_tick(20)
	check(not _mgr.is_alive(plain), "the plain shot ended on the wall")
	check(_mgr.is_alive(ghost) and _mgr.get_position_of(ghost).x < 0.0, "the ghost passed it")


func test_an_enemy_touching_the_wall_anywhere_along_it_is_hit_once_while_it_stays() -> void:
	_build(0, [&"wall"])
	var target: Node2D = _target(Vector2(SpellLimits.WALL_REACH + 6.0, 13.0))
	_cast()
	_tick(30)
	check_equal(_hits.size(), 1, "hit once at the row's end, and the wall stands on")
	check(not _hits.is_empty() and _hits[0][1] == target, "it is the enemy")
	check_equal(_mgr.get_count(), 1, "the hit did not spend the wall")


func test_a_beam_the_wall_casts_comes_out_of_it() -> void:
	# Rules R4 F8: what a wall casts leaves it, beams too (as its flying payloads do).
	_build(0, [&"timer", &"wall", &"beam"])
	var target: Node2D = _target(Vector2(SpellLimits.WALL_REACH + 80.0, 0.0))
	_cast()
	_tick(32)
	check(_hits.any(func(hit: Array) -> bool: return hit[1] == target), "the wall's beam reached the enemy beyond it: %s" % [_hits])
	check(_blocked(Vector2(0.0, 0.0), Vector2(60.0, 0.0)), "the wall still stops everything else")


func test_wall_shots_stay_out_of_a_wall() -> void:
	_mgr.set_walls([Rect2(14.0, -100.0, 40.0, 200.0)])
	_build(0, [&"wall"])
	_cast()
	for at in _positions():
		check(at.x < 14.0, "no shot is born inside the wall: %s" % [at])


func test_an_enemy_touching_a_wall_is_hit() -> void:
	_build(0, [&"wall"])
	var target: Node2D = _target(Vector2(SpellLimits.WALL_REACH, 0))
	_cast()
	_tick(3)
	check(not _hits.is_empty() and _hits[0][1] == target, "an enemy that touches the wall is hit")


func test_a_beam_with_no_pierce_hits_only_the_first() -> void:
	_build(0, [&"beam"])
	for n in 5:
		_target(Vector2(40.0 + n * 40.0, 0.0))
	_cast()
	check_equal(_hits.size(), 1, "a beam stops at one")
