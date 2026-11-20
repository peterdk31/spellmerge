extends RefCounted
## The one maker of the game's 2D batches' MultiMesh (core/README.md, "Batches are never culled").
## Godot culls a MultiMeshInstance2D by the box it read from its MultiMesh at the node's last
## redraw, not by where the instances are now; a batch is drawn every frame without a redraw, so
## with a box worked out from its instances it vanished whole once the camera left where they were
## at first (the shots, then other batches, 2026-11-02). Every MultiMesh made here
## has the world as its box (WORLD); a batch with a box of its own sets it after, and only a box that
## is never stale: one round everywhere its instances can ever be drawn, never one worked out from
## where they are now (`box_of`: a room's rect grown by how far its instances reach past it, so a
## view draws only the rooms it shows; the performance pass, 2026-11-20). `tests/core/test_batches.gd` fails for a script that makes a
## MultiMesh any other way, and for a scene or resource whose MultiMesh has no box.

## A box round all of any world: a batch with it is never culled.
const WORLD := AABB(Vector3(-100000.0, -100000.0, -1.0), Vector3(200000.0, 200000.0, 2.0))


## A new 2D MultiMesh (TRANSFORM_2D) whose box is WORLD; the caller sets the rest.
static func multimesh() -> MultiMesh:
	var made := MultiMesh.new()
	made.transform_format = MultiMesh.TRANSFORM_2D
	made.custom_aabb = WORLD
	return made


## The box of a batch whose instances are only ever drawn inside `rect` grown by `reach` (world
## pixels): a room's batch, culled by the views that do not show it.
static func box_of(rect: Rect2, reach: float = 0.0) -> AABB:
	var box: Rect2 = rect.grow(reach)
	return AABB(Vector3(box.position.x, box.position.y, -1.0), Vector3(box.size.x, box.size.y, 2.0))
