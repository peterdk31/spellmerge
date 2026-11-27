extends "res://tests/support/suite.gd"
## Beams and nova rings in gameplay/feel: `carrier_shown` shows a beam along the aim or a ring
## at the caster, in the owner's tint with the element's colour in the core. They fade out,
## stay inside the pool with four players, and ignore what is not a beam or a nova.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const BirthsScript := preload("res://gameplay/feel/births.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ShaderSource := preload("res://tests/support/shader_source.gd")

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
	# The carriers' looks are cues (`content/cues`).
	var registry: RegistryScript = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	feel.registry = registry
	root.add_child(feel)


## The beams Feel draws now, as one merged shape (`BeamUnion`; the beam card's look, or the plain
## beam's where no card is found): drawn as a frame draws them, with no time passing, so a beam just
## shown is in it.
func _union() -> BeamUnion:
	feel._job_beams._draw_live_beams(0.0)
	for shader: Shader in feel._beam_unions:
		return feel._beam_unions[shader] as BeamUnion
	return null


## How many beams are drawn now.
func _shown() -> int:
	var union: BeamUnion = _union()
	return union.beams if union != null else 0


func test_a_beam_is_drawn_along_the_aim_as_long_as_it_got() -> void:
	bus.carrier_shown.emit(1, &"beam", Vector2(10, 20), Vector2.DOWN, 150.0, FROST, 0)
	check_equal(_shown(), 1, "one beam on screen")
	var union: BeamUnion = _union()
	check(union.node.mesh != null and union.node.visible, "drawn by the union's mesh")
	var path: PackedVector3Array = union.path_of(0)
	check_equal(path.size(), 2, "a path of two points")
	check(path[0].is_equal_approx(Vector3(10, 20, 0)), "from the staff")
	check(path[1].is_equal_approx(Vector3(10, 170, 150)), "along the aim, 150 px along")
	check_equal(union.lengths[0], 150.0, "as long as it got")
	check_equal(union.material.get_shader_parameter(&"beam_lead"), FeelScript.BEAM_LEAD, "drawn a little past each end, so the flares are whole")
	check(union.ends[0].is_equal_approx(Vector2(10, 170)), "which ends where it landed, upright on the world's pixels")


func test_the_core_has_the_element_colour_and_the_body_the_owners() -> void:
	bus.carrier_shown.emit(2, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, FROST, 0)
	var core: Color = _union().cores[0]
	check(core.is_equal_approx(Color(FROST.r, FROST.g, FROST.b, 1.0)), "the core is frost")
	var body: Color = feel._shown_beam_body[2 * FeelScript.SHOWN_BEAMS_PER_PLAYER]
	var owner_tint: Color = projectiles.tint_of(2)
	check(is_equal_approx(body.r, owner_tint.r) and is_equal_approx(body.g, owner_tint.g) and is_equal_approx(body.b, owner_tint.b), "the body has the owner's tint")
	check(not core.is_equal_approx(body), "the two are not the same colour")


## A nova's ring is its card's cue (`nova`), which the spell runtime shows once per nova (`cue_shown`).
func test_a_nova_is_a_ring_at_the_caster_in_its_elements_colours() -> void:
	bus.cue_shown.emit(0, &"nova", Vector2(50, 60), Vector2.RIGHT, 0.0, FROST, 7)
	check_equal(_shown(), 0, "no beam: the ring is a flash")
	check_equal(feel.flashes_of(&"ring_out", 0), 1, "a ring flashes out")
	check_equal(feel.flash_dress(&"ring_out"), [FROST, 7], "in the element's colours, with the cast's cards")
	feel.step(0.01)
	var buffer: PackedFloat32Array = feel._flash_node.multimesh.buffer
	check(is_equal_approx(buffer[3], 50.0) and is_equal_approx(buffer[7], 60.0), "at the caster")
	var across: float = buffer[0]
	check(across >= 120.0 * 0.9, "as wide as the cue's ring, 120 px (%f)" % across)
	feel.step(0.25)
	check_equal(feel.flashes_of(&"ring_out"), 0, "and gone after its seconds")


func test_a_shot_whose_life_runs_out_pops() -> void:
	projectiles.events = bus
	projectiles.spawn(1, Vector2(50, 50), Vector2(100, 0), 0.05)
	for i in 5:
		projectiles.step(1.0 / 60.0)
	check_equal(feel.flashes_of(&"burst", 1), 1, "a small pop where it ended (the mockup's)")
	projectiles.spawn(1, Vector2(50, 50), Vector2.ZERO, 0.05, 14.0, ProjectilesScript.LAYER_ENEMY, 0, 0, ProjectilesScript.MOTION_STILL)
	for i in 5:
		projectiles.step(1.0 / 60.0)
	check_equal(feel.flashes_of(&"burst", 1), 1, "a rune's end is its own burst, not a pop")


func test_shown_beams_and_rings_end() -> void:
	bus.carrier_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, FROST, 0)
	bus.cue_shown.emit(0, &"nova", Vector2.ZERO, Vector2.RIGHT, 0.0, FROST, 0)
	feel.step(1.0)
	check_equal(_shown(), 0, "after its seconds the beam is gone")
	var union: BeamUnion = _union()
	check(union == null or not union.node.visible, "and nothing is drawn")
	check_equal(feel.live_flashes(), 0, "and the ring")


func test_other_carrier_cards_and_empty_beams_show_nothing() -> void:
	bus.carrier_shown.emit(0, &"bolt", Vector2.ZERO, Vector2.RIGHT, 100.0, FROST, 0)
	bus.carrier_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 0.0, FROST, 0)
	bus.carrier_shown.emit(0, &"beam", Vector2.ZERO, Vector2.ZERO, 100.0, FROST, 0)
	check_equal(_shown(), 0, "none of them is drawn")


func test_four_players_firing_at_once_stay_inside_the_pool() -> void:
	for round in 4:
		for player in 4:
			bus.carrier_shown.emit(player, &"beam", Vector2(player * 10, 0), Vector2.RIGHT, 100.0, FROST, 0)
	check(_shown() <= FeelScript.SHOWN_BEAM_SLOTS, "never more beams than the slots hold")
	check_equal(feel._shown_beam_paths.size(), FeelScript.SHOWN_BEAM_SLOTS, "and no slot is made on the way")
	check_equal(feel._beam_unions.size(), 1, "all drawn by one union")


func test_one_players_many_beams_never_push_out_another_players_beam() -> void:
	for player in 4:
		bus.carrier_shown.emit(player, &"beam", Vector2(player * 10, 0), Vector2.RIGHT, 100.0, FROST, 0)
	for ray in 20:
		bus.carrier_shown.emit(0, &"beam", Vector2(0, ray), Vector2.UP, 100.0, FROST, 0)
	for player in 4:
		var seen: int = 0
		for slot in range(player * FeelScript.SHOWN_BEAMS_PER_PLAYER, (player + 1) * FeelScript.SHOWN_BEAMS_PER_PLAYER):
			if feel._shown_beam_left[slot] > 0.0:
				seen += 1
		check(seen >= 1, "player %d still has a beam shown" % player)
	check(feel._shown_beam_paths[FeelScript.SHOWN_BEAMS_PER_PLAYER][0].is_equal_approx(Vector3(10, 0, 0)), "player 1's beam is untouched")


func test_one_cast_with_many_rays_shows_every_ray() -> void:
	for ray in 24:
		bus.carrier_shown.emit(1, &"beam", Vector2.ZERO, Vector2.RIGHT.rotated(ray * 0.1), 100.0, FROST, 0)
	check_equal(_shown(), 24, "a fan of 24 rays is drawn whole")


func test_an_enemys_beams_take_only_the_enemies_share() -> void:
	var enemy: int = ActorSeats.enemy(actors)
	for i in FeelScript.SHOWN_BEAMS_PER_PLAYER + 6:
		bus.carrier_shown.emit(enemy, &"beam", Vector2(0.0, i), Vector2.RIGHT, 100.0, FROST, 0)
	check_equal(_shown(), FeelScript.SHOWN_BEAMS_PER_PLAYER, "enemies' beams show, in their one share")
	check_equal(_union().players[0], -1, "drawn in the enemy ramp")
	bus.carrier_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, FROST, 0)
	check_equal(_shown(), FeelScript.SHOWN_BEAMS_PER_PLAYER + 1, "and never take a player's slot")


func test_the_shipped_preset_has_the_carrier_card_art() -> void:
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

	## As the runtime hands Feel its beams (`Spells.carrier(&"beam")`): itself.
	func carrier(id: StringName) -> Object:
		return self if id == &"beam" else null

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

	func beam_infusions(_at: int) -> PackedColorArray:
		return PackedColorArray([Color(FROST.r, FROST.g, FROST.b, 2.0 / 255.0), Color(0.88, 0.35, 0.18, 1.0 / 255.0)])

	func beam_since_hit(_at: int) -> float:
		return 1.0

	func beam_left(_at: int) -> float:
		return 1.0

	func beam_fade(_at: int) -> float:
		return 1.0

	func beam_tag(_at: int) -> int:
		return 55


## The live beams Feel drew last (the plain beam's union: the stand-in beams name no card).
func _live() -> BeamUnion:
	return feel.beam_union(FeelScript.BEAM_SHADER)


func test_a_live_beam_is_drawn_along_its_curve_every_frame() -> void:
	var beams := own(FakeBeams.new()) as FakeBeams
	feel.spells = beams
	feel.step(0.016)
	var union: BeamUnion = _live()
	check_equal(union.beams if union != null else 0, 1, "one live beam on screen")
	if union == null or union.beams != 1:
		return
	check_equal(union.starts[0], Vector2.ZERO, "from the staff")
	check(union.ends[0].is_equal_approx(Vector2(100, 40)), "to its end, on the target")
	check_equal(union.material.get_shader_parameter(&"beam_lead"), FeelScript.BEAM_LEAD, "drawn a little past each end, so the flares are whole")
	check(is_equal_approx(union.material.get_shader_parameter(&"sim_time"), feel._clock), "animated by Feel's clock (the owner, 2026-10-28: beams did not move)")
	var path: PackedVector3Array = union.path_of(0)
	var points: int = path.size()
	check(points > 2, "along its path's points: %d" % points)
	check(path[0].is_equal_approx(Vector3.ZERO), "from the staff, 0 px along")
	var middle: Vector3 = path[points / 2]
	check(middle.y > 0.0 and middle.y < 20.0, "bent, not straight: %s" % middle)
	check(is_equal_approx(path[points - 1].z, union.lengths[0]), "each point says how far along it is, the last as far as the beam got")
	check(union.cores[0].is_equal_approx(Color(FROST.r, FROST.g, FROST.b, 1.0)), "the core is the element's")
	var infusions: PackedColorArray = union.infusions[0]
	check(infusions.size() == 2 and infusions[1].is_equal_approx(Color(0.88, 0.35, 0.18, 1.0 / 255.0)), "its look is handed every infusion on it, in slot order, with their look kinds")
	check(is_equal_approx(union.glows[0], feel.preset.beam_alpha), "glowing as the preset says")
	beams.reach = 50.0
	feel.step(0.016)
	check(absf(union.ends[0].length() - 50.0) < 3.0, "cut where it stopped: %s" % union.ends[0])
	beams.reach = 500.0
	beams.on_again = true
	feel.step(0.016)
	check(union.ends[0].is_equal_approx(Vector2(160, 0)), "a beam bending on to a second target is drawn to it: %s" % union.ends[0])
	beams.on = false
	feel.step(0.016)
	check(union.beams == 0 and not union.node.visible, "gone when it ends")


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
	var union: BeamUnion = _live()
	check_equal(union.beams if union != null else 0, 1, "one live beam on screen")
	if union == null or union.beams != 1:
		return
	var path: PackedVector3Array = union.path_of(0)
	var points: int = path.size()
	check(points <= FeelScript.LIVE_BEAM_POINTS, "thinned to its most points: %d" % points)
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
	var union: BeamUnion = _live()
	check(union != null and union.material.shader == FeelScript.BEAM_SHADER and union.beams == 1, "a beam")
	if union == null or union.beams != 1:
		return
	check(is_equal_approx(union.lengths[0], 50.0), "as long as it got along its curve")
	check_equal(union.players[0], 1, "in its caster's hat ramp")
	check_equal(union.looks[0], 6, "with its cards")
	check_equal(union.widths[0], FeelScript.BEAM_WIDTH, "a fixed width: the shader swells its rim, never its pixels")
	beams.caster = ActorSeats.enemy(actors)
	feel.step(0.016)
	check_equal(union.players[0], -1, "an enemy's beam is in the enemy ramp")


## The quad kind and slot a mesh made by Feel's `_quads_mesh` gives its `n`th quad.
func _quad(mesh: ArrayMesh, n: int) -> Vector2i:
	var uv: Vector2 = (mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] as PackedVector2Array)[n * 4]
	return Vector2i(floori(uv.y), floori(uv.x))


func test_a_flash_is_one_mesh_of_small_quads() -> void:
	var mesh: ArrayMesh = FeelScript.flash_mesh()
	check(mesh == FeelScript.flash_mesh(), "one mesh, made once")
	var quads: int = 0
	for entry: Vector3i in FeelScript.FLASH_QUADS:
		quads += entry.y
	var arrays: Array = mesh.surface_get_arrays(0)
	check_equal((arrays[Mesh.ARRAY_VERTEX] as PackedVector2Array).size(), quads * 4, "a quad for every slot of every kind")
	check_equal((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), quads * 6, "two triangles each")
	check_equal(_quad(mesh, 0), Vector2i(FeelScript.FLASH_Q_LIGHT, 0), "the light first, under everything")
	check_equal(_quad(mesh, 1), Vector2i(FeelScript.FLASH_Q_CLOUD, 3), "then a poof's clouds, the first on top")
	# No sparks or card particles: they are the cues' motes (S6, item 3).
	check_equal(quads, 6, "the light, four clouds and the flash")
	check_equal(_quad(mesh, quads - 1), Vector2i(FeelScript.FLASH_Q_SHAPE, 0), "the flash last, on top")
	check(feel._flash_node.multimesh.mesh == mesh, "the flash batch draws it")
	check(feel._arc_node.multimesh.mesh != mesh and feel._status_node.multimesh.mesh != mesh, "the arcs and statuses keep their one quad")


func test_every_beam_is_one_mesh_of_small_quads_never_culled() -> void:
	for player in 4:
		bus.carrier_shown.emit(player, &"beam", Vector2(0, player * 30), Vector2.RIGHT, 300.0, FROST, 0)
	var union: BeamUnion = _union()
	var mesh: ArrayMesh = union.node.mesh as ArrayMesh
	check_equal(feel._beam_unions.size(), 1, "every beam of one look in one union")
	check_equal(mesh.surface_get_array_len(0), union.segment_room() * 4, "a quad a piece of every path, nothing else: its splash and card particles are motes (S6 item 10)")
	check(union.segments >= 4 * ceili(300.0 / BeamUnion.PIECE_MOST), "each path cut into pieces of at most PIECE_MOST pixels: %d" % union.segments)
	check(mesh.custom_aabb.size.x >= 100000.0 and mesh.custom_aabb.size.y >= 100000.0, "its box is the world: the shader places it, so it is never culled")
	check_equal(union.material.get_shader_parameter(&"seg_count"), union.segments, "the shader is told how many pieces to draw")
	check(union.material.get_shader_parameter(&"beam_data") is Texture2D, "and their data, in one texture")
	var children: int = feel.get_child_count()
	for ray in 100:
		bus.carrier_shown.emit(ray % 4, &"beam", Vector2(0, ray), Vector2.UP, 100.0, FROST, 0)
	_union()
	check_equal(feel.get_child_count(), children, "more beams make no node: one draw for them all")


## The births in the spectacle's collector now (Feel's own motes this frame, before they are given off).
func _births() -> Array[PackedFloat32Array]:
	var births: BirthsScript = feel.spectacle().births
	var found: Array[PackedFloat32Array] = []
	for n in births.count:
		found.append(births.rows.slice(n * BirthsScript.STRIDE, (n + 1) * BirthsScript.STRIDE))
	return found


func test_a_beam_gives_off_its_splash_and_card_particles_as_motes() -> void:
	# A straight beam 100 px down from (0, 0), of a mend card (its look kind 6), for one second.
	var path := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 100, 100)])
	feel.spectacle().births.clear()
	var look: int = 1 << (ProjectilesScript.LOOK_MOTES - 1)
	feel._beam_motes(path, 2, 100.0, Vector2(0, 100), Vector2.DOWN, 1.0, 1, look, FROST, 55, 1.0)
	var splash: int = 0
	var along: int = 0
	for b: PackedFloat32Array in _births():
		var at := Vector2(b[ProjectilesScript.SPARK_X], b[ProjectilesScript.SPARK_Y])
		var way := Vector2(b[ProjectilesScript.SPARK_BACK_X], b[ProjectilesScript.SPARK_BACK_Y])
		check_equal(ProjectilesScript.spark_tag(b, 0), 55, "of its spell")
		check_equal(int(b[ProjectilesScript.SPARK_RAMP]), 1, "in its caster's ramp")
		if int(b[ProjectilesScript.SPARK_KIND]) == 0:
			splash += 1
			check(at.is_equal_approx(Vector2(0, 100)) and way.is_equal_approx(Vector2.UP), "a splash spark thrown back off where it lands")
		else:
			along += 1
			check_equal(int(b[ProjectilesScript.SPARK_KIND]), ProjectilesScript.LOOK_MOTES, "a card particle of its look's kind")
			check(at.x == 0.0 and at.y >= 0.0 and at.y <= 100.0 and absf(way.x) > 0.99, "from a point along it, out to a side: %s %s" % [at, way])
	check(absf(float(splash) - FeelScript.BEAM_SPLASH_RATE) <= 1.0, "BEAM_SPLASH_RATE splash sparks a second: %d" % splash)
	check(absf(float(along) - 6.0 * FeelScript.BEAM_PARTICLE_RATE) <= 1.0, "each of its 6 card particles BEAM_PARTICLE_RATE times a second: %d" % along)
	feel.spectacle().births.clear()
	feel._beam_motes(path, 2, 100.0, Vector2(0, 100), Vector2.DOWN, FeelScript.BEAM_SPLASH_FADE, 1, 0, FROST, 55, 1.0)
	check_equal(feel.spectacle().births.count, 0, "a dissolving beam of no cards gives off nothing")


func test_live_and_shown_beams_give_their_motes_to_the_pool() -> void:
	var beams := own(FakeBeams.new()) as FakeBeams
	feel.spells = beams
	feel.step(0.016)
	var before: int = feel.motes().births
	for i in 30:
		feel.step(0.016)
	check(feel.motes().births - before > 10, "a live beam's births are thrown as motes: %d" % (feel.motes().births - before))
	feel.spells = null
	bus.carrier_shown.emit(1, &"beam", Vector2(10, 20), Vector2.DOWN, 150.0, FROST, 0)
	before = feel.motes().births
	for i in 10:
		feel.step(0.016)
	check(feel.motes().births > before, "a beam shown whole splashes too")
	check_equal(feel.spectacle().births.count, 0, "and the collector is emptied every frame")


func test_the_beam_shader_draws_no_particles() -> void:
	var code: String = ShaderSource.of(FeelScript.BEAM_SHADER)
	check(not code.contains("shot_particle") and not code.contains("Q_SPLASH") and not code.contains("Q_PARTICLE"), "its splash and card particles are motes (S6 item 10)")
