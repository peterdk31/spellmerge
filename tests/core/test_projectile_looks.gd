extends "res://tests/support/suite.gd"
## The look of a shot (staffs B6a): a player's shot is drawn as a body kind (bolt, rune, orbit)
## with its player, its look layers and its core colour in the instance data that
## `shot_core.gdshader` reads, at a size that follows its hit radius in whole pixels; cards
## give the layers (`look_layer`), the compiler packs the first two infusions' and the first
## two modifiers' looks, and the runtime hands them to the manager. Stepped and drawn by hand.

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


## The instance colour of instance `i`, decoded as the shader does: [player, l0, l1, l2, l3].
func look_at(node: MultiMeshInstance2D, i: int) -> Array[int]:
	var buffer: PackedFloat32Array = node.multimesh.buffer
	var at: int = i * ManagerScript.DRAW_STRIDE + 8
	var g: int = roundi(buffer[at + 1] * 255.0)
	var b: int = roundi(buffer[at + 2] * 255.0)
	return [roundi(buffer[at] * 255.0), g >> 4, g & 15, b >> 4, b & 15] as Array[int]


func test_pack_look_keeps_order_and_skips_nothing_kinds() -> void:
	var look: int = ManagerScript.pack_look(PackedInt32Array([1, 0, 2, 99, 7, 8, 11]))
	check_equal(look, (1 << 12) | (2 << 8) | (7 << 4) | 8, "four known kinds in order; none, unknown and the fifth dropped")
	check_equal(ManagerScript.pack_look(PackedInt32Array()), 0, "no kinds pack to 0")
	check_equal(ManagerScript.pack_look(PackedInt32Array([5])), 5 << 12, "a lone kind is the first layer")


func test_set_look_takes_a_live_shot_and_a_valid_look_only() -> void:
	var slot: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2(100.0, 0.0), 1.0)
	var look: int = ManagerScript.pack_look(PackedInt32Array([1, 2]))
	check(mgr.set_look(slot, look), "a live shot takes a look")
	check_equal(mgr.get_look_of(slot), look, "and keeps it")
	check(not mgr.set_look(slot, -1), "a negative look is refused")
	check(not mgr.set_look(slot, 1 << 16), "a look past four layers is refused")
	check(not mgr.set_look(slot, ManagerScript.LOOK_COUNT << 12), "an unknown kind is refused")
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
		var look: int = ManagerScript.pack_look(PackedInt32Array([player + 1, 7, 8, 11]))
		mgr.set_look(slot, look)
		mgr.set_core(slot, Color(0.25, 0.5, 0.75))
	mgr.update_draw(1.0)
	check_equal(mgr.drawn, 4, "four bolts drawn")
	var seen: Array[int] = []
	for i in 4:
		check_equal(kind_at(mgr._draw_node, i), ManagerScript.KIND_BOLT, "a straight shot is drawn as a bolt")
		var decoded: Array[int] = look_at(mgr._draw_node, i)
		check_equal(decoded.slice(1), [decoded[0] + 1, 7, 8, 11] as Array[int], "player %d's layers decode as the shader reads them" % (decoded[0] + 1))
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
	check_equal(look_at(mgr._rune_node, 0), [1, 2, 0, 0, 0] as Array[int], "with its player and its layers")
	check_equal(kind_at(mgr._orbit_node, 0), ManagerScript.KIND_ORBIT, "an orbit shot is drawn as a pair of beads")
	check_equal(look_at(mgr._orbit_node, 0)[0], 2, "of its player")


func test_enemy_shots_keep_their_sprite() -> void:
	mgr.spawn(-1, Vector2(80.0, 50.0), Vector2(60.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_PLAYER)
	mgr.update_draw(1.0)
	check_equal(kind_at(mgr._hostile_node, 0), 0, "an enemy shot is the enemy sprite")
	var buffer: PackedFloat32Array = mgr._hostile_node.multimesh.buffer
	check(is_equal_approx(buffer[0], 8.0 * ManagerScript.DRAW_SCALE), "at DRAW_SCALE of its hit circle")


func test_shots_are_drawn_about_their_hit_size_in_whole_pixels() -> void:
	check_equal(ManagerScript.look_size(5.0), 16.0, "a bolt (radius 5) is 16 single pixels: a 5 px core in a 10 px circle")
	check_equal(ManagerScript.look_size(1.0), 16.0, "never below single pixels")
	check_equal(ManagerScript.look_size(8.0), 32.0, "a bigger bolt (radius 8) doubles its pixels")
	check_equal(ManagerScript.look_size(14.0), 64.0, "a rune (radius 14) is drawn in 4 px cells")
	var cell: float = ManagerScript.look_size(5.0) / ManagerScript.LOOK_GRID
	check(5.0 * cell < 2.0 * 5.0, "the 5-cell core of a bolt is narrower than its hit circle: it hits a little wider than it looks")
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 1.0, 5.0)
	mgr.update_draw(1.0)
	check(slot >= 0 and is_equal_approx(mgr._draw_node.multimesh.buffer[0], 16.0), "the drawn quad is look_size")


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


func test_the_compiler_takes_two_infusions_then_two_modifiers_with_a_look() -> void:
	var elements: Array[ElementBase] = [FIRE, FROST, STORM]
	var modifiers: Array[ModifierBase] = [SPLIT, BIGGER, PIERCE, HOMING]
	var look: int = StaffCompiler._look_of(elements, modifiers)
	var want: int = ManagerScript.pack_look(PackedInt32Array([FIRE.look_layer, FROST.look_layer, BIGGER.look_layer, PIERCE.look_layer]))
	check_equal(look, want, "fire and frost, then bigger and pierce: storm is a third infusion, split has no look, homing is a third modifier")
	var only_modifiers: int = StaffCompiler._look_of([] as Array[ElementBase], [HOMING] as Array[ModifierBase])
	check_equal(only_modifiers, ManagerScript.pack_look(PackedInt32Array([HOMING.look_layer])), "a plain shot shows its modifier's look")
	check_equal(StaffCompiler._look_of([] as Array[ElementBase], [SPLIT] as Array[ModifierBase]), 0, "no card with a look, no layers")
