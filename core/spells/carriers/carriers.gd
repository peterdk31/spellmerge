class_name Carriers
extends RefCounted
## Finds each carrier by its id (`Carrier.id`, the `carrier` a carrier card names: &"atom", &"beam"...).
## `of` answers the compiler and anything that reads a carrier's tables; the spell runtime makes its
## own set with `make_all` and binds them, since a carrier with rows of its own (a beam, a swing, a
## slam) keeps them per runtime. A carrier is named, never numbered, and found by its script, so
## adding or removing one is its script in this folder (a `class_name` extending `Carrier`, with an
## `id`), and no other file changes.

## The folder of the carrier scripts. Each script here whose class extends `Carrier` and has an id
## is a carrier (the bases, `Carrier`, `CarrierMove`, `CarrierEntity` and `CarrierPulse`, have none).
const FOLDER: String = "res://core/spells/carriers/"

## The Pulse card's carrier (docs/CARRIERS.md, "Pulse: a strike round what casts it"): `PULSE`, the id
## the card names, round the caster in a cast's own group; in a payload the compiler takes
## `PULSE_BEARER` (round what fired it, a body or a shot) or `PULSE_POINT` (round the point it began
## at) in its place (`placed`). No card names those two, so they are not in `ids`.
const PULSE: StringName = &"pulse"
const PULSE_BEARER: StringName = &"pulse_bearer"
const PULSE_POINT: StringName = &"pulse_point"

## Not state: the carriers made once per script, shared by every runtime (core/sim/README.md).
const DERIVED: Array[StringName] = [&"_shared", &"_none"]

static var _shared: Dictionary = {}
static var _none: Carrier = Carrier.new()


## The carrier named `id`, or one that runs nothing (`Carrier`, id &"") for a name no carrier has.
static func of(id: StringName) -> Carrier:
	if _shared.is_empty():
		_shared = make_all()
	return _shared.get(id, _none) as Carrier


## The carrier a carrier card naming `id` fires in a group it is read in (`payload`: a trigger's), cast
## by `by` (the `Carrier.BY_*` bits of `Carrier.payload_cast_by`): the carrier of that id, except
## that the Pulse card's is round what casts it: `PULSE` in a cast's own group; in a payload
## `PULSE_BEARER` when a body or a live shot may cast it, else `PULSE_POINT`.
static func placed(id: StringName, payload: bool, by: int = Carrier.BY_POINT) -> Carrier:
	if id != PULSE or not payload:
		return of(id)
	return of(PULSE_BEARER if by & (Carrier.BY_BODY | Carrier.BY_SHOT) != 0 else PULSE_POINT)


## True when `id` is one of the Pulse card's carriers.
static func is_pulse(id: StringName) -> bool:
	return id == PULSE or id == PULSE_BEARER or id == PULSE_POINT


## True when `id` names a carrier a carrier card may fire (&"" names none: it is the id of the one that
## runs nothing; the Pulse card's payload carriers are named by no card).
static func exists(id: StringName) -> bool:
	if _shared.is_empty():
		_shared = make_all()
	return _shared.has(id) and id != PULSE_BEARER and id != PULSE_POINT


## The id of every carrier a carrier card may fire, in the order `make_all` lists them (the Pulse card's
## payload carriers left out).
static func ids() -> Array[StringName]:
	if _shared.is_empty():
		_shared = make_all()
	var out: Array[StringName] = []
	for id: StringName in _shared:
		if exists(id):
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
