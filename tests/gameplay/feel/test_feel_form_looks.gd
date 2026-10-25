extends "res://tests/support/suite.gd"
## The look of each form in gameplay/feel (#244, part 2): its own cast flash on the wizard
## (a bolt streaks along the aim, a beam is a long thin flare, a nova a wide burst, a rune and an
## orbit gather in), its own flare where it ends or hits, a beam that opens wide and thins,
## and an enemy's shot that always shows the same ember mark no player's flare resembles.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")

const FORMS: Array[StringName] = [&"bolt", &"beam", &"nova", &"rune", &"orbit"]

var bus: EventsScript
var feel: FeelScript
var preset: FeelPresetScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	preset = FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)


func _cast(player: int, form: StringName) -> Sprite2D:
	bus.spell_cast.emit(player, form, Vector2(10, 10), Vector2.DOWN)
	return feel.muzzle_flash(player)


func _wall_flare(player: int) -> Sprite2D:
	var before: int = feel.live_flashes()
	bus.projectile_impact.emit(player, null, Vector2(50, 50), Vector2.RIGHT)
	check_equal(feel.live_flashes(), before + 1, "an impact shows one flare")
	for slot in FeelScript.SPARK_SLOTS:
		var spark: Sprite2D = feel.wall_spark(slot)
		if spark.visible and spark.global_position == Vector2(50, 50):
			return spark
	return null


func test_every_form_has_a_cast_look_and_an_impact_look() -> void:
	for form in FORMS:
		check(preset.cast_looks.has(form), "%s has a cast flash" % form)
		check(preset.impact_looks.has(form), "%s has an impact flare" % form)


func test_each_form_flashes_differently_on_the_wizard() -> void:
	var seen: Dictionary = {}
	for form in FORMS:
		var flash: Sprite2D = _cast(0, form)
		check(flash.visible, "%s flashes" % form)
		seen[[snappedf(flash.scale.x, 0.01), snappedf(flash.scale.y, 0.01), snappedf(flash.rotation, 0.01)]] = true
	check_equal(seen.size(), FORMS.size(), "no two forms flash the same")


func test_a_beam_flash_is_long_and_thin_along_the_aim() -> void:
	var flash: Sprite2D = _cast(0, &"beam")
	check(flash.scale.x > 3.0 * flash.scale.y, "long and thin")
	check(is_equal_approx(flash.rotation, PI / 2.0), "along the aim")


func test_a_nova_flash_is_upright_wide_and_round() -> void:
	var flash: Sprite2D = _cast(0, &"nova")
	check_equal(flash.rotation, 0.0, "not turned")
	check(is_equal_approx(flash.scale.x, flash.scale.y), "round")
	check(flash.scale.x > _cast(1, &"bolt").scale.y, "bigger than a bolt's flash")


func test_a_rune_and_an_orbit_gather_in_while_a_bolt_bursts_out() -> void:
	var sizes: Dictionary = {}
	for form in [&"bolt", &"rune", &"orbit"]:
		var flash: Sprite2D = _cast(0, form)
		var start: float = flash.scale.x
		feel.step(preset.muzzle_flash_seconds * 0.5)
		sizes[form] = flash.scale.x - start
	check(sizes[&"bolt"] > 0.0, "a bolt's flash grows")
	check(sizes[&"rune"] < 0.0, "a rune's flash gathers")
	check(sizes[&"orbit"] < 0.0, "an orbit's flash gathers")


func test_rings_use_the_ring_art_and_the_others_the_spark() -> void:
	for form in FORMS:
		var flash: Sprite2D = _cast(0, form)
		var ring: bool = form == &"nova" or form == &"rune" or form == &"orbit"
		check_equal(flash.texture == preset.nova_texture, ring, "%s: ring art only for the ring forms" % form)
		check(ring or flash.texture == preset.spark_texture, "%s: the spark" % form)


func test_an_unknown_form_gets_the_plain_muzzle_flash() -> void:
	var plain: Vector2 = _cast(0, &"bolt").scale
	check_equal(_cast(1, &"fire_bolt").scale, plain, "the same as a bolt's")


func test_a_flash_gone_is_hidden_after_its_seconds() -> void:
	var flash: Sprite2D = _cast(0, &"rune")
	feel.step(preset.cast_looks[&"rune"]["seconds"] + 0.01)
	check(not flash.visible, "gone")


func test_each_form_ends_with_its_own_flare() -> void:
	var seen: Dictionary = {}
	for form in FORMS:
		_cast(0, form)
		var flare: Sprite2D = _wall_flare(0)
		check(flare != null, "%s flare shown at the spot" % form)
		if flare != null:
			seen[[snappedf(flare.scale.x, 0.01), snappedf(flare.scale.y, 0.01)]] = true
		feel.step(1.0)
	check_equal(seen.size(), FORMS.size(), "no two forms end the same")


func test_a_beam_end_is_stretched_along_the_beam() -> void:
	_cast(0, &"beam")
	var flare: Sprite2D = _wall_flare(0)
	check(flare.scale.x > flare.scale.y, "longer than it is tall")
	check_equal(flare.rotation, 0.0, "along a beam flying right")


func test_a_hit_on_a_character_shows_the_flare_too() -> void:
	_cast(2, &"rune")
	var enemy: Node2D = own(Node2D.new()) as Node2D
	root.add_child(enemy)
	bus.projectile_impact.emit(2, enemy, Vector2(7, 7), Vector2.LEFT)
	var shown: bool = false
	for slot in FeelScript.SPARK_SLOTS:
		var spark: Sprite2D = feel.wall_spark(slot)
		shown = shown or (spark.visible and spark.global_position == Vector2(7, 7))
	check(shown, "a flare at the hit")


func test_an_enemy_shot_always_ends_in_the_same_ember_mark() -> void:
	var marks: Dictionary = {}
	for form in FORMS:
		_cast(0, form)
		bus.projectile_impact.emit(-1, null, Vector2(50, 50), Vector2.RIGHT)
		var flare: Sprite2D = null
		for slot in FeelScript.SPARK_SLOTS:
			var spark: Sprite2D = feel.wall_spark(slot)
			if spark.visible and spark.global_position == Vector2(50, 50) and spark.modulate.is_equal_approx(preset.enemy_hit_color):
				flare = spark
		check(flare != null, "%s: an enemy's shot is ember" % form)
		if flare != null:
			marks[[flare.scale, flare.rotation]] = true
		feel.step(1.0)
	check_equal(marks.size(), 1, "the same mark whatever any player cast")


func test_an_enemy_mark_is_turned_on_its_corner_and_a_player_flare_is_not() -> void:
	bus.projectile_impact.emit(-1, null, Vector2(50, 50), Vector2.RIGHT)
	check(is_equal_approx(feel.wall_spark(0).rotation, PI / 4.0), "on its corner")
	for form in FORMS:
		_cast(0, form)
		bus.projectile_impact.emit(0, null, Vector2(50, 50), Vector2.UP)
	for slot in FeelScript.SPARK_SLOTS:
		var spark: Sprite2D = feel.wall_spark(slot)
		check_equal(is_equal_approx(spark.rotation, PI / 4.0), spark.modulate.is_equal_approx(preset.enemy_hit_color), "only ember marks sit on a corner")


func test_four_players_casting_and_hitting_stay_in_the_pools() -> void:
	var children: int = feel.get_child_count()
	for round in 6:
		for player in 4:
			_cast(player, FORMS[(player + round) % FORMS.size()])
			bus.projectile_impact.emit(player, null, Vector2(player * 10, 0), Vector2.RIGHT)
			bus.projectile_impact.emit(-1, null, Vector2(player * 10, 5), Vector2.LEFT)
	check(feel.live_flashes() <= FeelScript.ALL_FLASH_SLOTS, "inside the flash slots")
	check_equal(feel.get_child_count(), children, "no new nodes were needed")


func test_a_beam_opens_wide_then_thins() -> void:
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, Color.RED)
	var beam: Sprite2D = null
	for sprite in feel._forms:
		if sprite.visible:
			beam = sprite
	var first: float = beam.scale.y
	check(first > 1.5, "wider than the art at first")
	feel.step(preset.beam_seconds * 0.5)
	check(beam.scale.y < first, "thinner after")
	check(beam.scale.y < 1.0, "thinner than the art at last")


func test_a_flare_of_zero_leaves_the_beam_as_before() -> void:
	preset.beam_flare = 0.0
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, Color.RED)
	for sprite in feel._forms:
		if sprite.visible:
			check_equal(sprite.scale.y, 1.0, "the full art width at the start")
