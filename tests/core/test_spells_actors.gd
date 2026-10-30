extends "res://tests/support/suite.gd"
## Casters are actor ids in core/spells (actors G3b, docs/milestones/M2-actors.md): any actor id
## installs and casts a staff; `open_caster` gives a fresh row and `close_caster` ends what it
## holds (staffs, waiting launches, holds, beams) while its shots in the air fly on. The table
## here seats the four wizards at ids 7-10 (seats 0-3) behind seven unseated enemies (ids 0-6), so
## no test can pass by mistaking a seat for an actor id: events and tags carry the actor id, the
## per-step fire and chain caps and the shared beams and waiting launches go by budget (a seat's
## own, one shared by every unseated actor), `mana_reserved` goes to the seat, chains and arcs
## aim at other teams only, and `on hurt` fires on the hurt actor's `actor_hurt`. A four-player
## staff (wizards at ids 0-3) is unchanged. A real projectile manager and event bus, stepped by
## hand, with cards built in code and a stand-in registry.
##
## godot --headless --path . --script res://tests/core/test_spells_actors.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
## The wizards' first actor id (seat 0); seats 1-3 follow.
const W0: int = 7


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _fake: FakeRegistry
var _spells: SpellsScript
var _mgr: ManagerScript
var _bus: EventsScript
var _table: ActorSeats.ActorsScript
## Every projectile_hit as [caster, target, tag].
var _hits: Array = []
## The first argument (the actor id) and the tag of every caster_move_requested and
## blast cue; the caster of every form_shown and entity_spawn_requested.
var _moves: Array = []
var _areas: Array = []
var _shown: Array[int] = []
var _spawns: Array[int] = []
## Every mana_refund_requested and mana_reserved as [first argument, amount].
var _refunds: Array = []
var _reserved: Array = []


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(1024)
	_table = own(ActorSeats.table(4, W0)) as ActorSeats.ActorsScript
	_mgr.actors = _table
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_mgr, _bus)
	for list: Array in [_hits, _moves, _areas, _shown, _spawns, _refunds, _reserved]:
		list.clear()
	_bus.projectile_hit.connect(func(caster: int, target: Node, _at: Vector2, tag: int) -> void: _hits.append([caster, target, tag]))
	_bus.caster_move_requested.connect(func(caster: int, _mode: StringName, _to: Vector2, _seconds: float, tag: int) -> void: _moves.append([caster, tag]))
	_bus.cue_shown.connect(func(player: int, _cue: StringName, at: Vector2, _direction: Vector2, radius: float, _tint: Color, _look: int) -> void: _areas.append([player, at, radius]))
	_bus.form_shown.connect(func(caster: int, _form: StringName, _at: Vector2, _dir: Vector2, _length: float, _tint: Color, _look: int) -> void: _shown.append(caster))
	_bus.entity_spawn_requested.connect(func(caster: int, _kind: StringName, _at: Vector2, _seconds: float, _tag: int, _anchor: int) -> void: _spawns.append(caster))
	_bus.mana_refund_requested.connect(func(caster: int, amount: float) -> void: _refunds.append([caster, amount]))
	_bus.mana_reserved.connect(func(player: int, amount: float) -> void: _reserved.append([player, amount]))
	_form(&"bolt", 300.0, 1.0)
	_form(&"slow", 30.0, 5.0)
	var rune: FormBase = _form(&"rune", 0.0, 3.0)
	rune.motion = FormBase.Motion.STILL
	# Many shots at once, each with its own timer: one cast fills a budget's room for a step.
	var swarm: FormBase = _form(&"swarm", 30.0, 5.0)
	swarm.shots = SpellLimits.FIRE_SHOTS_PER_STEP
	swarm.spread = 360.0
	var beam: FormBase = _form(&"beam", 0.0, 5.0)
	beam.motion = FormBase.Motion.RAY
	beam.ray_length = 200.0
	var dash: FormBase = _form(&"dash", 400.0, 0.2)
	dash.motion = FormBase.Motion.DASH
	dash.ray_length = 80.0
	var orb: FormBase = _form(&"orb", 0.0, 5.0)
	orb.motion = FormBase.Motion.ORBIT
	orb.orbit_radius = 30.0
	var decoy: FormBase = _form(&"decoy", 0.0, 4.0)
	decoy.motion = FormBase.Motion.DECOY
	_modifier(&"chain", ModifierBase.Behaviour.CHAIN, 1.0)
	_modifier(&"echo", ModifierBase.Behaviour.ECHO, 1.0)
	_modifier(&"siphon", ModifierBase.Behaviour.SIPHON, 2.0)
	_modifier(&"blast", ModifierBase.Behaviour.BLAST, 24.0)
	_modifier(&"hold", ModifierBase.Behaviour.HOLD, 1.0)
	_modifier(&"arc", ModifierBase.Behaviour.ARC, 2.0).behaviour_reach = 60.0
	_trigger(&"on_hurt", TriggerBase.Event.HURT)
	_trigger(&"timer", TriggerBase.Event.TIMER).interval = 0.5


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


func _build(caster: int, cards: Array[StringName]) -> int:
	return StaffKit.build(_spells, caster, 0, cards)


## A body at `at` on `layer`, of the actor `owner` (none: -1, then its team is its layer's).
func _target(at: Vector2, layer: int, owner: int = EventsScript.NO_PLAYER) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	_mgr.add_target(node, 10.0, layer, owner)
	return node


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


func _cast(caster: int, origin: Vector2 = Vector2.ZERO, direction: Vector2 = Vector2.RIGHT) -> float:
	return _spells.cast_staff(caster, 0, origin, direction, 100.0)


func _hit_targets() -> Array[Node]:
	var out: Array[Node] = []
	for hit: Array in _hits:
		out.append(hit[1] as Node)
	return out


## Live shots of `tag`.
func _shots(tag: int) -> int:
	var count: int = 0
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot) and _mgr.get_tag_of(slot) == tag:
			count += 1
	return count


# --- Opening and closing a caster ---------------------------------------------------------

func test_open_caster_gives_a_fresh_row() -> void:
	var imp: int = ActorSeats.enemy(_table)
	_build(imp, [&"bolt", &"slow"])
	_cast(imp)
	check_equal(_spells.cast_index(imp, 0), 1, "the cycle moved on")
	check(_spells.open_caster(imp), "an actor id opens")
	check_equal(_spells.cast_index(imp, 0), 0, "from the first cast again")
	check_equal(_spells.cooldown_left(imp, 0), 0.0, "with no delay left")
	check(not _spells.open_caster(-1) and not _spells.open_caster(ActorSeats.ActorsScript.ACTORS), "an id outside the table does not")


func test_close_caster_empties_its_staffs() -> void:
	var imp: int = ActorSeats.enemy(_table)
	_build(imp, [&"bolt"])
	_spells.close_caster(imp)
	check_equal(_spells.current_tag(imp, 0), 0, "no build left")
	check_equal(_cast(imp), SpellsScript.REFUSED, "so it casts nothing")


func test_close_caster_drops_its_waiting_launches() -> void:
	var imp: int = ActorSeats.enemy(_table)
	var tag: int = _build(imp, [&"echo", &"slow"])
	_cast(imp)
	_spells.close_caster(imp)
	_tick(90)
	check_equal(_shots(tag), 1, "the echo never fires; the first shot flies on")


## Regression (rules R4 F4): closing a caster dropped the waiting payloads of its shots in the air
## (here a timer's echoed slow). They fire on, as its shots fly on and as after an edit.
func test_close_caster_lets_its_shots_payloads_fire_on() -> void:
	var imp: int = ActorSeats.enemy(_table)
	_build(imp, [&"timer", &"slow", &"echo", &"slow"])
	var payload: int = _spells.current_tag(imp, 0, 1)
	_cast(imp)
	_tick(40)
	check_equal(_shots(payload), 1, "the timer fired once; its echo waits")
	_spells.close_caster(imp)
	_tick(60)
	check_equal(_shots(payload), 4, "the echo fired on with the timer's later firings (0.5 s, 1 s, 1.5 s and its echo)")


func test_close_caster_ends_its_hold() -> void:
	var imp: int = ActorSeats.enemy(_table)
	var tag: int = _build(imp, [&"hold", &"slow"])
	_cast(imp)
	check(_spells.is_holding(imp, 0), "the hold is on")
	_spells.close_caster(imp)
	check(not _spells.is_holding(imp, 0), "and off once the caster is closed")
	check_equal(_spells.live_shots(tag), 0, "with its shot")
	check_equal(_spells.reserved_mana(imp), 0.0, "and its mana")


func test_close_caster_ends_its_beams_only() -> void:
	var imp: int = ActorSeats.enemy(_table)
	for caster in [imp, W0]:
		_build(caster, [&"beam"])
		_spells.set_aim(caster, Vector2(0.0, 50.0 * caster), Vector2.RIGHT)
		_cast(caster, Vector2(0.0, 50.0 * caster))
	check_equal(_spells.beam_count(), 2, "two beams on")
	_spells.close_caster(imp)
	check_equal(_spells.beam_count(), 1, "the closed caster's beam ends")
	for at in _spells.beam_slots():
		if _spells.beam_on(at):
			check_equal(_spells.beam_caster(at), W0, "the wizard's stays")


func test_close_caster_lets_its_shots_fly_on_with_their_numbers() -> void:
	var imp: int = ActorSeats.enemy(_table)
	var tag: int = _build(imp, [&"slow"])
	_cast(imp)
	_tick(5)
	_spells.close_caster(imp)
	check_equal(_spells.live_shots(tag), 1, "the shot flies on")
	check(_spells.hit_profile(tag) != null, "with its numbers")
	_tick(400)
	check_equal(_spells.live_shots(tag), 0, "until it ends")
	check(_spells.hit_profile(tag) == null, "then its numbers are forgotten")


func test_a_reopened_caster_goes_on_round_the_ring() -> void:
	var imp: int = ActorSeats.enemy(_table)
	var old: int = _build(imp, [&"slow"])
	_cast(imp)
	_spells.close_caster(imp)
	_spells.open_caster(imp)
	var fresh: int = _build(imp, [&"bolt"])
	check(fresh != old, "a new generation, not the old one's")
	check_equal(_spells.live_shots(old), 1, "the old shot is still counted")
	check(_spells.profile(old) != null and _spells.profile(old) != _spells.profile(fresh), "with its old numbers")


# --- Budgets ------------------------------------------------------------------------------

func test_each_seat_has_its_own_fire_count_a_step() -> void:
	for seat in 2:
		_build(W0 + seat, [&"timer", &"swarm", &"rune"])
		_cast(W0 + seat, Vector2(300.0 * seat, 0.0))
	_tick(31)
	check_equal(_spells.fires_waited, 0, "two seats fire a full step's worth each")


func test_unseated_casters_share_one_fire_count_a_step() -> void:
	for caster in 2:
		_build(caster, [&"timer", &"swarm", &"rune"])
		_cast(caster, Vector2(300.0 * caster, 0.0))
	_build(W0, [&"timer", &"bolt", &"rune"])
	_cast(W0, Vector2(600.0, 0.0), Vector2.DOWN)
	var payload: int = _spells.current_tag(W0, 0, 1)
	for _i in 40:
		_tick(1)
		if _spells.fires_waited > 0:
			break
	check_equal(_spells.fires_waited, SpellLimits.FIRE_SHOTS_PER_STEP, "two enemies together fire one budget's worth; the rest wait")
	check(_spells.live_shots(payload) > 0, "and the wizard's timer fires anyway")
	var made: int = _spells.fires_made
	_tick(1)
	check_equal(_spells.fires_made - made, SpellLimits.FIRE_SHOTS_PER_STEP, "the waiting ones fire in the next step")


## `count` unseated casters: the table's enemies (ids 0-6), then new ones (ids 11 on).
func _unseated(count: int) -> Array[int]:
	var ids: Array[int] = []
	for i in count:
		ids.append(i if i < W0 else ActorSeats.enemy(_table))
	return ids


## Each of `casters` casts a chain bolt at a body on `layer` with a second one beside it, a row
## each from row `first` down, all hitting in the same step.
func _chain_rows(casters: Array[int], layer: int, first: int = 0) -> void:
	for i in casters.size():
		var y: float = 45.0 * (first + i)
		_target(Vector2(30.0, y), layer)
		_target(Vector2(30.0, y + 20.0), layer)
		_build(casters[i], [&"chain", &"bolt"])
		_cast(casters[i], Vector2(0.0, y))


func test_every_casters_chain_jumps_however_many_jump_at_once() -> void:
	# The crowd and the four seats chain in the same step; no budget holds a jump back.
	_chain_rows(_unseated(20), ManagerScript.LAYER_PLAYER)
	_chain_rows([W0, W0 + 1, W0 + 2, W0 + 3] as Array[int], ManagerScript.LAYER_ENEMY, 20)
	_tick(20)
	var by_seats: int = 0
	for hit: Array in _hits:
		if hit[0] >= W0 and hit[0] < W0 + 4:
			by_seats += 1
	check_equal(by_seats, 8, "each wizard's bolt and its jump hit")
	check_equal(_hits.size(), 48, "and each of the 20 unseated casters' too")


func test_no_beam_ends_another_however_many_are_on() -> void:
	_build(W0, [&"beam"])
	_spells.set_aim(W0, Vector2(0.0, 300.0), Vector2.RIGHT)
	_cast(W0, Vector2(0.0, 300.0))
	var imps: Array[int] = _unseated(SpellLimits.BEAM_ROWS_START + 4)
	for i in imps.size():
		var imp: int = imps[i]
		_build(imp, [&"beam"])
		_spells.set_aim(imp, Vector2(0.0, 10.0 * i), Vector2.RIGHT)
		_cast(imp, Vector2(0.0, 10.0 * i))
	check_equal(_spells.beam_count(), SpellLimits.BEAM_ROWS_START + 5, "every beam is on: the rows grew")
	var seated: int = 0
	for at in _spells.beam_slots():
		if _spells.beam_on(at) and _spells.beam_caster(at) == W0:
			seated += 1
	check_equal(seated, 1, "and the wizard's beam was never ended by another")


func test_every_waiting_launch_waits_its_turn_however_many_casters() -> void:
	var imps: Array[int] = _unseated(40)
	for i in imps.size():
		var imp: int = imps[i]
		_build(imp, [&"echo", &"slow"])
		_cast(imp, Vector2(0.0, 4.0 * i))
	_build(W0 + 3, [&"echo", &"slow"])
	_cast(W0 + 3, Vector2(0.0, 300.0))
	check_equal(_spells._pending.size(), 41, "every echo waits, the crowd's and the seat's")


# --- Events carry the actor id ------------------------------------------------------------

func test_hits_and_tags_name_the_actor_id() -> void:
	var tag: int = _build(W0 + 1, [&"bolt"])
	check_equal(SpellTag.caster_of(tag), W0 + 1, "the tag names actor 8, not seat 1")
	var body: Node2D = _target(Vector2(60.0, 0.0), ManagerScript.LAYER_ENEMY)
	_cast(W0 + 1)
	_tick(20)
	check(_hits.size() == 1 and _hits[0][0] == W0 + 1 and _hits[0][1] == body and _hits[0][2] == tag, "the hit names actor 8: %s" % [_hits])


func test_an_enemys_hit_names_its_actor_id() -> void:
	var imp: int = ActorSeats.enemy(_table)
	_build(imp, [&"bolt"])
	_target(Vector2(60.0, 0.0), ManagerScript.LAYER_PLAYER, W0)
	_cast(imp)
	_tick(20)
	check(_hits.size() == 1 and _hits[0][0] == imp, "the hit names the enemy's id: %s" % [_hits])


func test_form_shown_names_the_actor_id() -> void:
	var imp: int = ActorSeats.enemy(_table)
	_build(imp, [&"swarm"])
	_cast(imp)
	check_equal(_shown, [imp] as Array[int], "a nova's cue names its caster")


func test_entity_spawn_names_the_actor_id() -> void:
	var imp: int = ActorSeats.enemy(_table)
	_build(imp, [&"decoy"])
	_cast(imp)
	check_equal(_spawns, [imp] as Array[int], "a decoy is asked for by its caster")


func test_a_dash_is_asked_for_by_the_actor_and_ends_with_its_blast() -> void:
	var imp: int = ActorSeats.enemy(_table)
	var tag: int = _build(imp, [&"blast", &"dash"])
	_cast(imp, Vector2(50.0, 50.0))
	check(_moves.size() == 1 and _moves[0][0] == imp and _moves[0][1] == tag, "the move is asked for by the enemy's id: %s" % [_moves])
	_bus.caster_move_finished.emit(W0, &"dash", Vector2(130.0, 50.0), tag)
	check_equal(_areas.size(), 0, "another actor's answer for its tag is ignored")
	_bus.caster_move_finished.emit(imp, &"dash", Vector2(130.0, 50.0), tag)
	check(_areas.size() == 1 and _areas[0][0] == imp and (_areas[0][1] as Vector2).is_equal_approx(Vector2(130.0, 50.0)), "where it ends, its blast, by its id")


func test_mana_reserved_goes_to_the_seat() -> void:
	_build(W0, [&"hold", &"slow"])
	_cast(W0)
	check(not _reserved.is_empty() and _reserved[-1][0] == 0 and _reserved[-1][1] > 0.0, "actor 7's hold is told to seat 0: %s" % [_reserved])


func test_mana_reserved_is_not_sent_for_an_unseated_enemy() -> void:
	var imp: int = ActorSeats.enemy(_table)
	_build(imp, [&"hold", &"slow"])
	_cast(imp)
	check(_spells.reserved_mana(imp) > 0.0, "its hold reserves mana")
	check(_reserved.is_empty(), "but no seat is told: %s" % [_reserved])


func test_an_enemys_siphon_is_refunded_by_event() -> void:
	var imp: int = ActorSeats.enemy(_table)
	_build(imp, [&"siphon", &"bolt"])
	_target(Vector2(80.0, 0.0), ManagerScript.LAYER_PLAYER, W0)
	_cast(imp)
	_tick(30)
	check(_refunds.size() == 1 and _refunds[0][0] == imp and is_equal_approx(_refunds[0][1], 2.0), "mana_refund_requested(enemy, 2): %s" % [_refunds])


func test_next_cast_mana_for_an_ai() -> void:
	var imp: int = ActorSeats.enemy(_table)
	check_equal(_spells.next_cast_mana(imp, 0), SpellsScript.REFUSED, "nothing built, nothing to cast")
	_build(imp, [&"bolt"])
	var cost: float = _spells.next_cast_mana(imp, 0)
	check(cost > 0.0, "the next cast's mana (%.2f)" % cost)
	check_equal(_spells.cast_staff(imp, 0, Vector2.ZERO, Vector2.RIGHT, cost * 0.5), SpellsScript.REFUSED, "less than that is refused")
	check_equal(_spells.cast_staff(imp, 0, Vector2.ZERO, Vector2.RIGHT, cost), cost, "enough casts and spends it")


# --- Aim: other teams only ----------------------------------------------------------------

func test_an_enemys_chain_skips_its_teammate() -> void:
	var imp: int = ActorSeats.enemy(_table)
	var mate: int = ActorSeats.enemy(_table)
	_build(imp, [&"chain", &"bolt"])
	var first: Node2D = _target(Vector2(100.0, 0.0), ManagerScript.LAYER_PLAYER, W0)
	var near: Node2D = _target(Vector2(100.0, 40.0), ManagerScript.LAYER_ENEMY, mate)
	var second: Node2D = _target(Vector2(160.0, 60.0), ManagerScript.LAYER_PLAYER, W0 + 1)
	_cast(imp)
	_tick(60)
	check(_hit_targets().has(first) and _hit_targets().has(second), "the bolt hits a wizard and jumps to the other")
	check(not _hit_targets().has(near), "past the nearer teammate")


func test_a_wizards_chain_skips_a_teammate() -> void:
	_build(W0, [&"chain", &"bolt"])
	var first: Node2D = _target(Vector2(100.0, 0.0), ManagerScript.LAYER_ENEMY)
	var mate: Node2D = _target(Vector2(100.0, 40.0), ManagerScript.LAYER_PLAYER, W0 + 1)
	var second: Node2D = _target(Vector2(160.0, 60.0), ManagerScript.LAYER_ENEMY)
	_cast(W0)
	_tick(60)
	check(_hit_targets().has(first) and _hit_targets().has(second), "the bolt hits an enemy and jumps to the other")
	check(not _hit_targets().has(mate), "past the nearer teammate")


func test_an_enemys_arc_zaps_another_team_only() -> void:
	var imp: int = ActorSeats.enemy(_table)
	var mate: Node2D = _target(Vector2(0.0, -30.0), ManagerScript.LAYER_ENEMY, ActorSeats.enemy(_table))
	var wizard: Node2D = _target(Vector2(0.0, 50.0), ManagerScript.LAYER_PLAYER, W0)
	_build(imp, [&"arc", &"rune"])
	_cast(imp)
	_tick(60)
	check(_hit_targets().has(wizard), "the rune zaps the wizard")
	check(not _hit_targets().has(mate), "never the nearer teammate")


# --- Triggers -----------------------------------------------------------------------------

func test_on_hurt_on_an_enemys_carrier_fires_on_its_actor_hurt() -> void:
	var imp: int = ActorSeats.enemy(_table)
	_build(imp, [&"on_hurt", &"slow", &"rune"])
	var payload: int = _spells.current_tag(imp, 0, 1)
	_cast(imp)
	_tick(2)
	_bus.actor_hurt.emit(W0, 3, Vector2(5.0, 5.0), 0, &"shot")
	check_equal(_shots(payload), 0, "a wizard's pain fires nothing of the enemy's")
	_bus.actor_hurt.emit(imp, 3, Vector2(5.0, 5.0), 0, &"shot")
	check_equal(_shots(payload), 1, "the enemy's own pain fires its payload")


# --- Unchanged ----------------------------------------------------------------------------

func test_an_orbit_circles_its_casters_anchor() -> void:
	var imp: int = ActorSeats.enemy(_table)
	_build(imp, [&"orb"])
	check_equal(_cast(imp, Vector2(200.0, 200.0)), SpellsScript.REFUSED, "with no anchor, no orbit")
	_mgr.set_anchor(imp, Vector2(200.0, 200.0))
	check(_cast(imp, Vector2(200.0, 200.0)) >= 0.0, "with its anchor it casts")
	check_equal(_mgr.get_count_for(imp), 1, "one shot round it")


func test_next_cast_reach_for_a_telegraph() -> void:
	var imp: int = ActorSeats.enemy(_table)
	check_equal(_spells.next_cast_reach(imp, 0), 0.0, "no build, no reach")
	_build(imp, [&"bolt"])
	check(is_equal_approx(_spells.next_cast_reach(imp, 0), 300.0), "a bolt reaches its speed times its life")
	_build(imp, [&"beam"])
	check(is_equal_approx(_spells.next_cast_reach(imp, 0), 200.0), "a beam its length")
	_build(imp, [&"orb"])
	check_equal(_spells.next_cast_reach(imp, 0), 0.0, "an orbit is not aimed")


func test_a_four_player_staff_is_unchanged() -> void:
	_table = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_mgr.actors = _table
	var tags: Array[int] = []
	var targets: Array[Node2D] = []
	for caster in 4:
		tags.append(_build(caster, [&"bolt"]))
		check_equal(tags[caster], SpellTag.make(caster, 0, 0, 0), "wizard %d's first tag is as before" % caster)
		targets.append(_target(Vector2(60.0 * caster, 100.0), ManagerScript.LAYER_ENEMY))
		_cast(caster, Vector2(60.0 * caster, 0.0), Vector2.DOWN)
	_tick(30)
	check_equal(_hits.size(), 4, "four wizards hit four enemies")
	for hit: Array in _hits:
		check(hit[1] == targets[hit[0]] and hit[0] == SpellTag.caster_of(hit[2]), "each as itself")
