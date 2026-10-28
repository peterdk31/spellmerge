extends "res://tests/support/suite.gd"
## The mark of a combo cast in gameplay/feel (#244, round 2): each combo class has a picture of
## its own, flat in one colour with no partial transparency, drawn on the caster for a short time,
## one mark per player, and none of it touches the particle limit.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ComboMarks := preload("res://gameplay/feel/combo_marks.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const FIRE: Color = Color("#e0592f")

var bus: EventsScript
var feel: FeelScript
var preset: FeelPresetScript
## Wizards seated 0-3 at the actor ids 0-3: a combo cast names its caster, the mark its seat.
var actors: ActorSeats.ActorsScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	preset = FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	feel.actors = actors
	feel.projectiles = own(ProjectilesScript.new()) as Node
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)


func _show(player: int, combo_class: StringName, tint: Color = FIRE) -> Sprite2D:
	bus.combo_cast.emit(player, combo_class, Vector2(40, 30), Vector2.DOWN, tint)
	return feel.combo_mark(player)


func _lit(image: Image) -> int:
	var count: int = 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func test_every_class_is_flat_and_has_a_shape_of_its_own() -> void:
	var images: Dictionary = {}
	for combo_class in ComboMarks.CLASSES:
		var image: Image = ComboMarks.make_image(combo_class)
		images[combo_class] = image
		var lit: int = _lit(image)
		check(lit >= 20 and lit <= ComboMarks.SIZE * ComboMarks.SIZE / 2, "%s: a mark of %d pixels, not empty and not a blob" % [combo_class, lit])
		var flat: bool = true
		for y in image.get_height():
			for x in image.get_width():
				var pixel: Color = image.get_pixel(x, y)
				if pixel.a > 0.0 and (pixel.a < 1.0 or pixel.r < 1.0 or pixel.g < 1.0 or pixel.b < 1.0):
					flat = false
		check(flat, "%s: opaque white pixels or empty ones only" % combo_class)
	for a in ComboMarks.CLASSES.size():
		for b in range(a + 1, ComboMarks.CLASSES.size()):
			var one: Image = images[ComboMarks.CLASSES[a]] as Image
			var other: Image = images[ComboMarks.CLASSES[b]] as Image
			var apart: int = 0
			for y in ComboMarks.SIZE:
				for x in ComboMarks.SIZE:
					if (one.get_pixel(x, y).a > 0.0) != (other.get_pixel(x, y).a > 0.0):
						apart += 1
			check(apart >= 80, "%s and %s differ in %d pixels" % [ComboMarks.CLASSES[a], ComboMarks.CLASSES[b], apart])


func test_a_combo_cast_marks_the_caster_in_the_element_colour() -> void:
	var mark: Sprite2D = _show(2, ComboMarks.ON_HIT)
	check(mark.visible, "the mark shows")
	check_equal(mark.global_position, Vector2(40, 30), "at the staff")
	check_equal(mark.modulate, FIRE, "in the element's colour, opaque")
	check(is_equal_approx(mark.rotation, PI / 2.0), "chevrons turned to the aim")
	bus.combo_cast.emit(2, ComboMarks.ON_HIT, Vector2.ZERO, Vector2.from_angle(0.6), FIRE)
	check(is_equal_approx(mark.rotation, PI / 2.0 * roundf(0.6 / (PI / 2.0))), "turned in quarter turns only, so the pixels stay square")
	check(not feel.combo_mark(0).visible and not feel.combo_mark(1).visible, "nobody else's mark shows")
	check_equal(_show(0, ComboMarks.BOOSTED, Color.WHITE).modulate, Color("#f4f1ea"), "plain arcane takes Bone, not white")


func test_each_class_shows_a_different_picture() -> void:
	var seen: Array = []
	for combo_class in ComboMarks.CLASSES:
		var mark: Sprite2D = _show(0, combo_class)
		check(mark.visible, "%s shows" % combo_class)
		check(not seen.has(mark.texture), "%s: its own picture" % combo_class)
		seen.append(mark.texture)


func test_a_mark_swells_in_whole_steps_and_ends_without_fading() -> void:
	var mark: Sprite2D = _show(0, ComboMarks.TIMER)
	check_equal(mark.scale, Vector2.ONE, "it starts at its own size")
	feel.step(preset.combo_mark_seconds * 0.6)
	check_equal(mark.scale, Vector2(2, 2), "then doubles, a whole multiple")
	check_equal(mark.modulate.a, 1.0, "never partly transparent")
	feel.step(preset.combo_mark_seconds)
	check(not mark.visible, "gone after its time")


func test_a_new_cast_replaces_the_players_mark_and_players_do_not_share() -> void:
	var first: Texture2D = _show(1, ComboMarks.BOOSTED).texture
	_show(3, ComboMarks.STACKED)
	check(feel.combo_mark(1).visible and feel.combo_mark(3).visible, "two players, two marks")
	var second: Texture2D = _show(1, ComboMarks.TIMER).texture
	check(first != second, "the player's mark changed")
	check(feel.combo_mark(3).texture != second, "the other player's did not")


func test_a_bad_cast_shows_nothing_and_a_plain_one_stays_silent() -> void:
	bus.combo_cast.emit(-1, ComboMarks.BOOSTED, Vector2.ZERO, Vector2.RIGHT, FIRE)
	bus.combo_cast.emit(4, ComboMarks.BOOSTED, Vector2.ZERO, Vector2.RIGHT, FIRE)
	bus.combo_cast.emit(0, &"unknown", Vector2.ZERO, Vector2.RIGHT, FIRE)
	bus.combo_cast.emit(0, ComboMarks.BOOSTED, Vector2(INF, 0), Vector2.RIGHT, FIRE)
	# An actor no seat drives (an enemy) has no mark of its own.
	bus.combo_cast.emit(ActorSeats.enemy(actors), ComboMarks.BOOSTED, Vector2.ZERO, Vector2.RIGHT, FIRE)
	for player in 4:
		check(not feel.combo_mark(player).visible, "player %d: nothing shown" % player)


func test_marks_use_no_particles() -> void:
	for player in 4:
		_show(player, ComboMarks.STACKED)
	check_equal(feel.live_effects(), 0, "the marks are sprites, outside the effect slots")


func test_a_preset_can_turn_the_marks_off() -> void:
	preset.combo_mark_seconds = 0.0
	check(not _show(0, ComboMarks.STACKED).visible, "off")


func test_a_mark_glows_and_has_room_for_it() -> void:
	bus.combo_cast.emit(0, &"boosted", Vector2(20.0, 20.0), Vector2.RIGHT, Color.WHITE)
	var mark: Sprite2D = feel.combo_mark(0)
	var material := mark.material as ShaderMaterial
	check(material != null and material.shader == FeelScript.CORE_SHADER, "drawn by the shot shader")
	check((material.get_shader_parameter(&"sprite_glow") as float) > 0.0, "with a glow round it")
	check_equal(mark.texture.get_width(), ComboMarks.SIZE + 2 * ComboMarks.PAD, "its picture has empty pixels round it for the glow")
