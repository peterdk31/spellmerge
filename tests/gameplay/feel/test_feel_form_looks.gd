extends "res://tests/support/suite.gd"
## The look of each form in gameplay/feel (#244, part 2; the glow look, 2026-10-27): a cast
## flash at the staff and, for a ring carrier, a ring (a nova's flashes out, a rune's and an
## orbit's gather in), an effect where its shot lands in the shot's own colours and cards (a
## rune goes off in a burst of its own), a beam that opens wide and thins, and an enemy's shot
## that always shows the same ember mark no player's flare resembles.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")


## A registry that knows one more carrier card, made in the test.
class CardsRegistry:
	extends RegistryScript
	var extra: Resource = null

	func get_resource(folder: StringName, id: StringName) -> Resource:
		if extra != null and folder == &"spells" and id == extra.get("id"):
			return extra
		return super(folder, id)


const FORMS: Array[StringName] = [&"bolt", &"beam", &"nova", &"rune", &"orbit"]

var bus: EventsScript
var feel: FeelScript
var preset: FeelPresetScript
var projectiles: Node
var registry: CardsRegistry


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	projectiles = own(ProjectilesScript.new()) as Node
	preset = FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.projectiles = projectiles
	feel.drive_engine = false
	registry = own(CardsRegistry.new()) as CardsRegistry
	registry.scan()
	feel.registry = registry
	feel.preset = preset
	root.add_child(feel)


## The look the carrier card `form` brings (`FormBase.cast_look` or `impact_look`).
func _card_look(form: StringName, cast: bool) -> Dictionary:
	var card: FormBase = registry.get_resource(&"spells", form) as FormBase
	return card.cast_look if cast else card.impact_look


func _cast(player: int, form: StringName) -> void:
	bus.spell_cast.emit(player, form, Vector2(10, 10), Vector2.DOWN)


## A shot of `form` ends on a wall at (50, 50) (the manager names the form, the core colour and
## the look while it sends the impact, as it does for a real shot; the form last cast has no say).
func _impact(player: int, form: StringName = &"", core: Color = Color.WHITE, look: int = 0, target: Node = null) -> void:
	projectiles.impact_form = form
	projectiles.impact_core = core
	projectiles.impact_look = look
	bus.projectile_impact.emit(player, target, Vector2(50, 50), Vector2.RIGHT)
	projectiles.impact_form = &""
	projectiles.impact_core = Color.WHITE
	projectiles.impact_look = 0


## Live effects of each kind, as [cast, burst, ring out, ring in, rune burst].
func _kinds() -> Array[int]:
	return [feel.effects_of(FeelScript.KIND_CAST), feel.effects_of(FeelScript.KIND_BURST), feel.effects_of(FeelScript.KIND_RING_OUT),
			feel.effects_of(FeelScript.KIND_RING_IN), feel.effects_of(FeelScript.KIND_RUNE_BURST)] as Array[int]


func test_the_looks_are_data_on_the_cards_not_in_the_preset() -> void:
	check(not ("cast_looks" in preset) and not ("impact_looks" in preset), "the preset has no per-form looks")
	for form in FORMS:
		check(registry.get_resource(&"spells", form) is FormBase, "%s is a carrier card" % form)
		check(not _card_look(form, false).is_empty(), "%s has an impact flare" % form)
	check(not _card_look(&"nova", true).is_empty(), "a nova has a cast flash of its own")
	check(_card_look(&"bolt", true).is_empty(), "a bolt takes the plain cast flash")


func test_a_cast_flashes_at_the_staff_in_its_players_colours() -> void:
	for player in 4:
		_cast(player, &"bolt")
		check_equal(feel.effects_of(FeelScript.KIND_CAST, player), 1, "player %d's cast flash" % (player + 1))
	check_equal(feel.effect_dress(FeelScript.KIND_CAST), [Color.WHITE, 0], "white: the shader draws it in the player's ramp")


func test_the_ring_carriers_add_a_ring_to_their_cast() -> void:
	var want: Dictionary = {
		&"bolt": [1, 0, 0, 0, 0], &"beam": [1, 0, 0, 0, 0], &"nova": [1, 0, 1, 0, 0],
		&"rune": [1, 0, 0, 1, 0], &"orbit": [1, 0, 0, 1, 0],
	}
	for form: StringName in want:
		_cast(0, form)
		check_equal(_kinds(), want[form] as Array[int], "%s: a nova flashes a ring out, a rune and an orbit gather one in" % form)
		feel.step(1.0)


func test_a_new_carrier_card_brings_its_own_look() -> void:
	var card := FormBase.new()
	card.id = &"test_wave"
	card.cast_look = {"seconds": 0.5, "size": 2.0, "grow": -1.0, "ring": true}
	card.impact_look = {"seconds": 0.3, "size": 1.5, "ring": true}
	registry.extra = card
	_cast(0, &"test_wave")
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 1, "its cast gathers a ring in, as the card says")
	_impact(0, &"test_wave")
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 1, "it lands in a burst")
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT), 1, "and a ring, as the card says")


func test_a_look_missed_for_want_of_a_registry_is_not_kept() -> void:
	feel.registry = null
	_cast(0, &"nova")
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT), 0, "no registry: the plain cast flash")
	check(feel._form_look(&"", false).is_empty(), "no form id, no look")
	feel.registry = registry
	_cast(0, &"nova")
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT), 1, "once the registry is there the nova has its ring")
	check(not feel._form_look(&"nova", false).is_empty(), "and its flare")


func test_each_form_ends_its_own_way() -> void:
	var want: Dictionary = {
		&"bolt": [0, 1, 0, 0, 0], &"beam": [0, 1, 0, 0, 0], &"nova": [0, 1, 1, 0, 0],
		&"rune": [0, 0, 0, 0, 1], &"orbit": [0, 1, 0, 0, 0], &"": [0, 1, 0, 0, 0],
	}
	for form: StringName in want:
		_impact(0, form)
		check_equal(_kinds(), want[form] as Array[int], "%s: a burst, a nova's with a ring, a rune goes off" % form)
		feel.step(1.0)


func test_the_flare_takes_the_shots_colours_and_cards() -> void:
	var frost := Color("4fd6dc")
	var look: int = ProjectilesScript.pack_look(PackedInt32Array([ProjectilesScript.LOOK_FLECKS, ProjectilesScript.LOOK_GLINTS]))
	_impact(1, &"bolt", frost, look)
	check_equal(feel.effect_dress(FeelScript.KIND_BURST), [frost, look], "the frost bolt's colour and both its looks")
	_impact(2, &"rune", Color.WHITE, 0)
	check_equal(feel.effect_dress(FeelScript.KIND_RUNE_BURST), [Color.WHITE, 0], "a plain rune: white, its player's ramp")
	check_equal(feel.effects_of(FeelScript.KIND_RUNE_BURST, 2), 1, "of its player")


func test_the_flare_follows_the_shot_not_the_last_cast() -> void:
	# A rune is cast, then a bolt: a rune that goes off after the bolt was cast still goes off.
	_cast(0, &"rune")
	_cast(0, &"bolt")
	_impact(0, &"rune")
	check_equal(feel.effects_of(FeelScript.KIND_RUNE_BURST), 1, "the rune goes off")
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 0, "not as a bolt")


func test_an_effect_ends_after_its_seconds() -> void:
	_impact(0, &"bolt")
	_cast(0, &"bolt")
	feel.step(FeelScript.CAST_SECONDS + 0.01)
	check_equal(feel.effects_of(FeelScript.KIND_CAST), 0, "the cast flash is gone")
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 1, "the burst lasts longer")
	feel.step(FeelScript.CHIPS_SECONDS)
	check_equal(feel.live_effects(), 0, "and then it is gone too, and the wall's chips")
	check_equal(feel._effect_node.multimesh.visible_instance_count, 0, "nothing is drawn")


func test_the_batch_draws_the_live_effects() -> void:
	_impact(0, &"bolt")
	_impact(1, &"nova")
	feel.step(0.01)
	var multimesh: MultiMesh = feel._effect_node.multimesh
	check_equal(multimesh.visible_instance_count, 5, "a burst, and a burst and a ring, and the wall's chips for each")
	var buffer: PackedFloat32Array = multimesh.buffer
	# The first drawn is the oldest: the first wall's chips, then its burst.
	check_equal(floori((1.0 - buffer[15]) * 16.0 + 0.5), FeelScript.KIND_CHIPS, "chips first")
	buffer = buffer.slice(FeelScript.EFFECT_STRIDE)
	var coded: float = (1.0 - buffer[15]) * 16.0
	check_equal(floori(coded + 0.5), FeelScript.KIND_BURST, "the kind travels as the shader reads it")
	check(coded - FeelScript.KIND_BURST > FeelScript.EFFECT_FROM and coded - FeelScript.KIND_BURST < 0.5, "with its age beside it")
	check(is_equal_approx(buffer[3], 50.0) and is_equal_approx(buffer[7], 50.0), "where it landed")
	check(is_equal_approx(buffer[0], FeelScript.EFFECT_GRID), "a quad of the shader's grid")


func test_a_cast_by_an_enemy_or_a_bad_index_changes_nothing() -> void:
	for bad in [-1, 4, 99]:
		bus.spell_cast.emit(bad, &"beam", Vector2(10, 10), Vector2.DOWN)
	check_equal(feel.live_effects(), 0, "no effect for a bad index")


func test_a_hit_on_a_character_shows_the_flare_too() -> void:
	var enemy: Node2D = own(Node2D.new()) as Node2D
	root.add_child(enemy)
	_impact(2, &"rune", Color.WHITE, 0, enemy)
	check_equal(feel.effects_of(FeelScript.KIND_RUNE_BURST, 2), 1, "a flare at the hit")


func test_effects_past_the_slots_take_the_oldest() -> void:
	for i in feel.effect_slots + 20:
		_impact(i % 4, &"bolt")
	check_equal(feel.live_effects(), feel.effect_slots, "every slot busy, no more")


func test_an_enemy_shot_lands_like_a_spell_in_the_enemy_ramp() -> void:
	# Staffs F7: no ember burst of its own any more; NO_PLAYER is the enemy ramp.
	for form in FORMS:
		_cast(0, form)
		bus.projectile_impact.emit(-1, null, Vector2(50, 50), Vector2.RIGHT)
		var shown: Dictionary = feel.effect_info(FeelScript.KIND_BURST)
		check(not shown.is_empty() and shown["player"] == -1 and shown["core"] == Color.WHITE, "%s: an enemy's plain shot lands in a burst in the enemy ramp" % form)
		check(shown["core"] != preset.enemy_hit_color, "%s: not in ember" % form)
		feel.step(1.0)





func test_four_players_casting_and_hitting_stay_in_the_pools() -> void:
	var children: int = feel.get_child_count()
	for round in 6:
		for player in 4:
			_cast(player, FORMS[(player + round) % FORMS.size()])
			bus.projectile_impact.emit(player, null, Vector2(player * 10, 0), Vector2.RIGHT)
			bus.projectile_impact.emit(-1, null, Vector2(player * 10, 5), Vector2.LEFT)
	check(feel.live_effects() <= feel.effect_slots, "inside the effect slots")
	check_equal(feel.get_child_count(), children, "no new nodes were needed")


func _the_shown_beam() -> Sprite2D:
	var beam: Sprite2D = null
	for sprite in feel._forms:
		if sprite.visible:
			beam = sprite
	return beam


func _swell() -> float:
	return (_the_shown_beam().material as ShaderMaterial).get_shader_parameter(&"beam_swell") as float


func test_a_beam_opens_wide_then_thins() -> void:
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, Color.RED, 0)
	var first: float = _swell()
	check(first > 1.5, "its rim and glow swell at first")
	feel.step(preset.beam_seconds * 0.5)
	check(_swell() < first, "thinner after")
	check(_swell() < 1.0, "thinner than at rest at last")
	check(_the_shown_beam().scale == Vector2.ONE, "its pixels are never stretched")


func test_a_beam_flickers_by_the_preset_depth_on_every_other_step() -> void:
	preset.beam_flare = 0.0
	preset.beam_flicker_rate = 10.0
	preset.beam_flicker_depth = 0.1
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, Color.RED, 0)
	check_equal(_swell(), 1.0, "step 0 is full width")
	feel.step(0.11)
	var t: float = (preset.beam_seconds - 0.11) / preset.beam_seconds
	check(is_equal_approx(_swell(), t * 0.9), "step 1 is 10% thinner")
	feel.step(0.11)
	t = (preset.beam_seconds - 0.22) / preset.beam_seconds
	check(is_equal_approx(_swell(), t), "step 2 is back to full")


func test_a_beam_with_no_flicker_depth_is_steady() -> void:
	preset.beam_flare = 0.0
	preset.beam_flicker_depth = 0.0
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, Color.RED, 0)
	feel.step(0.07)
	var t: float = (preset.beam_seconds - 0.07) / preset.beam_seconds
	check(is_equal_approx(_swell(), t), "only the fade thins it")
	var fade: float = (_the_shown_beam().material as ShaderMaterial).get_shader_parameter(&"beam_fade") as float
	check(is_equal_approx(fade, t), "and dissolves it by as much")


func test_a_beam_is_drawn_by_the_beam_mode_with_its_cards() -> void:
	bus.form_shown.emit(3, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, Color.RED, 9)
	var material: ShaderMaterial = _the_shown_beam().material as ShaderMaterial
	check_equal(material.get_shader_parameter(&"beam_mode"), 2, "a sprite beam")
	check_equal(material.get_shader_parameter(&"beam_length"), 100.0, "as long as it got")
	check_equal(material.get_shader_parameter(&"beam_player"), 3, "of its player")
	check_equal(material.get_shader_parameter(&"beam_look"), 9, "with the cast's cards")
	check(is_equal_approx(material.get_shader_parameter(&"beam_glow") as float, preset.beam_alpha), "glowing as the preset says")


func test_a_flare_of_zero_leaves_the_beam_as_before() -> void:
	preset.beam_flare = 0.0
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, Color.RED, 0)
	check_equal(_swell(), 1.0, "at rest at the start")


func test_the_effect_slots_setting_sizes_the_batch() -> void:
	check_equal(feel.effect_slots, EffectSlots.DEFAULT, "the default at the start")
	_impact(0, &"bolt")
	bus.effect_slots_changed.emit(128)
	check_equal(feel.effect_slots, 128, "the setting takes")
	check_equal(feel._effect_node.multimesh.instance_count, 128, "the batch has that room")
	check_equal(feel.live_effects(), 0, "the effects showing end")
	for i in 200:
		_impact(i % 4, &"bolt")
	check_equal(feel.live_effects(), 128, "no more than the setting")
	feel.step(0.01)
	check_equal(feel._effect_node.multimesh.visible_instance_count, 128, "and all of them drawn")
	check_equal(feel.set_effect_slots(5000), EffectSlots.MAX, "a number past the top is the top")
	check_equal(feel.set_effect_slots(1), EffectSlots.MIN, "below the bottom, the bottom")
	check_equal(feel.set_effect_slots(300), 320, "between steps, the nearest step")
