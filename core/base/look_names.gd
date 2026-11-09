class_name LookNames
extends RefCounted
## The names of the shots' looks: the particle styles a card makes its shots give off (staffs B6a;
## the LOOK_* kinds of `core/projectiles/projectile_manager.gd`, which the shaders and the native
## kernel read as numbers). A card names its look (`look_id = &"curl"`), a mote or mark kind the
## looks it belongs to (`look_ids`), and the engine reads the number through `layer_of`, so content
## never carries a number (owner, 2026-11-09: "We should work on giving these names instead of
## numbers"). `tests/core/test_look_names.gd` checks the table against the manager's constants.

## Each look's name, at its number: `plain` (0) is a shot with no look of its cards (a mote kind
## may belong to it; a card with no look leaves `look_id` empty).
const NAMES: Array[StringName] = [
	&"plain", &"embers", &"flecks", &"gusts", &"pull", &"sparks", &"motes", &"glints", &"streaks",
	&"burst", &"orbiters", &"weave", &"glitter", &"hops", &"wake", &"weight", &"ripple", &"curl",
	&"zig", &"double", &"converge", &"drift",
]


## The number of the look `id` (0 for empty, `plain`, or a name that is no look; `known` tells them
## apart).
static func layer_of(id: StringName) -> int:
	var at: int = NAMES.find(id)
	return at if at > 0 else 0


## The name of look number `layer` (empty for 0 or a number that is no look).
static func name_of(layer: int) -> StringName:
	return NAMES[layer] if layer > 0 and layer < NAMES.size() else &""


## True for a name that is a look (`plain` too).
static func known(id: StringName) -> bool:
	return NAMES.has(id)


## The numbers of the looks `ids`, in order (`plain` is 0; a name that is no look is left out).
static func layers_of(ids: Array[StringName]) -> PackedInt32Array:
	var layers := PackedInt32Array()
	for id in ids:
		if NAMES.has(id):
			layers.append(NAMES.find(id))
	return layers


## The names of the look numbers `layers`, in order (0 is `plain`; a number that is no look is left
## out).
static func names_of(layers: PackedInt32Array) -> Array[StringName]:
	var ids: Array[StringName] = []
	for layer in layers:
		if layer >= 0 and layer < NAMES.size():
			ids.append(NAMES[layer])
	return ids
