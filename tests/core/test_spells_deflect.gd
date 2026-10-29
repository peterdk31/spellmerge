extends "res://tests/support/suite.gd"
## Deflect (melee I3; docs/milestones/M2-staffs.md, "Phase I: melee", "Deflect"): a shot of another
## team that touches a deflecting carrier turns off it, flies 1.7 times faster with its life
## started again, and becomes the carrier's caster's (its team, hit credit and targets); a rally
## speeds up each time. It works on every carrier that touches shots: a shot (bolt, orbit, wall),
## a swing's sweep and a beam's line. With a shield on the same carrier the deflect goes first
## (owner, 2026-10-29), so the compiler lists the shield as wasted; a deflect sets off `on block`.
## Swings and beams now touch shots, so a shield on them blocks too (the parry). The deflect card
## is made in code here (its card is I5); the rest are the real cards, in the combo arena.
##
## godot --headless --path . --script res://tests/core/test_spells_deflect.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

var arena: ArenaScript
var enemy: int = -1
## Every shot_deflected and shot_blocked as [actor, tag].
var deflected: Array = []
var blocked: Array = []


func before_each() -> void:
	arena = ArenaScript.new(root)
	var card := ModifierBase.new()
	card.id = &"deflect"
	card.display_name = "Deflect"
	card.complexity = 2
	card.behaviour = ModifierBase.Behaviour.DEFLECT
	card.behaviour_strength = 1.0
	(arena.registry.get("_resources")[&"spells"] as Dictionary)[&"deflect"] = card
	enemy = ActorSeats.enemy(arena.projectiles.actors)
	deflected.clear()
	blocked.clear()
	arena.bus.shot_deflected.connect(func(actor: int, _at: Vector2, tag: int) -> void: deflected.append([actor, tag]))
	arena.bus.shot_blocked.connect(func(actor: int, _at: Vector2, tag: int) -> void: blocked.append([actor, tag]))


func after_each() -> void:
	arena.free_all()


## An enemy shot at `at` flying with `velocity`, hitting wizards (radius 3, 3 s of life).
func _enemy_shot(at: Vector2, velocity: Vector2) -> int:
	return arena.projectiles.spawn(enemy, at, velocity, 3.0, 3.0, ManagerScript.LAYER_PLAYER)


## A real enemy bolt (its hits hurt) from `from` toward the origin; returns its slot.
func _enemy_bolt(from: Vector2) -> int:
	arena.shoot_at(from, Vector2.ZERO)
	# The cast's shot is launched on the next step.
	arena.run(1.0 / 60.0)
	for slot in 512:
		if arena.projectiles.is_alive(slot):
			return slot
	return -1


func _cast(cards: Array) -> CompiledStaff:
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	check(arena.cast(0, 0), "%s is cast" % [cards])
	return staff


func test_a_deflecting_swing_bats_an_enemy_shot_back_as_its_casters() -> void:
	# The sweep runs from 0.12 s to 0.18 s; the enemy bolt (220 px/s) is 34 to 20 px away then.
	var shot: int = _enemy_bolt(Vector2(60.0, 0.0))
	var speed: float = arena.projectiles.get_velocity_of(shot).length()
	var imp: Node2D = arena.add_imp(Vector2(150.0, 0.0))
	_cast(["deflect", "swing"])
	arena.run(0.25)
	check_equal(deflected.size(), 1, "one deflect")
	check_equal(arena.projectiles.get_actor_of(shot), 0, "the shot is the swinging wizard's now")
	var way: Vector2 = arena.projectiles.get_velocity_of(shot)
	check(way.x > 0.0, "it flies out, away from the hand: %s" % way)
	check(is_equal_approx(way.length(), speed * SpellLimits.DEFLECT_SPEEDUP), "1.7 times faster: %f" % way.length())
	arena.run(1.0)
	check(arena.lost(imp) > 0, "it hits the enemies' side now")


func test_a_rally_speeds_up_each_time_and_the_shot_changes_hands() -> void:
	var shot: int = _enemy_shot(Vector2(100.0, 0.0), Vector2(-100.0, 0.0))
	check(arena.projectiles.deflect_shot(shot, 0, Vector2.RIGHT, 7), "the wizard deflects it")
	check_equal(arena.projectiles.get_actor_of(shot), 0, "it is the wizard's")
	check(arena.projectiles.get_velocity_of(shot).is_equal_approx(Vector2(170.0, 0.0)), "mirrored and 1.7 times faster")
	check(arena.projectiles.deflect_shot(shot, enemy, Vector2.LEFT, 9), "the enemy deflects it back")
	check_equal(arena.projectiles.get_actor_of(shot), enemy, "it is the enemy's again")
	check(arena.projectiles.get_velocity_of(shot).is_equal_approx(Vector2(-289.0, 0.0)), "faster again: %s" % arena.projectiles.get_velocity_of(shot))
	check_equal(deflected, [[0, 7], [enemy, 9]], "each deflect is announced with the deflecting carrier")


func test_a_shot_already_going_away_keeps_its_way() -> void:
	var shot: int = _enemy_shot(Vector2(100.0, 0.0), Vector2(100.0, 0.0))
	arena.projectiles.deflect_shot(shot, 0, Vector2.RIGHT, 7)
	check(arena.projectiles.get_velocity_of(shot).is_equal_approx(Vector2(170.0, 0.0)), "not turned back in, only faster")


func test_a_deflected_homing_shot_hunts_its_new_casters_enemies() -> void:
	# An enemy homing shot comes for the wizard; batted back, it bends onto an imp off its line.
	var shot: int = _enemy_bolt(Vector2(60.0, 0.0))
	arena.projectiles.set_homing(shot, 6.0, 200.0)
	var imp: Node2D = arena.add_imp(Vector2(90.0, 50.0))
	_cast(["deflect", "swing"])
	arena.run(2.0)
	check_equal(deflected.size(), 1, "deflected")
	check(arena.lost(imp) > 0, "it turned onto the imp off its line")


func test_a_deflecting_orbit_turns_a_shot_that_flies_into_its_ring() -> void:
	# Where the orbit shot starts (its radius out along the aim), coming in slowly.
	_cast(["deflect", "orbit"])
	var shot: int = _enemy_shot(Vector2(38.0, 0.0), Vector2(-10.0, 0.0))
	arena.run(0.2)
	check(deflected.size() >= 1, "the ring deflects it")
	check_equal(arena.projectiles.get_actor_of(shot), 0, "it is the wizard's now")


func test_a_deflecting_wall_sends_shots_back() -> void:
	_cast(["deflect", "wall"])
	var shot: int = _enemy_shot(Vector2(90.0, 0.0), Vector2(-60.0, 0.0))
	arena.run(1.5)
	check(deflected.size() >= 1, "the wall deflects it")
	check(arena.projectiles.get_velocity_of(shot).x > 0.0, "back the way it came")


func test_a_deflecting_beam_mirrors_a_shot_crossing_it() -> void:
	_cast(["deflect", "beam"])
	var shot: int = _enemy_shot(Vector2(100.0, -30.0), Vector2(0.0, 150.0))
	arena.run(0.3)
	check_equal(deflected.size(), 1, "the beam deflects it")
	var way: Vector2 = arena.projectiles.get_velocity_of(shot)
	check(way.y < 0.0 and is_equal_approx(way.length(), 150.0 * SpellLimits.DEFLECT_SPEEDUP), "mirrored off the line, faster: %s" % way)


func test_a_shielded_swing_parries_and_a_shielded_beam_blocks() -> void:
	_enemy_shot(Vector2(60.0, 0.0), Vector2(-200.0, 0.0))
	_cast(["shield", "swing"])
	arena.run(0.3)
	check_equal(blocked.size(), 1, "the swing's shield stops the shot (the parry)")
	check_equal(deflected.size(), 0, "nothing deflected")
	blocked.clear()
	arena.install_cards(1, 0, ["shield", "beam"])
	arena.place_caster(1, Vector2(0.0, 200.0))
	arena.cast(1, 0)
	_enemy_shot(Vector2(100.0, 170.0), Vector2(0.0, 150.0))
	arena.run(0.4)
	check_equal(blocked.size(), 1, "a beam's shield stops a shot crossing it too")


func test_deflect_goes_first_so_a_shield_beside_it_is_wasted() -> void:
	var staff: CompiledStaff = arena.install_cards(0, 0, ["shield", "deflect", "swing"])
	check(staff.wasted.has(0), "the shield is listed as wasted: %s" % [staff.wasted])
	_enemy_shot(Vector2(60.0, 0.0), Vector2(-200.0, 0.0))
	arena.cast(0, 0)
	arena.run(0.3)
	check_equal(deflected.size(), 1, "the shot is deflected")
	check_equal(blocked.size(), 0, "not blocked")
	# On a dash the shield is a barrier on the caster, which a deflect does not replace.
	check(not arena.install_cards(0, 0, ["shield", "deflect", "dash"]).wasted.has(0), "a dash keeps its shield")


func test_a_deflect_sets_off_on_block() -> void:
	# The nova goes off where the shot was turned and chills an imp beside it, out of the arc.
	var imp: Node2D = arena.add_imp(Vector2(30.0, -32.0))
	_enemy_shot(Vector2(60.0, 0.0), Vector2(-200.0, 0.0))
	_cast(["on_block", "deflect", "swing", "frost", "nova"])
	arena.run(1.0)
	check_equal(deflected.size(), 1, "deflected")
	check(arena.was_given(imp, &"chill"), "the block's nova chilled the imp")


func test_a_teammates_shot_is_never_deflected() -> void:
	var mate_shot: int = arena.projectiles.spawn(1, Vector2(60.0, 0.0), Vector2(-200.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_ENEMY)
	_cast(["deflect", "swing"])
	arena.run(0.3)
	check_equal(deflected.size(), 0, "a shot of the same team passes")
	check_equal(arena.projectiles.get_actor_of(mate_shot), 1, "and stays its caster's")
