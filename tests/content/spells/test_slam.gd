extends "res://tests/support/suite.gd"
## The Slam card and its kit (content/spells/forms/slam/, melee I8; docs/milestones/M2-staffs.md,
## "Phase I: melee", "Slam"): a mana-free melee carrier. The staff rises for its wind-up, strikes
## the floor ahead of the hand, and a ring grows from the impact, striking each body in it once
## and throwing it outward; the caster's own body is skipped and a teammate is hit. Its blast and
## `on expire` happen at the impact, and a shield or deflect works on the shots in its ring.
##
## godot --headless --path . --script res://tests/content/spells/test_slam.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")


func _card() -> FormBase:
	return load("res://content/spells/forms/slam/slam.tres") as FormBase


func test_the_card_is_a_valid_carrier() -> void:
	var card: FormBase = _card()
	check(card != null, "slam.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"slam", "its id is its folder")
	check_equal(card.carrier, &"slam", "it is a slam")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check_equal(card.mana_cost, 0.0, "it costs no mana")
	check(card.wind_up > 0.0, "it winds up, so it can be seen coming")


func test_nothing_is_hit_before_it_strikes_then_the_ring_hits_round_the_impact() -> void:
	var arena := ArenaScript.new(root)
	var near: Node2D = arena.add_imp(Vector2(34.0, 0.0))
	var side: Node2D = arena.add_imp(Vector2(20.0, 14.0))
	var behind: Node2D = arena.add_imp(Vector2(-20.0, 0.0))
	var far: Node2D = arena.add_imp(Vector2(90.0, 0.0))
	arena.install_cards(0, 0, ["slam"])
	check(arena.spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 0.0) != SpellsScript.REFUSED, "no mana needed")
	arena.run(_card().wind_up - 0.05)
	check_equal(arena.lost(near), 0, "nothing during the wind-up")
	arena.run(0.5)
	check_equal(arena.lost(near), _card().base_damage, "the imp past the impact is hit once")
	check_equal(arena.lost(side), _card().base_damage, "and the one beside it")
	check_equal(arena.lost(behind), 0, "not the one behind the caster")
	check_equal(arena.lost(far), 0, "nor one outside the ring")
	check_equal(arena.spells.slam_count(), 0, "the slam is over")
	arena.free_all()


func test_it_throws_bodies_outward_from_the_impact() -> void:
	var arena := ArenaScript.new(root)
	arena.pushable = true
	var ahead: Node2D = arena.add_imp(Vector2(34.0, 0.0))
	var beside: Node2D = arena.add_imp(Vector2(20.0, 14.0))
	arena.install_cards(0, 0, ["slam"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(ahead.global_position.x > 40.0, "the imp past the impact is thrown on: %s" % ahead.global_position)
	check(beside.global_position.y > 20.0, "the one beside it is thrown sideways: %s" % beside.global_position)
	arena.free_all()


func test_its_caster_is_skipped_and_a_teammate_is_hit() -> void:
	var arena := ArenaScript.new(root)
	var hits: Array = []
	arena.bus.projectile_hit.connect(func(_caster: int, target: Node, _at: Vector2, _tag: int) -> void: hits.append(target))
	var own: Node2D = arena.add_guard(0, Vector2(8.0, 0.0))
	var mate: Node2D = arena.add_mate(Vector2(24.0, 8.0), 1)
	arena.install_cards(0, 0, ["slam"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(not hits.has(own), "the caster's own body is not struck")
	check(hits.has(mate), "a teammate in the ring is")
	arena.free_all()


func test_its_blast_and_payload_go_off_at_the_impact() -> void:
	var arena := ArenaScript.new(root)
	var past: Node2D = arena.add_imp(Vector2(20.0, 56.0))
	arena.install_cards(0, 0, ["on_expire", "slam", "frost", "nova"])
	arena.cast(0, 0)
	arena.run(1.5)
	check(arena.was_given(past, &"chill"), "the payload nova went off at the impact and chilled an imp out of the ring")
	arena.free_all()


func test_a_shield_blocks_and_a_deflect_throws_back_the_shots_in_its_ring() -> void:
	var arena := ArenaScript.new(root)
	var enemy: int = ActorSeats.enemy(arena.projectiles.actors)
	var blocked: Array = []
	arena.bus.shot_blocked.connect(func(_actor: int, _at: Vector2, _tag: int) -> void: blocked.append(1))
	arena.install_cards(0, 0, ["shield", "slam"])
	arena.cast(0, 0)
	arena.projectiles.spawn(enemy, Vector2(28.0, 30.0), Vector2(0.0, -40.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER)
	arena.run(0.5)
	check_equal(blocked.size(), 1, "the shield stops a shot in the ring")
	arena.free_all()
	arena = ArenaScript.new(root)
	enemy = ActorSeats.enemy(arena.projectiles.actors)
	var deflected: Array = []
	arena.bus.shot_deflected.connect(func(actor: int, _at: Vector2, _tag: int) -> void: deflected.append(actor))
	arena.install_cards(0, 0, ["deflect", "slam"])
	arena.cast(0, 0)
	var shot: int = arena.projectiles.spawn(enemy, Vector2(28.0, 30.0), Vector2(0.0, -40.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER)
	arena.run(0.5)
	check_equal(deflected, [0], "the deflect turns it as the caster's")
	check(arena.projectiles.get_velocity_of(shot).y > 0.0, "back out of the ring: %s" % arena.projectiles.get_velocity_of(shot))
	arena.free_all()


func test_a_payload_slam_ends_a_sweep() -> void:
	# `on expire · swing · slam`: one press, a sweep, then a slam from the end of its arc.
	var arena := ArenaScript.new(root)
	var slams: Array[Vector2] = []
	arena.bus.form_shown.connect(func(_caster: int, form: StringName, at: Vector2, _dir: Vector2, _length: float, _tint: Color, _look: int) -> void:
		if form == &"slam":
			slams.append(at))
	arena.install_cards(0, 0, ["on_expire", "swing", "slam"])
	arena.cast(0, 0)
	arena.run(1.0)
	check_equal(slams.size(), 1, "one slam after the sweep")
	if slams.size() == 1:
		check(slams[0].length() > 30.0, "struck ahead of the arc's end, not of the hand: %s" % slams[0])
	check_equal(arena.spells.slam_count(), 0, "and it is over")
	arena.free_all()


func test_four_players_slam_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 200.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(34.0, 0.0)))
		arena.install_cards(player, 0, ["slam"])
	for player in 4:
		check(arena.cast(player, 0), "player %d slams" % player)
	arena.run(1.0)
	for imp in imps:
		check_equal(arena.lost(imp), _card().base_damage, "every imp past its player's impact took the hit")
	arena.free_all()


func test_its_staff_rises_glowing_drops_and_settles() -> void:
	# The card's animation (`staff_pose`), played for the wizard's body by Spells.
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["slam"])
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	arena.cast(0, 0)
	arena.run(0.18)
	var risen: Vector3 = arena.spells.staff_pose(0)
	check(risen.y > 4.0 and risen.z < -2.0 and risen.x < -0.5, "in the wind-up it rises, tilts up and draws back: %s" % risen)
	check(arena.spells.staff_glow(0) > 0.5, "glowing as it charges: %f" % arena.spells.staff_glow(0))
	arena.run(0.1)
	var struck: Vector3 = arena.spells.staff_pose(0)
	check(struck.y < 2.0 and struck.z > 3.0 and struck.x > 0.3, "at the impact it is down, tilted at the floor and thrust ahead: %s" % struck)
	arena.run(0.8)
	check_equal(arena.spells.staff_pose_dir(0), Vector2.ZERO, "then back on the aim")
	check_equal(arena.spells.staff_glow(0), 0.0, "and dark")
	arena.free_all()


func test_a_payload_slam_moves_no_body() -> void:
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["on_hit", "bolt", "slam"])
	arena.add_imp(Vector2(60.0, 0.0))
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	arena.cast(0, 0)
	arena.run(0.5)
	check_equal(arena.spells.staff_glow(0), 0.0, "the bolt's slam, cast where it hit, does not lift the wizard's staff")
	arena.free_all()
