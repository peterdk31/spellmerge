extends "res://tests/support/suite.gd"
## A swing's trail in gameplay/feel (melee I4; docs/milestones/M2-staffs.md, "Phase I: melee", "The
## look"): Feel draws every live swing of core/spells as a mesh of small quads by
## `shot_swing.gdshader`, round the swing's hand, in its caster's ramp and its cards, kept in step
## with the sweep, and keeps it TRAIL_SECONDS past the sweep's end, after the swing itself is over.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const SwingTrailsScript := preload("res://gameplay/feel/swing_trails.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const FIRE: Color = Color("e0592f")


## Stands in for core/spells' live swings: `rows` rows, the ones in `on` live, each born as its
## row + 10 * `generation`, of the actor in seat 1 (ramp 1), round (40, 20), aimed down,
## turning back (-1), 0.05 s into its 0.12 s wind-up of a 0.06 s sweep.
class FakeSwings:
	extends Node
	var rows: int = 2
	var on: Array[int] = [1]
	var generation: int = 0
	var age: float = 0.05
	var origin: Vector2 = Vector2(40.0, 20.0)

	## As the runtime hands Feel its swings (`Spells.swings`): itself.
	func swings() -> Object:
		return self

	func swing_slots() -> int:
		return rows

	func swing_on(at: int) -> bool:
		return on.has(at)

	func swing_born(at: int) -> int:
		return at + 10 * generation

	func swing_actor(_at: int) -> int:
		return 1

	func swing_origin(_at: int) -> Vector2:
		return origin

	func swing_dir(_at: int) -> Vector2:
		return Vector2.DOWN

	func swing_side(_at: int) -> int:
		return -1

	func swing_arc(_at: int) -> float:
		return 90.0

	func swing_reach(_at: int) -> float:
		return 24.0

	func swing_age(_at: int) -> float:
		return age

	func swing_wind(_at: int) -> float:
		return 0.12

	func swing_sweep(_at: int) -> float:
		return 0.06

	func swing_tint(_at: int) -> Color:
		return FIRE

	func swing_look(_at: int) -> int:
		return 1


var bus: EventsScript
var feel: FeelScript
var swings: FakeSwings


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	feel.events = bus
	feel.actors = own(ActorSeats.table(4)) as ActorSeats.ActorsScript
	feel.drive_engine = false
	feel.preset = FeelPresetScript.new()
	swings = own(FakeSwings.new()) as FakeSwings
	feel.spells = swings
	root.add_child(feel)


func _trails() -> SwingTrailsScript:
	return feel.swing_trails()


func test_a_live_swing_gets_a_trail_round_its_hand_in_its_look() -> void:
	feel.step(0.016)
	check_equal(_trails().live(), 1, "one trail on screen")
	check_equal(_trails().parameter_of(1, &"swing_origin"), Vector2(40.0, 20.0), "round the swing's hand")
	check_equal(_trails().parameter_of(1, &"swing_dir"), Vector2.DOWN, "from its locked aim")
	check_equal(_trails().parameter_of(1, &"swing_side"), -1.0, "turning its way")
	check(is_equal_approx(_trails().parameter_of(1, &"swing_half") as float, deg_to_rad(45.0)), "over half its arc each side")
	check(is_equal_approx(_trails().parameter_of(1, &"swing_lean") as float, deg_to_rad(45.0 + SpellLimits.SWING_LEAN)), "the tip leans past the arc, as the swing turns")
	check_equal(_trails().parameter_of(1, &"swing_reach"), 24.0, "at its reach")
	check_equal(_trails().parameter_of(1, &"swing_player"), 1, "in its caster's ramp")
	check_equal(_trails().parameter_of(1, &"swing_look"), 1, "with its cards")
	var core: Color = _trails().parameter_of(1, &"core_override")
	check(core.is_equal_approx(Color(FIRE.r, FIRE.g, FIRE.b, 1.0)), "and its infusion's colour")


func test_its_sweep_starts_on_feels_clock_where_the_swings_does() -> void:
	feel.step(0.016)
	# 0.05 s into a 0.12 s wind-up: the sweep starts 0.07 s from now.
	check(is_equal_approx(_trails().parameter_of(1, &"swing_start") as float, feel._clock + 0.07), "the sweep's start")
	check(is_equal_approx(_trails().parameter_of(1, &"sim_time") as float, feel._clock), "animated by Feel's clock")
	# A local stop holds the swing while Feel's clock runs on: the start moves with it.
	feel.step(0.05)
	check(is_equal_approx(_trails().parameter_of(1, &"swing_start") as float, feel._clock + 0.07), "kept in step with the swing")


func test_it_follows_the_hand_while_the_swing_lives() -> void:
	feel.step(0.016)
	swings.origin = Vector2(50.0, 20.0)
	feel.step(0.016)
	check_equal(_trails().parameter_of(1, &"swing_origin"), Vector2(50.0, 20.0), "moved with the hand")


func test_it_stays_past_the_swing_then_goes() -> void:
	swings.age = 0.18
	feel.step(0.016)
	swings.on.clear()
	feel.step(SwingTrailsScript.TRAIL_SECONDS - 0.1)
	check_equal(_trails().live(), 1, "the sparks still fly after the swing is over")
	feel.step(0.2)
	check_equal(_trails().live(), 0, "then it is gone")


func test_a_new_swing_in_a_row_used_again_gets_a_trail_of_its_own() -> void:
	swings.age = 0.18
	feel.step(0.016)
	swings.generation = 1
	swings.age = 0.0
	feel.step(0.016)
	check_equal(_trails().live(), 2, "the old trail keeps flying and the new one starts")


func test_many_swings_at_once_all_show() -> void:
	swings.rows = SwingTrailsScript.TRAILS_START + 4
	swings.on.clear()
	for at in swings.rows:
		swings.on.append(at)
	feel.step(0.016)
	check_equal(_trails().live(), swings.rows, "no swing goes without its trail")


func test_a_trail_is_one_mesh_of_small_quads_never_culled() -> void:
	var mesh: ArrayMesh = FeelScript.swing_mesh()
	var quads: int = 0
	for entry: Vector3i in SwingTrailsScript.SWING_QUADS:
		quads += entry.y
	check_equal(mesh.surface_get_array_len(0), quads * 4, "four corners a quad")
	check(mesh.custom_aabb.size.x >= 100000.0 and mesh.custom_aabb.size.y >= 100000.0, "its box is the whole world")
	check(feel.swing_mesh() == FeelScript.swing_mesh(), "made once")


func test_the_shader_is_warmed_before_play() -> void:
	check(preload("res://core/projectiles/shader_warmup.gd").shaders().has(SwingTrailsScript.SHADER), "compiled behind the loading screen")
