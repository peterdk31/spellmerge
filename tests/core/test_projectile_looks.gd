extends "res://tests/support/suite.gd"
## The look of a shot (staffs B6a): a player's shot is drawn as a body kind (bolt, rune, orbit)
## with its player, its look layers and its core colour in the instance data that
## `shot_core.gdshader` reads, at a size that follows its hit radius in whole pixels; cards
## give the layers (`look_layer`), the compiler combines every infusion's and modifier's look
## into one set, and the runtime hands it to the manager. Stepped and drawn by hand.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
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
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	mgr.set_cap(600)
	root.add_child(mgr)


## The kind written in the custom data of instance `i` of a node's buffer.
func kind_at(node: MultiMeshInstance2D, i: int) -> int:
	var buffer: PackedFloat32Array = node.multimesh.buffer
	return roundi((1.0 - buffer[i * ManagerScript.DRAW_STRIDE + 15]) * ManagerScript.KIND_STEPS)


## The instance colour of instance `i`, decoded as the shader does: [player, zoom, look].
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


func test_player_shots_carry_their_body_player_look_and_core() -> void:
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
		check_equal(decoded[2], want, "player %d's five layers decode as the shader reads them" % (decoded[0] + 1))
		check_equal(decoded[1], 1, "a bolt has zoom 1")
		seen.append(decoded[0])
		var buffer: PackedFloat32Array = mgr._draw_node.multimesh.buffer
		var core: Color = Color(buffer[i * ManagerScript.DRAW_STRIDE + 12], buffer[i * ManagerScript.DRAW_STRIDE + 13], buffer[i * ManagerScript.DRAW_STRIDE + 14])
		check(core.is_equal_approx(Color(0.25, 0.5, 0.75)), "the core colour is in the custom data")
	seen.sort()
	check_equal(seen, [0, 1, 2, 3] as Array[int], "each shot names its own player")


func test_runes_and_orbit_shots_are_drawn_as_their_form() -> void:
	var rune: int = mgr.spawn(1, Vector2(50.0, 50.0), Vector2.ZERO, 1.0, 14.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_look(rune, ManagerScript.pack_look(PackedInt32Array([2])))
	mgr.set_anchor(2, Vector2(200.0, 200.0))
	mgr.spawn_orbit(2, 20.0, 0.0, 1.0, 1.0)
	mgr.update_draw(1.0)
	check_equal(kind_at(mgr._rune_node, 0), ManagerScript.KIND_RUNE, "a rune is drawn as a rune")
	check_equal(look_at(mgr._rune_node, 0), [1, 4, ManagerScript.pack_look(PackedInt32Array([2]))] as Array[int], "with its player, its zoom (radius 14) and its layers")
	check_equal(kind_at(mgr._orbit_node, 0), ManagerScript.KIND_ORBIT, "an orbit shot is drawn as an orbit shot (a bolt whose tail bends)")
	check_equal(look_at(mgr._orbit_node, 0)[0], 2, "of its player")


func test_enemy_shots_keep_their_sprite() -> void:
	mgr.spawn(-1, Vector2(80.0, 50.0), Vector2(60.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_PLAYER)
	mgr.update_draw(1.0)
	check_equal(kind_at(mgr._hostile_node, 0), 0, "an enemy shot is the enemy sprite")
	var buffer: PackedFloat32Array = mgr._hostile_node.multimesh.buffer
	check(is_equal_approx(buffer[0], 8.0 * ManagerScript.DRAW_SCALE), "at DRAW_SCALE of its hit circle")


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
	check(slot >= 0 and is_equal_approx(buffer[0], 72.0), "the drawn quad is look_length along the flight")
	check(is_equal_approx(buffer[5], -24.0) and is_equal_approx(buffer[1], 0.0) and is_equal_approx(buffer[4], 0.0), "and look_size across")
	check(is_equal_approx(buffer[3], mgr.get_position_of(slot).x - 24.0) and is_equal_approx(buffer[7], 100.0), "reaching 12 px ahead of the shot, the rest behind it for the tail")


## The bend a shot's instance carries, decoded as the shader does (1 / the radius, signed).
func bend_at(node: MultiMeshInstance2D, i: int) -> float:
	var coded: float = (1.0 - node.multimesh.buffer[i * ManagerScript.DRAW_STRIDE + 15]) * ManagerScript.KIND_STEPS
	var code: float = coded - floorf(coded + 0.5)
	return (code - ManagerScript.BEND_ZERO) / ManagerScript.BEND_SPAN / ManagerScript.BEND_RADIUS


func test_a_long_quad_still_points_along_a_diagonal_flight() -> void:
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(60.0, 80.0), 1.0, 5.0)
	mgr.update_draw(1.0)
	var buffer: PackedFloat32Array = mgr._draw_node.multimesh.buffer
	var along := Vector2(buffer[0], buffer[4])
	var across := Vector2(buffer[1], buffer[5])
	check(along.is_equal_approx(Vector2(0.6, 0.8) * 72.0), "the quad's long axis is the heading (rows: x.x, y.x, _, o.x / x.y, y.y, _, o.y)")
	check(across.is_equal_approx(Vector2(0.8, -0.6) * 24.0), "and its short axis crosses it")
	check(is_equal_approx(along.dot(across), 0.0), "square to each other")
	check(slot >= 0, "the shot was live")


func test_a_straight_shot_does_not_bend() -> void:
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(200.0, 0.0), 1.0)
	for i in 3:
		mgr.step(1.0 / 60.0)
	check_equal(mgr.bend_of(slot), 0.0, "a straight path has no bend")
	mgr.update_draw(1.0)
	check(absf(bend_at(mgr._draw_node, 0)) < 0.0005, "and draws none")
	check_equal(kind_at(mgr._draw_node, 0), ManagerScript.KIND_BOLT, "the bend leaves the kind as it was")


func test_an_orbit_shot_bends_round_its_circle_either_way() -> void:
	mgr.set_anchor(0, Vector2(200.0, 200.0))
	var clockwise: int = mgr.spawn_orbit(0, 36.0, 0.0, 4.0, 5.0, 6.0)
	var back: int = mgr.spawn_orbit(0, 36.0, PI, -4.0, 5.0, 6.0)
	var tight: int = mgr.spawn_orbit(0, 4.0, 0.0, 4.0, 5.0, 6.0)
	mgr.step(1.0 / 60.0)
	check(is_equal_approx(mgr.bend_of(clockwise), 1.0 / 36.0), "1 / its radius")
	check(is_equal_approx(mgr.bend_of(back), -1.0 / 36.0), "the other way round, the other side")
	check(is_equal_approx(mgr.bend_of(tight), 1.0 / ManagerScript.BEND_RADIUS), "a tighter circle draws as the tightest bend")
	mgr.update_draw(1.0)
	for i in 3:
		check_equal(kind_at(mgr._orbit_node, i), ManagerScript.KIND_ORBIT, "orbit shot %d keeps its kind" % i)
	var drawn: Array[float] = []
	for i in 3:
		drawn.append(bend_at(mgr._orbit_node, i))
	drawn.sort()
	check(absf(drawn[0] + 1.0 / 36.0) < 0.0005 and absf(drawn[1] - 1.0 / 36.0) < 0.0005 and absf(drawn[2] - 1.0 / 16.0) < 0.0005, "the bends travel to the shader (%s)" % str(drawn))


func test_a_turning_shot_bends_and_a_corner_does_not() -> void:
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 1.0)
	mgr._prev[slot] = Vector2(100.0, 100.0)
	mgr._pos[slot] = Vector2(110.0, 100.0)
	mgr._vel[slot] = Vector2(100.0, 0.0).rotated(0.1)
	check(is_equal_approx(mgr.bend_of(slot), 2.0 * 0.1 / 10.0), "a heading 0.1 rad off a 10 px chord: a curve of radius 50")
	mgr._vel[slot] = Vector2(100.0, 0.0).rotated(-0.1)
	check(is_equal_approx(mgr.bend_of(slot), -0.02), "turning the other way bends the other way")
	mgr._vel[slot] = Vector2(100.0, 0.0).rotated(2.5)
	check_equal(mgr.bend_of(slot), 0.0, "a bounce is a corner, not a bend")
	mgr._vel[slot] = Vector2(100.0, 0.0).rotated(0.45)
	check(is_equal_approx(mgr.bend_of(slot), 1.0 / ManagerScript.BEND_RADIUS), "a sharp turn draws as the tightest bend")
	mgr._pos[slot] = Vector2(100.1, 100.0)
	check_equal(mgr.bend_of(slot), 0.0, "a shot that barely moved does not bend")


func test_the_shader_holds_the_same_quad_and_bend_as_the_manager() -> void:
	var shader: Shader = load("res://core/projectiles/shot_core.gdshader")
	check(shader.code.contains("const float GRID = %d.0;" % ManagerScript.LOOK_GRID), "the same width")
	check(shader.code.contains("const float LENGTH = %d.0;" % ManagerScript.LOOK_LENGTH), "the same length")
	check(shader.code.contains("const float FRONT = %d.0;" % (ManagerScript.LOOK_GRID / 2)), "the shot as far from the front")
	check(shader.code.contains("const float BEND_ZERO = %s;" % str(ManagerScript.BEND_ZERO)), "the same straight bend code")
	check(shader.code.contains("const float BEND_SPAN = %s;" % str(ManagerScript.BEND_SPAN)), "the same span")
	check(shader.code.contains("const float BEND_RADIUS = %d.0;" % int(ManagerScript.BEND_RADIUS)), "the same tightest bend")
	check(ManagerScript.BEND_ZERO + ManagerScript.BEND_SPAN < 0.5 and ManagerScript.BEND_ZERO - ManagerScript.BEND_SPAN > 0.0, "the bend code rounds away from the kind")


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


func _on_impact(_player: int, _target: Node, _position: Vector2, _direction: Vector2) -> void:
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


## Spawn `count` bolts for `player`, each with the look of `kinds`.
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
	var shader: Shader = load("res://core/projectiles/shot_core.gdshader")
	check(shader.code.contains("min(4.0 + 2.0 * emit_count, float(MAX_PARTICLES))"), "the shader asks 4 + 2 per kind")
	check(shader.code.contains("const int MAX_PARTICLES = %d;" % ManagerScript.PARTICLES_PER_SHOT_MAX), "with the same cap")
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


func test_the_pool_asks_nothing_for_enemy_shots_or_plain_ones() -> void:
	mgr.particle_cap = 10
	mgr.spawn(-1, Vector2(50.0, 50.0), Vector2(1.0, 0.0), 1.0)
	mgr.spawn(0, Vector2(80.0, 50.0), Vector2(1.0, 0.0), 1.0)
	mgr.update_draw(1.0)
	check_equal(mgr.particle_demand, 0, "no particles asked")
	check_equal(mgr.trail_demand, ManagerScript.TRAIL_COST, "only the player's bolt has a trail")
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
