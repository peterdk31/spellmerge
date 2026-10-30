class_name Carriers
extends RefCounted
## Finds the carrier of each `FormBase.Motion` (`Carrier`, one script each in this folder). `of`
## answers the compiler and anything that reads a carrier's tables; the spell runtime makes its
## own set with `make_all` and binds them, since a carrier with rows of its own (a beam, a swing,
## a slam) keeps them per runtime.

static var _shared: Array[Carrier] = []


## The carrier of `motion` (the retired slot's, which runs nothing, for one with none).
static func of(motion: int) -> Carrier:
	if _shared.is_empty():
		_shared = make_all()
	if motion < 0 or motion >= _shared.size():
		return _shared[FormBase.Motion._UNUSED_10]
	return _shared[motion]


## A fresh carrier for every motion, indexed by `FormBase.Motion`.
static func make_all() -> Array[Carrier]:
	var all: Array[Carrier] = []
	all.resize(FormBase.Motion.size())
	for carrier: Carrier in [CarrierBolt.new(), CarrierRune.new(), CarrierOrbit.new(), CarrierBeam.new(), CarrierDash.new(), CarrierTeleport.new(), CarrierHook.new(), CarrierSwap.new(), CarrierWall.new(), CarrierRain.new(), CarrierDecoy.new(), CarrierFamiliar.new(), CarrierSwing.new(), CarrierSlam.new()]:
		all[carrier.motion()] = carrier
	for motion in all.size():
		if all[motion] == null:
			all[motion] = Carrier.new()
	return all
