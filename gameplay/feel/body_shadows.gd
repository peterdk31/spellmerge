extends MultiMeshInstance2D
## Bodies' shadows (docs/milestones/atmosphere.md, C): every body that walks (a wizard, an enemy, a
## boss: an actor with a Mover) stands on a flat hard shadow, cast a few pixels away from the light
## near it, so a lit room has depth and a body reads as standing on the floor. One batch (made by
## `Batches.multimesh()`), one row a body, drawn by `body_shadow.gdshader` under every body (the
## spectacle's MARK_Z, after the floor marks). The spectacle's, made and freed with the spell light
## (only while the "Dynamic lighting" and "Shadows" settings are on, easing in and out with
## "Shadows": `share`).
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
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const ArriveLookScript := preload("res://gameplay/feel/arrive_look.gd")
const SHADER: Shader = preload("res://gameplay/feel/body_shadow.gdshader")

## Floats a row holds (a 2D MultiMesh row with colours and custom data; the light rows' too).
const STRIDE: int = SpellLightScript.STRIDE
## How long a gone body's shadow takes to shrink away where it last was (s): 6 frames.
const GONE_SECONDS: float = 0.1
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
## Each actor's cast as drawn (px, before rounding), and the step it last had a shadow in and whose
## it was (`Actors.key_of`): one that had none the step before, or a new body under an old id, takes
## its cast at once. Read only.
var cast: PackedVector2Array = PackedVector2Array()
var _stamp: PackedInt32Array = PackedInt32Array()
var _key: PackedInt64Array = PackedInt64Array()
var _steps: int = 0
## Each actor's shadow as last drawn (its feet and radius) and how much of it is left once its body
## is gone (1 while it stands; it shrinks away where it was over GONE_SECONDS), and the ids drawn
## this step and the last (swapped each step), `_shown_count` of them.
var _last_feet: PackedVector2Array = PackedVector2Array()
var _last_radius: PackedFloat32Array = PackedFloat32Array()
var _left: PackedFloat32Array = PackedFloat32Array()
var _shown: PackedInt32Array = PackedInt32Array()
var _shown_prev: PackedInt32Array = PackedInt32Array()
var _shown_count: int = 0
## The rows (grown, never shrunk) and the open ids' buffer.
var _rows: PackedFloat32Array = PackedFloat32Array()
var _ids: PackedInt32Array = PackedInt32Array()
## This frame's lights: where, how far they reach, how bright, and who carries each (NONE: nobody).
var _light_at: PackedVector2Array = PackedVector2Array()
var _light_reach: PackedFloat32Array = PackedFloat32Array()
var _light_strength: PackedFloat32Array = PackedFloat32Array()
var _light_owner: PackedInt32Array = PackedInt32Array()
## Where each stands on the floor (its row's ground: what it is cast away from and blocked by) and the
## boxes that come near it (a bit each; none: it is never blocked), worked out once a step.
var _light_from: PackedVector2Array = PackedVector2Array()
var _light_near: PackedInt32Array = PackedInt32Array()
var _light_count: int = 0
## Feel's clock at the last step (-1: none yet).
var _last: float = -1.0
## How much of the layer shows (0 to 1; the "Shadows" setting easing it in or out, the spectacle
## sets it each frame): Smooth in two halves by whole pixels. From 1 to 0.5 every cast comes in to the
## body's feet, leaving the contact shape a body's own drawn shadow has; from 0.5 to 0 the contact
## shape of a body with no drawn shadow (an enemy) shrinks away, while one with a drawn shadow keeps
## it, so the drawn one takes its place unchanged when this node leaves. Fading in, the reverse.
var share: float = 1.0
## The bodies with a drawn shadow of their own (their node's instance id: true), found as this node
## enters the tree or a drawn shadow is added, and again by `find_drawn_owners`.
var _drawn_owners: Dictionary = {}


func _init(z: int) -> void:
	name = "BodyShadows"
	z_index = z
	cast.resize(ActorsScript.ACTORS)
	_stamp.resize(ActorsScript.ACTORS)
	_stamp.fill(-1)
	_key.resize(ActorsScript.ACTORS)
	_last_feet.resize(ActorsScript.ACTORS)
	_last_radius.resize(ActorsScript.ACTORS)
	_left.resize(ActorsScript.ACTORS)
	_shown.resize(ActorsScript.ACTORS)
	_shown_prev.resize(ActorsScript.ACTORS)
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
		_own_drawn(node)


## The bodies with a drawn shadow of their own found again (a fade out starting: those made since
## are known, and the gone ones forgotten).
func find_drawn_owners() -> void:
	_drawn_owners.clear()
	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group(LightSpot.DRAWN_SHADOW):
			_own_drawn(node)


## Whether the body `body` has a drawn shadow of its own.
func has_drawn(body: Node) -> bool:
	return _drawn_owners.has(body.get_instance_id())


func _own_drawn(node: Node) -> void:
	var owner_body: Node = node.get_parent()
	if owner_body != null:
		_drawn_owners[owner_body.get_instance_id()] = true


func _show_drawn(tree: SceneTree, shown: bool) -> void:
	if not shown:
		_drawn_owners.clear()
	for node: Node in tree.get_nodes_in_group(LightSpot.DRAWN_SHADOW):
		_show_node(node, shown)
		if not shown:
			_own_drawn(node)


func _show_node(node: Node, shown: bool) -> void:
	var item := node as CanvasItem
	if item != null:
		item.visible = shown


## This frame's lights begin: none until `add_lights`.
func begin_lights() -> void:
	_light_count = 0


## `n` light rows of `rows` (STRIDE floats each, in the spot rows' layout: reach, middle, where it
## stands on the floor, `SpellLight.write_spot_row`), each as bright as its float `strength_at` says; `owners`, when not empty, the actor carrying each (its
## shadow is not cast by it). Read, not kept.
func add_lights(rows: PackedFloat32Array, n: int, strength_at: int, owners: PackedInt32Array) -> void:
	for at in mini(n, rows.size() / STRIDE):
		if _light_count >= LIGHTS:
			return
		var i: int = at * STRIDE
		var strength: float = rows[i + strength_at]
		var reach: float = rows[i + SpellLightScript.ROW_REACH]
		if strength <= 0.0 or reach <= 0.0:
			continue
		var middle := Vector2(rows[i + SpellLightScript.ROW_X], rows[i + SpellLightScript.ROW_Y])
		_light_at[_light_count] = middle
		_light_from[_light_count] = middle + Vector2(rows[i + SpellLightScript.SPOT_ROW_GROUND], rows[i + SpellLightScript.SPOT_ROW_GROUND + 1])
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
	# The layer's share (see `share`): the casts in the upper half, the contact shapes in the lower.
	var cast_share: float = clampf(share * 2.0 - 1.0, 0.0, 1.0)
	var size_share: float = clampf(share * 2.0, 0.0, 1.0)
	var near: Rect2 = view.grow(VIEW_MARGIN)
	for k in _light_count:
		var span: float = _light_reach[k] + _light_at[k].distance_to(_light_from[k])
		_light_near[k] = blockers.near(_light_at[k], span) if blockers != null and blockers.count > 0 else 0
	var open: int = table.open_ids(_ids) if table != null else 0
	var out: int = 0
	_steps += 1
	var swap: PackedInt32Array = _shown_prev
	_shown_prev = _shown
	_shown = swap
	var before: int = _shown_count
	_shown_count = 0
	for at in open:
		var id: int = _ids[at]
		var body := table.node_of(id) as Actor
		if body == null or body.mover == null or body.footprint == null or not body.is_inside_tree() or body.is_queued_for_deletion() or not body.is_visible_in_tree():
			continue
		var feet: Vector2 = body.global_position + Vector2(0.0, DROP)
		if view.has_area() and not near.has_point(feet):
			continue
		var key: int = table.key_of(id)
		var want: Vector2 = _cast_from(feet, id, blockers)
		if _stamp[id] != _steps - 1 or _key[id] != key:
			cast[id] = want
		else:
			cast[id] = cast[id].move_toward(want, most)
		_stamp[id] = _steps
		_key[id] = key
		var radius: float = (body.footprint.radius + RADIUS_PAD) * (1.0 - body.fall_share()) * rise_share(body.arrive_share())
		if size_share < 1.0 and not has_drawn(body):
			radius *= size_share
		_last_feet[id] = feet.round()
		_last_radius[id] = radius
		_left[id] = 1.0
		_shown[_shown_count] = id
		_shown_count += 1
		if radius < SMALLEST:
			continue
		_write_row(out, feet.round(), (cast[id] * cast_share).round(), radius)
		out += 1
	# A body gone since the last step (dead, freed, hidden, out of view): its shadow shrinks away
	# where it was, never vanishing in one frame.
	for at in before:
		var id: int = _shown_prev[at]
		if _stamp[id] == _steps:
			continue
		_left[id] = maxf(_left[id] - delta / GONE_SECONDS, 0.0)
		var radius: float = _last_radius[id] * _left[id]
		if radius < SMALLEST:
			continue
		_shown[_shown_count] = id
		_shown_count += 1
		_write_row(out, _last_feet[id], (cast[id] * cast_share).round(), radius)
		out += 1
	count = out
	multimesh.visible_instance_count = out
	if out > 0:
		multimesh.buffer = _rows


## How much of a body's shadow shows at `share` of its arrival (`Actor.arrive_share`; 1 standing):
## none while it is under the floor (Feel's arrival mark is drawn there instead, ArriveLook.MARK_END),
## then growing with it as it rises.
static func rise_share(share: float) -> float:
	if share >= 1.0:
		return 1.0
	return clampf((share - ArriveLookScript.MARK_END) / (1.0 - ArriveLookScript.MARK_END), 0.0, 1.0)


## Where the shadow of a body with its feet at `feet` (and the id `id`) should be cast this frame
## (px, at most LENGTH long): away from each light near, as much as it lights the feet (the lights'
## blocking worked out in `step`).
func _cast_from(feet: Vector2, id: int, blockers: LightBlockersScript) -> Vector2:
	var pull := Vector2.ZERO
	for k in _light_count:
		if _light_owner[k] == id:
			continue
		var reach: float = _light_reach[k]
		var far_sq: float = feet.distance_squared_to(_light_at[k])
		if far_sq >= reach * reach:
			continue
		# Cast away from where the light stands on the floor (a carried light: its body's feet).
		var away: Vector2 = feet - _light_from[k]
		var along: float = away.length()
		if along < 0.5:
			continue
		var fall: float = 1.0 - sqrt(far_sq) / reach
		var light: float = _light_strength[k] * fall * fall
		if light < FAINT:
			continue
		if blockers != null and _light_near[k] != 0:
			light *= 1.0 - blockers.shade_from(feet, _light_from[k], _light_near[k])
		pull += away / along * light
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
