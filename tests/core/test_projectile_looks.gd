extends "res://tests/support/suite.gd"
## The look of a shot (staffs B6a): a wizard's shot is drawn as a body kind (bolt, rune, orbit)
## with its ramp (actors G3a: its caster's `Actors.ramp_of`), its look layers and its core colour in the instance data that
## shot shaders read (`shot_trail.gdshader`, `shot_rune.gdshader`), at a size that follows its hit radius in whole pixels; cards
## give the layers (`look_layer`), the compiler combines every infusion's and modifier's look
## into one set, and the runtime hands it to the manager. Stepped and drawn by hand.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ELEMENTS: Array[String] = [
	"res://content/spells/elements/fire/fire.tres",
	"res://content/spells/elements/frost/frost.tres",
	"res://content/spells/elements/storm/storm.tres",
	"res://content/spells/elements/void/void.tres",
	"res://content/spells/elements/lightning/lightning.tres",
]
const FIRE := preload("res://content/spells/elements/fire/fire.tres")
const FROST := preload("res://content/spells/elements/frost/frost.tres")
const STORM := preload("res://content/spells/elements/storm/storm.tres")
const BIGGER := preload("res://content/spells/modifiers/bigger/bigger.tres")
const PIERCE := preload("res://content/spells/modifiers/pierce/pierce.tres")
const HOMING := preload("res://content/spells/modifiers/homing/homing.tres")
const SPLIT := preload("res://content/spells/modifiers/split/split.tres")

var mgr: ManagerScript


func before_each() -> void:
	mgr = own(ManagerScript.new()) as ManagerScript
	# Wizards at ids 0-3, seated (and drawn in hat ramps) 0-3.
	mgr.actors = own(ActorSeats.table()) as ActorsScript
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	mgr.set_cap(600)
	root.add_child(mgr)


## The kind written in the custom data of instance `i` of a node's buffer.
func kind_at(node: MultiMeshInstance2D, i: int) -> int:
	var buffer: PackedFloat32Array = node.multimesh.buffer
	return roundi((1.0 - buffer[i * ManagerScript.DRAW_STRIDE + 15]) * ManagerScript.KIND_STEPS)


## The instance colour of instance `i`, decoded as the shader does: [ramp, zoom, look].
func look_at(node: MultiMeshInstance2D, i: int) -> Array[int]:
	var buffer: PackedFloat32Array = node.multimesh.buffer
	var at: int = i * ManagerScript.DRAW_STRIDE + 8
	var red: int = roundi(buffer[at] * 255.0)
	var look: int = roundi(buffer[at + 1] * 255.0) | (roundi(buffer[at + 2] * 255.0) << 8) | (roundi(buffer[at + 3] * 255.0) << 16)
	return [red % 4, red / 4, look] as Array[int]


## Every layer kind there is.
func all_kinds() -> PackedInt32Array:
	var kinds := PackedInt32Array()
	for kind in range(1, ManagerScript.LOOK_COUNT):
		kinds.append(kind)
	return kinds


func test_pack_look_combines_every_kind() -> void:
	var look: int = ManagerScript.pack_look(PackedInt32Array([1, 0, 2, 99, 7, 8, 11, 5, 12]))
	for kind: int in [1, 2, 5, 7, 8, 11, 12]:
		check(ManagerScript.look_has(look, kind), "kind %d is in the look" % kind)
	for kind: int in [3, 4, 6, 9, 10]:
		check(not ManagerScript.look_has(look, kind), "kind %d is not" % kind)
	check_equal(ManagerScript.pack_look(PackedInt32Array([1, 1, 1])), ManagerScript.pack_look(PackedInt32Array([1])), "a kind brought twice shows once")
	check_equal(ManagerScript.pack_look(PackedInt32Array()), 0, "no kinds pack to 0")
	var everything: int = ManagerScript.pack_look(all_kinds())
	for kind in all_kinds():
		check(ManagerScript.look_has(everything, kind), "all the kinds at once keep kind %d" % kind)
	check(ManagerScript.LOOK_COUNT - 1 <= ManagerScript.LOOK_MAX_KINDS, "the kinds fit the instance data")


func test_set_look_takes_a_live_shot_and_a_valid_look_only() -> void:
	var slot: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2(100.0, 0.0), 1.0)
	var look: int = ManagerScript.pack_look(all_kinds())
	check(mgr.set_look(slot, look), "a live shot takes a look, every kind at once")
	check_equal(mgr.get_look_of(slot), look, "and keeps it")
	check(not mgr.set_look(slot, -1), "a negative look is refused")
	check(not mgr.set_look(slot, 1 << (ManagerScript.LOOK_COUNT - 1)), "a bit for a kind that does not exist is refused")
	check(not mgr.set_look(-1, look) and not mgr.set_look(999999, look), "a slot out of range is refused")
	check_equal(mgr.get_look_of(slot), look, "a refused look changes nothing")


func test_a_reused_slot_starts_plain() -> void:
	var slot: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2(100.0, 0.0), 1.0)
	mgr.set_look(slot, ManagerScript.pack_look(PackedInt32Array([3])))
	mgr.clear()
	var again: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2(100.0, 0.0), 1.0)
	check_equal(mgr.get_look_of(again), 0, "a new shot has no layers, not the last one's")


func test_wizard_shots_carry_their_body_ramp_look_and_core() -> void:
	var looks: Array[int] = []
	for player in 4:
		var slot: int = mgr.spawn(player, Vector2(50.0, 40.0 + player * 40.0), Vector2(100.0, 0.0), 1.0)
		mgr.set_look(slot, ManagerScript.pack_look(PackedInt32Array([player + 1, 7, 8, 11, 9 + player])))
		mgr.set_core(slot, Color(0.25, 0.5, 0.75))
	mgr.update_draw(1.0)
	check_equal(mgr.drawn, 4, "four bolts drawn")
	var seen: Array[int] = []
	for i in 4:
		check_equal(kind_at(mgr._draw_node, i), ManagerScript.KIND_BOLT, "a straight shot is drawn as a bolt")
		var decoded: Array[int] = look_at(mgr._draw_node, i)
		var want: int = ManagerScript.pack_look(PackedInt32Array([decoded[0] + 1, 7, 8, 11, 9 + decoded[0]]))
		check_equal(decoded[2], want, "ramp %d's five layers decode as the shader reads them" % (decoded[0] + 1))
		check_equal(decoded[1], 1, "a bolt has zoom 1")
		seen.append(decoded[0])
		var buffer: PackedFloat32Array = mgr._draw_node.multimesh.buffer
		var core: Color = Color(buffer[i * ManagerScript.DRAW_STRIDE + 12], buffer[i * ManagerScript.DRAW_STRIDE + 13], buffer[i * ManagerScript.DRAW_STRIDE + 14])
		check(core.is_equal_approx(Color(0.25, 0.5, 0.75)), "the core colour is in the custom data")
	seen.sort()
	check_equal(seen, [0, 1, 2, 3] as Array[int], "each shot names its wizard's ramp")


func test_runes_and_orbit_shots_are_drawn_as_their_form() -> void:
	var rune: int = mgr.spawn(1, Vector2(50.0, 50.0), Vector2.ZERO, 1.0, 14.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_look(rune, ManagerScript.pack_look(PackedInt32Array([2])))
	mgr.set_anchor(2, Vector2(200.0, 200.0))
	mgr.spawn_orbit(2, 20.0, 0.0, 1.0, 1.0)
	mgr.update_draw(1.0)
	check_equal(kind_at(mgr._rune_node, 0), ManagerScript.KIND_RUNE, "a rune is drawn as a rune")
	check_equal(look_at(mgr._rune_node, 0), [1, 4, ManagerScript.pack_look(PackedInt32Array([2]))] as Array[int], "with its ramp, its zoom (radius 14) and its layers")
	check_equal(kind_at(mgr._orbit_node, 0), ManagerScript.KIND_BOLT, "an orbit shot is drawn as a shot in flight, its trail round its circle")
	check_equal(roundi(mgr._orbit_node.multimesh.buffer[5]), ManagerScript.TRAIL_HEAD | ManagerScript.TRAIL_ORBIT, "flagged an orbit shot")
	check_equal(look_at(mgr._orbit_node, 0)[0], 2, "in its caster's ramp")


func test_a_shot_of_no_actor_is_drawn_as_an_enemys_bolt() -> void:
	mgr.spawn(-1, Vector2(80.0, 50.0), Vector2(60.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_PLAYER)
	mgr.update_draw(1.0)
	check_equal(kind_at(mgr._enemy_node, 0), ManagerScript.KIND_BOLT, "a shot of no actor is drawn by the shader as a bolt (staffs F9b: no sprite)")


func test_the_instance_colour_keeps_every_hat_ramps_bytes() -> void:
	for ramp in 4:
		for zoom in [1, 4, 15, 63]:
			var look: int = ManagerScript.pack_look(PackedInt32Array([1, 5, 12])) | (1 << 23)
			var data: Color = ManagerScript.look_color(ramp, zoom, look)
			check_equal(roundi(data.r * 255.0), ramp + zoom * 4, "ramp %d at zoom %d: red is ramp + zoom x 4" % [ramp, zoom])
			check_equal(roundi(data.g * 255.0) | (roundi(data.b * 255.0) << 8) | (roundi(data.a * 255.0) << 16), look, "and the look's bytes, Feel's EXACT included, are as they were")


func test_an_enemy_is_drawn_in_the_enemy_ramp() -> void:
	var look: int = ManagerScript.pack_look(PackedInt32Array([1, 9]))
	var data: Color = ManagerScript.look_color(ActorsScript.RAMP_ENEMY, 2, look)
	check_equal(roundi(data.r * 255.0), 2 * 4, "the enemy ramp takes ramp 0's place in red")
	check_equal(ManagerScript.look_color(ActorsScript.NONE, 2, look), data, "no ramp draws as the enemy ramp")
	var bits: int = roundi(data.g * 255.0) | (roundi(data.b * 255.0) << 8) | (roundi(data.a * 255.0) << 16)
	check_equal(bits, look | ManagerScript.LOOK_ENEMY_RAMP, "with the enemy ramp's flag beside its kinds")
	check_equal(ManagerScript.ramp_look(1, look | ManagerScript.LOOK_ENEMY_RAMP), look, "a hat ramp never carries the flag")
	check(1 << (ManagerScript.LOOK_COUNT - 2) < ManagerScript.LOOK_ENEMY_RAMP, "no particle kind reaches the flag")
	check_equal(ManagerScript.LOOK_ENEMY_RAMP, 1 << 22, "the flag is kind 23, below Feel's EXACT (kind 24)")
	var palette: ShaderInclude = load("res://core/projectiles/shot_palette.gdshaderinc")
	check(palette.code.contains("const float ENEMY_RAMP = 23.0;"), "the shaders read the same flag")
	check(palette.code.contains("const float ENEMY_PLAYER = 4.0;"), "as a fifth ramp after the hats'")
	check(palette.code.contains("vec3(0.651, 0.541, 0.165))"), "whose base is Blight ochre (#a68a2a), last in P_BASE")
	var look_code: ShaderInclude = load("res://core/projectiles/shot_look.gdshaderinc")
	check(look_code.code.contains("bit_set(b, ENEMY_RAMP) ? ENEMY_PLAYER"), "every shot shader's look takes it")
	var beam: Shader = load("res://core/projectiles/shot_beam.gdshader")
	check(beam.code.contains("beam_player < 0 ? ENEMY_PLAYER"), "and an enemy's beam uses it too")
	check(ManagerScript.ramp_color(ActorsScript.RAMP_ENEMY).is_equal_approx(Color("#a68a2a")), "the enemy ramp's colour is Blight ochre")
	var enemy: int = ActorSeats.enemy(mgr.actors)
	check(mgr.tint_of(enemy).is_equal_approx(Color.WHITE.lerp(Color("#a68a2a"), ManagerScript.TINT_STRENGTH)), "and so is an enemy's tint")
	check(mgr.tint_of(EventsScript.NO_PLAYER).is_equal_approx(mgr.tint_of(enemy)), "and a shot's of no actor")


func test_shots_are_drawn_about_their_hit_size_in_whole_pixels() -> void:
	check_equal(ManagerScript.look_size(5.0), 24.0, "a bolt (radius 5) has zoom 1: a 3 px core in a 10 px circle, in a quad 24 px across")
	check_equal(ManagerScript.look_size(1.0), 24.0, "never below zoom 1")
	check_equal(ManagerScript.look_size(8.0), 48.0, "a bigger bolt (radius 8) has zoom 2")
	check_equal(ManagerScript.look_size(14.0), 96.0, "a rune (radius 14) has zoom 4")
	check_equal(ManagerScript.look_length(5.0), 72.0, "and 72 px long, for its tail")
	check_equal(ManagerScript.look_length(8.0), 144.0, "which grows with the zoom too")
	var cell: float = ManagerScript.look_size(5.0) / ManagerScript.LOOK_GRID
	check(3.0 * cell < 2.0 * 5.0, "the 3-cell core of a bolt is narrower than its hit circle: it hits wider than it looks")
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 1.0, 5.0)
	mgr.update_draw(1.0)
	var buffer: PackedFloat32Array = mgr._draw_node.multimesh.buffer
	check(slot >= 0 and is_equal_approx(buffer[3], 100.0) and is_equal_approx(buffer[7], 100.0), "a flying shot's instance holds its head where it is drawn")
	check_equal(roundi(buffer[0]), mgr.get_trail_of(slot), "and its trail's row in the transform's x axis (TRAILS in the shader)")
	check_equal(roundi(buffer[5]), ManagerScript.TRAIL_HEAD, "flagged alive: the core is drawn")


func test_a_flying_shot_leaves_its_path_behind() -> void:
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(120.0, 0.0), 2.0)
	var row: int = mgr.get_trail_of(slot)
	check(row >= 0, "a bolt takes a trail row")
	check_equal(mgr.get_trail_kept(row), 1, "starting where it was cast")
	for i in 30:
		mgr.step(1.0 / 60.0)
	var kept: int = mgr.get_trail_kept(row)
	check(kept >= 15 and kept <= 17, "half a second keeps about 15 points, one every TRAIL_EVERY (%d)" % kept)
	var newest: Vector4 = mgr.get_trail_point(row, 0)
	var older: Vector4 = mgr.get_trail_point(row, 1)
	check(newest.x > older.x and is_equal_approx(newest.y, 100.0), "the points are where it flew")
	check(is_equal_approx(newest.z - older.z, newest.x - older.x), "with how far it had gone")
	check(newest.w > older.w and newest.w <= mgr.sim_time, "and when")
	check(mgr.get_trail_point(row, kept).x == INF, "nothing past what it keeps")


func test_a_homing_turn_stays_in_the_path() -> void:
	# The owner (2026-10-28): the tail turned with the shot. The path keeps where it went.
	var slot: int = mgr.spawn(0, Vector2(100.0, 200.0), Vector2(0.0, -150.0), 2.0)
	var row: int = mgr.get_trail_of(slot)
	for i in 12:
		mgr.step(1.0 / 60.0)
	mgr._vel[slot] = Vector2(150.0, 0.0)
	for i in 12:
		mgr.step(1.0 / 60.0)
	var oldest: Vector4 = mgr.get_trail_point(row, mgr.get_trail_kept(row) - 1)
	var newest: Vector4 = mgr.get_trail_point(row, 0)
	check(is_equal_approx(oldest.x, 100.0) and is_equal_approx(oldest.y, 200.0), "the tail still starts where it went up")
	check(newest.x > 110.0 and newest.y < 180.0, "and ends where it turned to")


func test_a_bounce_leaves_its_corner_in_the_path() -> void:
	mgr.set_walls([Rect2(0.0, 0.0, 640.0, 40.0)] as Array[Rect2])
	var slot: int = mgr.spawn(0, Vector2(100.0, 60.0), Vector2(0.0, -120.0), 2.0)
	mgr.set_bounce(slot, 1)
	var row: int = mgr.get_trail_of(slot)
	var corner: bool = false
	for i in 20:
		mgr.step(1.0 / 60.0)
		if mgr._vel[slot].y > 0.0 and not corner:
			corner = mgr.get_trail_point(row, 0).y <= 40.5
	check(corner, "the point where it bounced is kept, so the tail turns there")


func test_a_trail_cools_where_its_shot_ended_then_goes() -> void:
	var slot: int = mgr.spawn(1, Vector2(100.0, 100.0), Vector2(120.0, 0.0), 0.2)
	mgr.set_core(slot, Color(0.878, 0.349, 0.184))
	var row: int = mgr.get_trail_of(slot)
	for i in 13:
		mgr.step(1.0 / 60.0)
	check(not mgr.is_alive(slot), "the shot's life ran out")
	check_equal(mgr.get_trail_count(), 1, "its trail is still there")
	check(mgr.get_trail_point(row, 0).x > 120.0, "with its last point where it ended")
	mgr.update_draw(1.0)
	check_equal(mgr.drawn, 0, "no shot is drawn")
	check_equal(mgr.drawn_trails, 1, "but its trail is, without a core")
	var buffer: PackedFloat32Array = mgr._draw_node.multimesh.buffer
	check_equal(roundi(buffer[5]) & ManagerScript.TRAIL_HEAD, 0, "flagged without a head")
	check(Color(buffer[12], buffer[13], buffer[14]).is_equal_approx(Color(0.878, 0.349, 0.184)), "in its shot's colours")
	check_equal(look_at(mgr._draw_node, 0)[0], 1, "and its player")
	for i in roundi(ManagerScript.TRAIL_KEEP * 60.0) + 3:
		mgr.step(1.0 / 60.0)
	check_equal(mgr.get_trail_count(), 0, "once all of it has cooled, the row is given back")
	mgr.update_draw(1.0)
	check_equal(mgr.drawn_trails, 0, "and nothing is drawn")


func test_an_orbit_shot_is_drawn_spiralling_out_from_its_caster() -> void:
	mgr.set_anchor(0, Vector2(200.0, 200.0))
	var slot: int = mgr.spawn_orbit(0, 36.0, 0.0, 4.0, 5.0, 6.0)
	var row: int = mgr.get_trail_of(slot)
	check(mgr.get_trail_point(row, 0).is_equal_approx(Vector4(200.0, 200.0, 0.0, mgr.sim_time)), "its trail starts on its caster")
	mgr.step(1.0 / 60.0)
	check(is_equal_approx(mgr.get_position_of(slot).distance_to(Vector2(200.0, 200.0)), 36.0), "it hits at its circle from the start")
	mgr.update_draw(1.0)
	var buffer: PackedFloat32Array = mgr._orbit_node.multimesh.buffer
	var drawn_out: float = Vector2(buffer[3], buffer[7]).distance_to(Vector2(200.0, 200.0))
	check(drawn_out > 1.0 and drawn_out < 6.0, "but is drawn near its caster at first (%.1f px out)" % drawn_out)
	check_equal(roundi(buffer[5]), ManagerScript.TRAIL_HEAD | ManagerScript.TRAIL_ORBIT, "as an orbit shot's trail")
	for i in 20:
		mgr.step(1.0 / 60.0)
	mgr.update_draw(1.0)
	buffer = mgr._orbit_node.multimesh.buffer
	check(is_equal_approx(Vector2(buffer[3], buffer[7]).distance_to(Vector2(200.0, 200.0)), 36.0), "and on its circle after ORBIT_GROW")


func test_a_blink_starts_the_trail_afresh() -> void:
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(120.0, 0.0), 2.0)
	for i in 10:
		mgr.step(1.0 / 60.0)
	mgr.move_shot(slot, Vector2(0.0, 60.0), 0.0)
	var row: int = mgr.get_trail_of(slot)
	check_equal(mgr.get_trail_kept(row), 1, "no tail across the gap")


func test_a_caster_trail_follows_where_the_caster_goes() -> void:
	mgr.set_anchor(2, Vector2(100.0, 100.0))
	var row: int = mgr.follow_caster(2, Color.WHITE, 0, 0.2)
	check(row >= 0, "a dash takes a row")
	for i in 12:
		mgr.set_anchor(2, Vector2(100.0, 100.0) + Vector2(cos(i * 0.2), sin(i * 0.2)) * 40.0)
		mgr.step(1.0 / 60.0)
	var newest: Vector4 = mgr.get_trail_point(row, 0)
	check(Vector2(newest.x, newest.y).distance_to(Vector2(100.0, 100.0)) > 30.0, "its points are where the caster went, round a curve")
	mgr.update_draw(1.0)
	var buffer: PackedFloat32Array = mgr._draw_node.multimesh.buffer
	check_equal(roundi(buffer[5]), ManagerScript.TRAIL_DASH | ManagerScript.TRAIL_HEAD, "drawn as a dash, its head on the caster")
	check_equal(look_at(mgr._draw_node, 0)[0], 2, "in its player's colours")
	for i in roundi((0.2 + ManagerScript.TRAIL_KEEP) * 60.0) + 4:
		mgr.step(1.0 / 60.0)
	check_equal(mgr.get_trail_count(), 0, "after its time and its cooling, the row is given back")
	check_equal(mgr.follow_caster(3, Color.WHITE, 0, 0.2), -1, "a caster with no anchor has nothing to follow")
	var enemy: int = ActorSeats.enemy(mgr.actors)
	mgr.set_anchor(enemy, Vector2(50.0, 50.0))
	mgr.follow_caster(enemy, Color.WHITE, 0, 0.2)
	mgr.update_draw(1.0)
	check_equal(mgr.drawn_trails, 1, "an enemy actor's dash is drawn")
	check((look_at(mgr._enemy_node, 0)[2] & ManagerScript.LOOK_ENEMY_RAMP) != 0, "in the enemies' batch, in the enemy ramp")


func test_when_the_rows_run_out_a_shot_has_its_core_alone() -> void:
	mgr.set_cap(2)
	for i in 4:
		mgr.spawn(0, Vector2(100.0, 50.0 + i * 20.0), Vector2(120.0, 0.0), 0.05)
		mgr.step(1.0 / 60.0)
		mgr.step(1.0 / 60.0)
		mgr.step(1.0 / 60.0)
		mgr.step(1.0 / 60.0)
	var slot: int = mgr.spawn(0, Vector2(100.0, 300.0), Vector2(120.0, 0.0), 1.0)
	check_equal(mgr.get_trail_count(), ManagerScript.TRAIL_ROWS_PER_SLOT * 2, "every row is held, by shots or cooling trails")
	check_equal(mgr.get_trail_of(slot), -1, "a new shot finds none")
	mgr.update_draw(1.0)
	check_equal(mgr.drawn, 1, "and is still drawn")


func test_the_shader_holds_the_same_trail_numbers() -> void:
	var shader: Shader = load("res://core/projectiles/shot_trail.gdshader")
	check(shader.code.contains("const int TRAIL_SAMPLES = %d;" % ManagerScript.TRAIL_SAMPLES), "the same samples a row")
	check(shader.code.contains("const float TF_HEAD = %d.0;" % ManagerScript.TRAIL_HEAD), "the same alive flag")
	check(shader.code.contains("const float TF_ORBIT = %d.0;" % ManagerScript.TRAIL_ORBIT), "the same orbit flag")
	check(shader.code.contains("const float TF_DASH = %d.0;" % ManagerScript.TRAIL_DASH), "the same dash flag")
	check(shader.code.contains("const float TRAIL_LONGEST = %s;" % str(ManagerScript.TRAIL_KEEP)), "and a trail is drawn as long as it is kept")
	check(ManagerScript.TRAIL_KEEP <= (ManagerScript.TRAIL_SAMPLES - 1) * ManagerScript.TRAIL_EVERY, "which the samples cover")
	var orbit: Shader = load("res://core/projectiles/shot_orbit.gdshader")
	check(orbit.code.contains("const float BEND_ZERO = %s;" % str(ManagerScript.BEND_ZERO)), "a familiar's bend code is the same")
	check(orbit.code.contains("const float BEND_SPAN = %s;" % str(ManagerScript.BEND_SPAN)), "and its span")


## Regression (the owner, 2026-10-29: the web build lost its WebGL context on a real GPU): every
## pixel of a trail's one big quad walked the whole path. A trail is a ribbon now, a quad per
## piece of its path placed by the vertex shader, and no pixel reads the path.
func test_a_trail_is_a_ribbon_and_no_pixel_walks_its_path() -> void:
	var mesh: ArrayMesh = ManagerScript.trail_mesh()
	check(mesh == ManagerScript.trail_mesh(), "one ribbon, made once")
	var quads: int = (ManagerScript.TRAIL_SAMPLES + 1) * 2
	var arrays: Array = mesh.surface_get_arrays(0)
	check_equal((arrays[Mesh.ARRAY_VERTEX] as PackedVector2Array).size(), quads * 4, "a quad for the head and one per piece, in two passes")
	check_equal((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), quads * 6, "two triangles each")
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	check_equal(floori(uvs[0].x), 0, "the light pass starts with the head")
	check_equal(floori(uvs[0].y), 0, "in pass 0")
	check_equal(floori(uvs[(quads - 1) * 4].x), 0, "the pixels pass ends with the head, on top")
	check_equal(floori(uvs[(quads - 1) * 4].y), 1, "in pass 1")
	check_equal(floori(uvs[(ManagerScript.TRAIL_SAMPLES + 1) * 4].x), ManagerScript.TRAIL_SAMPLES, "after the oldest piece first")
	check(mgr._draw_node.multimesh.mesh == mesh and mgr._enemy_node.multimesh.mesh == mesh and mgr._orbit_node.multimesh.mesh == mesh, "every trail batch draws it")
	var shader: Shader = load("res://core/projectiles/shot_trail.gdshader")
	var fragments: String = shader.code.get_slice("// ---- Fragments ----", 1)
	check(not fragments.is_empty(), "the shader marks where its fragment code starts")
	check(not fragments.contains("trail_texel") and not fragments.contains("texelFetch") and not fragments.contains("TRAIL_SAMPLES"), "no pixel reads the path")
	check(mgr._draw_node.material is ShaderMaterial and (mgr._draw_node.material as ShaderMaterial).shader == shader, "the bolts' batch is drawn by the trail shader")
	check((mgr._rune_node.material as ShaderMaterial).shader == load("res://core/projectiles/shot_rune.gdshader"), "the runes' by the rune shader")


## The code beside a rune's kind, as the shader reads it.
func code_at(node: MultiMeshInstance2D, i: int) -> float:
	var coded: float = (1.0 - node.multimesh.buffer[i * ManagerScript.DRAW_STRIDE + 15]) * ManagerScript.KIND_STEPS
	return coded - floorf(coded + 0.5)


func test_a_new_rune_traces_itself_onto_the_floor() -> void:
	mgr.spawn(0, Vector2(50.0, 50.0), Vector2.ZERO, 5.0, 14.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.update_draw(1.0)
	check(absf(code_at(mgr._rune_node, 0) - ManagerScript.TRACE_FROM) < 0.001, "a rune just cast is not traced yet")
	for i in 6:
		mgr.step(1.0 / 60.0)
	mgr.update_draw(1.0)
	var half: float = ManagerScript.TRACE_FROM + ManagerScript.TRACE_SPAN * 0.1 / ManagerScript.RUNE_TRACE
	check(absf(code_at(mgr._rune_node, 0) - half) < 0.001, "a tenth of a second later, part of it is")
	check_equal(kind_at(mgr._rune_node, 0), ManagerScript.KIND_RUNE, "still a rune")
	for i in 12:
		mgr.step(1.0 / 60.0)
	mgr.update_draw(1.0)
	check_equal(code_at(mgr._rune_node, 0), 0.0, "past RUNE_TRACE it is whole")
	check_equal(ManagerScript.trace_code(-1.0), 0.0, "a time out of order draws it whole")


var _seen_impacts: Array = []


func _on_impact(_caster: int, _target: Node, _position: Vector2, _direction: Vector2) -> void:
	_seen_impacts.append([mgr.impact_form, mgr.impact_core, mgr.impact_look])


func test_an_impact_names_the_shots_colour_and_look() -> void:
	_seen_impacts.clear()
	mgr.events.projectile_impact.connect(_on_impact)
	mgr.set_walls([Rect2(100.0, 0.0, 16.0, 200.0)] as Array[Rect2])
	var frost := Color(0.31, 0.84, 0.86)
	var look: int = ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_FLECKS]))
	var slot: int = mgr.spawn(1, Vector2(80.0, 50.0), Vector2(600.0, 0.0), 1.0)
	mgr.set_core(slot, frost)
	mgr.set_look(slot, look)
	for i in 6:
		mgr.step(1.0 / 60.0)
	check_equal(_seen_impacts.size(), 1, "the shot met the wall")
	if _seen_impacts.size() == 1:
		check_equal(_seen_impacts[0][0], &"bolt", "a bolt")
		check((_seen_impacts[0][1] as Color).is_equal_approx(frost), "in its frost colour")
		check_equal(_seen_impacts[0][2], look, "with its look")
	check_equal(mgr.impact_core, Color.WHITE, "outside an impact the colour is white")
	check_equal(mgr.impact_look, 0, "and the look none")


func test_looks_animate_from_the_simulation_clock() -> void:
	mgr.spawn(0, Vector2(50.0, 50.0), Vector2(10.0, 0.0), 1.0)
	for i in 30:
		mgr.step(1.0 / 60.0)
	mgr.update_draw(1.0)
	var drawn_time: float = float((mgr._draw_node.material as ShaderMaterial).get_shader_parameter(&"sim_time"))
	check_equal(drawn_time, mgr.sim_time, "the batch is drawn at the simulation time")
	check(absf(mgr.sim_time - 0.5) < 0.001, "which counts the stepped seconds, not the engine's clock")


func test_kinds_fit_the_alpha_encoding_and_round_trip() -> void:
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(ManagerScript.DRAW_STRIDE)
	for kind in ManagerScript.KIND_MAX + 1:
		mgr._write_quad(buffer, 0, Vector2.RIGHT, 1.0, Vector2.ZERO, Color.WHITE, Color.WHITE, kind)
		var alpha: float = buffer[15]
		check(alpha > 0.0 and alpha <= 1.0, "kind %d keeps the alpha inside 0..1" % kind)
		check_equal(floori((1.0 - alpha) * ManagerScript.KIND_STEPS + 0.5), kind, "kind %d decodes back as the shader does" % kind)


func test_the_elements_have_looks_of_their_own() -> void:
	var seen: Array[int] = []
	for path in ELEMENTS:
		var element: ElementBase = load(path) as ElementBase
		check(element.look_layer > 0 and element.look_layer < ManagerScript.LOOK_COUNT, "%s has a look" % element.id)
		check(not seen.has(element.look_layer), "%s has a look of its own" % element.id)
		seen.append(element.look_layer)
		check(element.range_problems().is_empty(), "%s is in range" % element.id)
	check_equal(int((FIRE.ranges()["look_layer"] as Vector2).y), ManagerScript.LOOK_COUNT - 1, "an infusion's top look is the manager's last")
	check_equal(int((BIGGER.ranges()["look_layer"] as Vector2).y), ManagerScript.LOOK_COUNT - 1, "so is a modifier's")
	var bad: ElementBase = FIRE.duplicate() as ElementBase
	bad.look_layer = ManagerScript.LOOK_COUNT
	check(not bad.range_problems().is_empty(), "a look the shader does not know is a validator problem")


func test_the_compiler_combines_every_card_with_a_look() -> void:
	var elements: Array[ElementBase] = [FIRE, FROST, STORM, FIRE]
	var modifiers: Array[ModifierBase] = [SPLIT, BIGGER, PIERCE, HOMING]
	var look: int = StaffCompiler._look_of(elements, modifiers)
	var want: int = ManagerScript.pack_look(PackedInt32Array([FIRE.look_layer, FROST.look_layer, STORM.look_layer, BIGGER.look_layer, PIERCE.look_layer, HOMING.look_layer]))
	check_equal(look, want, "three infusions and three modifiers all show; split has none, and fire twice shows once")
	var only_modifiers: int = StaffCompiler._look_of([] as Array[ElementBase], [HOMING] as Array[ModifierBase])
	check_equal(only_modifiers, ManagerScript.pack_look(PackedInt32Array([HOMING.look_layer])), "a plain shot shows its modifier's look")
	check_equal(StaffCompiler._look_of([] as Array[ElementBase], [SPLIT] as Array[ModifierBase]), 0, "no card with a look, no layers")


## Spawn `count` bolts for the actor `player`, each with the look of `kinds`.
func _volley(count: int, player: int, kinds: PackedInt32Array) -> void:
	var look: int = ManagerScript.pack_look(kinds)
	for i in count:
		var slot: int = mgr.spawn(player, Vector2(20.0 + i % 50 * 10.0, 40.0 + i / 50 * 6.0), Vector2(1.0, 0.0), 1.0)
		mgr.set_look(slot, look)


func _shader_share(node: MultiMeshInstance2D, name: StringName) -> float:
	return (node.material as ShaderMaterial).get_shader_parameter(name) as float


func test_a_shot_asks_the_pool_for_four_plus_two_per_emitting_kind() -> void:
	check_equal(ManagerScript.particles_of(0), 0, "a plain shot asks for none")
	check_equal(ManagerScript.particles_of(ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_WEAVE]))), 0, "a weave only changes the body")
	check_equal(ManagerScript.particles_of(ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_EMBERS]))), 6, "one kind: six")
	check_equal(ManagerScript.particles_of(ManagerScript.pack_look(PackedInt32Array([1, 2, 3]))), 10, "three kinds: ten")
	check_equal(ManagerScript.particles_of(ManagerScript.pack_look(all_kinds())), ManagerScript.PARTICLES_PER_SHOT_MAX, "never more than twelve")


func test_the_shader_holds_the_same_particle_rule_as_the_manager() -> void:
	for path: String in ["res://core/projectiles/shot_rune.gdshader", "res://core/projectiles/shot_orbit.gdshader"]:
		var shader: Shader = load(path)
		check(shader.code.contains("min(4.0 + 2.0 * emit_count(), float(MAX_PARTICLES))"), "%s asks 4 + 2 per kind" % path.get_file())
	var palette: ShaderInclude = load("res://core/projectiles/shot_palette.gdshaderinc")
	check(palette.code.contains("const int MAX_PARTICLES = %d;" % ManagerScript.PARTICLES_PER_SHOT_MAX), "with the same cap")
	check_equal(ManagerScript.EMITTING_MASK & (1 << (ManagerScript.LOOK_WEAVE - 1)), 0, "the weave does not emit")


func test_under_the_cap_nothing_thins() -> void:
	mgr.particle_cap = 1000
	_volley(20, 0, PackedInt32Array([ManagerScript.LOOK_EMBERS]))
	mgr.update_draw(1.0)
	check_equal(mgr.particle_demand, 20 * 6, "twenty shots ask for 120")
	check_equal(mgr.trail_demand, 20 * ManagerScript.TRAIL_COST, "and twenty trails")
	check_equal(mgr.particle_share, 1.0, "all particles")
	check_equal(mgr.trail_share, 1.0, "all trails")
	check_equal(_shader_share(mgr._draw_node, &"trail_share"), 1.0, "the shader is told")


func test_at_the_cap_the_trails_thin_first() -> void:
	mgr.particle_cap = 150
	_volley(20, 0, PackedInt32Array([ManagerScript.LOOK_EMBERS]))
	mgr.update_draw(1.0)
	check_equal(mgr.particle_share, 1.0, "the particles (120) fit, so they all show")
	check(is_equal_approx(mgr.trail_share, 30.0 / 80.0), "the trails get what is left: 30 of 80")
	check(is_equal_approx(_shader_share(mgr._draw_node, &"trail_share"), mgr.trail_share), "the shader draws that much trail")
	mgr.particle_cap = 100
	mgr.update_draw(1.0)
	check_equal(mgr.trail_share, 0.0, "when the particles fill the pool there is no trail")
	check(is_equal_approx(mgr.particle_share, 100.0 / 120.0), "and then the particles thin, every shot alike")
	check(is_equal_approx(_shader_share(mgr._rune_node, &"particle_share"), mgr.particle_share), "for every batch")


func test_four_players_share_one_pool() -> void:
	mgr.particle_cap = 240
	for player in 4:
		_volley(10, player, PackedInt32Array([ManagerScript.LOOK_EMBERS, ManagerScript.LOOK_SPARKS]))
	mgr.update_draw(1.0)
	check_equal(mgr.particle_demand, 40 * 8, "all four players' shots ask the same pool")
	check(is_equal_approx(mgr.particle_share, 240.0 / 320.0), "so everyone thins by the same share")


func test_the_pool_asks_no_particles_for_plain_shots() -> void:
	mgr.particle_cap = 10
	mgr.spawn(-1, Vector2(50.0, 50.0), Vector2(1.0, 0.0), 1.0)
	mgr.spawn(0, Vector2(80.0, 50.0), Vector2(1.0, 0.0), 1.0)
	mgr.update_draw(1.0)
	check_equal(mgr.particle_demand, 0, "no particles asked")
	check_equal(mgr.trail_demand, 2 * ManagerScript.TRAIL_COST, "both bolts have a trail (an enemy's shot is a shader bolt since staffs F9b)")
	check_equal(mgr.trail_share, 1.0, "which fits")


func test_a_crowd_of_looked_shots_stays_inside_the_cap() -> void:
	# 500 shots with five kinds each ask for 6,000 particles.
	_volley(500, 1, PackedInt32Array([1, 2, 3, 5, 7]))
	mgr.update_draw(1.0)
	check_equal(mgr.drawn, 500, "every shot is still drawn")
	check_equal(mgr.particle_demand, 500 * 12, "they ask for 6,000")
	var shown: float = float(mgr.particle_demand) * mgr.particle_share + float(mgr.trail_demand) * mgr.trail_share
	check(shown <= float(mgr.particle_cap) + 0.5, "what is drawn is no more than the cap")
	check_equal(mgr.trail_share, 0.0, "and the trails went first")


## Regression (performance pass, 2026-10-28): what a shot is drawn as is worked out once and kept
## with the slot; a new look, a radius that grew, or a new shot in the same slot redo it.
func test_a_kept_look_follows_set_look_growth_and_a_new_shot_in_the_slot() -> void:
	var slot: int = mgr.spawn(0, Vector2(50.0, 40.0), Vector2(100.0, 0.0), 2.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 7)
	mgr.set_look(slot, ManagerScript.pack_look(PackedInt32Array([1])))
	mgr.update_draw(1.0)
	check_equal(look_at(mgr._draw_node, 0)[2], ManagerScript.pack_look(PackedInt32Array([1])), "the first look")
	mgr.set_look(slot, ManagerScript.pack_look(PackedInt32Array([2, 3])))
	mgr.update_draw(1.0)
	check_equal(look_at(mgr._draw_node, 0)[2], ManagerScript.pack_look(PackedInt32Array([2, 3])), "a new look is drawn at once")
	mgr.set_growth(slot, 8.0)
	for i in 30:
		mgr.step(1.0 / 60.0)
	mgr.update_draw(1.0)
	check(look_at(mgr._draw_node, 0)[1] > 1, "a shot that grew is drawn bigger")
	check_equal(mgr.remove_by_tag(7), 1, "the shot ends")
	var again: int = mgr.spawn(ActorsScript.SEATS + 6, Vector2(50.0, 40.0), Vector2(100.0, 0.0), 2.0)
	check_equal(again, slot, "a new shot of another ramp takes the slot")
	mgr.update_draw(1.0)
	check_equal(mgr._draw_node.multimesh.visible_instance_count - mgr.drawn_trails, 0, "no live hat-ramp shot is left")
	check((look_at(mgr._enemy_node, 0)[2] & ManagerScript.LOOK_ENEMY_RAMP) != 0, "it is drawn in the enemy ramp, not the old shot's")
