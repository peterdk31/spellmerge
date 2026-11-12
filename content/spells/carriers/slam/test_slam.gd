extends "res://tests/support/suite.gd"
## The Slam card and its kit (content/spells/carriers/slam/, melee I8; docs/milestones/M2-staffs.md,
## "Phase I: melee", "Slam"): a mana-free melee carrier. The staff rises for its wind-up, strikes
## the floor ahead of the hand, and a ring grows from the impact, striking each body in it once
## and throwing it outward; the caster's own body is skipped and a teammate is hit. Its blast and
## `on expire` happen at the impact, and a shield or deflect works on the shots in its ring.
##
## godot --headless --path . --script res://content/spells/carriers/slam/test_slam.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")


func _card() -> FormBase:
	return load("res://content/spells/carriers/slam/slam.tres") as FormBase


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
	check_equal(CarrierSlam.of(arena.spells).slam_count(), 0, "the slam is over")
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
	arena.bus.projectile_hit.connect(func(_caster: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void: hits.append(target))
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
	arena.install_cards(0, 0, ["on_expire", "slam", "frost", "nova", "bolt"])
	arena.cast(0, 0)
	arena.run(1.5)
	check(arena.was_given(past, &"chill"), "the payload nova went off at the impact and chilled an imp out of the ring")
	arena.free_all()


func test_a_shield_blocks_and_a_deflect_throws_back_the_shots_in_its_ring() -> void:
	var arena := ArenaScript.new(root)
	var enemy: int = ActorSeats.enemy(arena.projectiles.actors)
	var blocked: Array = []
	arena.bus.shot_blocked.connect(func(_actor: int, _at: Vector2, _tag: int, _shot: int) -> void: blocked.append(1))
	arena.install_cards(0, 0, ["shield", "slam"])
	arena.cast(0, 0)
	arena.projectiles.spawn(enemy, Vector2(28.0, 30.0), Vector2(0.0, -40.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER)
	arena.run(0.5)
	check_equal(blocked.size(), 1, "the shield stops a shot in the ring")
	arena.free_all()
	arena = ArenaScript.new(root)
	enemy = ActorSeats.enemy(arena.projectiles.actors)
	var deflected: Array = []
	arena.bus.shot_deflected.connect(func(actor: int, _at: Vector2, _tag: int, _shot: int) -> void: deflected.append(actor))
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
	check_equal(CarrierSlam.of(arena.spells).slam_count(), 0, "and it is over")
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
	var risen: Vector3 = arena.spells.poses().staff_pose(0)
	check(risen.y > 4.0 and risen.z < -2.0 and risen.x < -0.5, "in the wind-up it rises, tilts up and draws back: %s" % risen)
	check(arena.spells.poses().staff_glow(0) > 0.5, "glowing as it charges: %f" % arena.spells.poses().staff_glow(0))
	arena.run(0.1)
	var struck: Vector3 = arena.spells.poses().staff_pose(0)
	check(struck.y < 2.0 and struck.z > 3.0 and struck.x > 0.3, "at the impact it is down, tilted at the floor and thrust ahead: %s" % struck)
	arena.run(0.8)
	check_equal(arena.spells.poses().staff_pose_dir(0), Vector2.ZERO, "then back on the aim")
	check_equal(arena.spells.poses().staff_glow(0), 0.0, "and dark")
	arena.free_all()


func test_its_blow_hangs_at_the_top_then_whips_down() -> void:
	# A hard hit (the owner, 2026-11-08: "start a bit slower and then accelerate"): the drop's key
	# eases "slam", so halfway through the drop the staff has come only a little of the way down,
	# and it covers the rest in the drop's last moments.
	check(is_equal_approx(StaffPoses.pose_ease(0.5, FormBase.POSE_EASES["slam"]), 0.0625), "slam eases as x to the fourth")
	check(StaffPoses.pose_ease(0.5, FormBase.POSE_EASES["slam"]) < StaffPoses.pose_ease(0.5, FormBase.POSE_EASES["in"]), "slower to start than \"in\"")
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["slam"])
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	arena.cast(0, 0)
	# The staff's turn every frame from the cast to past the impact.
	var turns: Array[float] = []
	for n in 24:
		arena.run(1.0 / 60.0)
		turns.append(arena.spells.poses().staff_pose(0).x)
	var top: int = 0
	for n in turns.size():
		top = n if turns[n] < turns[top] else top
	var hit: int = top
	while hit < turns.size() - 1 and turns[hit] < 0.3:
		hit += 1
	var mid: int = top + (hit - top) / 2
	check(hit - top >= 4, "its drop takes a few frames: %d" % (hit - top))
	check(turns[mid] - turns[top] < 0.25 * (turns[hit] - turns[top]), "halfway through its drop it has come less than a quarter of the way down: %s" % [turns])
	arena.free_all()


## The frames from the top of a slam's wind-up (its staff turned furthest back) to its blow
## landing, cast with `cards` and watched for `seconds`; and the frame of the top.
func _drop_frames(cards: Array, seconds: float) -> Vector2i:
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, cards)
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	arena.cast(0, 0)
	var turns: Array[float] = []
	for n in roundi(seconds * 60.0):
		arena.run(1.0 / 60.0)
		turns.append(arena.spells.poses().staff_pose(0).x)
	arena.free_all()
	var top: int = 0
	for n in turns.size():
		top = n if turns[n] < turns[top] - 0.0001 else top
	var hit: int = top
	while hit < turns.size() - 1 and turns[hit] < 0.3:
		hit += 1
	return Vector2i(hit - top, top)


func test_a_charged_slam_raises_its_hammer_slowly_and_still_smashes_it_down_fast() -> void:
	# The owner, 2026-11-08: with charge the slow wind-up is nice, but the hit "should be really
	# fast, like winding up a hammer and smacking it down". The blow (the last wind key) keeps the
	# card's own pace; charge's 2 s more go to the keys before it (`StaffPoses._time_wind`).
	var plain: Vector2i = _drop_frames(["slam"], 0.5)
	var charged: Vector2i = _drop_frames(["charge", "slam"], 2.6)
	check(charged.y > 60, "the charged one takes its time to the top: frame %d" % charged.y)
	check(absi(charged.x - plain.x) <= 1, "and comes down as fast as a plain slam: %d frames, plain %d" % [charged.x, plain.x])
	check(charged.x <= 8, "in a blink: %d frames" % charged.x)


func test_its_hammer_is_told_every_infusion_on_it() -> void:
	# The hammer binds each infusion in a band of its own (StaffLook): the animation hands its look
	# the spell's infusions in slot order, and none once it is over.
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["frost", "fire", "slam"])
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	arena.cast(0, 0)
	arena.run(0.1)
	var infusions: PackedColorArray = arena.spells.poses().staff_infusions(0)
	var frost: ElementBase = arena.spells.registry.call("get_resource", &"spells", &"frost")
	var fire: ElementBase = arena.spells.registry.call("get_resource", &"spells", &"fire")
	check_equal(infusions.size(), 2, "both")
	if infusions.size() == 2:
		check(Color(infusions[0].r, infusions[0].g, infusions[0].b).is_equal_approx(Color(frost.tint.r, frost.tint.g, frost.tint.b)), "frost first, as on the staff")
		check(Color(infusions[1].r, infusions[1].g, infusions[1].b).is_equal_approx(Color(fire.tint.r, fire.tint.g, fire.tint.b)), "then fire")
	arena.run(0.8)
	check(arena.spells.poses().staff_infusions(0).is_empty(), "none once it is over")
	arena.free_all()


func test_its_staff_turns_into_a_hammer_and_back() -> void:
	# The card's `hammer` channel (the owner, 2026-11-08): the staff's head grows into a hammer's as it
	# winds up, is one when it strikes, and goes back as it settles (StaffLook draws it).
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["slam"])
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	check_equal(arena.spells.poses().staff_hammer(0), 0.0, "a staff before it slams")
	arena.cast(0, 0)
	arena.run(0.1)
	var growing: float = arena.spells.poses().staff_hammer(0)
	check(growing > 0.0 and growing < 1.0, "growing in the wind-up: %f" % growing)
	arena.run(0.16)
	check(is_equal_approx(arena.spells.poses().staff_hammer(0), 1.0), "a hammer at the impact: %f" % arena.spells.poses().staff_hammer(0))
	check(is_equal_approx(arena.spells.poses().staff_grown(0), 1.0), "a slam no card grew")
	arena.run(0.8)
	check_equal(arena.spells.poses().staff_hammer(0), 0.0, "a staff again once it settles")
	arena.free_all()


func test_a_bigger_slam_tells_its_look_how_much_it_grew() -> void:
	# The hammer is drawn as big as the slam's cards grew it (`CompiledSpell.radius_scale`, read by
	# the look through `StaffPoses.staff_grown`), not from the slam's own radius.
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["bigger", "slam"])
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	arena.cast(0, 0)
	arena.run(0.1)
	var bigger: ModifierBase = arena.spells.registry.call("get_resource", &"spells", &"bigger")
	check(is_equal_approx(arena.spells.poses().staff_grown(0), bigger.radius_mult), "grown by the bigger card: %f" % arena.spells.poses().staff_grown(0))
	arena.run(0.8)
	check_equal(arena.spells.poses().staff_grown(0), 1.0, "and 1 once its animation is over")
	arena.free_all()


func test_its_staff_lands_its_tip_on_the_impact_short_of_a_wall() -> void:
	# The card's strike keys `land` the staff (StaffLook puts the drawn tip on the point struck),
	# and the slam strikes a point (`STRIKES_POINT`): `ray_length` along the locked aim, short of a wall.
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["slam"])
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	arena.cast(0, 0)
	arena.run(0.1)
	check_equal(arena.spells.poses().staff_land(0), 0.0, "rising, it lands nowhere yet")
	arena.run(0.16)
	check(is_equal_approx(arena.spells.poses().staff_land(0), 1.0), "at the impact it lands: %f" % arena.spells.poses().staff_land(0))
	check(arena.spells.poses().staff_land_point(0).is_equal_approx(Vector2(_card().ray_length, 0.0)), "on the impact, ray_length ahead: %s" % arena.spells.poses().staff_land_point(0))
	arena.run(0.8)
	check_equal(arena.spells.poses().staff_land(0), 0.0, "then it lets go")
	arena.add_wall(Rect2(10.0, -20.0, 10.0, 40.0))
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	arena.cast(0, 0)
	arena.run(0.26)
	check(arena.spells.poses().staff_land_point(0).x < 10.5, "short of a wall, on the wall: %s" % arena.spells.poses().staff_land_point(0))
	arena.free_all()


func test_its_staff_lands_along_the_aim_turned_to_in_the_wind_up() -> void:
	# Regression: the land point was worked out once, along the aim at the press, while the staff
	# turned with the live aim through the wind-up; turned after the press (plainest with reach), the
	# staff came down toward the press and jumped to the impact when it struck.
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["slam"])
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	arena.cast(0, 0)
	arena.run(0.1)
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.DOWN)
	arena.run(0.12)
	check(arena.spells.poses().staff_land(0) > 0.0, "coming down at the end of the wind-up: %f" % arena.spells.poses().staff_land(0))
	var coming: Vector2 = arena.spells.poses().staff_land_point(0)
	check(coming.is_equal_approx(Vector2(0.0, _card().ray_length)), "toward where it aims now: %s" % coming)
	arena.run(0.04)
	var impact: Vector2 = arena.spells.poses().staff_land_point(0)
	check(impact.is_equal_approx(coming), "and on the impact, with no jump: %s then %s" % [coming, impact])
	arena.free_all()


func test_a_payload_slam_moves_no_body() -> void:
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["on_hit", "bolt", "slam"])
	arena.add_imp(Vector2(60.0, 0.0))
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	arena.cast(0, 0)
	arena.run(0.5)
	check_equal(arena.spells.poses().staff_glow(0), 0.0, "the bolt's slam, cast where it hit, does not lift the wizard's staff")
	arena.free_all()


func test_clearing_the_runtime_ends_a_slam_in_its_wind_up() -> void:
	# Regression: `Spells.clear` ended beams and swings but left slams on, so a slam winding up
	# when a room was cleared still struck afterwards.
	var arena := ArenaScript.new(root)
	var near: Node2D = arena.add_imp(Vector2(34.0, 0.0))
	arena.install_cards(0, 0, ["slam"])
	arena.cast(0, 0)
	arena.run(0.05)
	check(arena.spells.is_winding(0, 0), "it is winding up (its cast, docs/milestones/cast-timing.md)")
	arena.spells.clear()
	check(not arena.spells.is_winding(0, 0), "clearing ends it")
	check_equal(CarrierSlam.of(arena.spells).slam_count(), 0, "and no slam is out")
	arena.run(1.0)
	check_equal(arena.lost(near), 0, "and it never strikes")
	arena.free_all()


func test_closing_its_caster_ends_a_slam_in_its_wind_up() -> void:
	# Regression: `Spells.close_caster` ended the caster's beams and swings but not its slams.
	var arena := ArenaScript.new(root)
	var near: Node2D = arena.add_imp(Vector2(34.0, 0.0))
	arena.install_cards(0, 0, ["slam"])
	arena.cast(0, 0)
	arena.run(0.05)
	check(arena.spells.is_winding(0, 0), "it is winding up")
	arena.spells.close_caster(0)
	check(not arena.spells.is_winding(0, 0), "closing its caster ends it")
	check_equal(CarrierSlam.of(arena.spells).slam_count(), 0, "and no slam is out")
	arena.run(1.0)
	check_equal(arena.lost(near), 0, "and it never strikes")
	arena.free_all()


## Its looks (S6 2): the cue each moment plays (every cue a card names is a cue file:
## tests/content/spells/test_carrier_looks.gd).
func test_its_moments_have_their_cues() -> void:
	var card: FormBase = load("res://content/spells/carriers/slam/slam.tres") as FormBase
	check_equal(card.end_cue, &"slam", "its end plays slam")
