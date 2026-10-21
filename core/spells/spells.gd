extends Node
## The spell runtime (autoload `Spells`), part 5: the compiler, the limits and the tags.
## Casting and triggers arrive in M2 part 6.
##
## A recipe is a Dictionary of component ids (a held spell is a recipe too):
##
##     {"form": &"bolt", "element": &"fire", "modifiers": [&"split", &"homing"],
##      "trigger": &"on_hit", "held": {"form": &"nova"}}
##
## Only `form` is required; `element`, `modifiers`, `trigger` and `held` may be left out.
## `compile` never errors: a recipe that breaks a rule gives a spell with `valid == false`
## and a plain `reason`, and numbers over a limit are clamped and said so in `description`.
##
## Tags: `begin_generation(player, slot, spell)` registers a built spell under a new
## generation of that slot and returns the tag of its cast (depth 0); its held spells get
## the same tag with depth 1 and 2. Shots keep the tag they were born with, so a shot still
## in the air after a rebuild hits with its old numbers (`profile(tag)`). A generation is
## forgotten when its last shot has ended (`shot_ended`) and it is no longer current.

## Tags whose shots the last `begin_generation` call revoked, because all 8 generations of
## the slot were in the air. The caller removes those shots from the projectile manager.
var revoked_tags: PackedInt64Array = PackedInt64Array()

## Registry stand-in for tests: anything with `get_resource(folder, id)`. Null uses `Registry`.
var registry: Node = null

## player * SLOTS + slot -> the current generation (0-7)
var _current: PackedInt32Array = PackedInt32Array()
## tag -> CompiledSpell
var _profiles: Dictionary = {}
## tag -> live shots
var _live: Dictionary = {}


func _init() -> void:
	_current.resize(SpellLimits.PLAYERS * SpellLimits.SLOTS)
	_current.fill(-1)


## Turns a recipe into a CompiledSpell. See the class doc for the recipe shape.
func compile(recipe: Dictionary) -> CompiledSpell:
	var spell: CompiledSpell = _compile(recipe, 0)
	if not spell.valid:
		return spell
	if spell.complexity > SpellLimits.MAX_COMPLEXITY:
		return _refused("Too complex: %d of %d." % [spell.complexity, SpellLimits.MAX_COMPLEXITY])
	_describe(spell)
	return spell


## The spell registered under `tag`, or null when its generation is gone.
func profile(tag: int) -> CompiledSpell:
	return _profiles.get(tag)


## Registers `spell` (which must be valid) as the new build of this player's slot and
## returns the tag of its cast, or 0 for an invalid spell or a bad player or slot.
## The slot's generation advances; if its shots from 8 builds ago are still in the air the
## oldest generation is revoked (see `revoked_tags`).
func begin_generation(player: int, slot: int, spell: CompiledSpell) -> int:
	revoked_tags.clear()
	if spell == null or not spell.valid or not _in_range(player, slot):
		return 0
	var index: int = player * SpellLimits.SLOTS + slot
	var old: int = _current[index]
	var generation: int = (old + 1) % SpellLimits.GENERATIONS
	_current[index] = generation
	for depth in SpellLimits.MAX_DEPTH + 1:
		var tag: int = SpellTag.make(player, slot, depth, generation)
		if _live.get(tag, 0) > 0:
			revoked_tags.append(tag)
		_forget(tag)
	var level: CompiledSpell = spell
	for depth in SpellLimits.MAX_DEPTH + 1:
		if level == null:
			break
		_profiles[SpellTag.make(player, slot, depth, generation)] = level
		level = level.held
	if old >= 0:
		_release_generation(player, slot, old)
	return SpellTag.make(player, slot, 0, generation)


## The tag of the current build of this slot at `depth`, or 0 when it was never built.
func current_tag(player: int, slot: int, depth: int = 0) -> int:
	if not _in_range(player, slot):
		return 0
	var generation: int = _current[player * SpellLimits.SLOTS + slot]
	return 0 if generation < 0 else SpellTag.make(player, slot, depth, generation)


## A shot with `tag` was spawned. Ignored for a tag that has no spell.
func shot_started(tag: int) -> void:
	if _profiles.has(tag):
		_live[tag] = _live.get(tag, 0) + 1


## A shot with `tag` ended (hit, expired or was removed). The generation's spell is freed
## once its last shot is gone and a newer build has replaced it.
func shot_ended(tag: int) -> void:
	var live: int = _live.get(tag, 0)
	if live <= 0:
		return
	if live == 1:
		_live.erase(tag)
		if not _is_current(tag):
			_profiles.erase(tag)
	else:
		_live[tag] = live - 1


## Live shots counted for `tag`.
func live_shots(tag: int) -> int:
	return _live.get(tag, 0)


## Generations of this slot that still have a spell registered (the current one and any
## older ones with shots in the air).
func generations_held(player: int, slot: int) -> int:
	var count: int = 0
	if not _in_range(player, slot):
		return 0
	for generation in SpellLimits.GENERATIONS:
		if _profiles.has(SpellTag.make(player, slot, 0, generation)):
			count += 1
	return count


## Forgets every registered spell and shot count (a new run, and tests).
func clear() -> void:
	_current.fill(-1)
	_profiles.clear()
	_live.clear()
	revoked_tags.clear()


func _in_range(player: int, slot: int) -> bool:
	return player >= 0 and player < SpellLimits.PLAYERS and slot >= 0 and slot < SpellLimits.SLOTS


func _is_current(tag: int) -> bool:
	var index: int = SpellTag.player_of(tag) * SpellLimits.SLOTS + SpellTag.slot_of(tag)
	return _current[index] == SpellTag.generation_of(tag)


func _forget(tag: int) -> void:
	_profiles.erase(tag)
	_live.erase(tag)


## The old generation is no longer current: free the depths that have no shots left.
func _release_generation(player: int, slot: int, generation: int) -> void:
	for depth in SpellLimits.MAX_DEPTH + 1:
		var tag: int = SpellTag.make(player, slot, depth, generation)
		if _live.get(tag, 0) == 0:
			_profiles.erase(tag)


func _component(id: StringName) -> SpellComponent:
	var source: Node = registry if registry != null else get_node_or_null("/root/Registry")
	if source == null:
		return null
	return source.call("get_resource", &"spells", id) as SpellComponent


func _refused(reason: String) -> CompiledSpell:
	var spell := CompiledSpell.new()
	spell.valid = false
	spell.reason = reason
	return spell


## One component of `kind` by id, or null with the reason in `problem[0]`.
func _pick(id: StringName, kind: StringName, problem: PackedStringArray) -> SpellComponent:
	var component: SpellComponent = _component(id)
	if component == null:
		problem.append("Unknown component '%s'." % id)
		return null
	if component.kind() != kind:
		problem.append("'%s' is %s %s, not %s %s." % [id, _article(component.kind()), component.kind(), _article(kind), kind])
		return null
	return component


func _article(word: StringName) -> String:
	return "an" if String(word).left(1) in ["a", "e", "i", "o", "u"] else "a"


func _name_of(component: SpellComponent) -> String:
	return component.display_name if not component.display_name.is_empty() else String(component.id)


func _compile(recipe: Dictionary, depth: int) -> CompiledSpell:
	var problem: PackedStringArray = PackedStringArray()
	var form: FormBase = null
	var element: ElementBase = null
	var trigger: TriggerBase = null
	var modifiers: Array[ModifierBase] = []

	var form_id: StringName = StringName(recipe.get("form", ""))
	if form_id == &"":
		return _refused("A spell needs a form.")
	form = _pick(form_id, &"form", problem) as FormBase
	var element_id: StringName = StringName(recipe.get("element", ""))
	if element_id != &"" and form != null:
		element = _pick(element_id, &"element", problem) as ElementBase
	var modifier_ids: Array = recipe.get("modifiers", [])
	if modifier_ids.size() > SpellLimits.MAX_MODIFIERS:
		return _refused("A spell holds at most %d modifiers." % SpellLimits.MAX_MODIFIERS)
	for id in modifier_ids:
		if problem.is_empty():
			modifiers.append(_pick(StringName(id), &"modifier", problem) as ModifierBase)
	var trigger_id: StringName = StringName(recipe.get("trigger", ""))
	if trigger_id != &"" and problem.is_empty():
		trigger = _pick(trigger_id, &"trigger", problem) as TriggerBase
	if not problem.is_empty():
		return _refused(problem[0])

	var held_recipe: Variant = recipe.get("held")
	var held: CompiledSpell = null
	if held_recipe is Dictionary and not (held_recipe as Dictionary).is_empty():
		if trigger == null:
			return _refused("A held spell needs a trigger to fire it.")
		if depth + 1 > SpellLimits.MAX_DEPTH:
			return _refused("Triggers can hold spells at most %d levels deep." % SpellLimits.MAX_DEPTH)
		held = _compile(held_recipe as Dictionary, depth + 1)
		if not held.valid:
			return held

	var spell := CompiledSpell.new()
	spell.depth = depth
	_apply(spell, form, element, modifiers, trigger)
	spell.held = held
	spell.complexity += 0 if held == null else held.complexity
	return spell


## Fills the numbers: the form's base, then the element, then the modifiers in slot order.
func _apply(spell: CompiledSpell, form: FormBase, element: ElementBase, modifiers: Array[ModifierBase], trigger: TriggerBase) -> void:
	spell.form_id = form.id
	spell.complexity = form.complexity
	var damage: float = form.base_damage
	var mana: float = form.mana_cost
	var cooldown: float = form.cooldown
	var speed: float = form.speed
	var radius: float = form.radius
	var shots: int = form.shots
	var pierce: int = form.pierce
	if element != null:
		spell.element_id = element.id
		spell.complexity += element.complexity
		spell.status_id = element.status_id
		spell.status_duration = element.status_duration
		spell.status_strength = element.status_strength
		spell.tint = element.tint
		damage *= element.damage_scale
	for modifier in modifiers:
		spell.modifier_ids.append(modifier.id)
		spell.complexity += modifier.complexity
		damage *= modifier.damage_mult
		mana *= modifier.mana_mult
		cooldown *= modifier.cooldown_mult
		speed *= modifier.speed_mult
		radius *= modifier.radius_mult
		shots *= modifier.shot_mult
		pierce += modifier.extra_pierce
		match modifier.behaviour:
			ModifierBase.Behaviour.HOMING:
				spell.homing_turn = maxf(spell.homing_turn, modifier.behaviour_strength)
			ModifierBase.Behaviour.CHAIN:
				spell.chain_jumps += int(modifier.behaviour_strength)
	spell.damage = clampi(roundi(damage), 1, SpellLimits.MAX_DAMAGE)
	spell.mana_cost = mana
	spell.cooldown = maxf(cooldown, SpellLimits.MIN_COOLDOWN)
	spell.speed = minf(speed, SpellLimits.MAX_SPEED)
	spell.lifetime = form.lifetime
	spell.radius = minf(radius, SpellLimits.MAX_RADIUS)
	spell.pierce = mini(pierce, SpellLimits.MAX_PIERCE)
	spell.motion = form.motion
	spell.orbit_radius = form.orbit_radius
	spell.ray_length = form.ray_length
	spell.spread = form.spread
	spell.shots_requested = shots
	if shots > SpellLimits.MAX_SHOTS:
		spell.shots_clamped = true
		spell.shots = SpellLimits.MAX_SHOTS
	else:
		spell.shots = shots
	if spell.shots > 1 and spell.spread <= 0.0 and spell.motion != FormBase.Motion.ORBIT:
		spell.spread = SpellLimits.SPLIT_SPREAD
	if trigger != null:
		spell.trigger_id = trigger.id
		spell.complexity += trigger.complexity
		spell.trigger_event = trigger.event
		spell.trigger_interval = trigger.interval
		spell.trigger_max_fires = trigger.max_fires
		if trigger.event == TriggerBase.Event.TIMER:
			spell.trigger_max_fires = mini(trigger.max_fires, SpellLimits.MAX_TIMER_FIRES)


## Writes the description of this spell and, first, of the spells it holds.
func _describe(spell: CompiledSpell) -> void:
	if spell.held != null:
		_describe(spell.held)
	var form: SpellComponent = _component(spell.form_id)
	var parts: PackedStringArray = PackedStringArray()
	var title: String = _name_of(form)
	if spell.element_id != &"":
		title = "%s %s" % [_name_of(_component(spell.element_id)), title]
	parts.append("%s: %d damage" % [title, spell.damage])
	if spell.motion == FormBase.Motion.RAY:
		parts.append("a ray")
	elif spell.shots > 1:
		parts.append("%d shots" % spell.shots)
	else:
		parts.append("1 shot")
	if spell.shots_clamped:
		parts.append("cut from %d to the limit of %d" % [spell.shots_requested, SpellLimits.MAX_SHOTS])
	parts.append("cooldown %s s" % _number(spell.cooldown))
	if spell.mana_cost > 0.0:
		parts.append("%s mana" % _number(spell.mana_cost))
	var text: String = ", ".join(parts) + "."
	if spell.pierce > 0:
		text += " Pierces %d." % spell.pierce
	if spell.homing_turn > 0.0:
		text += " Homing."
	if spell.chain_jumps > 0:
		text += " Chains %d times." % spell.chain_jumps
	if spell.held != null:
		var when: String = "on hit"
		if spell.trigger_event == TriggerBase.Event.EXPIRE:
			when = "when it ends"
		elif spell.trigger_event == TriggerBase.Event.TIMER:
			when = "every %s s" % _number(spell.trigger_interval)
		text += " Then, %s: %s" % [when, spell.held.description]
	spell.description = text


func _number(value: float) -> String:
	return String.num(value, 2)
