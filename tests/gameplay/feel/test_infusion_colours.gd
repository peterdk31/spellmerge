extends "res://tests/support/suite.gd"
## Every infusion on a spell shows (the owner, 2026-11-08: a beam of several infusions shows each,
## "I would like this to be the case for all carriers/cards", and its motes "should also be different
## motes based on infusions (as a general rule)"). The infusion table (core/spells/infusion_table.gd)
## gives each infusion's colour by its look layer, from the cards; the shaders read it as a global
## uniform and weave a look of several (shot_look.gdshaderinc); the motes of a spell of several take
## their own infusion's colours, or its infusions in turn (`Motes.set_infusions`).
##
## godot --headless --path . --script res://tests/gameplay/feel/test_infusion_colours.gd

const MotesScript := preload("res://gameplay/feel/mote.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

const FIRE: Color = Color("e0592f")
const FROST: Color = Color("4fd6dc")
const FIRE_LOOK: int = 1 << 0
const FROST_LOOK: int = 1 << 1
const BIGGER_LOOK: int = 1 << 6

var registry: RegistryScript = null


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


## A table of fire on layer 1 and frost on layer 2.
func _table() -> PackedColorArray:
	var table := PackedColorArray()
	table.resize(InfusionTable.LAYERS)
	table.fill(Color(0.0, 0.0, 0.0, 0.0))
	table[1] = FIRE
	table[2] = FROST
	return table


func _kind(id: StringName, layer: int) -> MoteKind:
	var kind := MoteKind.new()
	kind.id = id
	kind.gravity = 300.0
	kind.look_layers = PackedInt32Array([layer])
	return kind


## A pool of embers (fire's, layer 1), flecks (frost's, layer 2) and sparks (layer 0, any shot's),
## knowing the infusions of `_table`.
func _pool() -> MotesScript:
	var kinds: Array[MoteKind] = [_kind(&"ember", 1), _kind(&"fleck", 2), _kind(&"spark", 0)]
	var motes: MotesScript = own(MotesScript.new(4096, 0, kinds)) as MotesScript
	root.add_child(motes)
	motes.set_infusions(_table())
	return motes


func _core(motes: MotesScript, row: int) -> Color:
	var data: PackedFloat32Array = motes.row_data(row)
	return Color(data[MotesScript.ROW_CORE], data[MotesScript.ROW_CORE + 1], data[MotesScript.ROW_CORE + 2])


func _kind_of(motes: MotesScript, row: int) -> StringName:
	return motes.kinds()[roundi(motes.row_data(row)[MotesScript.ROW_KIND] * MotesScript.KIND_CODE)].id


func test_the_table_holds_each_infusion_by_its_look_layer() -> void:
	var table: PackedColorArray = InfusionTable.of_registry(registry)
	check_equal(table.size(), InfusionTable.LAYERS, "a colour for every look layer")
	var seen: Dictionary = {}
	for card: Resource in registry.get_all(&"spells"):
		var element := card as ElementBase
		if element == null:
			continue
		check(element.look_layer > 0, "%s: an infusion has a look layer, which is how its colour is known" % element.id)
		check(not seen.has(element.look_layer), "%s and %s share look layer %d: only one shows" % [element.id, seen.get(element.look_layer, &""), element.look_layer])
		seen[element.look_layer] = element.id
		var tint: Color = table[element.look_layer]
		check(tint.a == 1.0 and Color(tint.r, tint.g, tint.b).is_equal_approx(Color(element.tint.r, element.tint.g, element.tint.b)), "%s's colour on its layer" % element.id)
	check(seen.size() >= 6, "every infusion: %d" % seen.size())
	var bits: int = InfusionTable.mask(table)
	for layer in range(1, InfusionTable.LAYERS):
		check_equal((bits >> (layer - 1)) & 1 == 1, seen.has(layer), "layer %d is an infusion's in the mask exactly when a card has it" % layer)
		if not seen.has(layer):
			check_equal(table[layer].a, 0.0, "layer %d is no infusion's" % layer)


func test_the_shaders_read_it_as_a_global_marked_texture() -> void:
	# A texture never published reads white or black: neither is an infusion, so a look drawn before
	# Spells publishes the table (or with none) is as it was.
	check(ProjectSettings.has_setting("shader_globals/" + InfusionTable.PARAMETER), "project.godot declares the global uniform")
	var image: Image = InfusionTable.texture(_table()).get_image()
	check_equal(image.get_size(), Vector2i(InfusionTable.LAYERS, 1), "a texel a layer")
	check(absf(image.get_pixel(1, 0).a - InfusionTable.MARK) < 0.003 and image.get_pixel(1, 0).r > 0.8, "fire's texel: its tint, marked")
	check_equal(image.get_pixel(5, 0).a, 0.0, "a layer of no infusion is not")
	var look: String = FileAccess.get_file_as_string("res://core/projectiles/shot_look.gdshaderinc")
	check(look.contains("global uniform sampler2D %s;" % InfusionTable.PARAMETER), "the shared look reads it")
	check(look.contains("const float INFUSION_MARK = 128.0 / 255.0;") and is_equal_approx(InfusionTable.MARK, 128.0 / 255.0), "with the table's mark")
	check(look.contains("#ifndef LOOK_OWN_INFUSIONS"), "and weaves a look of several unless the shader shows them its own way")
	# These show each infusion their own way (the beam's strands) or are in one infusion's colours
	# already (a mote, the mark it leaves): their looks are not woven.
	for path: String in ["res://content/spells/forms/beam/beam.gdshader", "res://gameplay/feel/light_beam.gdshader", "res://gameplay/feel/mote.gdshader", "res://gameplay/feel/mark.gdshader"]:
		var code: String = FileAccess.get_file_as_string(path)
		var own_at: int = code.find("#define LOOK_OWN_INFUSIONS")
		check(own_at >= 0 and own_at < code.find("shot_look.gdshaderinc\""), "%s opts out before it includes the look" % path)


func test_a_spells_motes_take_each_of_its_infusions_colours() -> void:
	var motes: MotesScript = _pool()
	# Fire first (its core colour), then frost, and a modifier's layer that is no infusion.
	motes.shed_kinds(PackedInt32Array([0, 1, 2]), Vector2.ZERO, Vector2.LEFT, FIRE, 0, FIRE_LOOK | FROST_LOOK | BIGGER_LOOK, 3.0)
	var written: int = motes.next_row()
	check(written > 6, "it shed: %d" % written)
	var sparks: Array[Color] = []
	for row in written:
		var core: Color = _core(motes, row)
		match _kind_of(motes, row):
			&"ember":
				check(core.is_equal_approx(FIRE), "an ember is fire's")
			&"fleck":
				check(core.is_equal_approx(FROST), "a fleck is frost's, not the first infusion's")
			&"spark":
				sparks.append(core)
	check(sparks.size() >= 2, "sparks too: %d" % sparks.size())
	for n in sparks.size():
		check(sparks[n].is_equal_approx(FIRE if n % 2 == 0 else FROST), "a spark is no infusion's own: each takes the next in turn (%d)" % n)


func test_a_spell_of_one_infusion_keeps_its_own_colour() -> void:
	var motes: MotesScript = _pool()
	# A frost card (its core colour) with a modifier: every mote in its core, even a fire-layer kind
	# thrown for it by a cue (the infusions are a spell's two or more).
	motes.shed_kinds(PackedInt32Array([0, 2]), Vector2.ZERO, Vector2.LEFT, FROST, 0, FROST_LOOK | BIGGER_LOOK, 2.0)
	var written: int = motes.next_row()
	check(written > 0, "it shed")
	for row in written:
		check(_core(motes, row).is_equal_approx(FROST), "row %d: in its own colour" % row)
	check_equal(motes.infusions_of(FROST_LOOK | BIGGER_LOOK), 0, "one infusion is no weave")
	check_equal(motes.infusions_of(FIRE_LOOK | FROST_LOOK | BIGGER_LOOK), FIRE_LOOK | FROST_LOOK, "two are")


func test_a_cue_part_in_a_spells_colours_takes_its_infusions() -> void:
	var motes: MotesScript = _pool()
	motes.throw_part(2, Vector2.ZERO, Vector2.UP, 0, FIRE, 6, 20.0, 360.0, 1.0, false, false, Vector2.ZERO, 1.0, FIRE_LOOK | FROST_LOOK)
	check_equal(motes.next_row(), 6, "six sparks")
	for row in 6:
		check(_core(motes, row).is_equal_approx(FIRE if row % 2 == 0 else FROST), "spark %d: the infusions in turn" % row)
	motes.throw_part(1, Vector2.ZERO, Vector2.UP, 0, FIRE, 2, 20.0, 360.0, 1.0, false, false, Vector2.ZERO, 1.0, FIRE_LOOK | FROST_LOOK)
	check(_core(motes, 6).is_equal_approx(FROST) and _core(motes, 7).is_equal_approx(FROST), "frost's own kind in frost's colours")


func test_a_trails_births_take_their_spells_infusions() -> void:
	# A beam's, a tail's or a trail's births (`give_off`): of an infusion's layer, its colours; of
	# any other (a splash, layer 0; a tail code), the infusions in turn. The native kernel does the
	# same (test_native_motes).
	var motes: MotesScript = _pool()
	motes.native = false
	motes.set_native(false)
	var stride: int = ProjectilesScript.SPARK_BIRTH_STRIDE
	var layers: PackedInt32Array = PackedInt32Array([0, 0, 2, 0, ProjectilesScript.SPARK_TAIL])
	var given := PackedFloat32Array()
	given.resize(layers.size() * stride)
	for n in layers.size():
		var b: int = n * stride
		given[b + ProjectilesScript.SPARK_X] = 100.0
		given[b + ProjectilesScript.SPARK_Y] = 100.0
		given[b + ProjectilesScript.SPARK_BACK_X] = -1.0
		given[b + ProjectilesScript.SPARK_KIND] = layers[n]
		given[b + ProjectilesScript.SPARK_LOOK] = FIRE_LOOK | FROST_LOOK
		given[b + ProjectilesScript.SPARK_CORE] = FIRE.r
		given[b + ProjectilesScript.SPARK_CORE + 1] = FIRE.g
		given[b + ProjectilesScript.SPARK_CORE + 2] = FIRE.b
	motes.step(0.0)
	motes.give_off(given, layers.size())
	var cores: Array[Color] = []
	for row in motes.next_row():
		cores.append(_core(motes, row))
	# The tail code has no kind in this pool, so four were written: splash, splash, frost, splash.
	check_equal(cores.size(), 4, "a mote a birth with a kind")
	if cores.size() == 4:
		check(cores[0].is_equal_approx(FIRE) and cores[1].is_equal_approx(FROST), "the splashes take the infusions in turn")
		check(cores[2].is_equal_approx(FROST), "frost's own layer: frost's colours")
		check(cores[3].is_equal_approx(FIRE), "and the next splash the next in turn")
