extends "res://tests/support/suite.gd"
## Every card's own look, over the whole registry (docs/milestones/card-looks.md, phase 4). A card
## that names a `look_shader` is drawn by the area its carrier says (`Carrier.look_drawer`), so its
## shader must keep that area's contract: a canvas-item shader its carrier draws, the instance and
## mesh its area hands it (the quad kinds and flags of the area's plain shader, which it copies),
## the particle rule of that area, nothing read from the row floats the spell light reads, and a
## warm-up before the first room.
##
## godot --headless --path . --script res://tests/content/spells/test_card_looks.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const WarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const ShaderSource := preload("res://tests/support/shader_source.gd")

## The plain shader each area draws a card with no look of its own by: what a card's shader copies.
const PLAIN: Dictionary = {
	Carrier.LOOK_SHOT: "res://core/projectiles/shot_head.gdshader",
	Carrier.LOOK_STILL: "res://core/projectiles/shot_still.gdshader",
	Carrier.LOOK_BEAM: "res://core/projectiles/shot_beam.gdshader",
	Carrier.LOOK_SWING: "res://core/projectiles/shot_swing.gdshader",
	Carrier.LOOK_ORB: "res://core/projectiles/shot_orbit.gdshader",
	Carrier.LOOK_PORTAL: "res://core/projectiles/shot_portal.gdshader",
}
## The particle rule of a shader that draws its card particles (a still shot's quad, an orb):
## 4 + 2 a kind, at most MAX_PARTICLES. The others' particles are Feel's motes.
const PARTICLE_RULE: String = "min(4.0 + 2.0 * emit_count(), float(MAX_PARTICLES))"
const DRAWS_PARTICLES: Array[int] = [Carrier.LOOK_STILL, Carrier.LOOK_ORB]

var registry: Node


func before_each() -> void:
	registry = own(RegistryScript.new()) as Node
	registry.call("scan")


## The carrier cards that name a look of their own, as [card, the area that draws it].
func _looked_cards() -> Array:
	var found: Array = []
	for card: Resource in registry.call("get_all", &"spells"):
		var form := card as FormBase
		if form != null and form.look_shader != null:
			found.append([form, Carriers.of(form.carrier).look_drawer()])
	return found


func test_some_cards_have_a_look_of_their_own() -> void:
	var ids: Array[StringName] = []
	for each: Array in _looked_cards():
		ids.append((each[0] as FormBase).id)
	for id: StringName in [&"rune", &"wall", &"pool", &"bolt", &"swap", &"beam", &"swing", &"familiar", &"portal"]:
		check(ids.has(id), "%s draws with its folder's shader" % id)


func test_every_card_shader_is_one_its_carrier_draws() -> void:
	for each: Array in _looked_cards():
		var form: FormBase = each[0]
		check(form.look_problems().is_empty(), "%s: %s" % [form.id, form.look_problems()])
		check(PLAIN.has(each[1]), "%s's carrier %s draws a look (got %d)" % [form.id, form.carrier, each[1]])
		check(form.look_shader.resource_path.begins_with("res://content/spells/carriers/%s/" % form.id), "%s's shader is in its own folder" % form.id)


func test_every_card_shader_keeps_its_areas_instance_and_mesh() -> void:
	for each: Array in _looked_cards():
		var form: FormBase = each[0]
		if not PLAIN.has(each[1]):
			continue
		var plain: String = ShaderSource.of(load(PLAIN[each[1]]) as Shader)
		var code: String = ShaderSource.of(form.look_shader)
		for line: String in plain.split("\n"):
			if line.begins_with("const float Q_") or line.begins_with("const float HF_"):
				check(code.contains(line), "%s keeps its area's `%s`" % [form.id, line])
		check(code.contains("render_mode blend_premul_alpha"), "%s blends as the shot shaders do" % form.id)


func test_every_card_shader_keeps_its_areas_particle_rule() -> void:
	for each: Array in _looked_cards():
		var form: FormBase = each[0]
		var code: String = ShaderSource.of(form.look_shader)
		if DRAWS_PARTICLES.has(each[1]):
			check(code.contains(PARTICLE_RULE), "%s asks 4 + 2 particles a kind" % form.id)
		else:
			check(not code.contains(PARTICLE_RULE), "%s draws no card particles: its area's are motes" % form.id)


func test_no_card_shader_reads_the_light_floats() -> void:
	for each: Array in _looked_cards():
		var form: FormBase = each[0]
		check(not ShaderSource.of(form.look_shader).contains("MODEL_MATRIX[2]"), "%s leaves the row floats the spell light reads alone (LIGHT_*_FLOAT)" % form.id)


func test_every_card_shader_is_warmed_before_the_first_room() -> void:
	# Each area warms the card shaders it draws, as it draws them: the projectile manager its
	# bodies (numbered when Spells starts), Feel its beams', trails' and portals', Entities its orbs'.
	var manager := own(ProjectilesScript.new()) as ProjectilesScript
	var spells := own(SpellsScript.new()) as Node
	spells.set(&"registry", registry)
	spells.set(&"projectiles", manager)
	spells.call(&"register_bodies")
	var feel := own(FeelScript.new()) as FeelScript
	feel.spells = spells
	feel._warm_card_looks()
	var entities := own(EntitiesScript.new()) as EntitiesScript
	entities.spells = spells as SpellsScript
	entities.use_familiar_look()
	var warmed: Array[Shader] = WarmupScript.shaders()
	for each: Array in _looked_cards():
		var form: FormBase = each[0]
		check(warmed.has(form.look_shader), "%s's shader is warmed before the first room" % form.id)
	# A shot carrier's body was numbered then, with its mesh: asked again, it is one of those.
	var numbered: int = manager.batch_count()
	for each: Array in _looked_cards():
		var form: FormBase = each[0]
		if each[1] == Carrier.LOOK_SHOT or each[1] == Carrier.LOOK_STILL:
			var mesh: int = ProjectilesScript.MESH_HEAD if each[1] == Carrier.LOOK_SHOT else ProjectilesScript.MESH_QUAD
			check(manager.register_body(form.look_shader, mesh) > 0, "%s has a body" % form.id)
	check_equal(manager.batch_count(), numbered, "every shot carrier card's body was numbered when Spells started")


func test_a_look_shader_on_a_carrier_with_no_look_is_reported() -> void:
	var form := FormBase.new()
	form.id = &"test_form"
	form.carrier = &"dash"
	form.look_shader = preload("res://content/spells/carriers/pool/pool.gdshader")
	var found: String = " ".join(form.look_problems())
	check(found.contains("never drawn"), "a dash draws no look: %s" % found)


func test_every_card_shader_takes_every_uniform_its_area_sets() -> void:
	# A card that draws a look of its own (no longer its area's plain include: the beam, the swing,
	# the familiar; the owner, 2026-11-08) is still handed its area's uniforms (Feel's beams and
	# trails, Entities' orbs, the manager's batches), so it declares every one, or a setting falls
	# on nothing and the look draws stale.
	for each: Array in _looked_cards():
		var form: FormBase = each[0]
		if not PLAIN.has(each[1]):
			continue
		var plain: String = ShaderSource.of(load(PLAIN[each[1]]) as Shader)
		var code: String = ShaderSource.of(form.look_shader)
		for line: String in plain.split("\n"):
			if line.begins_with("uniform "):
				check(code.contains(line), "%s keeps its area's `%s`" % [form.id, line])


func test_every_still_cards_look_is_one_its_shader_and_clock_can_draw() -> void:
	# A still card's shape and clock reach its shader by its body (`set_body_shape`), and a body is
	# its shader: cards sharing one must share them, or one card's motes leave from the other's shape.
	# Its coming and going fit what the still clock tells (`STILL_START`, `STILL_END`).
	var by_shader: Dictionary = {}
	for each: Array in _looked_cards():
		var form: FormBase = each[0]
		if each[1] != Carrier.LOOK_STILL:
			continue
		check(form.look_open <= ProjectilesScript.STILL_START and form.look_fade <= ProjectilesScript.STILL_END, "%s comes and goes within what its still clock tells" % form.id)
		var numbers: Array = [form.look_shape, form.look_open, form.look_fade]
		if by_shader.has(form.look_shader):
			var first: Array = by_shader[form.look_shader]
			check(first[1] == numbers, "%s shares %s's shader, so its look shape and clock too" % [form.id, first[0]])
		else:
			by_shader[form.look_shader] = [form.id, numbers]
