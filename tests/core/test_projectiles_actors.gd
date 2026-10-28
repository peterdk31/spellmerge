extends "res://tests/support/suite.gd"
## Casters in core/projectiles are actor ids (actors G3a, docs/milestones/M2-actors.md): nothing
## asks "player or enemy"; the actor table answers a shot's team (aim: homing, nearest_target,
## shields), ramp (look and batch) and budget (drop bucket). Events carry the actor id. Every
## shot hits every body but its caster's own. The wizards here sit at ids that are not their
## seats (enemies at 0-6, wizards at 7-10 seated 0-3), so no test passes by a seat number
## standing in for an id. The manager is stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectiles_actors.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const SpellTagScript := preload("res://core/spells/spell_tag.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const DT: float = 1.0 / 60.0
## Enemies (unseated) at ids 0-6.
const IMP: int = 2
const OTHER_IMP: int = 3
## Wizards at ids 7-10, seated 0-3.
const WIZ_0: int = 7
const WIZ_1: int = 8
## An id no actor has.
const NOBODY: int = 100

var mgr: ManagerScript
var bus: EventsScript
var table: ActorsScript
## Every projectile_hit as [caster, target, tag].
var hits: Array = []
## Every projectile_expired and projectile_impact's caster.
var expired: Array[int] = []
var impacts: Array[int] = []
## Every shot_blocked as [caster, tag].
var blocked: Array = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	table = own(ActorSeats.table(4, 7)) as ActorsScript
	mgr.actors = table
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	root.add_child(mgr)
	hits.clear()
	expired.clear()
	impacts.clear()
	blocked.clear()
	bus.projectile_hit.connect(func(caster: int, target: Node, _at: Vector2, tag: int) -> void: hits.append([caster, target, tag]))
	bus.projectile_expired.connect(func(caster: int, _at: Vector2, _tag: int) -> void: expired.append(caster))
	bus.projectile_impact.connect(func(caster: int, _target: Node, _at: Vector2, _dir: Vector2) -> void: impacts.append(caster))
	bus.shot_blocked.connect(func(caster: int, _at: Vector2, tag: int) -> void: blocked.append([caster, tag]))


func _target(at: Vector2, layer: int, owner: int = EventsScript.NO_PLAYER) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	mgr.add_target(node, 8.0, layer, owner)
	return node


## An enemy body at `at` owned by the actor `caster` (as the AI registers it, then names it).
func _enemy(at: Vector2, caster: int) -> Node2D:
	var node: Node2D = _target(at, ManagerScript.LAYER_ENEMY)
	check(mgr.set_target_owner(node, caster), "the enemy's body takes its actor")
	return node


func _run(steps: int) -> void:
	for _i in steps:
		mgr.step(DT)


func _hit_targets() -> Array[Node]:
	var out: Array[Node] = []
	for hit: Array in hits:
		out.append(hit[1] as Node)
	return out


func _homing(caster: int) -> Vector2:
	return mgr.homing_point(caster, Vector2(100.0, 100.0), Vector2.RIGHT, PI, ManagerScript.ACTOR_LAYERS, 300.0, 0, 1)


func test_the_table_has_wizards_at_non_seat_ids() -> void:
	check_equal(table.seat_of(WIZ_0), 0, "id 7 is seat 0's wizard")
	check_equal(table.seat_of(WIZ_1), 1, "id 8 is seat 1's")
	check_equal(table.seat_of(0), ActorsScript.NONE, "id 0 is an unseated enemy")
	check(ManagerScript.is_caster(ManagerScript.ACTORS - 1) and not ManagerScript.is_caster(ManagerScript.ACTORS), "every actor id is a caster, the one after is not")
	check(ManagerScript.is_caster(EventsScript.NO_PLAYER), "no actor is a caster too")


func test_a_hit_and_its_impact_carry_the_casters_actor_id() -> void:
	var tag: int = SpellTagScript.make(IMP, 0, 1, 0)
	var wizard: Node2D = _target(Vector2(200.0, 100.0), ManagerScript.LAYER_PLAYER, WIZ_0)
	mgr.spawn(IMP, Vector2(100.0, 100.0), Vector2(300.0, 0.0), 2.0, 4.0, ManagerScript.LAYER_PLAYER, 0, tag)
	_run(30)
	check(hits.size() == 1 and hits[0][1] == wizard and hits[0][0] == IMP and hits[0][2] == tag, "the hit names the enemy's id and its tag")
	check(not impacts.is_empty() and impacts.all(func(c: int) -> bool: return c == IMP), "its impacts name the id too")


func test_an_expiry_carries_the_casters_actor_id() -> void:
	mgr.spawn(WIZ_1, Vector2(300.0, 300.0), Vector2(10.0, 0.0), 0.1, 4.0)
	mgr.spawn(IMP, Vector2(300.0, 200.0), Vector2(10.0, 0.0), 0.1, 4.0)
	_run(10)
	expired.sort()
	check_equal(expired, [IMP, WIZ_1] as Array[int], "each expiry names its caster's id, never a seat")


func test_a_shield_block_carries_the_shields_actor_id() -> void:
	var ward: int = mgr.spawn(WIZ_1, Vector2(200.0, 200.0), Vector2.ZERO, 3.0, 6.0, ManagerScript.LAYER_ENEMY, 0, 9)
	mgr.set_shield(ward, 1)
	mgr.spawn(IMP, Vector2(260.0, 200.0), Vector2(-200.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER)
	_run(30)
	check(blocked.size() == 1 and blocked[0][0] == WIZ_1 and blocked[0][1] == 9, "shot_blocked names the shield's actor (8, not seat 1) and its tag")


## Everything hurts everything (actors G3c): an enemy's spell hits the other enemies whatever
## layer it was given, never its own body; a shot of no actor hits enemies too.
func test_an_enemys_spell_hits_the_others_but_never_itself() -> void:
	var imp: Node2D = _enemy(Vector2(100.0, 100.0), IMP)
	var other: Node2D = _enemy(Vector2(200.0, 100.0), OTHER_IMP)
	mgr.spawn(IMP, Vector2(100.0, 100.0), Vector2(300.0, 0.0), 2.0, 4.0, ManagerScript.LAYER_PLAYER)
	mgr.spawn(EventsScript.NO_PLAYER, Vector2(200.0, 160.0), Vector2(0.0, -300.0), 2.0, 4.0, ManagerScript.LAYER_PLAYER)
	_run(40)
	check_equal(_hit_targets(), [other, other] as Array[Node], "the enemy's shot and the no-actor one each hit the other enemy")
	check(not _hit_targets().has(imp), "never the caster's own body")
	hits.clear()
	mgr.ray(IMP, Vector2(100.0, 100.0), Vector2.RIGHT, 200.0, 0, ManagerScript.LAYER_PLAYER)
	check_equal(_hit_targets(), [other] as Array[Node], "its beam hits the other enemy too")


func test_a_wizards_spell_hits_a_teammate_but_never_itself() -> void:
	var own_body: Node2D = _target(Vector2(100.0, 100.0), ManagerScript.LAYER_PLAYER, WIZ_0)
	var mate: Node2D = _target(Vector2(200.0, 100.0), ManagerScript.LAYER_PLAYER, WIZ_1)
	mgr.spawn(WIZ_0, Vector2(100.0, 100.0), Vector2(300.0, 0.0), 2.0, 4.0, ManagerScript.LAYER_ENEMY)
	_run(30)
	check_equal(_hit_targets(), [mate] as Array[Node], "a shot given only the enemy layer hits the teammate")
	check(not _hit_targets().has(own_body), "never its caster's own body")


func test_a_seats_wizard_counts_in_its_seats_bucket() -> void:
	mgr.spawn(WIZ_0, Vector2(20.0, 20.0), Vector2.ZERO, 30.0)
	mgr.spawn(WIZ_0, Vector2(30.0, 20.0), Vector2.ZERO, 30.0)
	check_equal(mgr.get_count_for(WIZ_0), 2, "id 7 counts its shots")
	check_equal(mgr.get_count_for_budget(0), 2, "in seat 0's bucket")
	check_equal(mgr.get_count_for(0), 0, "not in the bucket of actor 0, an enemy")


func test_unseated_enemies_share_one_bucket() -> void:
	for i in 7:
		mgr.spawn(i, Vector2(20.0 + i, 60.0), Vector2.ZERO, 30.0, 4.0, ManagerScript.LAYER_PLAYER)
	check_equal(mgr.get_count_for_budget(ActorsScript.SHARED), 7, "every enemy counts in SHARED")
	check_equal(mgr.get_count_for(IMP), 7, "each enemy's count is the shared one")
	check_equal(mgr.get_count_for(EventsScript.NO_PLAYER), 7, "a shot of no actor's too")
	check_equal(mgr.get_count_for(WIZ_0), 0, "a seat's bucket is apart")


func test_at_the_cap_the_richest_budget_loses_its_oldest() -> void:
	mgr.set_cap(8)
	var ended: Array[int] = []
	mgr.shot_ended.connect(func(tag: int) -> void: ended.append(tag))
	mgr.spawn(WIZ_0, Vector2(20.0, 20.0), Vector2.ZERO, 30.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 11)
	for i in 4:
		mgr.spawn(WIZ_0, Vector2(30.0 + i, 20.0), Vector2.ZERO, 30.0)
	for i in 3:
		mgr.spawn(i, Vector2(20.0 + i, 60.0), Vector2.ZERO, 30.0, 4.0, ManagerScript.LAYER_PLAYER)
	mgr.spawn(WIZ_1, Vector2(100.0, 100.0), Vector2.ZERO, 30.0)
	check_equal(mgr.dropped, 1, "one shot dropped")
	check_equal(ended, [11] as Array[int], "the richest budget (seat 0, at id 7) lost its oldest")
	check_equal(mgr.get_count_for(WIZ_0), 4, "seat 0 keeps four")
	check_equal(mgr.get_count_for_budget(ActorsScript.SHARED), 3, "the enemies keep theirs")
	check_equal(mgr.get_count_for(WIZ_1), 1, "the newcomer is in")


func test_at_the_cap_a_tie_drops_from_the_shared_budget() -> void:
	mgr.set_cap(8)
	for i in 4:
		mgr.spawn(WIZ_0, Vector2(30.0 + i, 20.0), Vector2.ZERO, 30.0)
	for i in 4:
		mgr.spawn(i, Vector2(20.0 + i, 60.0), Vector2.ZERO, 30.0, 4.0, ManagerScript.LAYER_PLAYER)
	mgr.spawn(WIZ_1, Vector2(100.0, 100.0), Vector2.ZERO, 30.0)
	check_equal(mgr.dropped, 1, "one shot dropped")
	check_equal(mgr.get_count_for(WIZ_0), 4, "the seat keeps its shots on a tie")
	check_equal(mgr.get_count_for_budget(ActorsScript.SHARED), 3, "the shared budget gives one up")


func test_an_enemy_orbit_follows_its_own_anchor_and_ends_with_it() -> void:
	check_equal(mgr.spawn_orbit(IMP, 20.0, 0.0, 1.0, 5.0), -1, "no anchor, no orbit")
	mgr.set_anchor(IMP, Vector2(300.0, 200.0))
	mgr.set_anchor(WIZ_0, Vector2(100.0, 100.0))
	var slot: int = mgr.spawn_orbit(IMP, 20.0, 0.0, 0.0, 5.0, 4.0, ManagerScript.LAYER_PLAYER)
	check(slot >= 0, "an enemy's orbit spawns round its anchor")
	mgr.set_anchor(IMP, Vector2(340.0, 200.0))
	_run(1)
	check(mgr.get_position_of(slot).is_equal_approx(Vector2(360.0, 200.0)), "and follows it (%s)" % mgr.get_position_of(slot))
	mgr.clear_anchor(IMP)
	_run(2)
	check(not mgr.is_alive(slot), "clearing the anchor ends it")
	check(expired.is_empty(), "quietly")
	check_equal(mgr.get_anchor(WIZ_0), Vector2(100.0, 100.0), "a wizard's anchor is untouched")
	check_equal(mgr.spawn_orbit(EventsScript.NO_PLAYER, 20.0, 0.0, 1.0, 5.0, 4.0, ManagerScript.LAYER_PLAYER, 0, 0, Vector2(50.0, 50.0)), -1, "no actor has no orbit")


func test_a_shield_stops_other_teams_shots_but_not_its_own_teams() -> void:
	var guard: int = mgr.spawn(IMP, Vector2(200.0, 100.0), Vector2.ZERO, 3.0, 6.0, ManagerScript.LAYER_PLAYER, 0, 7)
	check(mgr.set_shield(guard, 2), "an enemy's shot can have a shield")
	var friend: int = mgr.spawn(OTHER_IMP, Vector2(150.0, 100.0), Vector2(200.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER)
	var bolt: int = mgr.spawn(WIZ_1, Vector2(250.0, 100.0), Vector2(-200.0, 0.0), 3.0, 3.0)
	_run(30)
	check(mgr.is_alive(friend), "another enemy's shot passes")
	check(not mgr.is_alive(bolt), "a wizard's bolt is stopped")
	check(blocked.size() == 1 and blocked[0][0] == IMP and blocked[0][1] == 7, "one block, named by the shield's actor and tag")


func test_homing_picks_only_other_teams() -> void:
	var wizard: Node2D = _target(Vector2(200.0, 60.0), ManagerScript.LAYER_PLAYER, WIZ_1)
	var imp: Node2D = _enemy(Vector2(200.0, 140.0), OTHER_IMP)
	check_equal(_homing(IMP), wizard.global_position, "an enemy's homing finds the wizard, never another enemy")
	check_equal(_homing(WIZ_0), imp.global_position, "a wizard's finds the enemy, never its teammate")


func test_homing_never_picks_its_casters_own_body() -> void:
	_enemy(Vector2(200.0, 100.0), NOBODY)
	check_equal(_homing(NOBODY), Vector2.INF, "even with no team, a caster never homes on its own body")


func test_nearest_target_skips_the_given_team() -> void:
	var wizard: Node2D = _target(Vector2(110.0, 100.0), ManagerScript.LAYER_PLAYER, WIZ_0)
	var imp: Node2D = _enemy(Vector2(140.0, 100.0), IMP)
	var at: Vector2 = Vector2(100.0, 100.0)
	check(mgr.nearest_target(at, 100.0, ManagerScript.ACTOR_LAYERS) == wizard, "with no team, the nearest is the wizard")
	check(mgr.nearest_target(at, 100.0, ManagerScript.ACTOR_LAYERS, null, null, ActorsScript.TEAM_WIZARDS) == imp, "the wizards' team skips the wizard")
	check(mgr.nearest_target(at, 100.0, ManagerScript.ACTOR_LAYERS, null, null, ActorsScript.TEAM_ENEMIES) == wizard, "the enemies' team skips the enemy")


func test_a_wizard_draws_in_its_hat_ramp_and_an_enemy_in_the_enemy_batch() -> void:
	mgr.spawn(WIZ_1, Vector2(250.0, 100.0), Vector2(100.0, 0.0), 2.0, 5.0)
	mgr.spawn(IMP, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 2.0, 5.0, ManagerScript.LAYER_PLAYER)
	mgr.update_draw(1.0)
	check_equal(mgr.drawn, 2, "both drawn")
	check_equal(mgr.drawn_enemy, 1, "the enemy's in the enemy batch")
	var hat: PackedFloat32Array = mgr._draw_node.multimesh.buffer
	var red: int = roundi(hat[8] * 255.0)
	var hat_bits: int = roundi(hat[11] * 255.0) << 16
	check_equal(red % 4, 1, "the wizard at id 8 (seat 1) draws in hat ramp 1")
	check_equal(hat_bits & ManagerScript.LOOK_ENEMY_RAMP, 0, "without the enemy ramp's flag")
	var enemy: PackedFloat32Array = mgr._enemy_node.multimesh.buffer
	var bits: int = roundi(enemy[9] * 255.0) | (roundi(enemy[10] * 255.0) << 8) | (roundi(enemy[11] * 255.0) << 16)
	check(roundi(enemy[8] * 255.0) % 4 == 0 and (bits & ManagerScript.LOOK_ENEMY_RAMP) != 0, "the enemy's shot has the enemy ramp's flag")


func test_enemy_shots_are_drawn_by_the_shader_above_the_hats() -> void:
	mgr.set_anchor(IMP, Vector2(300.0, 200.0))
	var bolt: int = mgr.spawn(IMP, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 2.0, 5.0, ManagerScript.LAYER_PLAYER)
	mgr.set_look(bolt, ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_EMBERS])))
	mgr.spawn(IMP, Vector2(150.0, 100.0), Vector2.ZERO, 2.0, 14.0, ManagerScript.LAYER_PLAYER, 0, 0, ManagerScript.MOTION_STILL)
	mgr.spawn_orbit(IMP, 20.0, 0.0, 1.0, 2.0, 5.0, ManagerScript.LAYER_PLAYER)
	mgr.update_draw(1.0)
	check_equal(mgr.drawn_enemy, 3, "a bolt, a rune and an orbit shot in the enemy batch")
	var node: MultiMeshInstance2D = mgr._enemy_node
	check(node.material is ShaderMaterial, "drawn by the shot shader")
	check_equal(node.z_index, mgr._draw_node.z_index + 1, "one layer above the hat ramps' shots")
	var kinds: Array[int] = []
	var buffer: PackedFloat32Array = node.multimesh.buffer
	for i in 3:
		var at: int = i * ManagerScript.DRAW_STRIDE
		var kind: int = roundi((1.0 - buffer[at + 15]) * ManagerScript.KIND_STEPS)
		# A shot in flight is drawn as its trail; an orbit shot's is flagged so.
		if kind == ManagerScript.KIND_BOLT and (roundi(buffer[at + 5]) & ManagerScript.TRAIL_ORBIT) != 0:
			kind = ManagerScript.KIND_ORBIT
		kinds.append(kind)
		var bits: int = roundi(buffer[at + 9] * 255.0) | (roundi(buffer[at + 10] * 255.0) << 8) | (roundi(buffer[at + 11] * 255.0) << 16)
		if kind == ManagerScript.KIND_BOLT:
			check_equal(bits & ~ManagerScript.LOOK_ENEMY_RAMP, ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_EMBERS])), "the bolt keeps its cards' look")
	kinds.sort()
	check_equal(kinds, [ManagerScript.KIND_BOLT, ManagerScript.KIND_RUNE, ManagerScript.KIND_ORBIT] as Array[int], "each its own body")


func test_the_ramp_colours_are_four_hats_and_blight() -> void:
	check_equal(ManagerScript.RAMP_COLORS.size(), 5, "four hat ramps and the enemy ramp")
	check_equal(ManagerScript.RAMP_COLORS[ActorsScript.RAMP_ENEMY], Color("#a68a2a"), "the enemy ramp is Blight ochre")
	check_equal(ManagerScript.ramp_color(ActorsScript.NONE), Color("#a68a2a"), "no ramp draws as Blight")
	for ramp in 4:
		check(ManagerScript.is_hat_ramp(ramp), "ramp %d is a hat" % ramp)
	check(not ManagerScript.is_hat_ramp(ActorsScript.RAMP_ENEMY), "the enemy ramp is not")


func test_the_look_statics_take_a_ramp() -> void:
	check_equal(ManagerScript.look_red(2, 1), 2 + 4, "a hat ramp in the red, beside the zoom")
	check_equal(ManagerScript.look_red(ActorsScript.RAMP_ENEMY, 1), 4, "the enemy ramp adds nothing to the red")
	check_equal(ManagerScript.ramp_look(1, ManagerScript.LOOK_ENEMY_RAMP), 0, "a hat ramp clears the enemy flag")
	check_equal(ManagerScript.ramp_look(ActorsScript.RAMP_ENEMY, 0), ManagerScript.LOOK_ENEMY_RAMP, "the enemy ramp sets it")
	check_equal(ManagerScript.look_color(3, 2, 0), Color(float(3 + 8) / 255.0, 0.0, 0.0, 0.0), "look_color packs the ramp and zoom")


func test_tint_of_a_caster_follows_its_ramp() -> void:
	check(mgr.tint_of(WIZ_1).is_equal_approx(ManagerScript.ramp_tint(1)), "the wizard at id 8 tints in hat ramp 1")
	check(mgr.tint_of(IMP).is_equal_approx(ManagerScript.ramp_tint(ActorsScript.RAMP_ENEMY)), "an enemy in the enemy ramp")
	check(mgr.look_color_for(WIZ_1, 1, 0) == ManagerScript.look_color(1, 1, 0), "look_color_for reads the caster's ramp")


func test_an_unopened_id_is_no_actor() -> void:
	check(mgr.tint_of(NOBODY).is_equal_approx(ManagerScript.ramp_tint(ActorsScript.RAMP_ENEMY)), "drawn in the enemy ramp")
	mgr.spawn(NOBODY, Vector2(20.0, 20.0), Vector2.ZERO, 30.0)
	check_equal(mgr.get_count_for_budget(ActorsScript.SHARED), 1, "it spends the shared budget")
	var wizard: Node2D = _target(Vector2(200.0, 60.0), ManagerScript.LAYER_PLAYER, WIZ_0)
	check_equal(_homing(NOBODY), wizard.global_position, "with no team it homes on a wizard")
	mgr.remove_target(wizard)
	var imp: Node2D = _enemy(Vector2(200.0, 140.0), IMP)
	check_equal(_homing(NOBODY), imp.global_position, "and on an enemy")
