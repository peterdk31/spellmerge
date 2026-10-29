extends "res://tests/support/suite.gd"
## Beams and nova rings in gameplay/feel: `form_shown` shows a beam along the aim or a ring
## at the caster, in the owner's tint with the element's colour in the core. They fade out,
## stay inside the pool with four players, and ignore what is not a beam or a nova.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const FROST := Color(0.5, 0.75, 0.94)
## The look of a lightning card (its sparks).
const SPARKS: int = 1 << (ProjectilesScript.LOOK_SPARKS - 1)

var bus: EventsScript
var feel: FeelScript
var preset: FeelPresetScript
var projectiles: ProjectilesScript
## Wizards seated 0-3 at the actor ids 0-3 (caster 0-3 draws in hat ramp 0-3), shared by Feel and
## the projectile manager.
var actors: ActorSeats.ActorsScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	projectiles = own(ProjectilesScript.new()) as ProjectilesScript
	actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	projectiles.actors = actors
	feel.actors = actors
	preset = FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.projectiles = projectiles
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)


func _shown() -> Array[MeshInstance2D]:
	var found: Array[MeshInstance2D] = []
	for node in feel._forms:
		if node.visible:
			found.append(node)
	return found


func _param(node: MeshInstance2D, name: StringName) -> Variant:
	return (node.material as ShaderMaterial).get_shader_parameter(name)


func _path(node: MeshInstance2D) -> PackedVector3Array:
	return _param(node, &"beam_path") as PackedVector3Array


func test_a_beam_is_drawn_along_the_aim_as_long_as_it_got() -> void:
	bus.form_shown.emit(1, &"beam", Vector2(10, 20), Vector2.DOWN, 150.0, FROST, 0)
	var shown: Array[MeshInstance2D] = _shown()
	check_equal(shown.size(), 1, "one beam on screen")
	var beam: MeshInstance2D = shown[0]
	check(beam.mesh == FeelScript.beam_mesh(), "drawn as the beam mesh")
	check_equal(_param(beam, &"beam_points"), 2, "a path of two points")
	check(_path(beam)[0].is_equal_approx(Vector3(10, 20, 0)), "from the staff")
	check(_path(beam)[1].is_equal_approx(Vector3(10, 170, 150)), "along the aim, 150 px along")
	check_equal(_param(beam, &"beam_length"), 150.0, "as long as it got")
	check_equal(_param(beam, &"beam_lead"), FeelScript.BEAM_LEAD, "drawn a little past each end, so the flares are whole")
	check((_param(beam, &"beam_end") as Vector2).is_equal_approx(Vector2(10, 170)), "which ends where it landed, upright on the world's pixels")


func test_the_core_has_the_element_colour_and_the_body_the_owners() -> void:
	bus.form_shown.emit(2, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, FROST, 0)
	var beam: MeshInstance2D = _shown()[0]
	var core: Color = _param(beam, &"core_override")
	check(core.is_equal_approx(Color(FROST.r, FROST.g, FROST.b, 1.0)), "the core is frost")
	var body: Color = _param(beam, &"body_tint")
	var owner_tint: Color = projectiles.tint_of(2)
	check(is_equal_approx(body.r, owner_tint.r) and is_equal_approx(body.g, owner_tint.g) and is_equal_approx(body.b, owner_tint.b), "the body has the owner's tint")
	check(not core.is_equal_approx(body), "the two are not the same colour")


func test_a_nova_is_a_ring_at_the_caster_in_its_elements_colours() -> void:
	bus.form_shown.emit(0, &"nova", Vector2(50, 60), Vector2.RIGHT, 0.0, FROST, 7)
	check_equal(_shown().size(), 0, "no sprite: the ring is an effect")
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT, 0), 1, "a ring flashes out")
	check_equal(feel.effect_dress(FeelScript.KIND_RING_OUT), [FROST, 7], "in the element's colours, with the cast's cards")
	feel.step(0.01)
	var buffer: PackedFloat32Array = feel._effect_node.multimesh.buffer
	check(is_equal_approx(buffer[3], 50.0) and is_equal_approx(buffer[7], 60.0), "at the caster")
	var across: float = buffer[0]
	check(across >= preset.nova_ring_size * 0.9, "as wide as the preset's ring (%f)" % across)
	feel.step(preset.nova_seconds)
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT), 0, "and gone after its seconds")


func test_a_dash_kicks_up_dust_and_lands_in_a_ring() -> void:
	# Its way is the caster's trail (the projectile manager's `follow_caster`), where the wizard
	# really went (the owner, 2026-10-28: the dash look went the aim's way, not the wizard's).
	bus.form_shown.emit(2, &"dash", Vector2(10, 20), Vector2.DOWN, 80.0, FROST, SPARKS)
	check_equal(feel.effects_of(FeelScript.KIND_DASH, 2), 1, "dust where player 3 left")
	check_equal(feel.effect_dress(FeelScript.KIND_DASH), [FROST, SPARKS], "with the dash's colours and cards")
	feel.step(0.01)
	var buffer: PackedFloat32Array = feel._effect_node.multimesh.buffer
	check(is_equal_approx(buffer[3], 12.0) and is_equal_approx(buffer[7], 20.0), "at its start, whatever the aim")
	bus.caster_move_finished.emit(2, &"dash", Vector2(60, 30), 0)
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT, 2), 1, "a ring where it landed")
	check_equal(feel.effects_of(FeelScript.KIND_ARC, 2), 1, "lightning (its sparks) arcs from where it left")
	check_equal(feel.effects_of(FeelScript.KIND_BURST, 2), 1, "and an infused dash lands in a flare of its element")
	bus.caster_move_finished.emit(2, &"teleport", Vector2(60, 30), 0)
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT, 2), 1, "a teleport is not a dash")
	bus.form_shown.emit(2, &"dash", Vector2(10, 20), Vector2.DOWN, 0.0, FROST, 5)
	check_equal(feel.effects_of(FeelScript.KIND_DASH), 1, "a dash that went nowhere shows nothing")
	bus.form_shown.emit(ActorSeats.enemy(actors), &"dash", Vector2(10, 20), Vector2.DOWN, 80.0, FROST, 5)
	check_equal(feel.effects_of(FeelScript.KIND_DASH), 2, "an enemy's dash shows like a wizard's (staffs F7)")
	check_equal(feel.effect_info(FeelScript.KIND_DASH)["ramp"], ActorSeats.ActorsScript.RAMP_ENEMY, "in the enemy ramp")


func test_a_shot_whose_life_runs_out_pops() -> void:
	projectiles.events = bus
	projectiles.spawn(1, Vector2(50, 50), Vector2(100, 0), 0.05)
	for i in 5:
		projectiles.step(1.0 / 60.0)
	check_equal(feel.effects_of(FeelScript.KIND_BURST, 1), 1, "a small pop where it ended (the mockup's)")
	projectiles.spawn(1, Vector2(50, 50), Vector2.ZERO, 0.05, 14.0, ProjectilesScript.LAYER_ENEMY, 0, 0, ProjectilesScript.MOTION_STILL)
	for i in 5:
		projectiles.step(1.0 / 60.0)
	check_equal(feel.effects_of(FeelScript.KIND_BURST, 1), 1, "a rune's end is its own burst, not a pop")


func test_forms_end() -> void:
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, FROST, 0)
	bus.form_shown.emit(0, &"nova", Vector2.ZERO, Vector2.RIGHT, 0.0, FROST, 0)
	feel.step(1.0)
	check_equal(_shown().size(), 0, "after its seconds the beam is gone")
	check_equal(feel.live_effects(), 0, "and the ring")


func test_other_forms_and_empty_beams_show_nothing() -> void:
	bus.form_shown.emit(0, &"bolt", Vector2.ZERO, Vector2.RIGHT, 100.0, FROST, 0)
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 0.0, FROST, 0)
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.ZERO, 100.0, FROST, 0)
	check_equal(_shown().size(), 0, "none of them is drawn")


func test_four_players_firing_at_once_stay_inside_the_pool() -> void:
	for round in 4:
		for player in 4:
			bus.form_shown.emit(player, &"beam", Vector2(player * 10, 0), Vector2.RIGHT, 100.0, FROST, 0)
	check(_shown().size() <= FeelScript.FORM_SLOTS, "never more sprites than the pool holds")
	check_equal(feel._forms.size(), FeelScript.FORM_SLOTS, "and no sprite is made on the way")


func test_one_players_many_beams_never_push_out_another_players_beam() -> void:
	for player in 4:
		bus.form_shown.emit(player, &"beam", Vector2(player * 10, 0), Vector2.RIGHT, 100.0, FROST, 0)
	for ray in 20:
		bus.form_shown.emit(0, &"beam", Vector2(0, ray), Vector2.UP, 100.0, FROST, 0)
	for player in 4:
		var seen: int = 0
		for slot in range(player * FeelScript.FORMS_PER_PLAYER, (player + 1) * FeelScript.FORMS_PER_PLAYER):
			if feel._forms[slot].visible:
				seen += 1
		check(seen >= 1, "player %d still has a visible beam" % player)
	check(_path(feel._forms[FeelScript.FORMS_PER_PLAYER])[0].is_equal_approx(Vector3(10, 0, 0)), "player 1's beam is untouched")


func test_one_cast_with_many_rays_shows_every_ray() -> void:
	for ray in 24:
		bus.form_shown.emit(1, &"beam", Vector2.ZERO, Vector2.RIGHT.rotated(ray * 0.1), 100.0, FROST, 0)
	check_equal(_shown().size(), 24, "a fan of 24 rays is drawn whole")


func test_an_enemys_beams_take_only_the_enemies_share() -> void:
	var enemy: int = ActorSeats.enemy(actors)
	for i in FeelScript.FORMS_PER_PLAYER + 6:
		bus.form_shown.emit(enemy, &"beam", Vector2(0.0, i), Vector2.RIGHT, 100.0, FROST, 0)
	check_equal(_shown().size(), FeelScript.FORMS_PER_PLAYER, "enemies' beams show, in their one share")
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, FROST, 0)
	check_equal(_shown().size(), FeelScript.FORMS_PER_PLAYER + 1, "and never take a player's slot")
	var enemy_beam: MeshInstance2D = feel._forms[FeelScript.ENEMY_FORMS * FeelScript.FORMS_PER_PLAYER]
	check_equal(_param(enemy_beam, &"beam_player"), -1, "drawn in the enemy ramp")


func test_a_rain_shows_its_marker_until_it_falls() -> void:
	bus.form_shown.emit(1, &"rain", Vector2(40, 40), Vector2.RIGHT, 0.6, FROST, 3)
	bus.form_shown.emit(ActorSeats.enemy(actors), &"rain", Vector2(80, 40), Vector2.RIGHT, 0.6, FROST, 3)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 2, "a ring closes on each rain's point, a wizard's and an enemy's")
	check(is_equal_approx(feel.effect_info(FeelScript.KIND_RING_IN)["seconds"], 0.6), "for as long as it takes to fall")
	feel.step(0.5)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 2, "still there just before")
	feel.step(0.2)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 0, "gone when it lands")


func test_the_shipped_preset_has_the_form_art() -> void:
	var shipped := load("res://gameplay/feel/presets/punchy.tres") as FeelPresetScript
	check(shipped.beam_texture != null and shipped.nova_texture != null, "beam and ring art")


## Stands in for core/spells' live beams: one beam of `caster` (the actor id of the wizard in
## seat 1) bending from (0, 0) to (100, 40),
## and with `on_again` bending on from there to (160, 0).
class FakeBeams:
	extends Node
	var on: bool = true
	var reach: float = 500.0
	var on_again: bool = false
	var caster: int = 1

	func beam_point_count(_at: int) -> int:
		return 17 if on_again else 9

	func beam_point(_at: int, n: int) -> Vector2:
		if n <= 8:
			return _curve(Vector2.ZERO, Vector2(60, 0), Vector2(100, 40), float(n) / 8.0)
		return _curve(Vector2(100, 40), Vector2(124, 64), Vector2(160, 0), float(n - 8) / 8.0)

	static func _curve(from: Vector2, bend: Vector2, end: Vector2, t: float) -> Vector2:
		var u: float = 1.0 - t
		return from * (u * u) + bend * (2.0 * u * t) + end * (t * t)

	func beam_slots() -> int:
		return 2

	func beam_on(at: int) -> bool:
		return on and at == 1

	func beam_caster(_at: int) -> int:
		return caster

	func beam_look(_at: int) -> int:
		return 6

	func beam_origin(_at: int) -> Vector2:
		return Vector2.ZERO

	func beam_bend(_at: int) -> Vector2:
		return Vector2(60, 0)

	func beam_end(_at: int) -> Vector2:
		return Vector2(100, 40)

	func beam_reach(_at: int) -> float:
		return reach

	func beam_tint(_at: int) -> Color:
		return FROST

	func beam_since_hit(_at: int) -> float:
		return 1.0

	func beam_left(_at: int) -> float:
		return 1.0


func _live_lines() -> Array[MeshInstance2D]:
	var found: Array[MeshInstance2D] = []
	for node in feel._live_beams:
		if node.visible:
			found.append(node)
	return found


func test_a_live_beam_is_drawn_along_its_curve_every_frame() -> void:
	var beams := own(FakeBeams.new()) as FakeBeams
	feel.spells = beams
	feel.step(0.016)
	var lines: Array[MeshInstance2D] = _live_lines()
	check_equal(lines.size(), 1, "one live beam on screen")
	var line: MeshInstance2D = lines[0]
	var material: ShaderMaterial = line.material as ShaderMaterial
	check_equal(material.get_shader_parameter(&"beam_start"), Vector2.ZERO, "from the staff")
	check((material.get_shader_parameter(&"beam_end") as Vector2).is_equal_approx(Vector2(100, 40)), "to its end, on the target")
	check_equal(material.get_shader_parameter(&"beam_lead"), FeelScript.BEAM_LEAD, "drawn a little past each end, so the flares are whole")
	check(is_equal_approx(material.get_shader_parameter(&"sim_time"), feel._clock), "animated by Feel's clock (the owner, 2026-10-28: beams did not move)")
	var path: PackedVector3Array = _path(line)
	var points: int = material.get_shader_parameter(&"beam_points")
	check(points > 2, "along its path's points: %d" % points)
	check(path[0].is_equal_approx(Vector3.ZERO), "from the staff, 0 px along")
	var middle: Vector3 = path[points / 2]
	check(middle.y > 0.0 and middle.y < 20.0, "bent, not straight: %s" % middle)
	check(is_equal_approx(path[points - 1].z, material.get_shader_parameter(&"beam_length") as float), "each point says how far along it is, the last as far as the beam got")
	check((line.material as ShaderMaterial).get_shader_parameter(&"core_override").is_equal_approx(Color(FROST.r, FROST.g, FROST.b, 1.0)), "the core is the element's")
	var tint: Color = (line.material as ShaderMaterial).get_shader_parameter(&"body_tint")
	check(is_equal_approx(tint.a, feel.preset.beam_alpha) and tint.a < 1.0, "a little see-through, so crossing beams all show: %f" % tint.a)
	beams.reach = 50.0
	feel.step(0.016)
	var tip: Vector2 = (line.material as ShaderMaterial).get_shader_parameter(&"beam_end")
	check(absf(tip.length() - 50.0) < 3.0, "cut where it stopped: %s" % tip)
	beams.reach = 500.0
	beams.on_again = true
	feel.step(0.016)
	var second: Vector2 = (line.material as ShaderMaterial).get_shader_parameter(&"beam_end")
	check(second.is_equal_approx(Vector2(160, 0)), "a beam bending on to a second target is drawn to it: %s" % second)
	beams.on = false
	feel.step(0.016)
	check(_live_lines().is_empty(), "gone when it ends")


## A live beam longer than the shader holds: a zig-zag of 200 points, one pixel apart, turning
## sharply at every 40th (a beam bouncing between two walls).
class LongBeams:
	extends FakeBeams

	func beam_point_count(_at: int) -> int:
		return 200

	func beam_point(_at: int, n: int) -> Vector2:
		var leg: int = n / 40
		var into: float = float(n % 40)
		var y: float = into if leg % 2 == 0 else 40.0 - into
		return Vector2(float(n), y)


func test_a_beam_longer_than_the_shader_holds_keeps_its_ends_and_its_turns() -> void:
	var beams := own(LongBeams.new()) as LongBeams
	feel.spells = beams
	feel.step(0.016)
	var lines: Array[MeshInstance2D] = _live_lines()
	check_equal(lines.size(), 1, "one live beam on screen")
	if lines.is_empty():
		return
	var material: ShaderMaterial = lines[0].material as ShaderMaterial
	var points: int = material.get_shader_parameter(&"beam_points")
	check(points <= FeelScript.LIVE_BEAM_POINTS, "it fits the shader: %d points" % points)
	var path: PackedVector3Array = _path(lines[0])
	var drawn: Array[Vector2] = []
	for n in points:
		drawn.append(Vector2(path[n].x, path[n].y))
	check(drawn[0].is_equal_approx(Vector2.ZERO), "from its start")
	check(drawn[points - 1].is_equal_approx(beams.beam_point(1, 199)), "to its end: %s" % drawn[points - 1])
	for corner in [40, 80, 120, 160]:
		check(drawn.has(beams.beam_point(1, corner)), "the turn at point %d is drawn, not cut across" % corner)


func test_a_live_beam_is_drawn_by_the_beam_mode_as_long_as_it_got() -> void:
	var beams := own(FakeBeams.new()) as FakeBeams
	beams.reach = 50.0
	feel.spells = beams
	feel.step(0.016)
	var line: MeshInstance2D = _live_lines()[0]
	var material: ShaderMaterial = line.material as ShaderMaterial
	check(material.shader == FeelScript.BEAM_SHADER and line.mesh == FeelScript.beam_mesh(), "a beam")
	check(is_equal_approx(material.get_shader_parameter(&"beam_length") as float, 50.0), "as long as it got along its curve")
	check_equal(material.get_shader_parameter(&"beam_player"), 1, "in its caster's hat ramp")
	check_equal(material.get_shader_parameter(&"beam_look"), 6, "with its cards")
	check_equal(material.get_shader_parameter(&"beam_width"), FeelScript.BEAM_WIDTH, "a fixed width: the shader swells its rim, never its pixels")
	beams.caster = ActorSeats.enemy(actors)
	feel.step(0.016)
	check_equal(material.get_shader_parameter(&"beam_player"), -1, "an enemy's beam is in the enemy ramp")


## The quad kind and slot a mesh made by Feel's `_quads_mesh` gives its `n`th quad.
func _quad(mesh: ArrayMesh, n: int) -> Vector2i:
	var uv: Vector2 = (mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] as PackedVector2Array)[n * 4]
	return Vector2i(floori(uv.y), floori(uv.x))


func test_an_effect_is_one_mesh_of_small_quads() -> void:
	var mesh: ArrayMesh = FeelScript.effect_mesh()
	check(mesh == FeelScript.effect_mesh(), "one mesh, made once")
	var quads: int = 0
	for entry: Vector3i in FeelScript.EFFECT_QUADS:
		quads += entry.y
	var arrays: Array = mesh.surface_get_arrays(0)
	check_equal((arrays[Mesh.ARRAY_VERTEX] as PackedVector2Array).size(), quads * 4, "a quad for every slot of every kind")
	check_equal((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), quads * 6, "two triangles each")
	check_equal(_quad(mesh, 0), Vector2i(FeelScript.EFFECT_Q_LIGHT, 0), "the light first, under everything")
	check_equal(_quad(mesh, 1), Vector2i(FeelScript.EFFECT_Q_PARTICLE, 0), "then the particles, the newest on top")
	check_equal(_quad(mesh, 13), Vector2i(FeelScript.EFFECT_Q_SPARK, 15), "then the sparks, the first on top")
	check_equal(_quad(mesh, quads - 1), Vector2i(FeelScript.EFFECT_Q_SHAPE, 0), "the flash last, on top")
	check(feel._effect_node.multimesh.mesh == mesh, "the effect batch draws it")
	check(feel._arc_node.multimesh.mesh != mesh and feel._status_node.multimesh.mesh != mesh, "the arcs and statuses keep their one quad")


func test_a_beam_is_one_mesh_of_small_quads_never_culled() -> void:
	var mesh: ArrayMesh = FeelScript.beam_mesh()
	check(mesh == FeelScript.beam_mesh(), "one mesh, made once")
	var pieces: int = FeelScript.LIVE_BEAM_POINTS - 1
	check_equal(_quad(mesh, 0), Vector2i(FeelScript.BEAM_Q_PIECE_LIGHT, 0), "the pieces' light first")
	check_equal(_quad(mesh, pieces), Vector2i(FeelScript.BEAM_Q_SPLASH_LIGHT, 0), "then the splash's light")
	check_equal(_quad(mesh, pieces + 6), Vector2i(FeelScript.BEAM_Q_PARTICLE, 0), "then the particles")
	check_equal(_quad(mesh, pieces + 18), Vector2i(FeelScript.BEAM_Q_SPLASH, 5), "then the splash, the first on top")
	check_equal(_quad(mesh, pieces + 24), Vector2i(FeelScript.BEAM_Q_PIECE, 0), "the beam's own pixels last, on top")
	check(mesh.custom_aabb.size.x >= 100000.0 and mesh.custom_aabb.size.y >= 100000.0, "its box is the world: the shader places it, so it is never culled")
	var shader: Shader = FeelScript.BEAM_SHADER
	check(shader.code.contains("uniform vec3 beam_path[%d];" % FeelScript.LIVE_BEAM_POINTS), "the shader takes as many points as a path has")
	var drawn: int = 0
	for node: MeshInstance2D in feel._forms + feel._live_beams:
		if node.mesh == mesh:
			drawn += 1
	check_equal(drawn, FeelScript.FORM_SLOTS + FeelScript.LIVE_BEAMS, "every beam draws it")
