extends "res://tests/support/suite.gd"
## Tests for the tags and generations of the spell runtime (staffs A5/A6c; M2 part 5 before):
## the tag layout (staff, generation, node and caster, every actor id 0-511 since actors G2), every compiled spell of a staff registered
## under its node, four players building at once, a rebuild mid-flight, the generation ring
## wrapping and revoking. It uses cards built in code and a stand-in registry, so no content is
## needed. The compiler's own rules are in test_staff_compiler.gd.
##
## godot --headless --path . --script res://tests/core/test_spell_tags.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")

const SpellsScript := preload("res://core/spells/spells.gd")
const ActorsScript := preload("res://core/actors/actors.gd")


## A registry stand-in with the same question as the real one.
class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _spells: Node
var _fake: FakeRegistry


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_spells = own(SpellsScript.new())
	_spells.set("registry", _fake)
	_form(&"bolt", 1, 5, 1)
	_form(&"nova", 2, 4, 8).spread = 360.0
	_form(&"heavy", 4, 4, 1)
	var beam: FormBase = _form(&"beam", 2, 3, 1)
	beam.motion = FormBase.Motion.RAY
	beam.ray_length = 200.0
	var fire: ElementBase = _element(&"fire", 1)
	fire.damage_scale = 1.5
	fire.status_id = &"burn"
	_element(&"frost", 1)
	var split: ModifierBase = _modifier(&"split", 2)
	split.shot_mult = 3
	var homing: ModifierBase = _modifier(&"homing", 2)
	homing.behaviour = ModifierBase.Behaviour.HOMING
	homing.behaviour_strength = 4.0
	homing.behaviour_reach = 160.0
	var chain: ModifierBase = _modifier(&"chain", 2)
	chain.behaviour = ModifierBase.Behaviour.CHAIN
	chain.behaviour_strength = 2.0
	var pierce: ModifierBase = _modifier(&"pierce", 1)
	pierce.extra_pierce = 2
	var bigger: ModifierBase = _modifier(&"bigger", 1)
	bigger.radius_mult = 2.0
	bigger.damage_mult = 2.0
	_trigger(&"on_hit", 1, TriggerBase.Event.HIT)
	_trigger(&"on_expire", 1, TriggerBase.Event.EXPIRE)
	var timer: TriggerBase = _trigger(&"timer", 2, TriggerBase.Event.TIMER)
	timer.interval = 0.5
	timer.max_fires = 4


func _put(component: SpellComponent, id: StringName, complexity: int) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = complexity
	_fake.items[id] = component


func _form(id: StringName, complexity: int, damage: int, shots: int) -> FormBase:
	var form := FormBase.new()
	form.base_damage = damage
	form.shots = shots
	form.speed = 300.0
	form.mana_cost = 2.0
	_put(form, id, complexity)
	return form


func _element(id: StringName, complexity: int) -> ElementBase:
	var element := ElementBase.new()
	_put(element, id, complexity)
	return element


func _modifier(id: StringName, complexity: int) -> ModifierBase:
	var modifier := ModifierBase.new()
	_put(modifier, id, complexity)
	return modifier


func _trigger(id: StringName, complexity: int, event: TriggerBase.Event) -> TriggerBase:
	var trigger := TriggerBase.new()
	trigger.event = event
	_put(trigger, id, complexity)
	return trigger


## The staff for `recipe` (the old recipe shape, see staff_kit.gd).
func _staff(recipe: Dictionary) -> CompiledStaff:
	return StaffKit.compile(_spells, StaffKit.cards(recipe))


## A recipe of `form` that holds `held` through `trigger`.
func _holding(form: StringName, trigger: StringName, held: Dictionary) -> Dictionary:
	return {"form": form, "trigger": trigger, "held": held}


func _begin(actor: int, staff: int, compiled: CompiledStaff) -> int:
	return _spells.call("begin_generation", actor, staff, compiled)


func test_tags_pack_and_unpack() -> void:
	for caster in [0, 1, 3, 4, 259, 260, 300, SpellTag.CASTER_MASK]:
		for staff in SpellLimits.STAFFS:
			for node in [0, 1, 2, SpellTag.NODE_MASK]:
				for generation in SpellLimits.GENERATIONS:
					var tag: int = SpellTag.make(caster, staff, node, generation)
					check(tag > 0 and SpellTag.is_spell_tag(tag), "tag is positive")
					check(SpellTag.caster_of(tag) == caster and SpellTag.staff_of(tag) == staff and SpellTag.node_of(tag) == node and SpellTag.generation_of(tag) == generation, "tag %d unpacks to what made it" % tag)
	check(not SpellTag.is_spell_tag(0), "0 is no tag")


func test_every_actor_id_round_trips() -> void:
	for caster in SpellTag.CASTER_MASK + 1:
		var tag: int = SpellTag.make(caster, 2, 300, 5)
		check(SpellTag.caster_of(tag) == caster and SpellTag.staff_of(tag) == 2 and SpellTag.node_of(tag) == 300 and SpellTag.generation_of(tag) == 5, "caster %d round trips" % caster)
	check_equal(SpellTag.CASTER_MASK + 1, ActorsScript.ACTORS, "a tag holds every actor id")


func test_all_tags_are_different() -> void:
	var seen: Dictionary = {}
	for caster in SpellTag.CASTER_MASK + 1:
		for staff in SpellLimits.STAFFS:
			for node in [0, 1, SpellTag.NODE_MASK]:
				for generation in [0, 7]:
					seen[SpellTag.make(caster, staff, node, generation)] = true
	check_equal(seen.size(), (SpellTag.CASTER_MASK + 1) * SpellLimits.STAFFS * 3 * 2, "every combination has its own tag")
	check(SpellTag.make(SpellTag.CASTER_MASK, 3, SpellTag.NODE_MASK, 7) < SpellTag.FLAG << 1, "the largest tag is still a spell tag")
	check(not SpellTag.is_spell_tag(101000), "the highest enemy attack tag (gameplay/ai) is not a spell tag")


func test_tags_fit_an_int32_and_miss_the_ai_tags() -> void:
	var largest: int = SpellTag.make(SpellTag.CASTER_MASK, 3, SpellTag.NODE_MASK, 7)
	check(largest < SpellTag.LIMIT and SpellTag.is_spell_tag(largest), "the largest tag is a spell tag")
	check(SpellTag.LIMIT <= 1 << 29, "every spell tag is below 2^29")
	var shields := PackedInt32Array([largest])
	check_equal(shields[0], largest, "an int32 array keeps the largest tag")
	check(SpellTag.make(0, 0, 0, 0) > 101000, "the smallest tag is above the AI's attack tags")
	check(not SpellTag.is_spell_tag(SpellTag.LIMIT), "nothing at the limit is a spell tag")
	check_equal(SpellTag.generation_key(SpellTag.make(7, 0, 9, 2)), SpellTag.make(7, 0, 0, 2), "a generation key keeps its caster")
	check(SpellTag.generation_key(SpellTag.make(7, 0, 9, 2)) != SpellTag.generation_key(SpellTag.make(8, 0, 9, 2)), "two casters have their own keys")


func test_a_built_staff_registers_every_node() -> void:
	var staff: CompiledStaff = _staff(_holding(&"bolt", &"on_hit", _holding(&"nova", &"on_hit", {"form": &"bolt"})))
	var tag: int = _begin(2, 1, staff)
	check(SpellTag.caster_of(tag) == 2 and SpellTag.staff_of(tag) == 1 and SpellTag.node_of(tag) == 0, "the first tag names caster, staff and node 0")
	for node in staff.nodes.size():
		check(_spells.call("profile", _spells.call("current_tag", 2, 1, node)) == staff.nodes[node], "node %d finds its spell" % node)
	check_equal(_spells.call("current_tag", 2, 0), 0, "the other staff was never built")


func test_empty_staffs_and_bad_arguments_give_tag_zero() -> void:
	check_equal(_begin(0, 0, StaffKit.compile(_spells, [] as Array[StringName])), 0, "an empty staff is not registered")
	var good: CompiledStaff = _staff({"form": &"bolt"})
	check_equal(_begin(ActorsScript.ACTORS, 0, good), 0, "actor 512 does not exist")
	check(_begin(ActorsScript.ACTORS - 1, 0, good) != 0, "the last actor id may build")
	check_equal(_begin(0, SpellLimits.STAFFS, good), 0, "a fifth staff does not exist")
	check_equal(_begin(-1, 0, good), 0, "actor -1 does not exist")
	check_equal(_begin(0, 0, null), 0, "null is not a staff")


func test_four_players_build_at_once_without_mixing() -> void:
	var tags: Array[int] = []
	var builds: Array[CompiledStaff] = []
	for player in 4:
		for staff in SpellLimits.STAFFS:
			var built: CompiledStaff = _staff({"form": &"bolt", "modifiers": [&"pierce"]})
			builds.append(built)
			tags.append(_begin(player, staff, built))
	for i in tags.size():
		check(_spells.call("profile", tags[i]) == builds[i].nodes[0], "tag %d finds its own spell" % i)
	# Rebuilding one staff leaves the others alone.
	var rebuilt: int = _begin(1, 0, _staff({"form": &"nova"}))
	var at: int = SpellLimits.STAFFS
	check(rebuilt != tags[at], "the new build has a new tag")
	for i in tags.size():
		if i != at:
			check(_spells.call("profile", tags[i]) == builds[i].nodes[0], "staff %d is untouched" % i)


func test_a_rebuild_mid_flight_keeps_the_old_profile_until_the_last_shot_ends() -> void:
	var old: CompiledStaff = _staff({"form": &"bolt"})
	var old_tag: int = _begin(0, 0, old)
	_spells.call("shot_started", old_tag)
	_spells.call("shot_started", old_tag)
	var new_tag: int = _begin(0, 0, _staff({"form": &"nova"}))
	check(new_tag != old_tag, "a rebuild moves to a new generation")
	check(_spells.call("profile", old_tag) == old.nodes[0], "shots in the air keep their old numbers")
	check_equal(_spells.call("generations_held", 0, 0), 2, "old and new are both held")
	_spells.call("shot_ended", old_tag)
	check(_spells.call("profile", old_tag) == old.nodes[0], "one shot is still in the air")
	_spells.call("shot_ended", old_tag)
	check(_spells.call("profile", old_tag) == null, "the last shot frees the old build")
	check_equal(_spells.call("generations_held", 0, 0), 1, "only the new build is left")


func test_a_rebuild_mid_flight_keeps_every_node_until_the_last_shot_of_any_node() -> void:
	var old: CompiledStaff = _staff(_holding(&"bolt", &"on_hit", _holding(&"nova", &"on_hit", {"form": &"bolt"})))
	var tag0: int = _begin(0, 0, old)
	var tag1: int = _spells.call("current_tag", 0, 0, 1)
	var tag2: int = _spells.call("current_tag", 0, 0, 2)
	_spells.call("shot_started", tag0)
	_begin(0, 0, _staff({"form": &"bolt"}))
	check(_spells.call("profile", tag1) == old.nodes[1], "the payload survives while its parent shot is in the air")
	check(_spells.call("profile", tag2) == old.nodes[2], "and so does the one below it")
	# The parent hits: the child is counted first, then the parent ends.
	_spells.call("shot_started", tag1)
	check_equal(_spells.call("live_shots", tag1), 1, "a payload's shot counts after the rebuild")
	_spells.call("shot_ended", tag0)
	check(_spells.call("profile", tag0) == old.nodes[0] and _spells.call("profile", tag1) == old.nodes[1], "the child keeps the build alive")
	_spells.call("shot_started", tag2)
	_spells.call("shot_ended", tag1)
	check(_spells.call("profile", tag2) == old.nodes[2], "the grandchild keeps it alive")
	_spells.call("shot_ended", tag2)
	for tag in [tag0, tag1, tag2]:
		check(_spells.call("profile", tag) == null, "the whole build is freed with its last shot")


func test_a_rebuild_with_no_shots_in_the_air_frees_the_old_build_at_once() -> void:
	var old_tag: int = _begin(3, 1, _staff({"form": &"bolt"}))
	_begin(3, 1, _staff({"form": &"nova"}))
	check(_spells.call("profile", old_tag) == null, "nothing needs the old build")
	check_equal(_spells.call("generations_held", 3, 1), 1, "one generation held")


func test_the_current_build_stays_when_its_shots_end() -> void:
	var tag: int = _begin(0, 0, _staff({"form": &"bolt"}))
	_spells.call("shot_started", tag)
	_spells.call("shot_ended", tag)
	check(_spells.call("profile", tag) != null, "the build in use is never freed")
	_spells.call("shot_ended", tag)
	check_equal(_spells.call("live_shots", tag), 0, "ending a shot too many does not go negative")
	_spells.call("shot_started", 12345)
	check_equal(_spells.call("live_shots", 12345), 0, "a tag with no spell is not counted")


func test_the_ring_wraps_after_eight_builds() -> void:
	var first_tag: int = _begin(0, 0, _staff({"form": &"bolt"}))
	for build in range(1, SpellLimits.GENERATIONS):
		var tag: int = _begin(0, 0, _staff({"form": &"bolt"}))
		check_equal(SpellTag.generation_of(tag), build, "build %d is generation %d" % [build, build])
	var wrapped: int = _begin(0, 0, _staff({"form": &"nova"}))
	check_equal(wrapped, first_tag, "the ninth build reuses generation 0")
	check_equal((_spells.get("revoked_tags") as PackedInt64Array).size(), 0, "nothing was in the air, so nothing is revoked")


func test_a_full_ring_revokes_the_oldest_generations_shots() -> void:
	var first_tag: int = _begin(0, 0, _staff({"form": &"bolt"}))
	_spells.call("shot_started", first_tag)
	# Seven more builds, each with a shot still in the air: all eight generations are live.
	for build in range(1, SpellLimits.GENERATIONS):
		var tag: int = _begin(0, 0, _staff({"form": &"bolt"}))
		_spells.call("shot_started", tag)
	check_equal(_spells.call("generations_held", 0, 0), SpellLimits.GENERATIONS, "all eight generations are held")
	var newest: CompiledStaff = _staff({"form": &"nova"})
	var tag: int = _begin(0, 0, newest)
	check_equal(tag, first_tag, "the ring is back at generation 0")
	var revoked: PackedInt64Array = _spells.get("revoked_tags")
	check(revoked.size() == 1 and revoked[0] == first_tag, "the oldest generation's shots are revoked")
	check(_spells.call("profile", tag) == newest.nodes[0], "the tag now means the new spell, never the old one")
	check_equal(_spells.call("live_shots", tag), 0, "the old shot count is cleared")
	_begin(0, 0, newest)
	check_equal((_spells.get("revoked_tags") as PackedInt64Array).size(), 1, "the next build revokes generation 1's shot")
	_begin(1, 0, newest)
	check_equal((_spells.get("revoked_tags") as PackedInt64Array).size(), 0, "another player's staff has no shots to revoke")


func test_revoking_covers_the_payload_nodes() -> void:
	var staff: CompiledStaff = _staff(_holding(&"bolt", &"on_hit", {"form": &"bolt"}))
	_begin(0, 1, staff)
	var payload_tag: int = _spells.call("current_tag", 0, 1, 1)
	_spells.call("shot_started", payload_tag)
	for build in SpellLimits.GENERATIONS:
		_begin(0, 1, staff)
	var revoked: PackedInt64Array = _spells.get("revoked_tags")
	check(revoked.size() == 1 and revoked[0] == payload_tag, "a payload's shot is revoked with its generation")


func test_clear_forgets_everything() -> void:
	var tag: int = _begin(0, 0, _staff({"form": &"bolt"}))
	_spells.call("clear")
	check(_spells.call("profile", tag) == null, "no profile")
	check_equal(_spells.call("current_tag", 0, 0), 0, "no current build")
