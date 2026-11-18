extends RefCounted
## Steps a room's spawning enemies past their spawn (enemy spawning EA3,
## docs/milestones/enemy-spawning.md, "Tests that need a look"): for the tests that hurt, kill or
## count enemies right after a room starts, which would otherwise hit bodies that are not there yet.
## Each spawning body is stepped as the tick steps it (`Actor.tick_step`, at the tick's 60 a second)
## until it has landed; the tick it lands is its one step as a standing body. Bosses never spawn in, so
## they are left as they are. Since EA5 a room's enemies come in groups as the room gets quiet:
## `land(flow)` first calls every group still to come (`Flow.stand_all_now`), so the whole room stands.
##
##     const Spawns := preload("res://tests/support/spawning.gd")
##     Spawning.land(flow)              # the room's enemies (`Flow._enemies`), its queue too
##     Spawning.land_bodies(bodies)     # any bodies

const STEP: float = 1.0 / 60.0


## Every enemy still to come in `flow`'s room starts spawning (`Flow.stand_all_now`), then every one
## of its enemies (its `_enemies`) that spawns in is stepped until it has landed.
static func land(flow: Node) -> void:
	if flow.has_method(&"stand_all_now"):
		flow.call(&"stand_all_now")
	land_bodies(flow.get("_enemies") as Array)


## Every body of `bodies` that spawns in is stepped until it has landed.
static func land_bodies(bodies: Array) -> void:
	for node: Variant in bodies:
		if not is_instance_valid(node):
			continue
		var body := node as Actor
		if body == null or not body.is_inside_tree():
			continue
		while body.is_spawning():
			body.tick_step(STEP)
