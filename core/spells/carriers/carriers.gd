class_name Carriers
extends RefCounted
## Finds each carrier by its id (`Carrier.id`, the `carrier` a form card names: &"bolt", &"beam"...).
## `of` answers the compiler and anything that reads a carrier's tables; the spell runtime makes its
## own set with `make_all` and binds them, since a carrier with rows of its own (a beam, a swing, a
## slam) keeps them per runtime. A carrier is named, never numbered, and found by its script, so
## adding or removing one is its script in this folder (a `class_name` extending `Carrier`, with an
## `id`), and no other file changes.

## The folder of the carrier scripts. Each script here whose class extends `Carrier` and has an id
## is a carrier (the bases, `Carrier`, `CarrierMove` and `CarrierEntity`, have none).
const FOLDER: String = "res://core/spells/carriers/"

static var _shared: Dictionary = {}
static var _none: Carrier = Carrier.new()


## The carrier named `id`, or one that runs nothing (`Carrier`, id &"") for a name no carrier has.
static func of(id: StringName) -> Carrier:
	if _shared.is_empty():
		_shared = make_all()
	return _shared.get(id, _none) as Carrier


## True when `id` names a carrier (&"" names none: it is the id of the one that runs nothing).
static func exists(id: StringName) -> bool:
	if _shared.is_empty():
		_shared = make_all()
	return _shared.has(id)


## Every carrier's id, in the order `make_all` lists them.
static func ids() -> Array[StringName]:
	if _shared.is_empty():
		_shared = make_all()
	var out: Array[StringName] = []
	for id: StringName in _shared:
		out.append(id)
	return out


## A fresh carrier of every kind, by id, in the order the runtime steps and ends them
## (`Carrier.step_order`, then by id).
static func make_all() -> Dictionary:
	var bases: Dictionary = {}
	var paths: Dictionary = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		bases[entry["class"]] = entry["base"]
		if String(entry["path"]).begins_with(FOLDER):
			paths[entry["class"]] = entry["path"]
	var found: Array[Carrier] = []
	for name: StringName in paths:
		if not _extends_carrier(name, bases):
			continue
		var script: GDScript = load(paths[name]) as GDScript
		var carrier: Carrier = script.new() as Carrier if script != null and script.can_instantiate() else null
		if carrier != null and carrier.id() != &"":
			found.append(carrier)
	found.sort_custom(_runs_before)
	var all: Dictionary = {}
	for carrier in found:
		all[carrier.id()] = carrier
	return all


## True when the global class `name` extends `Carrier` (`bases`: class -> its base class).
static func _extends_carrier(name: StringName, bases: Dictionary) -> bool:
	var at: StringName = bases.get(name, &"")
	while at != &"":
		if at == &"Carrier":
			return true
		at = bases.get(at, &"")
	return false


static func _runs_before(a: Carrier, b: Carrier) -> bool:
	if a.step_order() != b.step_order():
		return a.step_order() < b.step_order()
	return String(a.id()) < String(b.id())
