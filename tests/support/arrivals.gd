extends RefCounted
## Steps a room's arriving enemies past their arrival (enemy arrivals EA3,
## docs/milestones/enemy-arrivals.md, "Tests that need a look"): for the tests that hurt, kill or
## count enemies right after a room starts, which would otherwise hit bodies that are not there yet.
## Each arriving body is stepped as the tick steps it (`Actor.tick_step`, at the tick's 60 a second)
## until it has landed; the tick it lands is its one step as a standing body. Bosses never arrive, so
## they are left as they are.
##
##     const Arrivals := preload("res://tests/support/arrivals.gd")
##     Arrivals.land(flow)              # the room's enemies (`Flow._enemies`)
##     Arrivals.land_bodies(bodies)     # any bodies

const STEP: float = 1.0 / 60.0


## Every enemy of `flow`'s room (its `_enemies`) that arrives is stepped until it has landed.
static func land(flow: Node) -> void:
	land_bodies(flow.get("_enemies") as Array)


## Every body of `bodies` that arrives is stepped until it has landed.
static func land_bodies(bodies: Array) -> void:
	for node: Variant in bodies:
		if not is_instance_valid(node):
			continue
		var body := node as Actor
		if body == null or not body.is_inside_tree():
			continue
		while body.is_arriving():
			body.tick_step(STEP)
