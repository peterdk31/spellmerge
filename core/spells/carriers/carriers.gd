class_name Carriers
extends RefCounted
## Finds each carrier by its id (`Carrier.id`, the `carrier` a carrier card names: &"atom", &"beam"...).
## `of` answers the compiler and anything that reads a carrier's tables; the spell runtime makes its
## own set with `make_all` and binds them, since a carrier with rows of its own (a beam, a swing, a
## slam) keeps them per runtime. A carrier is named, never numbered, and found by its script, so
## adding or removing one is its script in this folder (a `class_name` extending `Carrier`, with an
## `id`), and no other file changes.

## The folder of the carrier scripts. Each script here whose class extends `Carrier` and has an id
## is a carrier (the bases, `Carrier`, `CarrierMove`, `CarrierEntity` and `CarrierFallback`, have none).
const FOLDER: String = "res://core/spells/carriers/"

## The three fallback carriers (docs/CARRIERS.md, "The fallback carriers"): what the cards a group
## read with no carrier after them land on: the caster for a cast's own group; for a payload, what
## fired it (a body or a shot) when one may have, else the point it began at. No carrier card fires
## them, so they are not in `ids` and a carrier card may not name them.
const ON_CASTER: StringName = &"caster"
const ON_BEARER: StringName = &"bearer"
const AT_POINT: StringName = &"point"

## Not state: the carriers made once per script, shared by every runtime (core/sim/README.md).
const DERIVED: Array[StringName] = [&"_shared", &"_none"]

static var _shared: Dictionary = {}
static var _none: Carrier = Carrier.new()


## The carrier named `id`, or one that runs nothing (`Carrier`, id &"") for a name no carrier has.
static func of(id: StringName) -> Carrier:
	if _shared.is_empty():
		_shared = make_all()
	return _shared.get(id, _none) as Carrier


## The fallback carrier the cards with no carrier after them land on: `ON_CASTER` in a cast's own
## group; in a payload (`payload`), `ON_BEARER` when a body or a live shot may cast it (`by`, the
## `Carrier.BY_*` bits of `Carrier.payload_cast_by`), else `AT_POINT`.
static func fallback(payload: bool, by: int = Carrier.BY_POINT) -> Carrier:
	if not payload:
		return of(ON_CASTER)
	return of(ON_BEARER if by & (Carrier.BY_BODY | Carrier.BY_SHOT) != 0 else AT_POINT)


## True when `id` is one of the fallback carriers.
static func is_fallback(id: StringName) -> bool:
	return id == ON_CASTER or id == ON_BEARER or id == AT_POINT


## True when `id` names a carrier a carrier card may fire (&"" names none: it is the id of the one that
## runs nothing; the fallback carriers are fired by no card).
static func exists(id: StringName) -> bool:
	if _shared.is_empty():
		_shared = make_all()
	return _shared.has(id) and not is_fallback(id)


## The id of every carrier a carrier card may fire, in the order `make_all` lists them (the fallback
## carriers left out).
static func ids() -> Array[StringName]:
	if _shared.is_empty():
		_shared = make_all()
	var out: Array[StringName] = []
	for id: StringName in _shared:
		if not is_fallback(id):
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
