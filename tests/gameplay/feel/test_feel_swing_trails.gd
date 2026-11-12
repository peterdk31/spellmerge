extends "res://tests/support/suite.gd"
## A swing's trail in gameplay/feel (melee I4; docs/milestones/M2-staffs.md, "Phase I: melee", "The
## look"): Feel draws every live swing of core/spells as a mesh of small quads by
## `shot_swing.gdshader`, round the swing's hand, in its caster's ramp and its cards, kept in step
## with the sweep, and keeps it TRAIL_SECONDS past the sweep's end, after the swing itself is over.
## Its sparks and card particles are motes given off as its tip passes (spell spectacle 2, S6 item
## 10): births of its spell (`gameplay/feel/births.gd`).

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const SwingTrailsScript := preload("res://gameplay/feel/swing_trails.gd")
const BirthsScript := preload("res://gameplay/feel/births.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ShaderSource := preload("res://tests/support/shader_source.gd")

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
	## How far it has turned (radians, its own turning): waiting at the start of its wind-up.
	var turned: float = -deg_to_rad(45.0 + SpellLimits.SWING_LEAN)
	var look: int = 1

	## As the runtime hands Feel its swings (`Spells.carrier(&"swing")`): itself.
	func carrier(id: StringName) -> Object:
		return self if id == &"swing" else null

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
		return look

	func swing_turned(_at: int) -> float:
		return turned

	func swing_tag(_at: int) -> int:
		return 77

	## The card each swing is (`swing_form`), and the looks Spells would answer for a card id
	## drawn as a swing trail (`look_of`): none by default, every trail plain.
	var form: StringName = &"swing"
	var trail_shaders: Dictionary = {}

	func swing_form(_at: int) -> StringName:
		return form

	func look_of(id: StringName, drawer: int) -> CardLook:
		if drawer != Carrier.LOOK_SWING or not trail_shaders.has(id):
			return CardLook.PLAIN
		return CardLook.of(trail_shaders[id] as Shader, 1.0, 1.0)


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


## The births a whole sweep of `swings` gives off, turned in `steps` even steps from the lean
## before its arc to the lean past it, through a trail of its own: each frame's births, appended.
func _sweep(steps: int) -> Array[PackedFloat32Array]:
	var trails := SwingTrailsScript.new(FeelScript.swing_mesh())
	own(trails)
	var births := BirthsScript.new(5)
	var lean: float = deg_to_rad(45.0 + SpellLimits.SWING_LEAN)
	var frames: Array[PackedFloat32Array] = []
	var ramp_of: Callable = func(_actor: int) -> int: return 1
	for n in steps + 1:
		swings.turned = lerpf(-lean, lean, float(n) / float(steps))
		births.clear()
		trails.step(swings, 0.016 * n, ramp_of, 1.0, births)
		frames.append(births.rows.slice(0, births.count * BirthsScript.STRIDE))
	return frames


func test_a_sweep_gives_off_its_sparks_and_card_particles_as_motes() -> void:
	var sparks: int = 0
	var particles: int = 0
	var infused: int = 0
	var stride: int = BirthsScript.STRIDE
	for frame: PackedFloat32Array in _sweep(8):
		for b in range(0, frame.size(), stride):
			var at: Vector2 = Vector2(frame[b + ProjectilesScript.SPARK_X], frame[b + ProjectilesScript.SPARK_Y])
			var way: Vector2 = Vector2(frame[b + ProjectilesScript.SPARK_BACK_X], frame[b + ProjectilesScript.SPARK_BACK_Y])
			var out: Vector2 = (at - swings.origin).normalized()
			var off: float = rad_to_deg(absf(Vector2.DOWN.angle_to(out)))
			check(off <= 45.0 + 0.01, "only where it hits, within its 90 degree arc: %.1f off its aim" % off)
			check(absf(at.distance_to(swings.origin) - (24.0 - SwingTrailsScript.LINE_IN)) <= 1.01, "from the line at its reach: %.2f" % at.distance_to(swings.origin))
			check_equal(int(frame[b + ProjectilesScript.SPARK_RAMP]), 1, "in its caster's ramp")
			check_equal(ProjectilesScript.spark_tag(frame, b), 77, "of its spell, so they take its cards' motes")
			if int(frame[b + ProjectilesScript.SPARK_KIND]) == 0:
				sparks += 1
				check(way.dot(out) > 0.99, "a spark flung outward")
				if Color(frame[b + ProjectilesScript.SPARK_CORE], frame[b + ProjectilesScript.SPARK_CORE + 1], frame[b + ProjectilesScript.SPARK_CORE + 2]) != Color.WHITE:
					infused += 1
			else:
				particles += 1
				check_equal(int(frame[b + ProjectilesScript.SPARK_KIND]), ProjectilesScript.LOOK_EMBERS, "a card particle of its look's kind (fire's embers)")
				check(absf(way.dot(out)) < 0.01, "given off along the arc, back the way the tip came")
	check(absf(float(sparks) - SwingTrailsScript.SPARKS) <= 6.0, "about SPARKS sparks a sweep: %d" % sparks)
	check(infused > 0 and infused < sparks / 2, "a share in the infusion's ramp, the rest in the player's: %d of %d" % [infused, sparks])
	check(particles >= 3 and particles <= 10, "about 6 card particles (4, 2 more a card kind): %d" % particles)


func test_a_swing_with_no_cards_gives_off_only_sparks_and_none_with_motes_off() -> void:
	swings.look = 0
	for frame: PackedFloat32Array in _sweep(4):
		for b in range(0, frame.size(), BirthsScript.STRIDE):
			check_equal(int(frame[b + ProjectilesScript.SPARK_KIND]), 0, "sparks only")
	var trails := SwingTrailsScript.new(FeelScript.swing_mesh())
	own(trails)
	var ramp_of: Callable = func(_actor: int) -> int: return 1
	swings.turned = -1.0
	trails.step(swings, 0.0, ramp_of, 1.0, null)
	swings.turned = 1.0
	trails.step(swings, 0.016, ramp_of, 1.0, null)
	check_equal(trails.live(), 1, "with motes off (no births) it still draws its line, giving off nothing")


func test_the_shader_draws_only_the_line_and_its_light() -> void:
	var code: String = ShaderSource.of(SwingTrailsScript.SHADER)
	check(not code.contains("shot_particle") and not code.contains("Q_SPARK") and not code.contains("Q_PARTICLE"), "its sparks and card particles are motes (S6 item 10)")
	check_equal(SwingTrailsScript.SWING_QUADS.size(), 2, "two quads: the light and the line")


## A swing card's own look (docs/milestones/card-looks.md, phase 2): its trail is drawn by the shader
## Spells answers for its card (`look_of`, as a swing trail), on the trail's own material;
## a card that names none, or that another area draws, trails with the plain shader.
func test_a_swing_trails_with_its_cards_own_shader() -> void:
	var own_look: Shader = preload("res://content/spells/carriers/swing/swing.gdshader")
	swings.trail_shaders[&"swing"] = own_look
	feel.step(0.016)
	var trail: MeshInstance2D = null
	for node: MeshInstance2D in _trails()._nodes:
		if node.visible:
			trail = node
	check(trail != null and (trail.material as ShaderMaterial).shader == own_look, "drawn by its card's shader")
	check_equal(_trails().parameter_of(1, &"swing_reach"), 24.0, "with its own uniforms, as before")
	# A new swing of a card with no look of its own takes a trail drawn plain.
	swings.form = &"bolt"
	swings.generation = 1
	feel.step(0.016)
	var plain: int = 0
	for node: MeshInstance2D in _trails()._nodes:
		if node.visible and (node.material as ShaderMaterial).shader == SwingTrailsScript.SHADER:
			plain += 1
	check_equal(plain, 1, "the other swing's trail is plain")
