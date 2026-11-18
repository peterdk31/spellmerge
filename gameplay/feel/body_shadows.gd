extends MultiMeshInstance2D
## Bodies' shadows (docs/milestones/atmosphere.md, C): every body that walks (a wizard, an enemy, a
## boss: an actor with a Mover) stands on a flat hard shadow, cast a few pixels away from the light
## near it, so a lit room has depth and a body reads as standing on the floor. One batch (made by
## `Batches.multimesh()`), one row a body, drawn by `body_shadow.gdshader` under every body (the
## spectacle's MARK_Z, after the floor marks). The spectacle's, made and freed with the spell light
## (only while the "Spell light" setting is on).
##
## - **Where the light is** is handed over each frame (`begin_lights`, `add_lights`: rows in the spot
##   rows' layout, `SpellLight.write_spot_row`: the room's spots and the carried lights); this knows
##   nothing of how they are drawn. Shots, flashes and cues cast no body shadow (thousands of rows;
##   they come and go faster than a shadow eases).
## - **Away from the light:** each light within its reach of the feet pulls the shadow away from it as
##   much as it lights the feet (its strength times the light's falloff, `light.gdshader`), less what
##   blocks it (`LightBlockers.shade`: a body behind a pillar casts no shadow from the candle the
##   pillar hides), and the pulls add up, so two lights either side share the shadow and it never
##   flips from one to the other. It reaches LENGTH px at most (from FULL_AT light). A body's own
##   carried light casts none (it is over its head: `add_lights`' owners).
## - **Smooth:** the cast eases toward where it should be at LENGTH px per EASE_SECONDS, drawn in
##   whole pixels, so it moves a pixel at a time as lights move. A body that comes takes its cast at
##   once (it comes with it), and as it falls into a hole its shadow shrinks with it (`fall_share`).
## - **It takes the drawn shadow's place:** a body's look may draw a soft shadow of its own (a staff's,
##   the group `LightSpot.DRAWN_SHADOW`); those are hidden while this node is in the tree and shown
##   again when it leaves, so a body has one shadow. Its contact shape is the same (RADIUS_PAD past
##   the body's footprint, FLAT times as deep, DROP below the feet), so with no light near it is the
##   shadow the body had.

const ActorsScript := preload("res://core/actors/actors.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const LightBlockersScript := preload("res://gameplay/feel/light_blockers.gd")
const SHADER: Shader = preload("res://gameplay/feel/body_shadow.gdshader")

## Floats a row holds (a 2D MultiMesh row with colours and custom data).
const STRIDE: int = 16
## Where a light row holds its reach and its middle (`SpellLight.write_spot_row`'s layout).
const ROW_REACH: int = 0
const ROW_X: int = 3
const ROW_Y: int = 7
## The most light rows a frame looks at (the room's spots and four carried lights are far fewer).
const LIGHTS: int = 128
## How far a shadow is cast at most (px), and from how much light at the feet (a light's strength
## times its falloff there) it is cast that far.
const LENGTH: float = 3.0
const FULL_AT: float = 0.2
## Light below this at the feet casts nothing.
const FAINT: float = 0.01
## How long the cast takes to move LENGTH px (s): a pixel about every 5 frames.
const EASE_SECONDS: float = 0.25
## The shadow's shape: its radius past the body's footprint (px), how flat it lies (its depth over
## its width) and how far below the feet it is: the staff's drawn shadow's (gameplay/player/
## staff_look.gd: a 7 px radius round a wizard's 6 px footprint, 0.4 flat, 2 below).
const RADIUS_PAD: float = 1.0
const FLAT: float = 0.4
const DROP: float = 2.0
## Its colour: the Outline's (docs/STYLE.md, the deepest shadow), a little denser than the staff's
## drawn shadow (black at 0.35), since a room lit by spell light is darker round it.
const COLOUR: Color = Color(0.078, 0.071, 0.122, 0.45)
## A shadow smaller than this radius (px) is not drawn (a body nearly gone down a hole).
const SMALLEST: float = 1.0
## How far outside the view a body's shadow is still worked out (px).
const VIEW_MARGIN: float = 32.0

## How many shadows are drawn. Read only.
var count: int = 0
## Each actor's cast as drawn (px, before rounding), and the step it last had a shadow in (one that
## had none the step before takes its cast at once). Read only.
var cast: PackedVector2Array = PackedVector2Array()
var _stamp: PackedInt32Array = PackedInt32Array()
var _steps: int = 0
## The rows (grown, never shrunk) and the open ids' buffer.
var _rows: PackedFloat32Array = PackedFloat32Array()
var _ids: PackedInt32Array = PackedInt32Array()
## This frame's lights: where, how far they reach, how bright, and who carries each (NONE: nobody).
var _light_at: PackedVector2Array = PackedVector2Array()
var _light_reach: PackedFloat32Array = PackedFloat32Array()
var _light_strength: PackedFloat32Array = PackedFloat32Array()
var _light_owner: PackedInt32Array = PackedInt32Array()
## Where each is lit from (`LightBlockers.lit_as`) and the boxes that come near it (a bit each; none:
## it is never blocked), worked out once a step.
var _light_from: PackedVector2Array = PackedVector2Array()
var _light_near: PackedInt32Array = PackedInt32Array()
var _light_count: int = 0
## Feel's clock at the last step (-1: none yet).
var _last: float = -1.0


func _init(z: int) -> void:
	name = "BodyShadows"
	z_index = z
	cast.resize(ActorsScript.ACTORS)
	_stamp.resize(ActorsScript.ACTORS)
	_stamp.fill(-1)
	_light_at.resize(LIGHTS)
	_light_reach.resize(LIGHTS)
	_light_strength.resize(LIGHTS)
	_light_owner.resize(LIGHTS)
	_light_from.resize(LIGHTS)
	_light_near.resize(LIGHTS)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var made: MultiMesh = BatchesScript.multimesh()
	made.use_colors = true
	made.use_custom_data = true
	made.mesh = quad
	made.instance_count = 0
	made.visible_instance_count = 0
	multimesh = made
	var shading := ShaderMaterial.new()
	shading.shader = SHADER
	shading.set_shader_parameter(&"flatness", FLAT)
	material = shading


func _enter_tree() -> void:
	var tree: SceneTree = get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	_show_drawn(tree, false)


func _exit_tree() -> void:
	var tree: SceneTree = get_tree()
	if tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)
	_show_drawn(tree, true)


func _on_node_added(node: Node) -> void:
	if node.is_in_group(LightSpot.DRAWN_SHADOW):
		_show_node(node, false)


func _show_drawn(tree: SceneTree, shown: bool) -> void:
	for node: Node in tree.get_nodes_in_group(LightSpot.DRAWN_SHADOW):
		_show_node(node, shown)


func _show_node(node: Node, shown: bool) -> void:
	var item := node as CanvasItem
	if item != null:
		item.visible = shown


## This frame's lights begin: none until `add_lights`.
func begin_lights() -> void:
	_light_count = 0


## `n` light rows of `rows` (STRIDE floats each, in the spot rows' layout: reach, middle), each as
## bright as its float `strength_at` says; `owners`, when not empty, the actor carrying each (its
## shadow is not cast by it). Read, not kept.
func add_lights(rows: PackedFloat32Array, n: int, strength_at: int, owners: PackedInt32Array) -> void:
	for at in mini(n, rows.size() / STRIDE):
		if _light_count >= LIGHTS:
			return
		var i: int = at * STRIDE
		var strength: float = rows[i + strength_at]
		var reach: float = rows[i + ROW_REACH]
		if strength <= 0.0 or reach <= 0.0:
			continue
		_light_at[_light_count] = Vector2(rows[i + ROW_X], rows[i + ROW_Y])
		_light_reach[_light_count] = reach
		_light_strength[_light_count] = strength
		_light_owner[_light_count] = owners[at] if at < owners.size() else ActorsScript.NONE
		_light_count += 1


## Once a frame at Feel's clock `now` (real seconds): every body that walks in `table` (the actor
## table; null: none) within the view `view` (empty: anywhere) gets its shadow, cast from this
## frame's lights, blocked by `blockers` (null: nothing blocks).
func step(table: ActorsScript, now: float, view: Rect2, blockers: LightBlockersScript) -> void:
	var delta: float = clampf(now - _last, 0.0, 0.25) if _last >= 0.0 else 0.0
	_last = now
	var most: float = LENGTH * delta / EASE_SECONDS
	var near: Rect2 = view.grow(VIEW_MARGIN)
	for k in _light_count:
		_light_near[k] = blockers.near(_light_at[k], _light_reach[k]) if blockers != null and blockers.count > 0 else 0
		if _light_near[k] != 0:
			_light_from[k] = LightBlockersScript.lit_as(_light_at[k], blockers.boxes, blockers.bodies, blockers.count)
	var open: int = table.open_ids(_ids) if table != null else 0
	var out: int = 0
	_steps += 1
	for at in open:
		var id: int = _ids[at]
		var body := table.node_of(id) as Actor
		if body == null or body.mover == null or body.footprint == null or not body.is_inside_tree() or body.is_queued_for_deletion() or not body.is_visible_in_tree():
			continue
		var feet: Vector2 = body.global_position + Vector2(0.0, DROP)
		if view.has_area() and not near.has_point(feet):
			continue
		var want: Vector2 = _cast_from(feet, id, blockers)
		if _stamp[id] != _steps - 1:
			cast[id] = want
		else:
			cast[id] = cast[id].move_toward(want, most)
		_stamp[id] = _steps
		var radius: float = (body.footprint.radius + RADIUS_PAD) * (1.0 - body.fall_share())
		if radius < SMALLEST:
			continue
		_write_row(out, feet.round(), cast[id].round(), radius)
		out += 1
	count = out
	multimesh.visible_instance_count = out
	if out > 0:
		multimesh.buffer = _rows


## Where the shadow of a body with its feet at `feet` (and the id `id`) should be cast this frame
## (px, at most LENGTH long): away from each light near, as much as it lights the feet (the lights'
## blocking worked out in `step`).
func _cast_from(feet: Vector2, id: int, blockers: LightBlockersScript) -> Vector2:
	var pull := Vector2.ZERO
	for k in _light_count:
		if _light_owner[k] == id:
			continue
		var away: Vector2 = feet - _light_at[k]
		var reach: float = _light_reach[k]
		var far_sq: float = away.length_squared()
		if far_sq >= reach * reach or far_sq < 0.25:
			continue
		var far: float = sqrt(far_sq)
		var fall: float = 1.0 - far / reach
		var light: float = _light_strength[k] * fall * fall
		if light < FAINT:
			continue
		if blockers != null and _light_near[k] != 0:
			light *= 1.0 - blockers.shade_from(feet, _light_from[k], _light_near[k])
		pull += away / far * light
	var strength: float = pull.length()
	if strength < FAINT:
		return Vector2.ZERO
	return pull / strength * LENGTH * minf(strength / FULL_AT, 1.0)


## Row `at`: a shadow at `feet` (whole px), cast by `by` (whole px), `radius` px wide.
func _write_row(at: int, feet: Vector2, by: Vector2, radius: float) -> void:
	if multimesh.instance_count <= at:
		var room: int = maxi(at + 1, multimesh.instance_count * 2)
		room = maxi(room, 16)
		multimesh.instance_count = room
		_rows.resize(room * STRIDE)
	var size := Vector2(radius * 2.0 + absf(by.x) + 2.0, radius * 2.0 * FLAT + absf(by.y) + 2.0)
	var middle: Vector2 = feet + by * 0.5
	var i: int = at * STRIDE
	_rows[i] = size.x
	_rows[i + 1] = 0.0
	_rows[i + 2] = 0.0
	_rows[i + 3] = middle.x
	_rows[i + 4] = 0.0
	_rows[i + 5] = size.y
	_rows[i + 6] = 0.0
	_rows[i + 7] = middle.y
	_rows[i + 8] = COLOUR.r
	_rows[i + 9] = COLOUR.g
	_rows[i + 10] = COLOUR.b
	_rows[i + 11] = COLOUR.a
	_rows[i + 12] = by.x
	_rows[i + 13] = by.y
	_rows[i + 14] = radius
	_rows[i + 15] = 0.0
