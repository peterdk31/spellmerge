extends "res://tests/support/suite.gd"
## The look of each form in gameplay/feel (#244, part 2; the glow look, 2026-10-27): a cast
## flash at the staff and, for a ring carrier, a ring (a dash's flashes out, a rune's gathers
## in), a flash where its shot lands in the shot's own colours and cards (a
## rune goes off in a burst of its own), a beam that opens wide and thins, and an enemy's shot
## that always shows the same ember mark no player's flare resembles. The cast and the impact are
## the cues the carrier card names (`FormBase.cast_cue`, `impact_cue`; S6 2).

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")


## A registry that knows one more carrier card, made in the test.
class CardsRegistry:
	extends RegistryScript
	var extra: Resource = null

	func get_resource(folder: StringName, id: StringName) -> Resource:
		if extra != null and folder == &"spells" and id == extra.get("id"):
			return extra
		return super(folder, id)


const FORMS: Array[StringName] = [&"bolt", &"beam", &"dash", &"rune"]
## The beam card's own look (`FormBase.look_shader`; docs/milestones/card-looks.md, phase 2).
const BEAM_CARD_SHADER: Shader = preload("res://content/spells/carriers/beam/beam.gdshader")

var bus: EventsScript
var feel: FeelScript
var preset: FeelPresetScript
var projectiles: Node
var registry: CardsRegistry
## Wizards seated 0-3 at the actor ids 0-3: a shot of caster 0-3 lands in hat ramp 0-3.
var actors: ActorSeats.ActorsScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	projectiles = own(ProjectilesScript.new()) as Node
	actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	projectiles.set("actors", actors)
	feel.actors = actors
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


## The cue the carrier card `form` names for its cast or its impact (`FormBase.cast_cue`,
## `impact_cue`).
func _card_cue(form: StringName, cast: bool) -> CueBase:
	var card: FormBase = registry.get_resource(&"spells", form) as FormBase
	return feel.cue_of(card.cast_cue if cast else card.impact_cue)


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


## Live flashes of each kind, as [cast, burst, ring out, ring in, rune burst].
func _kinds() -> Array[int]:
	return [feel.flashes_of(&"cast"), feel.flashes_of(&"burst"), feel.flashes_of(&"ring_out"),
			feel.flashes_of(&"ring_in"), feel.flashes_of(&"rune_burst")] as Array[int]


func test_the_looks_are_cues_the_cards_name_not_in_the_preset() -> void:
	check(not ("cast_looks" in preset) and not ("impact_looks" in preset), "the preset has no per-form looks")
	check(not ("wall_spark_size" in preset) and not ("cast_kick_pixels" in preset), "nor a flare's size or a cast's kick")
	for form in FORMS:
		check(registry.get_resource(&"spells", form) is FormBase, "%s is a carrier card" % form)
		check(_card_cue(form, true) != null, "%s has a cast cue" % form)
		check(_card_cue(form, false) != null, "%s has an impact cue" % form)
	check_equal(_card_cue(&"dash", true).id, &"cast_ring", "a dash has a cast flash of its own")
	var flashes: int = 0
	for part: Dictionary in _card_cue(&"bolt", true).parts:
		if StringName(part.get("part", "flash")) == &"flash":
			flashes += 1
	check_equal(flashes, 1, "a bolt's is the plain spark, with no ring (its sparks are motes, S6 item 3)")
	check_equal(FormBase.new().cast_cue, &"cast", "a card naming none casts `cast`")
	check_equal(FormBase.new().impact_cue, &"impact", "and lands in `impact`")


func test_a_cast_flashes_at_the_staff_in_its_players_colours() -> void:
	for player in 4:
		_cast(player, &"bolt")
		check_equal(feel.flashes_of(&"cast", player), 1, "player %d's cast flash" % (player + 1))
	check_equal(feel.flash_dress(&"cast"), [Color.WHITE, 0], "white: the shader draws it in the player's ramp")


func test_the_ring_carriers_add_a_ring_to_their_cast() -> void:
	var want: Dictionary = {
		&"bolt": [1, 0, 0, 0, 0], &"beam": [1, 0, 0, 0, 0], &"dash": [1, 0, 1, 0, 0],
		&"rune": [1, 0, 0, 1, 0],
	}
	for form: StringName in want:
		_cast(0, form)
		check_equal(_kinds(), want[form] as Array[int], "%s: a dash flashes a ring out, a rune gathers one in" % form)
		feel.step(1.0)


func test_a_new_carrier_card_brings_its_own_look() -> void:
	var card := FormBase.new()
	card.id = &"test_wave"
	card.cast_cue = &"cast_gather"
	card.impact_cue = &"impact_ring"
	registry.extra = card
	_cast(0, &"test_wave")
	check_equal(feel.flashes_of(&"ring_in"), 1, "its cast gathers a ring in, as the card says")
	_impact(0, &"test_wave")
	check_equal(feel.flashes_of(&"burst"), 1, "it lands in a burst")
	check_equal(feel.flashes_of(&"ring_out"), 1, "and a ring, as the card says")


func test_a_carrier_whose_impact_cue_is_a_quake_cracks_the_floor_where_it_strikes() -> void:
	var card := FormBase.new()
	card.id = &"test_meteor"
	card.radius = 12.0
	card.impact_cue = &"quake"
	registry.extra = card
	_impact(0, &"test_meteor")
	check_equal(feel.flashes_of(&"quake"), 1, "the floor cracks where it ends on a wall")
	check_equal(feel.flash_info(&"quake").get("zoom"), roundi(12.0 * 1.5 / feel.flash_kind(&"quake").step), "as big as its radius")
	check(is_equal_approx(feel.trauma(), feel.cue_of(&"quake").shake), "with the ground's shake")
	_impact(0, &"test_meteor", Color.WHITE, 0, own(Node2D.new()) as Node2D)
	check_equal(feel.flashes_of(&"quake"), 2, "and where it strikes a body: one rule for every impact")
	_impact(0, &"bolt")
	check_equal(feel.flashes_of(&"quake"), 2, "a carrier without it leaves no mark")


func test_a_cue_missed_for_want_of_a_registry_is_not_kept() -> void:
	feel.registry = null
	_cast(0, &"dash")
	check_equal(feel.flashes_of(&"ring_out"), 0, "no registry: no cue to play")
	check_equal(feel._form_cues_of(&"dash"), FeelScript.NO_FORM_CUES, "the defaults")
	check_equal(feel._form_cues_of(&""), FeelScript.NO_FORM_CUES, "no form id, the defaults")
	feel.registry = registry
	_cast(0, &"dash")
	check_equal(feel.flashes_of(&"ring_out"), 1, "once the registry is there the dash has its ring")
	check_equal(feel._form_cues_of(&"dash")[FeelScript.CUE_IMPACT], &"impact_ring", "and its flare")
	check_equal(feel._form_cues_of(&"fire_bolt"), FeelScript.NO_FORM_CUES, "an id that is no carrier card: the defaults")


func test_each_form_ends_its_own_way() -> void:
	var want: Dictionary = {
		&"bolt": [0, 1, 0, 0, 0], &"beam": [0, 1, 0, 0, 0], &"dash": [0, 1, 1, 0, 0],
		&"rune": [0, 0, 0, 0, 1], &"": [0, 1, 0, 0, 0],
	}
	for form: StringName in want:
		_impact(0, form)
		check_equal(_kinds(), want[form] as Array[int], "%s: a burst, a dash's with a ring, a rune goes off" % form)
		feel.step(1.0)


func test_the_flare_takes_the_shots_colours_and_cards() -> void:
	var frost := Color("4fd6dc")
	var look: int = ProjectilesScript.pack_look(PackedInt32Array([ProjectilesScript.LOOK_FLECKS, ProjectilesScript.LOOK_GLINTS]))
	_impact(1, &"bolt", frost, look)
	check_equal(feel.flash_dress(&"burst"), [frost, look], "the frost bolt's colour and both its looks")
	_impact(2, &"rune", Color.WHITE, 0)
	check_equal(feel.flash_dress(&"rune_burst"), [Color.WHITE, 0], "a plain rune: white, its player's ramp")
	check_equal(feel.flashes_of(&"rune_burst", 2), 1, "of its player")


func test_the_flare_follows_the_shot_not_the_last_cast() -> void:
	# A rune is cast, then a bolt: a rune that goes off after the bolt was cast still goes off.
	_cast(0, &"rune")
	_cast(0, &"bolt")
	_impact(0, &"rune")
	check_equal(feel.flashes_of(&"rune_burst"), 1, "the rune goes off")
	check_equal(feel.flashes_of(&"burst"), 0, "not as a bolt")


func test_a_flash_ends_after_its_seconds() -> void:
	_impact(0, &"bolt")
	_cast(0, &"bolt")
	feel.step(feel.flash_kind(&"cast").seconds + 0.01)
	check_equal(feel.flashes_of(&"cast"), 0, "the cast flash is gone")
	check_equal(feel.flashes_of(&"burst"), 1, "the burst lasts longer")
	feel.step(feel.flash_kind(&"burst").seconds)
	check_equal(feel.live_flashes(), 0, "and then it is gone too")
	check_equal(feel._flash_node.multimesh.visible_instance_count, 0, "nothing is drawn")


func test_the_batch_draws_the_live_flashes() -> void:
	_impact(0, &"bolt")
	_impact(1, &"dash")
	feel.step(0.01)
	var multimesh: MultiMesh = feel._flash_node.multimesh
	check_equal(multimesh.visible_instance_count, 3, "a burst, and a burst and a ring (a wall's chips are motes)")
	# The first drawn is the oldest: the first wall's burst.
	var buffer: PackedFloat32Array = multimesh.buffer
	var coded: float = (1.0 - buffer[15]) * 16.0
	check_equal(roundi(buffer[2]), (feel.get("_flash_kinds") as Array).find(feel.flash_kind(&"burst")), "the kind travels as the shader reads it: its table row")
	check_equal(floori(coded + 0.5), FeelScript.FLASH_TABLE_CODE, "beside the table's code")
	check(coded - FeelScript.FLASH_TABLE_CODE > FeelScript.FLASH_FROM and coded - FeelScript.FLASH_TABLE_CODE < 0.5, "with its age beside it")
	check(is_equal_approx(buffer[3], 50.0) and is_equal_approx(buffer[7], 50.0), "where it landed")
	check(is_equal_approx(buffer[0], FeelScript.FLASH_GRID), "a quad of the shader's grid")


func test_a_cast_by_an_enemy_or_a_bad_index_changes_nothing() -> void:
	for bad in [-1, 4, 99]:
		bus.spell_cast.emit(bad, &"beam", Vector2(10, 10), Vector2.DOWN)
	check_equal(feel.live_flashes(), 0, "no flash for a bad index")


func test_a_hit_on_a_character_shows_the_flare_too() -> void:
	var enemy: Node2D = own(Node2D.new()) as Node2D
	root.add_child(enemy)
	_impact(2, &"rune", Color.WHITE, 0, enemy)
	check_equal(feel.flashes_of(&"rune_burst", 2), 1, "a flare at the hit")


func test_flashes_past_the_slots_take_the_oldest() -> void:
	for i in feel.effect_slots + 20:
		_impact(i % 4, &"bolt")
	check_equal(feel.live_flashes(), feel.effect_slots, "every slot busy, no more")


func test_an_enemy_shot_lands_like_a_spell_in_the_enemy_ramp() -> void:
	# Staffs F7: no ember burst of its own any more; an enemy actor's shot is in the enemy ramp.
	var enemy: int = ActorSeats.enemy(actors)
	for form in FORMS:
		_cast(0, form)
		bus.projectile_impact.emit(enemy, null, Vector2(50, 50), Vector2.RIGHT)
		var shown: Dictionary = feel.flash_info(&"burst")
		check(not shown.is_empty() and shown["ramp"] == ActorSeats.ActorsScript.RAMP_ENEMY and shown["core"] == Color.WHITE, "%s: an enemy's plain shot lands in a burst in the enemy ramp" % form)
		check(shown["core"] != EnemyBase.DEFAULT_HIT_COLOR, "%s: not in ember" % form)
		feel.step(1.0)





func test_four_players_casting_and_hitting_stay_in_the_pools() -> void:
	var children: int = feel.get_child_count()
	var enemy: int = ActorSeats.enemy(actors)
	for round in 6:
		for player in 4:
			_cast(player, FORMS[(player + round) % FORMS.size()])
			bus.projectile_impact.emit(player, null, Vector2(player * 10, 0), Vector2.RIGHT)
			bus.projectile_impact.emit(enemy, null, Vector2(player * 10, 5), Vector2.LEFT)
	check(feel.live_flashes() <= feel.effect_slots, "inside the effect slots")
	check_equal(feel.get_child_count(), children, "no new nodes were needed")


func _the_shown_beam() -> MeshInstance2D:
	var beam: MeshInstance2D = null
	for node in feel._forms:
		if node.visible:
			beam = node
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
	check_equal((_the_shown_beam().material as ShaderMaterial).get_shader_parameter(&"beam_width"), FeelScript.BEAM_TEXTURE_HEIGHT, "nor its width: the shader swells its rim")


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


func test_a_beam_is_drawn_by_the_beam_shader_with_its_cards() -> void:
	bus.form_shown.emit(3, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, Color.RED, 9)
	var material: ShaderMaterial = _the_shown_beam().material as ShaderMaterial
	check(material.shader == BEAM_CARD_SHADER, "a beam, by its card's own shader (card-looks phase 2)")
	check_equal(material.get_shader_parameter(&"beam_points"), 2, "along a path of two points")
	check_equal(material.get_shader_parameter(&"beam_length"), 100.0, "as long as it got")
	check_equal(material.get_shader_parameter(&"beam_player"), 3, "in its caster's hat ramp")
	check_equal(material.get_shader_parameter(&"beam_look"), 9, "with the cast's cards")
	check_equal(material.get_shader_parameter(&"beam_infusion_count"), 0, "a shown beam hands no infusions: its look works them out from its tint and cards")
	check(is_equal_approx(material.get_shader_parameter(&"beam_glow") as float, preset.beam_alpha), "glowing as the preset says")


func test_a_flare_of_zero_leaves_the_beam_as_before() -> void:
	preset.beam_flare = 0.0
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, Color.RED, 0)
	check_equal(_swell(), 1.0, "at rest at the start")


func test_the_screen_shake_setting_follows_the_event() -> void:
	check(feel.shake_enabled, "on by default")
	bus.screen_shake_changed.emit(false)
	check(not feel.shake_enabled, "the event turns it off")
	bus.screen_shake_changed.emit(true)
	check(feel.shake_enabled, "and on again")


func test_the_effect_slots_setting_sizes_the_batch() -> void:
	check_equal(feel.effect_slots, EffectSlots.DEFAULT, "the default at the start")
	_impact(0, &"bolt")
	bus.effect_slots_changed.emit(128)
	check_equal(feel.effect_slots, 128, "the setting takes")
	check_equal(feel._flash_node.multimesh.instance_count, 128, "the batch has that room")
	check_equal(feel.live_flashes(), 0, "the flashes showing end")
	for i in 200:
		_impact(i % 4, &"bolt")
	check_equal(feel.live_flashes(), 128, "no more than the setting")
	feel.step(0.01)
	check_equal(feel._flash_node.multimesh.visible_instance_count, 128, "and all of them drawn")
	check_equal(feel.set_effect_slots(5000), EffectSlots.MAX, "a number past the top is the top")
	check_equal(feel.set_effect_slots(1), EffectSlots.MIN, "below the bottom, the bottom")
	check_equal(feel.set_effect_slots(300), 320, "between steps, the nearest step")


func test_a_casts_kick_is_its_cues() -> void:
	var cue: CueBase = feel.cue_of(&"cast_bolt")
	check(cue.kick > 0.0 and cue.kick_way == &"back", "a cast cue kicks the camera back")
	_cast(0, &"bolt")
	check(feel.kick().is_equal_approx(Vector2.UP * cue.kick), "against the aim (down), by the cue's pixels")
	feel.step(1.0)
	bus.spell_cast.emit(0, &"bolt", Vector2(10, 10), Vector2.ZERO)
	check_equal(feel.kick(), Vector2.ZERO, "a cast with no aim kicks nowhere")
	check_equal(feel.flashes_of(&"cast"), 1, "but still flashes")


func test_a_rings_impact_has_the_shots_colour_but_not_its_cards() -> void:
	var frost := Color("4fd6dc")
	var look: int = ProjectilesScript.pack_look(PackedInt32Array([ProjectilesScript.LOOK_FLECKS]))
	_impact(1, &"dash", frost, look)
	check_equal(feel.flash_dress(&"burst"), [frost, look], "its burst: the colour and the cards")
	check_equal(feel.flash_dress(&"ring_out"), [frost, 0], "its ring: the colour only (`no_cards`)")


func test_an_impact_cue_is_of_the_shots_spell() -> void:
	var tags: Array[int] = []
	feel.add_cue_part(&"mark", func(_part: Dictionary, cue: FeelScript.CueContextScript) -> void: tags.append(cue.tag))
	projectiles.impact_tag = 77
	_impact(0, &"rune")
	projectiles.impact_tag = 0
	check_equal(tags, [77] as Array[int], "a rune's burst leaves its scar by the cards of the shot's spell (`impact_tag`)")


## Two beams on screen at once keep their own materials: each sets its own path and length, so a
## card's shader is set on each beam's own material, never shared (card-looks phase 2).
func test_two_beams_keep_their_own_materials() -> void:
	bus.form_shown.emit(0, &"beam", Vector2.ZERO, Vector2.RIGHT, 100.0, Color.RED, 0)
	bus.form_shown.emit(1, &"beam", Vector2(0, 50), Vector2.RIGHT, 60.0, Color.BLUE, 0)
	var shown: Array[MeshInstance2D] = []
	for node in feel._forms:
		if node.visible:
			shown.append(node)
	check_equal(shown.size(), 2, "two beams")
	if shown.size() != 2:
		return
	check(shown[0].material != shown[1].material, "each its own material")
	var lengths: Array = [(shown[0].material as ShaderMaterial).get_shader_parameter(&"beam_length"), (shown[1].material as ShaderMaterial).get_shader_parameter(&"beam_length")]
	lengths.sort()
	check_equal(lengths, [60.0, 100.0], "each its own length")
	for node in shown:
		check((node.material as ShaderMaterial).shader == BEAM_CARD_SHADER, "each by the beam card's shader")


## Only a card its own area draws lends a beam its shader: a ray of another card (a zap of a bolt
## is drawn as a beam, but the bolt's shader draws heads) and an id that is no card draw plain.
func test_a_beam_of_another_card_is_drawn_plain() -> void:
	check(feel._form_shader_of(&"beam", Carrier.LOOK_BEAM, FeelScript.BEAM_SHADER) == BEAM_CARD_SHADER, "the beam card's own")
	check(feel._form_shader_of(&"bolt", Carrier.LOOK_BEAM, FeelScript.BEAM_SHADER) == FeelScript.BEAM_SHADER, "a bolt's ray: plain")
	check(feel._form_shader_of(&"no_such_card", Carrier.LOOK_BEAM, FeelScript.BEAM_SHADER) == FeelScript.BEAM_SHADER, "no card: plain")
