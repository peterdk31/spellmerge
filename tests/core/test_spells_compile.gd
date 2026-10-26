extends "res://tests/support/suite.gd"
## Tests for the spell compiler in core/spells (M2 part 5): the numbers, the descriptions,
## each limit at and over its value (complexity, shots, depth, modifiers), and the tag
## scheme with generations (four players at once, a rebuild mid-flight, the ring wrapping).
## It uses components built in code and a stand-in registry, so no content is needed.
##
## godot --headless --path . --script res://tests/core/test_spells_compile.gd

const SpellsScript := preload("res://core/spells/spells.gd")


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


func _compile(recipe: Dictionary) -> CompiledSpell:
	return _spells.call("compile", recipe) as CompiledSpell


## A recipe of `form` that holds `held` through `trigger`.
func _holding(form: StringName, trigger: StringName, held: Dictionary) -> Dictionary:
	return {"form": form, "trigger": trigger, "held": held}


func test_a_bolt_compiles_to_the_form_numbers() -> void:
	var spell: CompiledSpell = _compile({"form": &"bolt"})
	check(spell.valid, "a bare bolt is valid")
	check_equal(spell.damage, 5, "damage is the form's")
	check_equal(spell.shots, 1, "one shot")
	check_equal(spell.complexity, 1, "complexity is the form's")
	check_equal(spell.status_id, &"", "no element means plain arcane damage")
	check(spell.held == null, "nothing is held")
	check(spell.description.begins_with("Bolt: 5 damage, 1 shot"), "the description starts with the stats: " + spell.description)


func test_element_and_modifiers_change_the_numbers_in_order() -> void:
	var spell: CompiledSpell = _compile({"form": &"bolt", "element": &"fire", "modifiers": [&"bigger", &"pierce", &"homing"]})
	check(spell.valid, "bolt, fire and three modifiers is valid: " + spell.reason)
	check_equal(spell.damage, 15, "5 x 1.5 (fire) x 2 (bigger) is 15")
	check_equal(spell.radius, 8.0, "radius doubles")
	check_equal(spell.pierce, 2, "pierce adds")
	check_equal(spell.status_id, &"burn", "the element's status is carried")
	check_equal(spell.complexity, 1 + 1 + 1 + 1 + 2, "complexity is the sum")
	check_equal(spell.homing_turn, 4.0, "a homing modifier sets the turn rate")
	check(spell.description.contains("Fire Bolt") and spell.description.contains("Pierces 2."), "the description names the element and pierce: " + spell.description)


func test_chain_adds_its_jumps() -> void:
	var spell: CompiledSpell = _compile({"form": &"bolt", "modifiers": [&"chain", &"chain"]})
	check_equal(spell.chain_jumps, 4, "two chains jump four times")
	check(spell.description.contains("Chains 4 times."), "the description says so: " + spell.description)


func test_a_split_fans_a_form_that_has_no_spread() -> void:
	var spell: CompiledSpell = _compile({"form": &"bolt", "modifiers": [&"split"]})
	check_equal(spell.shots, 3, "split triples the shots")
	check_equal(spell.spread, SpellLimits.SPLIT_SPREAD, "a fan opens")
	var nova: CompiledSpell = _compile({"form": &"nova"})
	check_equal(nova.spread, 360.0, "a nova keeps its ring")


func test_a_held_spell_adds_its_complexity_and_description() -> void:
	var spell: CompiledSpell = _compile(_holding(&"bolt", &"on_hit", {"form": &"nova", "element": &"frost"}))
	check(spell.valid, "valid: " + spell.reason)
	check_equal(spell.complexity, 1 + 1 + 2 + 1, "both spells and the trigger count")
	check(spell.held != null and spell.held.depth == 1, "the held spell is one level down")
	check(spell.description.contains("Then, on hit: Frost Nova"), "the description includes the held spell: " + spell.description)
	check_equal(spell.chain_length(), 2, "two spells in the chain")


func test_triggers_describe_when_they_fire() -> void:
	var expire: CompiledSpell = _compile(_holding(&"bolt", &"on_expire", {"form": &"bolt"}))
	check(expire.description.contains("when it ends"), "on expire: " + expire.description)
	var timer: CompiledSpell = _compile(_holding(&"bolt", &"timer", {"form": &"bolt"}))
	check(timer.description.contains("every 0.5 s"), "timer: " + timer.description)
	check_equal(timer.trigger_max_fires, 4, "a timer fires at most four times")


func test_a_trigger_with_nothing_held_is_valid() -> void:
	var spell: CompiledSpell = _compile({"form": &"bolt", "trigger": &"on_hit"})
	check(spell.valid and spell.held == null, "the builder can place the trigger first")
	check_equal(spell.complexity, 2, "the trigger still costs")


func test_complexity_at_the_limit_compiles() -> void:
	# nova 2 + fire 1 + split 2 + homing 2 + chain 2 + on hit 1 = 10; held bolt 1 + fire 1 = 12.
	var recipe: Dictionary = {"form": &"nova", "element": &"fire", "modifiers": [&"split", &"homing", &"chain"], "trigger": &"on_hit", "held": {"form": &"bolt", "element": &"fire"}}
	var spell: CompiledSpell = _compile(recipe)
	check_equal(spell.complexity, SpellLimits.MAX_COMPLEXITY, "exactly the budget")
	check(spell.valid, "the budget itself is allowed: " + spell.reason)


func test_complexity_over_the_limit_is_refused_with_the_reason() -> void:
	var recipe: Dictionary = {"form": &"nova", "element": &"fire", "modifiers": [&"split", &"homing", &"chain"], "trigger": &"on_hit", "held": {"form": &"bolt", "element": &"fire", "modifiers": [&"pierce"]}}
	var spell: CompiledSpell = _compile(recipe)
	check(not spell.valid, "13 of 12 is refused")
	check_equal(spell.reason, "Too complex: 13 of 12. Remove one.", "the reason says how much")
	var heavy: CompiledSpell = _compile({"form": &"heavy", "modifiers": [&"split", &"homing"], "trigger": &"timer", "held": {"form": &"heavy"}})
	check(not heavy.valid and heavy.reason.begins_with("Too complex"), "a held spell counts toward the budget")


func test_shots_at_the_limit_are_not_clamped() -> void:
	var spell: CompiledSpell = _compile({"form": &"nova", "modifiers": [&"split"]})
	check_equal(spell.shots, SpellLimits.MAX_SHOTS, "8 x 3 is exactly 24")
	check(not spell.shots_clamped, "nothing was cut")
	check(not spell.description.contains("limit"), "the description says nothing about a limit")


func test_shots_over_the_limit_are_clamped_and_said() -> void:
	var spell: CompiledSpell = _compile({"form": &"nova", "modifiers": [&"split", &"split"]})
	check(spell.valid, "clamping is not a refusal")
	check_equal(spell.shots, SpellLimits.MAX_SHOTS, "72 shots become 24")
	check(spell.shots_clamped, "the clamp is recorded")
	check_equal(spell.shots_requested, 72, "the asked-for count is kept")
	check(spell.description.contains("Cut from 72 to 24 shots, the limit."), "the description says so: " + spell.description)


func test_the_status_is_described_in_plain_words() -> void:
	(_fake.items[&"fire"] as ElementBase).status_duration = 3.0
	var spell: CompiledSpell = _compile({"form": &"bolt", "element": &"fire"})
	check(spell.description.contains("Burns for 3.0 s."), spell.description)


func test_chain_jumps_timer_interval_and_lifetime_are_clamped() -> void:
	var many: CompiledSpell = _compile({"form": &"bolt", "modifiers": [&"chain", &"chain", &"chain"]})
	check_equal(many.chain_jumps, SpellLimits.MAX_CHAIN_JUMPS, "three chains of 2 jumps are exactly the limit")
	(_fake.items[&"chain"] as ModifierBase).behaviour_strength = 3.0
	var over: CompiledSpell = _compile({"form": &"bolt", "modifiers": [&"chain", &"chain", &"chain"]})
	check_equal(over.chain_jumps, SpellLimits.MAX_CHAIN_JUMPS, "9 jumps are cut to the limit")
	var timer: TriggerBase = _fake.items[&"timer"] as TriggerBase
	timer.interval = SpellLimits.MIN_TIMER_INTERVAL
	check_equal(_compile(_holding(&"bolt", &"timer", {"form": &"bolt"})).trigger_interval, SpellLimits.MIN_TIMER_INTERVAL, "the minimum interval is kept")
	timer.interval = 0.0
	check_equal(_compile(_holding(&"bolt", &"timer", {"form": &"bolt"})).trigger_interval, SpellLimits.MIN_TIMER_INTERVAL, "an interval of 0 is raised")
	timer.interval = 99.0
	check_equal(_compile(_holding(&"bolt", &"timer", {"form": &"bolt"})).trigger_interval, SpellLimits.MAX_TIMER_INTERVAL, "a huge interval is cut")
	(_fake.items[&"bolt"] as FormBase).lifetime = 500.0
	check_equal(_compile({"form": &"bolt"}).lifetime, SpellLimits.MAX_LIFETIME, "lifetime is capped")


func test_other_numbers_are_clamped() -> void:
	var form: FormBase = _fake.items[&"bolt"] as FormBase
	form.speed = 1500.0
	form.radius = 60.0
	var faster: ModifierBase = _modifier(&"faster", 1)
	faster.speed_mult = 4.0
	faster.radius_mult = 4.0
	faster.cooldown_mult = 0.1
	form.cooldown = 0.2
	var spell: CompiledSpell = _compile({"form": &"bolt", "modifiers": [&"faster"]})
	check_equal(spell.speed, SpellLimits.MAX_SPEED, "speed is capped")
	check_equal(spell.radius, SpellLimits.MAX_RADIUS, "radius is capped")
	check_equal(spell.cooldown, SpellLimits.MIN_COOLDOWN, "cooldown has a floor")


func test_depth_two_compiles_and_depth_three_is_refused() -> void:
	var deep: Dictionary = _holding(&"bolt", &"on_hit", _holding(&"bolt", &"on_hit", {"form": &"bolt"}))
	var at_limit: CompiledSpell = _compile(deep)
	check(at_limit.valid, "three spells, two levels below the cast: " + at_limit.reason)
	check(at_limit.at_depth(2) != null and at_limit.at_depth(2).depth == 2, "the third spell is at depth 2")
	check(at_limit.at_depth(3) == null, "nothing below it")
	var too_deep: Dictionary = _holding(&"bolt", &"on_hit", _holding(&"bolt", &"on_hit", _holding(&"bolt", &"on_hit", {"form": &"bolt"})))
	var over: CompiledSpell = _compile(too_deep)
	check(not over.valid, "a fourth spell is refused")
	check(over.reason.contains("2 levels"), "the reason names the depth: " + over.reason)


func test_modifier_count_at_and_over_the_limit() -> void:
	check(_compile({"form": &"bolt", "modifiers": [&"pierce", &"pierce", &"pierce"]}).valid, "three modifiers are allowed, repeats too")
	var over: CompiledSpell = _compile({"form": &"bolt", "modifiers": [&"pierce", &"pierce", &"pierce", &"pierce"]})
	check(not over.valid and over.reason.contains("3 modifiers"), "four are refused: " + over.reason)


func test_bad_recipes_are_refused_with_a_reason() -> void:
	check_equal(_compile({}).reason, "Pick a form (F) first.", "no form")
	check_equal(_compile({"form": &"nope"}).reason, "Unknown component 'nope'.", "unknown id")
	check_equal(_compile({"form": &"fire"}).reason, "'fire' is an element, not a form.", "wrong kind in the form slot")
	check(not _compile({"form": &"bolt", "element": &"pierce"}).valid, "a modifier is not an element")
	check(not _compile({"form": &"bolt", "modifiers": [&"fire"]}).valid, "an element is not a modifier")
	check(not _compile({"form": &"bolt", "trigger": &"split"}).valid, "a modifier is not a trigger")
	var no_trigger: CompiledSpell = _compile({"form": &"bolt", "held": {"form": &"bolt"}})
	check(not no_trigger.valid and no_trigger.reason.contains("needs a trigger"), "a held spell needs a trigger: " + no_trigger.reason)
	var bad_held: CompiledSpell = _compile(_holding(&"bolt", &"on_hit", {"form": &"nope"}))
	check_equal(bad_held.reason, "Unknown component 'nope'.", "the held spell's problem is reported")
	var strings: CompiledSpell = _compile({"form": "bolt", "modifiers": ["pierce"]})
	check(strings.valid, "plain strings (from JSON) work like names")


func test_malformed_recipes_are_refused_not_crashed() -> void:
	check(_compile({"form": null}).reason == "Pick a form (F) first.", "a null form is a missing form")
	check(not _compile({"form": 5}).valid, "a number is no form id")
	check(not _compile({"form": &"bolt", "modifiers": "pierce"}).valid, "modifiers as a String")
	check(not _compile({"form": &"bolt", "modifiers": [3]}).valid, "a number in the modifiers")
	check(_compile({"form": &"bolt", "modifiers": null}).valid, "null modifiers are none")
	check(_compile({"form": &"bolt", "modifiers": PackedStringArray(["pierce"])}).valid, "a PackedStringArray works")
	var held: CompiledSpell = _compile({"form": &"bolt", "trigger": &"on_hit", "held": "nova"})
	check(not held.valid and held.reason.contains("held spell"), "a held spell that is no recipe is refused: " + held.reason)
	check(_compile({"form": &"bolt", "held": null}).valid, "a null held spell is none")

func test_compiling_does_not_change_the_components() -> void:
	var form: FormBase = _fake.items[&"bolt"] as FormBase
	_compile({"form": &"bolt", "element": &"fire", "modifiers": [&"bigger", &"split"]})
	check_equal(form.base_damage, 5, "the shared form keeps its damage")
	check_equal(form.shots, 1, "and its shots")


func test_tags_pack_and_unpack() -> void:
	for player in SpellLimits.PLAYERS:
		for slot in SpellLimits.SLOTS:
			for depth in SpellLimits.MAX_DEPTH + 1:
				for generation in SpellLimits.GENERATIONS:
					var tag: int = SpellTag.make(player, slot, depth, generation)
					check(tag > 0 and SpellTag.is_spell_tag(tag), "tag is positive")
					check(SpellTag.player_of(tag) == player and SpellTag.slot_of(tag) == slot and SpellTag.depth_of(tag) == depth and SpellTag.generation_of(tag) == generation, "tag %d unpacks to what made it" % tag)
	check(not SpellTag.is_spell_tag(0), "0 is no tag")


func test_all_tags_are_different() -> void:
	var seen: Dictionary = {}
	for player in SpellLimits.PLAYERS:
		for slot in SpellLimits.SLOTS:
			for depth in SpellLimits.MAX_DEPTH + 1:
				for generation in SpellLimits.GENERATIONS:
					seen[SpellTag.make(player, slot, depth, generation)] = true
	check_equal(seen.size(), SpellLimits.PLAYERS * SpellLimits.STAFFS * (SpellLimits.MAX_DEPTH + 1) * SpellLimits.GENERATIONS, "every combination has its own tag")
	check(SpellTag.make(3, 3, SpellTag.NODE_MASK, 7) < SpellTag.FLAG << 1, "the largest tag is still a spell tag")
	check(not SpellTag.is_spell_tag(101000), "the highest enemy attack tag (gameplay/ai) is not a spell tag")


func test_a_built_spell_registers_every_depth() -> void:
	var spell: CompiledSpell = _compile(_holding(&"bolt", &"on_hit", _holding(&"nova", &"on_hit", {"form": &"bolt"})))
	var tag: int = _spells.call("begin_generation", 2, 1, spell)
	check(SpellTag.player_of(tag) == 2 and SpellTag.slot_of(tag) == 1 and SpellTag.depth_of(tag) == 0, "the cast's tag names player, slot and depth 0")
	check(_spells.call("profile", tag) == spell, "the cast's tag finds the spell")
	check(_spells.call("profile", _spells.call("current_tag", 2, 1, 1)) == spell.held, "depth 1 finds the held spell")
	check(_spells.call("profile", _spells.call("current_tag", 2, 1, 2)) == spell.held.held, "depth 2 finds the one below")
	check_equal(_spells.call("current_tag", 2, 0), 0, "the other slot was never built")


func test_invalid_builds_and_bad_arguments_give_tag_zero() -> void:
	var bad: CompiledSpell = _compile({})
	check_equal(_spells.call("begin_generation", 0, 0, bad), 0, "an invalid spell is not registered")
	var good: CompiledSpell = _compile({"form": &"bolt"})
	check_equal(_spells.call("begin_generation", 4, 0, good), 0, "player 4 does not exist")
	check_equal(_spells.call("begin_generation", 0, SpellLimits.STAFFS, good), 0, "a fifth staff does not exist")
	check_equal(_spells.call("begin_generation", -1, 0, good), 0, "player -1 does not exist")
	check_equal(_spells.call("begin_generation", 0, 0, null), 0, "null is not a spell")


func test_four_players_build_at_once_without_mixing() -> void:
	var tags: Array[int] = []
	var spells: Array[CompiledSpell] = []
	for player in SpellLimits.PLAYERS:
		for slot in SpellLimits.SLOTS:
			var spell: CompiledSpell = _compile({"form": &"bolt", "modifiers": [&"pierce"]})
			spells.append(spell)
			tags.append(_spells.call("begin_generation", player, slot, spell))
	for i in tags.size():
		check(_spells.call("profile", tags[i]) == spells[i], "tag %d finds its own spell" % i)
	# Rebuilding one staff leaves the others alone.
	var rebuilt: int = _spells.call("begin_generation", 1, 0, _compile({"form": &"nova"}))
	var at: int = SpellLimits.STAFFS
	check(rebuilt != tags[at], "the new build has a new tag")
	for i in tags.size():
		if i != at:
			check(_spells.call("profile", tags[i]) == spells[i], "slot %d is untouched" % i)


func test_a_rebuild_mid_flight_keeps_the_old_profile_until_the_last_shot_ends() -> void:
	var old_spell: CompiledSpell = _compile({"form": &"bolt"})
	var old_tag: int = _spells.call("begin_generation", 0, 0, old_spell)
	_spells.call("shot_started", old_tag)
	_spells.call("shot_started", old_tag)
	var new_tag: int = _spells.call("begin_generation", 0, 0, _compile({"form": &"nova"}))
	check(new_tag != old_tag, "a rebuild moves to a new generation")
	check(_spells.call("profile", old_tag) == old_spell, "shots in the air keep their old numbers")
	check_equal(_spells.call("generations_held", 0, 0), 2, "old and new are both held")
	_spells.call("shot_ended", old_tag)
	check(_spells.call("profile", old_tag) == old_spell, "one shot is still in the air")
	_spells.call("shot_ended", old_tag)
	check(_spells.call("profile", old_tag) == null, "the last shot frees the old build")
	check_equal(_spells.call("generations_held", 0, 0), 1, "only the new build is left")


func test_a_rebuild_mid_flight_keeps_every_held_depth_until_the_last_shot_of_any_depth() -> void:
	var recipe: Dictionary = _holding(&"bolt", &"on_hit", _holding(&"nova", &"on_hit", {"form": &"bolt"}))
	var old_spell: CompiledSpell = _compile(recipe)
	var tag0: int = _spells.call("begin_generation", 0, 0, old_spell)
	var tag1: int = _spells.call("current_tag", 0, 0, 1)
	var tag2: int = _spells.call("current_tag", 0, 0, 2)
	_spells.call("shot_started", tag0)
	_spells.call("begin_generation", 0, 0, _compile({"form": &"bolt"}))
	check(_spells.call("profile", tag1) == old_spell.held, "the held spell survives while its parent shot is in the air")
	check(_spells.call("profile", tag2) == old_spell.held.held, "and so does the one below it")
	# The parent hits: the child is counted first, then the parent ends.
	_spells.call("shot_started", tag1)
	check_equal(_spells.call("live_shots", tag1), 1, "a held spell's shot counts after the rebuild")
	_spells.call("shot_ended", tag0)
	check(_spells.call("profile", tag0) == old_spell and _spells.call("profile", tag1) == old_spell.held, "the child keeps the build alive")
	_spells.call("shot_started", tag2)
	_spells.call("shot_ended", tag1)
	check(_spells.call("profile", tag2) == old_spell.held.held, "the grandchild keeps it alive")
	_spells.call("shot_ended", tag2)
	for tag in [tag0, tag1, tag2]:
		check(_spells.call("profile", tag) == null, "the whole build is freed with its last shot")


func test_a_rebuild_with_no_shots_in_the_air_frees_the_old_build_at_once() -> void:
	var old_tag: int = _spells.call("begin_generation", 3, 1, _compile({"form": &"bolt"}))
	_spells.call("begin_generation", 3, 1, _compile({"form": &"nova"}))
	check(_spells.call("profile", old_tag) == null, "nothing needs the old build")
	check_equal(_spells.call("generations_held", 3, 1), 1, "one generation held")


func test_the_current_build_stays_when_its_shots_end() -> void:
	var tag: int = _spells.call("begin_generation", 0, 0, _compile({"form": &"bolt"}))
	_spells.call("shot_started", tag)
	_spells.call("shot_ended", tag)
	check(_spells.call("profile", tag) != null, "the build in use is never freed")
	_spells.call("shot_ended", tag)
	check_equal(_spells.call("live_shots", tag), 0, "ending a shot too many does not go negative")
	_spells.call("shot_started", 12345)
	check_equal(_spells.call("live_shots", 12345), 0, "a tag with no spell is not counted")


func test_the_ring_wraps_after_eight_builds() -> void:
	var first_tag: int = _spells.call("begin_generation", 0, 0, _compile({"form": &"bolt"}))
	for build in range(1, SpellLimits.GENERATIONS):
		var tag: int = _spells.call("begin_generation", 0, 0, _compile({"form": &"bolt"}))
		check_equal(SpellTag.generation_of(tag), build, "build %d is generation %d" % [build, build])
	var wrapped: int = _spells.call("begin_generation", 0, 0, _compile({"form": &"nova"}))
	check_equal(wrapped, first_tag, "the ninth build reuses generation 0")
	check_equal((_spells.get("revoked_tags") as PackedInt64Array).size(), 0, "nothing was in the air, so nothing is revoked")


func test_a_full_ring_revokes_the_oldest_generations_shots() -> void:
	var first: CompiledSpell = _compile({"form": &"bolt"})
	var first_tag: int = _spells.call("begin_generation", 0, 0, first)
	_spells.call("shot_started", first_tag)
	# Seven more builds, each with a shot still in the air: all eight generations are live.
	for build in range(1, SpellLimits.GENERATIONS):
		var tag: int = _spells.call("begin_generation", 0, 0, _compile({"form": &"bolt"}))
		_spells.call("shot_started", tag)
	check_equal(_spells.call("generations_held", 0, 0), SpellLimits.GENERATIONS, "all eight generations are held")
	var newest: CompiledSpell = _compile({"form": &"nova"})
	var tag: int = _spells.call("begin_generation", 0, 0, newest)
	check_equal(tag, first_tag, "the ring is back at generation 0")
	var revoked: PackedInt64Array = _spells.get("revoked_tags")
	check(revoked.size() == 1 and revoked[0] == first_tag, "the oldest generation's shots are revoked")
	check(_spells.call("profile", tag) == newest, "the tag now means the new spell, never the old one")
	check_equal(_spells.call("live_shots", tag), 0, "the old shot count is cleared")
	_spells.call("begin_generation", 0, 0, newest)
	check_equal((_spells.get("revoked_tags") as PackedInt64Array).size(), 1, "the next build revokes generation 1's shot")
	_spells.call("begin_generation", 1, 0, newest)
	check_equal((_spells.get("revoked_tags") as PackedInt64Array).size(), 0, "another player's slot has no shots to revoke")


func test_revoking_covers_the_held_depths() -> void:
	var spell: CompiledSpell = _compile(_holding(&"bolt", &"on_hit", {"form": &"bolt"}))
	_spells.call("begin_generation", 0, 1, spell)
	var held_tag: int = _spells.call("current_tag", 0, 1, 1)
	_spells.call("shot_started", held_tag)
	for build in SpellLimits.GENERATIONS:
		_spells.call("begin_generation", 0, 1, spell)
	var revoked: PackedInt64Array = _spells.get("revoked_tags")
	check(revoked.size() == 1 and revoked[0] == held_tag, "a held spell's shot is revoked with its generation")


func test_clear_forgets_everything() -> void:
	var tag: int = _spells.call("begin_generation", 0, 0, _compile({"form": &"bolt"}))
	_spells.call("clear")
	check(_spells.call("profile", tag) == null, "no profile")
	check_equal(_spells.call("current_tag", 0, 0), 0, "no current build")
