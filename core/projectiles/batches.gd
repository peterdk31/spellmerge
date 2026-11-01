extends RefCounted
## The one maker of the game's 2D batches' MultiMesh (core/README.md, "Batches are never culled").
## Godot culls a MultiMeshInstance2D by the box it read from its MultiMesh at the node's last
## redraw, not by where the instances are now; a batch is drawn every frame without a redraw, so
## with a box worked out from its instances it vanished whole once the camera left where they were
## at first (the shots, then the horde's swarmers and gems, 2026-11-02). Every MultiMesh made here
## has the world as its box (WORLD); a batch with a box of its own (the projectile manager's,
## fitted to the room) sets it after. `tests/core/test_batches.gd` fails for a script that makes a
## MultiMesh any other way, and for a scene or resource whose MultiMesh has no box.

## A box round all of any world: a batch with it is never culled.
const WORLD := AABB(Vector3(-100000.0, -100000.0, -1.0), Vector3(200000.0, 200000.0, 2.0))


## A new 2D MultiMesh (TRANSFORM_2D) whose box is WORLD; the caller sets the rest.
static func multimesh() -> MultiMesh:
	var made := MultiMesh.new()
	made.transform_format = MultiMesh.TRANSFORM_2D
	made.custom_aabb = WORLD
	return made
