extends "res://tests/support/suite.gd"
## The portal look (gameplay/feel/portal_look.gd; docs/milestones/carrier-looks-fixes.md, phase 2):
## from one typed read of the open portals (`PortalView`), each gate's lens is a quad drawn by the
## portal card's shader (or the plain one), sized by how open it is, and its lips, loose motes and
## the line to each exit are real motes (`placed_motes.gd`), the first lip in the first infusion and
## the second in the second.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_portal_look.gd

const PortalLookScript := preload("res://gameplay/feel/portal_look.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const CARD_SHADER: Shader = preload("res://content/spells/forms/portal/portal.gdshader")
const FIRE := Color("e0592f")
const FROST := Color("7fd4f0")

var look: PortalLookScript
var motes: MotesScript
var view: PortalView


func before_each() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var kinds: Array[MoteKind] = []
	for kind: Resource in registry.get_all(&"motes"):
		kinds.append(kind as MoteKind)
	motes = own(MotesScript.new(4096, 0, kinds)) as MotesScript
	root.add_child(motes)
	look = own(PortalLookScript.new()) as PortalLookScript
	root.add_child(look)
	view = PortalView.new()


## One portal of `infusions`, open `since` s with `left` s to go: its mouth at (100, 100) and one
## exit at (200, 100), both facing right, radius 12.
func _one_portal(infusions: PackedColorArray, since: float, left: float) -> void:
	view.portals = 1
	view.hold_portals(1)
	view.key[0] = 3
	view.caster[0] = -1
	view.look[0] = 0
	view.core[0] = infusions[0] if not infusions.is_empty() else Color.WHITE
	view.infusions[0] = infusions
	view.since[0] = since
	view.left[0] = left
	view.first_gate[0] = 0
	view.gate_count[0] = 2
	view.gates = 2
	view.hold_gates(2)
	for g in 2:
		view.centre[g] = Vector2(100.0 + 100.0 * g, 100.0)
		view.face[g] = Vector2.RIGHT
		view.radius[g] = 12.0
		view.mouth[g] = 1 if g == 0 else 0


## The lens quad of gate `g` as written: [x axis, y axis, centre, custom alpha].
func _lens(g: int) -> Array:
	var rows: PackedFloat32Array = look._rows
	var i: int = g * ManagerScript.DRAW_STRIDE
	return [Vector2(rows[i], rows[i + 4]), Vector2(rows[i + 1], rows[i + 5]), Vector2(rows[i + 3], rows[i + 7]), rows[i + 15]]


func test_an_open_portal_draws_a_lens_a_gate_sized_by_how_open_it_is() -> void:
	_one_portal(PackedColorArray([FIRE]), 2.0, 2.0)
	look.step(view, null, motes, 2.0)
	check_equal(look.gates_drawn, 2, "a lens for its mouth and its exit")
	var mouth: Array = _lens(0)
	check(mouth[2].is_equal_approx(Vector2(100.0, 100.0)), "the mouth's lens on the mouth")
	check(is_equal_approx(mouth[0].length(), 2.0 * (PortalLookScript.HALF_WIDE + PortalLookScript.GATE_PAD)), "open: its width across the way through (%s)" % mouth[0])
	check(is_equal_approx(mouth[1].length(), 2.0 * (PortalLookScript.HALF_TALL + PortalLookScript.GATE_PAD)), "and its height up it (%s)" % mouth[1])
	check(mouth[0].normalized().is_equal_approx(Vector2.RIGHT), "its width along the way through")
	check(mouth[3] >= 0.5 and _lens(1)[3] < 0.5, "the mouth told from the exit")
	_one_portal(PackedColorArray([FIRE]), 0.1, 2.0)
	look.step(view, null, motes, 2.1)
	var opening: Array = _lens(0)
	check(opening[1].length() > 2.0 * PortalLookScript.GATE_PAD and opening[0].length() < 2.0 * (PortalLookScript.HALF_WIDE * 0.5 + PortalLookScript.GATE_PAD), "a tenth of a second in: tall, not yet wide (%s, %s)" % [opening[0], opening[1]])
	_one_portal(PackedColorArray([FIRE]), 0.0, 2.0)
	look.step(view, null, motes, 2.2)
	check_equal(look.gates_drawn, 0, "the moment it opens, nothing yet")


func test_its_lips_are_motes_an_infusion_each() -> void:
	_one_portal(PackedColorArray([FIRE, FROST]), 2.0, 2.0)
	look.step(view, null, motes, 2.0)
	check(look.motes_placed >= 2 * 2 * PortalLookScript.LIP_ROWS * PortalLookScript.LIP_MOTES, "two lips of motes a gate (%d)" % look.motes_placed)
	var ward: int = motes.kind_index(PortalLookScript.KIND)
	var left_side: Array[Color] = []
	var right_side: Array[Color] = []
	for row in PortalLookScript.LIP_ROWS * PortalLookScript.LIP_MOTES * 2:
		var data: PackedFloat32Array = look._placed.row_data(row)
		check_equal(roundi(data[MotesScript.ROW_KIND] * MotesScript.KIND_CODE), ward, "a ward mote")
		var core := Color(data[MotesScript.ROW_CORE], data[MotesScript.ROW_CORE + 1], data[MotesScript.ROW_CORE + 2])
		if data[MotesScript.ROW_X] < 100.0:
			left_side.append(core)
		elif data[MotesScript.ROW_X] > 100.0:
			right_side.append(core)
	check(not left_side.is_empty() and left_side.all(func(c: Color) -> bool: return c.is_equal_approx(Color(FIRE.r, FIRE.g, FIRE.b))), "one lip in the first infusion")
	check(not right_side.is_empty() and right_side.all(func(c: Color) -> bool: return c.is_equal_approx(Color(FROST.r, FROST.g, FROST.b))), "the other in the second")


func test_with_no_pool_it_draws_its_lenses_and_no_motes() -> void:
	_one_portal(PackedColorArray(), 2.0, 2.0)
	look.step(view, null, null, 2.0)
	check_equal(look.gates_drawn, 2, "the lenses still")
	check_equal(look.motes_placed, 0, "no motes with particles off")
	look.step(null, null, motes, 2.1)
	check(look.gates_drawn == 0 and look.motes_placed == 0, "nothing with no portals")


func test_the_lens_is_the_cards_shader_or_the_plain_one() -> void:
	check(look.lens_shader() == PortalLookScript.PLAIN_SHADER, "plain before any card says")
	look.use_shaders([CARD_SHADER] as Array[Shader])
	check(look.lens_shader() == CARD_SHADER, "the portal card's own")
	look.use_shaders([] as Array[Shader])
	check(look.lens_shader() == PortalLookScript.PLAIN_SHADER, "plain when no card names one")


func test_it_opens_tall_then_wide_and_closes_the_other_way() -> void:
	var early: Vector2 = PortalLookScript.opening(0.15, 3.0)
	check(early.x > 0.5 and early.y < 0.05, "tall first (%s)" % early)
	check(PortalLookScript.opening(1.0, 3.0).is_equal_approx(Vector2.ONE), "then whole")
	var closing: Vector2 = PortalLookScript.opening(3.0, 0.4)
	check(closing.x > 0.9 and closing.y < 0.9, "narrowing first as it closes (%s)" % closing)
	check(PortalLookScript.opening(3.0, 0.0).is_zero_approx(), "gone at its end")


func test_the_gate_include_pads_the_lens_as_the_look_does() -> void:
	var code: String = (load("res://core/projectiles/shot_portal.gdshaderinc") as ShaderInclude).code
	var found := RegEx.create_from_string("const\\s+float\\s+GATE_PAD\\s*=\\s*([-0-9.]+)\\s*;").search(code)
	check(found != null and is_equal_approx(found.get_string(1).to_float(), PortalLookScript.GATE_PAD), "shot_portal.gdshaderinc's GATE_PAD is the look's, so a quad's size is read back as the lens it was sized for")
