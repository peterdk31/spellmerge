extends RefCounted
## What a hashed area is reported as in the benchmarks' costliest areas (prop_cost_runner.gd,
## stress_runner.gd): the parts of an area kept by actor id together ("Spells parts",
## `SimHash.ActorPart`), anything else by its name.


static func of(name: String, object: Object) -> String:
	if object is SimHash.ActorPart and (object as SimHash.ActorPart).id >= 0:
		return "%s parts" % (object as SimHash.ActorPart).area_name
	return name
