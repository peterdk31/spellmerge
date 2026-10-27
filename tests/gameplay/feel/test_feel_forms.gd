extends "res://tests/support/suite.gd"
## Beams and nova rings in gameplay/feel: `form_shown` shows a beam along the aim or a ring
## at the caster, in the owner's tint with the element's colour in the core. They fade out,
## stay inside the pool with four players, and ignore what is not a beam or a nova.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

const FROST := Color(0.5, 0.75, 0.94)

var bus: EventsScript
var feel: FeelScript
var preset: FeelPresetScript
var projectiles: ProjectilesScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	projectiles = own(ProjectilesScript.new()) as ProjectilesScript
	preset = FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.projectiles = projectiles
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)


func _shown() -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	for sprite in feel._forms:
		if sprite.visible:
			found.append(sprite)
	return found


func _param(sprite: Sprite2D, name: StringName) -> Color:
	return (sprite.material as ShaderMaterial).get_shader_parameter(name) as Color


func test_a_beam_is_drawn_along_the_aim_as_long_as_it_got() -> void:
	bus.form_shown.emit(1, &"beam", Vector2(10, 20), Vector2.DOWN, 150.0, FROST, 0)
	var shown: Array[Sprite2D] = _shown()
	check_equal(shown.size(), 1, "one beam on screen")
	var beam: Sprite2D = shown[0]
	check_equal(beam.global_position, Vector2(10, 20), "from the staff")
	check(is_equal_approx(beam.rotation, PI / 2.0), "turned along the aim")
	check_equal(beam.region_rect.size.x, 150.0, "as long as it got")
	check(beam.texture == preset.beam_texture, "with the beam art")


func test_the_core_has_the_element_colour_and_the_body_the_owners() -> void:
	bus.form_shown.emit(2, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, FROST, 0)
	var beam: Sprite2D = _shown()[0]
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


func test_a_dash_leaves_its_trail_along_its_way() -> void:
	bus.form_shown.emit(2, &"dash", Vector2(10, 20), Vector2.DOWN, 80.0, FROST, 5)
	check_equal(feel.effects_of(FeelScript.KIND_DASH, 2), 1, "a dash effect for player 3")
	check_equal(feel.effect_dress(FeelScript.KIND_DASH), [FROST, 5], "with the dash's colours and cards")
	feel.step(0.01)
	var buffer: PackedFloat32Array = feel._effect_node.multimesh.buffer
	check(Vector2(buffer[0], buffer[4]).is_equal_approx(Vector2.DOWN * (80.0 + 2.0 * FeelScript.DASH_MARGIN)), "along its way, a margin past each end")
	check(is_equal_approx(buffer[3], 10.0) and is_equal_approx(buffer[7], 60.0), "centred half way along")
	check_equal(roundi(buffer[8] * 255.0) / 4, 20, "its length travels in the zoom's place (80 px is 20 steps of 4)")
	bus.form_shown.emit(2, &"dash", Vector2(10, 20), Vector2.DOWN, 0.0, FROST, 5)
	check_equal(feel.effects_of(FeelScript.KIND_DASH), 1, "a dash that went nowhere shows nothing")
	bus.form_shown.emit(-1, &"dash", Vector2(10, 20), Vector2.DOWN, 80.0, FROST, 5)
	check_equal(feel.effects_of(FeelScript.KIND_DASH), 2, "an enemy's dash shows like a wizard's (staffs F7)")
	check_equal(feel.effect_info(FeelScript.KIND_DASH)["player"], -1, "in the enemy ramp")


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
	check_equal(feel._forms[FeelScript.FORMS_PER_PLAYER].global_position, Vector2(10, 0), "player 1's beam is untouched")


func test_one_cast_with_many_rays_shows_every_ray() -> void:
	for ray in 24:
		bus.form_shown.emit(1, &"beam", Vector2.ZERO, Vector2.RIGHT.rotated(ray * 0.1), 100.0, FROST, 0)
	check_equal(_shown().size(), 24, "a fan of 24 rays is drawn whole")


func test_an_enemys_beams_take_only_the_enemies_share() -> void:
	for i in FeelScript.FORMS_PER_PLAYER + 6:
		bus.form_shown.emit(-1, &"beam", Vector2(0.0, i), Vector2.RIGHT, 100.0, FROST, 0)
	check_equal(_shown().size(), FeelScript.FORMS_PER_PLAYER, "enemies' beams show, in their one share")
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, FROST, 0)
	check_equal(_shown().size(), FeelScript.FORMS_PER_PLAYER + 1, "and never take a player's slot")
	var enemy_sprite: Sprite2D = feel._forms[FeelScript.ENEMY_FORMS * FeelScript.FORMS_PER_PLAYER]
	check_equal((enemy_sprite.material as ShaderMaterial).get_shader_parameter(&"beam_player"), -1, "drawn in the enemy ramp")


func test_a_rain_shows_its_marker_until_it_falls() -> void:
	bus.form_shown.emit(1, &"rain", Vector2(40, 40), Vector2.RIGHT, 0.6, FROST, 3)
	bus.form_shown.emit(-1, &"rain", Vector2(80, 40), Vector2.RIGHT, 0.6, FROST, 3)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 2, "a ring closes on each rain's point, a wizard's and an enemy's")
	check(is_equal_approx(feel.effect_info(FeelScript.KIND_RING_IN)["seconds"], 0.6), "for as long as it takes to fall")
	feel.step(0.5)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 2, "still there just before")
	feel.step(0.2)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 0, "gone when it lands")


func test_the_shipped_preset_has_the_form_art() -> void:
	var shipped := load("res://gameplay/feel/presets/punchy.tres") as FeelPresetScript
	check(shipped.beam_texture != null and shipped.nova_texture != null, "beam and ring art")


## Stands in for core/spells' live beams: one beam of player 1 bending from (0, 0) to (100, 40),
## and with `on_again` bending on from there to (160, 0).
class FakeBeams:
	extends Node
	var on: bool = true
	var reach: float = 500.0
	var on_again: bool = false

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

	func beam_player(_at: int) -> int:
		return 1

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


func _live_lines() -> Array[Line2D]:
	var found: Array[Line2D] = []
	for line in feel._live_beams:
		if line.visible:
			found.append(line)
	return found


func test_a_live_beam_is_drawn_along_its_curve_every_frame() -> void:
	var beams := own(FakeBeams.new()) as FakeBeams
	feel.spells = beams
	feel.step(0.016)
	var lines: Array[Line2D] = _live_lines()
	check_equal(lines.size(), 1, "one live beam on screen")
	var line: Line2D = lines[0]
	check_equal(line.get_point_position(0), Vector2.ZERO, "from the staff")
	check(line.get_point_position(line.get_point_count() - 1).is_equal_approx(Vector2(100, 40)), "to its end, on the target")
	var middle: Vector2 = line.get_point_position(line.get_point_count() / 2)
	check(middle.y > 0.0 and middle.y < 20.0, "bent, not straight: %s" % middle)
	check((line.material as ShaderMaterial).get_shader_parameter(&"core_override").is_equal_approx(Color(FROST.r, FROST.g, FROST.b, 1.0)), "the core is the element's")
	var tint: Color = (line.material as ShaderMaterial).get_shader_parameter(&"body_tint")
	check(is_equal_approx(tint.a, feel.preset.beam_alpha) and tint.a < 1.0, "a little see-through, so crossing beams all show: %f" % tint.a)
	beams.reach = 50.0
	feel.step(0.016)
	var tip: Vector2 = line.get_point_position(line.get_point_count() - 1)
	check(absf(tip.length() - 50.0) < 3.0, "cut where it stopped: %s" % tip)
	beams.reach = 500.0
	beams.on_again = true
	feel.step(0.016)
	check(line.get_point_position(line.get_point_count() - 1).is_equal_approx(Vector2(160, 0)), "a beam bending on to a second target is drawn to it: %s" % line.get_point_position(line.get_point_count() - 1))
	beams.on = false
	feel.step(0.016)
	check(_live_lines().is_empty(), "gone when it ends")


func test_a_live_beam_is_drawn_by_the_beam_mode_as_long_as_it_got() -> void:
	var beams := own(FakeBeams.new()) as FakeBeams
	beams.reach = 50.0
	feel.spells = beams
	feel.step(0.016)
	var line: Line2D = _live_lines()[0]
	var material: ShaderMaterial = line.material as ShaderMaterial
	check_equal(material.get_shader_parameter(&"beam_mode"), 1, "a line beam")
	check(is_equal_approx(material.get_shader_parameter(&"beam_length") as float, 50.0), "as long as it got along its curve")
	check_equal(material.get_shader_parameter(&"beam_player"), 1, "of its player")
	check_equal(material.get_shader_parameter(&"beam_look"), 6, "with its cards")
	check_equal(line.width, FeelScript.BEAM_WIDTH, "a fixed width: the shader swells its rim, never its pixels")
	check_equal(line.texture_mode, Line2D.LINE_TEXTURE_STRETCH, "its UV runs once along it")
