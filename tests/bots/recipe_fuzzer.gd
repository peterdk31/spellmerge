extends RefCounted
## Seeded random spell recipes for the bots and the spell fuzz test (M2 part 20). Give it
## the component ids by kind and a `RandomNumberGenerator`; the same seed always gives the
## same recipes, so a failure can be replayed from its seed.
##
## A recipe is the dictionary of core/spells (`form`, `element`, `modifiers`, `trigger`,
## `held`). `candidate` may build something the compiler refuses (that is what the fuzz test
## feeds it); `random_recipe` keeps trying until the `compiles` callable says yes.
##
## `steps` turns a recipe into the `build_change_requested` calls a person would make, in an
## order in which every prefix compiles: form, element, modifiers, trigger, then the held
## spell one level down.
##
## Example:
##   var fuzzer := FuzzerScript.new({&"form": [&"bolt"], &"element": [&"fire"]})
##   var recipe := fuzzer.random_recipe(rng, func(r: Dictionary) -> bool: return Spells.compile(r).valid)

const SLOT_FORM: int = 0
const SLOT_ELEMENT: int = 1
const SLOT_FIRST_MODIFIER: int = 2
const SLOT_TRIGGER: int = 5
## Tries before `random_recipe` gives up and returns the plainest spell.
const ATTEMPTS: int = 40
## Chance (percent) of an element, of each modifier slot, and of a trigger.
const ELEMENT_CHANCE: int = 75
const MODIFIER_CHANCE: int = 50
const TRIGGER_CHANCE: int = 45

var _ids: Dictionary = {}


## `ids` maps a kind (`&"form"`, `&"element"`, `&"modifier"`, `&"trigger"`) to its ids.
func _init(ids: Dictionary) -> void:
	for kind: StringName in ids:
		var list: Array[StringName] = []
		for id: StringName in ids[kind]:
			list.append(id)
		_ids[kind] = list


## True when there is a form to build with.
func can_build() -> bool:
	return not (_ids.get(&"form", []) as Array).is_empty()


## A random recipe that may or may not compile. `depth` is how deep a held spell is.
func candidate(rng: RandomNumberGenerator, depth: int = 0) -> Dictionary:
	var recipe: Dictionary = {}
	var forms: Array = _ids.get(&"form", [])
	if forms.is_empty():
		return recipe
	recipe["form"] = _pick(rng, forms)
	var elements: Array = _ids.get(&"element", [])
	if not elements.is_empty() and rng.randi_range(1, 100) <= ELEMENT_CHANCE:
		recipe["element"] = _pick(rng, elements)
	var pool: Array = (_ids.get(&"modifier", []) as Array).duplicate()
	var modifiers: Array[StringName] = []
	for slot in 3:
		if pool.is_empty() or rng.randi_range(1, 100) > MODIFIER_CHANCE:
			continue
		var at: int = rng.randi_range(0, pool.size() - 1)
		modifiers.append(pool[at])
		pool.remove_at(at)
	if not modifiers.is_empty():
		recipe["modifiers"] = modifiers
	var triggers: Array = _ids.get(&"trigger", [])
	if not triggers.is_empty() and rng.randi_range(1, 100) <= TRIGGER_CHANCE / (depth + 1):
		recipe["trigger"] = _pick(rng, triggers)
		recipe["held"] = candidate(rng, depth + 1)
	return recipe


## A random recipe for which `compiles` (Callable(recipe: Dictionary) -> bool) is true; just
## the first form when none was found in ATTEMPTS tries.
func random_recipe(rng: RandomNumberGenerator, compiles: Callable) -> Dictionary:
	for attempt in ATTEMPTS:
		var recipe: Dictionary = candidate(rng)
		if not recipe.is_empty() and bool(compiles.call(recipe)):
			return recipe
	var forms: Array = _ids.get(&"form", [])
	return {"form": forms[0]} if not forms.is_empty() else {}


## The build calls for `recipe` as `[path: PackedInt32Array, slot: int, id: StringName]`.
## `top` is the prepared spell (0 or 1) it is built into.
func steps(recipe: Dictionary, top: int) -> Array:
	var out: Array = []
	_add_steps(recipe, PackedInt32Array([top]), out)
	return out


## The calls that empty a prepared spell: every slot but the form, trigger last (which also
## drops the held spell). Each of them leaves a spell that compiles.
func clear_steps(top: int) -> Array:
	var out: Array = []
	for slot: int in [SLOT_FIRST_MODIFIER + 2, SLOT_FIRST_MODIFIER + 1, SLOT_FIRST_MODIFIER, SLOT_TRIGGER, SLOT_ELEMENT]:
		out.append([PackedInt32Array([top]), slot, &""])
	return out


func _add_steps(node: Dictionary, path: PackedInt32Array, out: Array) -> void:
	out.append([path, SLOT_FORM, StringName(node.get("form", &""))])
	if node.has("element"):
		out.append([path, SLOT_ELEMENT, StringName(node["element"])])
	var modifiers: Array = node.get("modifiers", [])
	for at in modifiers.size():
		out.append([path, SLOT_FIRST_MODIFIER + at, StringName(modifiers[at])])
	if node.has("trigger"):
		out.append([path, SLOT_TRIGGER, StringName(node["trigger"])])
		var held: Variant = node.get("held")
		if held is Dictionary:
			var deeper: PackedInt32Array = path.duplicate()
			deeper.append(0)
			_add_steps(held as Dictionary, deeper, out)


func _pick(rng: RandomNumberGenerator, list: Array) -> StringName:
	return list[rng.randi_range(0, list.size() - 1)]
