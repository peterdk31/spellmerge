extends "res://gameplay/feel/spawn_motions/spawn_motion.gd"
## The motion `rise` (enemy spawning EA2's look, docs/milestones/enemy-spawning.md, "The look"; spawn
## styles: its code moved here unchanged, docs/milestones/spawn-styles.md): through the mark the
## body is all under the floor, then it comes up out of the mark, drawn shifted down by whole pixels
## from its full height (`body_height`, and the rows its art has under its feet, `body_bottom`) to 0
## at the end of its spawn, and cut off at the line of its lowest row, so what is still under the
## floor is not drawn and nothing of it appears in one jump as it lands. Its own sprite and pose all
## the way: no fade, no blur, no scale.
##
## The cut (checked against the world's y-sort and the light pass on a virtual display before it was
## built, EA2): the body's root is made a clip parent (`CanvasItem.clip_children`) whose own canvas
## item draws one rect, above that line, as the mask, and each of its direct drawn children (its
## sprite, its face, its look; not a top-level one) is drawn shifted down by the rise
## (`RenderingServer.canvas_item_set_transform`, re-set every frame), so a part's own parts go with
## it. That is one cut for any body, layered (`BodyPart`) or not. The root itself is never moved: the
## world's y-sort orders it by its own place, so a rising body stays behind a wizard standing just in
## front of its mark (a shifted root would sort as if its feet were lower and draw over that wizard),
## and the light pass, drawn over the world, lights it as any body. Nothing in the simulation reads
## any of it: its position and its parts' are untouched. A body put back gets its children's own
## transforms back and is no clip parent any more.
##
## Nothing here allocates while bodies spawn in: the dictionaries of the bodies it cut grow only when a
## body first spawns in.

## The bodies cut (by instance id): how far below their place each was drawn at its last cut, and how
## far below its feet its mask reached (`body_bottom`), in pixels.
var _drawn: Dictionary[int, Vector2] = {}


## How far below its place a body `height` pixels tall is drawn at `share` of its spawn as `style`
## times it, in whole pixels: all of it under the floor through the mark, then up to 0 as it lands.
static func shift(height: float, share: float, style: SpawnStyle) -> float:
	if share < style.mark_end:
		return height
	var t: float = clampf((share - style.mark_end) / (1.0 - style.mark_end), 0.0, 1.0)
	return roundf(height * (1.0 - t))


## One spawning body cut at its feet's line (the lowest row of its art) and its parts shifted by its rise.
func apply(body: Actor, share: float, style: SpawnStyle) -> void:
	var key: int = body.get_instance_id()
	if not _drawn.has(key):
		body.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var size: float = maxf(absf(body.size), 0.01)
	var bottom: float = body_bottom(body)
	var by: float = shift(height_of(body, key) + bottom, share, style)
	_drawn[key] = Vector2(by, bottom)
	shift_parts(body, Vector2(0.0, by / size))
	var item: RID = body.get_canvas_item()
	RenderingServer.canvas_item_clear(item)
	# The mask: everything above the line (in the body's own pixels). Always drawn, every frame: a
	# clip parent that draws nothing clips nothing. Through the mark the parts are shifted their whole
	# height and more, so all of them are under the line.
	RenderingServer.canvas_item_add_rect(item, mask_rect(bottom, size), Color.WHITE)


## The body spawns in no more (or went): its parts' own transforms back, and no clip parent any more.
func put_back(key: int, body: Actor) -> void:
	if body != null:
		body.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
		RenderingServer.canvas_item_clear(body.get_canvas_item())
		shift_parts(body, Vector2.ZERO)
	_drawn.erase(key)
	forget(key)


## What it drew `body` as at its last cut: how far below its place, and how far below its feet its
## mask reached (empty: not cut; tests).
func look_of(body: Actor) -> PackedInt32Array:
	var key: int = body.get_instance_id()
	if not _drawn.has(key):
		return PackedInt32Array()
	return PackedInt32Array([int(_drawn[key].x), int(_drawn[key].y)])


## How far below its feet `body`'s mask reached at its last cut, in pixels (-1: not cut; tests).
func bottom_of(body: Actor) -> float:
	return _drawn.get(body.get_instance_id(), Vector2(-1.0, -1.0)).y


## How far below its place `body` was drawn at its last cut, in pixels (-1: not cut; tests).
func shift_of(body: Actor) -> float:
	return _drawn.get(body.get_instance_id(), Vector2(-1.0, -1.0)).x
