extends RefCounted
## A laid room's floor baked into one texture (the owner's choice of 2026-11-21, after #900: "bake
## each room's floor"), so a room in view draws its floor in one call, not seven: the floor art, the
## rock face under it (`Underside`), the edges' glow (`Glow`, added) and the shades its walls cast
## (`Shade`'s polygons) are drawn once, in that order (the order the screen draws them in), into a
## viewport of the floor's size (`bake`), and from the frame after it was drawn (`step`) the `Floor`
## sprite shows that viewport's texture and the four layers are hidden, their textures let go.
##
## The texture is premultiplied (`floor_bake.gdshader`): the layers' colours summed as the screen
## would sum them, over a clear pixel (the void seen through a pit) the glow only light. Drawn
## premultiplied it puts the same pixels on screen as the layers did, but where something drawn
## between them on screen lies over them: a floor mark, ground cover, a floor prop or a shot on the
## floor now lies over the glow and the shades, not under (docs/LOG.md, 2026-11-21, "Baked floors").
##
## Until the bake is drawn the layers show as before, so nothing is ever missing for a frame. With
## no renderer (a headless run, whose viewports are never drawn) nothing is baked (`enabled`).
## Memory: one RGBA8 texture of the floor's size a piece (a 704×448 crypt room 1.2 MB), in place of
## the floor's, the rock face's and the glow's (a drawn room's 2.25 times that). View only: it
## changes no node the simulation reads (the walls, holes and places stay the layout's).

const SHADER: Shader = preload("res://gameplay/feel/ground/floor_bake.gdshader")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")

## The layout's nodes it bakes (the ground scene's, `GroundShape`; the template's shades).
const FLOOR: StringName = &"Floor"
const GLOW: StringName = &"Glow"
const UNDERSIDE: StringName = &"Underside"
const SHADE: StringName = &"Shade"
## The viewport's name on the layout root (one a layout).
const BAKE: StringName = &"FloorBake"
## The floor's own texture, kept on it while `keep_layers` is on.
const KEPT_META: StringName = &"floor_bake_kept"

## Whether floors are baked (off without a renderer; a test may set it).
var enabled: bool = DisplayServer.get_name() != "headless"
## The bakes laid and not yet shown, and the frame each was first seen in the tree (-1: not yet).
var _pending: Array[SubViewport] = []
var _seen_at: PackedInt64Array = PackedInt64Array()
## How many floors were baked and shown (for tests and the benchmarks).
var shown: int = 0
## Whether the hidden layers keep their textures, so `unshow` can show them again (for the
## screenshots that hold the bake against the layers in one frame; off: they are let go).
var keep_layers: bool = false

static var _shown_material: ShaderMaterial = null
static var _glow_material: ShaderMaterial = null


func _init() -> void:
	ShaderWarmupScript.want(SHADER, ShaderWarmupScript.RECT)


## Lay the bake of `root`'s floor (a layout as `room_built` hands it over, its ground drawn): the
## viewport holding copies of the layers, drawn once. Null when there is nothing to bake (no plain
## `Floor` sprite with a texture, baked already, or `enabled` off).
func bake(root: Node) -> SubViewport:
	if not enabled or root == null or root.has_node(NodePath(BAKE)):
		return null
	var ground := root.get_node_or_null(NodePath(FLOOR)) as Sprite2D
	if ground == null or ground.texture == null or not _plain(ground) or ground.modulate != Color.WHITE or ground.self_modulate != Color.WHITE:
		return null
	var rect: Rect2 = ground.get_rect()
	var viewport := SubViewport.new()
	viewport.name = BAKE
	viewport.size = Vector2i(rect.size)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	# The floor's own pixels at the viewport's (0, 0).
	var base := Transform2D(0.0, -rect.position)
	var to_floor: Transform2D = _in(ground, root).affine_inverse()
	viewport.add_child(_sprite_copy(ground, base))
	for layer: Sprite2D in layers(root):
		var copy := _sprite_copy(layer, base * to_floor * _in(layer, root))
		if layer.name == GLOW:
			copy.material = glow_material()
		viewport.add_child(copy)
	for shade: Polygon2D in shades(root):
		var copy := Polygon2D.new()
		copy.polygon = shade.polygon
		copy.color = shade.color
		copy.offset = shade.offset
		copy.modulate = shade.modulate
		copy.self_modulate = shade.self_modulate
		copy.antialiased = shade.antialiased
		copy.transform = base * to_floor * _in(shade, root)
		viewport.add_child(copy)
	root.add_child(viewport)
	_pending.append(viewport)
	_seen_at.append(-1)
	return viewport


## Show each bake drawn since it was laid (a frame drawn after it was first in the tree): its
## floor shows the baked texture and the layers in it are hidden. Every frame; nothing is made.
## `drawn` is the frames drawn so far (the engine's; a test hands its own).
func step(drawn: int = Engine.get_frames_drawn()) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var viewport: SubViewport = _pending[i]
		if not is_instance_valid(viewport):
			_drop(i)
			continue
		if not viewport.is_inside_tree():
			continue
		if _seen_at[i] < 0:
			_seen_at[i] = drawn
		elif drawn > _seen_at[i]:
			show_bake(viewport)
			_drop(i)


## Show the bake `viewport` (laid by `bake`) on its layout's floor in place of the layers.
func show_bake(viewport: SubViewport) -> void:
	var root: Node = viewport.get_parent()
	var ground := root.get_node_or_null(NodePath(FLOOR)) as Sprite2D if root != null else null
	if ground == null:
		return
	for layer: Sprite2D in layers(root):
		layer.visible = false
		if not keep_layers:
			layer.texture = null
	if keep_layers:
		ground.set_meta(KEPT_META, ground.texture)
	var holder := root.get_node_or_null(NodePath(SHADE)) as CanvasItem
	if holder != null:
		holder.visible = false
	ground.texture = viewport.get_texture()
	ground.material = shown_material()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for copy: Node in viewport.get_children():
		viewport.remove_child(copy)
		copy.queue_free()
	shown += 1


## The layers shown again in place of the bake on `root`'s floor, baked with `keep_layers` on (for
## the screenshots; false when they were not kept).
static func unshow(root: Node) -> bool:
	var ground := root.get_node_or_null(NodePath(FLOOR)) as Sprite2D if root != null else null
	if ground == null or not ground.has_meta(KEPT_META):
		return false
	ground.texture = ground.get_meta(KEPT_META)
	ground.material = null
	ground.remove_meta(KEPT_META)
	var under := ground.find_child(String(UNDERSIDE), true, false) as Sprite2D
	var glow := ground.get_node_or_null(NodePath(GLOW)) as Sprite2D
	for layer: Sprite2D in [under, glow]:
		if layer != null and layer.texture != null:
			layer.visible = true
	var holder := root.get_node_or_null(NodePath(SHADE)) as CanvasItem
	if holder != null:
		holder.visible = true
	return true


## True when `root`'s floor shows its bake.
static func is_baked(root: Node) -> bool:
	var ground := root.get_node_or_null(NodePath(FLOOR)) as Sprite2D if root != null else null
	return ground != null and ground.texture is ViewportTexture and ground.material == _shown_material and _shown_material != null


## The floor's layers baked with it, in the order drawn: its rock face, then its glow (shown ones).
static func layers(root: Node) -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	var ground := root.get_node_or_null(NodePath(FLOOR)) as Sprite2D
	if ground == null:
		return found
	var under := ground.find_child(String(UNDERSIDE), true, false) as Sprite2D
	var glow := ground.get_node_or_null(NodePath(GLOW)) as Sprite2D
	for layer: Sprite2D in [under, glow]:
		if layer != null and layer.visible and layer.texture != null and _plain(layer):
			found.append(layer)
	return found


## The template's shades baked with the floor (the shown polygons under its `Shade`).
static func shades(root: Node) -> Array[Polygon2D]:
	var found: Array[Polygon2D] = []
	var holder := root.get_node_or_null(NodePath(SHADE)) as CanvasItem
	if holder == null or not holder.visible:
		return found
	for child: Node in holder.get_children():
		var shade := child as Polygon2D
		if shade != null and shade.visible and shade.texture == null and shade.material == null and shade.get_child_count() == 0:
			found.append(shade)
	return found


static func shown_material() -> ShaderMaterial:
	if _shown_material == null:
		_shown_material = ShaderMaterial.new()
		_shown_material.shader = SHADER
	return _shown_material


static func glow_material() -> ShaderMaterial:
	if _glow_material == null:
		_glow_material = ShaderMaterial.new()
		_glow_material.shader = SHADER
		_glow_material.set_shader_parameter(&"glow", true)
	return _glow_material


func _drop(i: int) -> void:
	_pending.remove_at(i)
	_seen_at.remove_at(i)


## A sprite drawn as a plain texture: no frames, region, flip or skew, its own material (or none,
## the glow's add) and children drawn on their own.
static func _plain(sprite: Sprite2D) -> bool:
	return not sprite.region_enabled and sprite.hframes == 1 and sprite.vframes == 1 \
		and not sprite.flip_h and not sprite.flip_v and sprite.skew == 0.0


## A copy of `sprite`'s drawing (not its children) placed by `xf` in the viewport.
static func _sprite_copy(sprite: Sprite2D, xf: Transform2D) -> Sprite2D:
	var copy := Sprite2D.new()
	copy.texture = sprite.texture
	copy.centered = sprite.centered
	copy.offset = sprite.offset
	copy.texture_filter = sprite.texture_filter
	copy.modulate = sprite.modulate
	copy.self_modulate = sprite.self_modulate
	copy.transform = xf
	return copy


## `node`'s transform from `root` (its layout root; not in the tree yet when it is baked).
static func _in(node: Node, root: Node) -> Transform2D:
	var xf := Transform2D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		if at is Node2D:
			xf = (at as Node2D).transform * xf
		at = at.get_parent()
	return xf
