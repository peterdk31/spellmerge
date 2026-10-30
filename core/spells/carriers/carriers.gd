class_name Carriers
extends RefCounted
## Finds each carrier by its id (`Carrier.id`, the `carrier` a form card names: &"bolt", &"beam"...).
## `of` answers the compiler and anything that reads a carrier's tables; the spell runtime makes its
## own set with `make_all` and binds them, since a carrier with rows of its own (a beam, a swing, a
## slam) keeps them per runtime. A carrier is named, never numbered, so adding or removing one is
## its script and its line in `make_all`, and no card's file changes.

static var _shared: Dictionary = {}
static var _none: Carrier = Carrier.new()


## The carrier named `id`, or one that runs nothing (`Carrier`, id &"") for a name no carrier has.
static func of(id: StringName) -> Carrier:
	if _shared.is_empty():
		_shared = make_all()
	return _shared.get(id, _none) as Carrier


## Every carrier's id, in the order `make_all` lists them.
static func ids() -> Array[StringName]:
	if _shared.is_empty():
		_shared = make_all()
	var out: Array[StringName] = []
	for id: StringName in _shared:
		out.append(id)
	return out


## A fresh carrier of every kind, by id, in the order the runtime steps them (a dash's strikes, then
## beams, swings and slams, as before carriers had their own scripts).
static func make_all() -> Dictionary:
	var all: Dictionary = {}
	for carrier: Carrier in [CarrierBolt.new(), CarrierRune.new(), CarrierOrbit.new(), CarrierDash.new(), CarrierTeleport.new(), CarrierBeam.new(), CarrierHook.new(), CarrierSwap.new(), CarrierWall.new(), CarrierRain.new(), CarrierDecoy.new(), CarrierFamiliar.new(), CarrierSwing.new(), CarrierSlam.new()]:
		all[carrier.id()] = carrier
	return all
