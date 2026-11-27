class_name GroundShape
extends RefCounted
## A room's ground drawn when it is laid out (connected biomes CB4, docs/milestones/connected-biomes.md,
## decision 6): what `GroundDrawing` is handed (`spec`: the room's shape, where its template's things
## stand, its edge styles, ground materials and the palette, and how it is mirrored), the drawing
## itself (`draw`: the native module's when it is loaded, else the GDScript), and the drawn art put
## on the laid-out room's `Floor` (`apply`: the floor, glow, rock face and wall art as textures, the
## rims' and drips' mote lines made again). View only. Static only.
##
## What stands in the room is read from its template's scene as saved (`PackedScene.get_state`), the
## same nodes and numbers `tools/ground_shape.py` reads from the scene's text (`placements`,
## `clear_points`), so the drawing is a function of the template and its mirroring alone, wherever
## and however the room is laid.

const NativeScript := preload("res://core/native/native.gd")
const DrawingScript := preload("res://gameplay/feel/ground/ground_drawing.gd")
const NoiseScript := preload("res://gameplay/feel/ground/ground_noise.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## The layout root's metadata saying how the room is placed (`Vector2i`: x 1 when it is mirrored left
## to right, y 1 when top to bottom; absent: as the template is). Whoever lays a mirrored room sets it
## before `room_built` (the biome map, connected biomes CB5). It mirrors the art only: the layout's
## walls, holes and places are its caller's to mirror (until then they and the art disagree).
const MIRROR_META: StringName = &"ground_mirror"
## Where the edge styles and the ground materials are (content/edges, content/grounds).
const EDGES: StringName = &"edges"
const EDGE_FILE: String = "edge.json"
const GROUNDS: StringName = &"grounds"
const GROUND_FILE: String = "ground.json"
## The names of the drawn nodes in a ground scene (`tools/ground_shape.py`'s `scene_text`).
const GLOW: StringName = &"Glow"
## The floor at 2x (ArtDetail), the floor's first child, over its 1x texture exactly.
const DETAIL: StringName = &"Detail"
const UNDERSIDE: StringName = &"Underside"
const WALL_ART: StringName = &"WallArt"
const WALLS: StringName = &"Walls"


## What `GroundDrawing.draw` is handed for `shape` (a shape file's data), laid from the template
## `scene` and mirrored as `mirror` says (`MIRROR_META`), its styles and materials from `registry`
## (`Registry.get_data`). Empty, with a warning, when a style or material is missing.
static func spec(shape: Dictionary, scene: PackedScene, registry: RegistryScript, mirror: Vector2i = Vector2i.ZERO) -> Dictionary:
	var edge: Dictionary = registry.get_data(EDGES, StringName(shape.get("edge", "")), EDGE_FILE)
	var pit_style: bool = shape.has("pit_edge")
	var pit_edge: Dictionary = registry.get_data(EDGES, StringName(shape["pit_edge"]), EDGE_FILE) if pit_style else edge
	var grounds: Array = [registry.get_data(GROUNDS, StringName(shape.get("ground", "")), GROUND_FILE)]
	for area: Dictionary in shape.get("areas", []):
		grounds.append(registry.get_data(GROUNDS, StringName(area.get("ground", "")), GROUND_FILE))
	if edge.is_empty() or pit_edge.is_empty() or grounds.any(func(g: Dictionary) -> bool: return g.is_empty()):
		push_warning("GroundShape: the shape names an edge style or ground material there is none of, so its ground is not drawn.")
		return {}
	return {
		"shape": shape, "placed": placements(shape, scene), "clear": clear_points(shape, scene),
		"styles": [edge, pit_edge], "pit_style": pit_style, "grounds": grounds, "palette": NoiseScript.palette(),
		"mirror_x": mirror.x != 0, "mirror_y": mirror.y != 0,
	}


## The ground `spec` describes, drawn (`GroundDrawing.draw`'s dictionary): by the native module when
## it is loaded and `native`, else by the GDScript.
static func draw(ground_spec: Dictionary, native: bool = true) -> Dictionary:
	var kernel: Object = NativeScript.ground_kernel() if native else null
	if kernel != null:
		return kernel.call(&"draw", ground_spec)
	return DrawingScript.draw(ground_spec)


## Where the template's things stand, as circles a crack keeps clear of (`placements`): every node
## placed under another node with a position of its own, `keep_clear_round` pixels round, and every
## zone (a `ReferenceRect` under `Zones`) as a row of circles along it; x, y, radius triples.
static func placements(shape: Dictionary, scene: PackedScene) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	var radius: float = float(shape.get("keep_clear_round", 0))
	if radius <= 0.0 or scene == null:
		return found
	var state: SceneState = scene.get_state()
	for i in range(1, state.get_node_count()):
		var parent: String = _parent(state, i)
		if parent == "." or parent == "":
			continue
		var props: Dictionary = _properties(state, i)
		if state.get_node_type(i) == &"ReferenceRect":
			if parent != "Zones":
				continue
			var sides: Array[StringName] = [&"offset_left", &"offset_top", &"offset_right", &"offset_bottom"]
			if not sides.all(func(name: StringName) -> bool: return props.has(name)):
				continue
			# A row (or column) of circles along a long zone, each round a square-ish piece of it.
			var left: float = float(props[&"offset_left"])
			var top: float = float(props[&"offset_top"])
			var zone_w: float = float(props[&"offset_right"]) - left
			var zone_h: float = float(props[&"offset_bottom"]) - top
			var count: int = maxi(1, ceili(maxf(zone_w, zone_h) / maxf(1.0, minf(zone_w, zone_h))))
			for k in count:
				var t: float = (float(k) + 0.5) / float(count)
				var cx: float = left + (zone_w * t if zone_w >= zone_h else zone_w / 2.0)
				var cy: float = top + (zone_h * t if zone_h > zone_w else zone_h / 2.0)
				var piece_w: float = zone_w / float(count) if zone_w >= zone_h else zone_w
				var piece_h: float = zone_h if zone_w >= zone_h else zone_h / float(count)
				found.append_array(PackedFloat64Array([cx, cy, NoiseScript.length_of(piece_w, piece_h) / 2.0 + radius]))
			continue
		if props.get(&"position") is Vector2:
			var at: Vector2 = props[&"position"]
			found.append_array(PackedFloat64Array([at.x, at.y, radius]))
	return found


## Where a frame's floor is pushed out to (`clear_points`): every node whose parent is one of
## `frame.clear.of`, `frame.clear.round` pixels round; x, y, radius triples.
static func clear_points(shape: Dictionary, scene: PackedScene) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	var clear: Dictionary = (shape.get("frame", {}) as Dictionary).get("clear", {})
	if clear.is_empty() or scene == null:
		return found
	var radius: float = float(clear["round"])
	var parents: Array = clear["of"]
	var state: SceneState = scene.get_state()
	for i in range(1, state.get_node_count()):
		# Direct children only: a child's position is its own place in the room.
		if not parents.has(_parent(state, i)):
			continue
		var props: Dictionary = _properties(state, i)
		if props.get(&"position") is Vector2:
			var at: Vector2 = props[&"position"]
			found.append_array(PackedFloat64Array([at.x, at.y, radius]))
	return found


## The path of a node's parent as the scene's text writes it (`.`, `Props`, `Decor/Candles1`).
static func _parent(state: SceneState, node: int) -> String:
	var path: String = String(state.get_node_path(node, true))
	return path.substr(2) if path.begins_with("./") else path


static func _properties(state: SceneState, node: int) -> Dictionary:
	var found: Dictionary = {}
	for k in state.get_node_property_count(node):
		found[state.get_node_property_name(node, k)] = state.get_node_property_value(node, k)
	return found


## Put the drawn `art` (`draw`'s) on `ground`, a laid-out room's `Floor` (an instanced ground scene):
## its floor, glow, rock face and wall art become the drawn ones, and its rims' and drips' mote lines
## are made again from the drawing, in the styles of `ground_spec`. Before it is in the tree (Feel
## hears `room_built` first), so the motes read the new lines as the room is shown. The floor keeps its
## 1x texture (what a room's readers measure and sample) under its `Detail` child, the 2x art drawn
## over it at its size (ArtDetail); the rock face and the wall art are the 2x art.
static func apply(ground: Sprite2D, art: Dictionary, ground_spec: Dictionary) -> void:
	var w: int = art["width"]
	var h: int = art["height"]
	var d: int = art["detail"]
	ground.texture = _texture(art["floor"], w, h)
	var detail := ground.get_node_or_null(NodePath(DETAIL)) as Sprite2D
	if detail == null:
		detail = Sprite2D.new()
		detail.name = DETAIL
		detail.centered = false
		detail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ground.add_child(detail)
		ground.move_child(detail, 0)
	detail.texture = _texture(art["fine_floor"], w * d, h * d, d)
	ArtDetail.fit(detail)
	var glow := ground.get_node_or_null(NodePath(GLOW)) as Sprite2D
	if glow != null:
		# Filtered (linear), so its clear pixels take their neighbours' colour, as the import does the
		# baked glow's (`fix_alpha_border`): its fringe is not darkened.
		var glow_image: Image = Image.create_from_data(art["glow_width"], art["glow_height"], false, Image.FORMAT_RGBA8, art["glow"])
		glow_image.fix_alpha_edges()
		glow.texture = ImageTexture.create_from_image(glow_image)
	var under := ground.find_child(UNDERSIDE, true, false) as Sprite2D
	if under != null:
		under.texture = _texture(art["fine_under"], w * d, h * d, d)
		ArtDetail.fit(under)
	var wall_art := ground.find_child(WALL_ART, true, false) as Sprite2D
	if wall_art != null:
		var wall: PackedByteArray = art["fine_wall"]
		wall_art.visible = not wall.is_empty()
		if not wall.is_empty():
			wall_art.texture = _texture(wall, w * d, h * d, d)
			ArtDetail.fit(wall_art)
	for child: Node in ground.get_children():
		if child is Line2D and child.is_in_group(MoteSource.GROUP):
			ground.remove_child(child)
			child.free()
	var styles: Array = ground_spec["styles"]
	var rims: Array = art["rims"]
	var rim_sides: PackedInt32Array = art["rim_sides"]
	for i in rims.size():
		var style: Dictionary = styles[rim_sides[i]]
		var rim: Dictionary = style["rim"]
		var points: PackedVector2Array = rims[i]
		var source := MoteSource.new()
		source.kind = StringName(rim["kind"])
		source.rate = _tenths(_length(points, true) / 100.0 * float(rim["per_100px"]))
		source.from = MoteSource.From.LINE
		if rim.has("colours"):
			# The rim's own colours, at random along it (not the seam's bands).
			source.colours = _names(rim["colours"])
		elif style.has("seam"):
			source.colours = _names(style["seam"]["colours"])
			source.band_length = float(style["seam"]["band_length"])
		_add_line(ground, "Rim" if i == 0 else "Rim%d" % (i + 1), points, true, source)
	var drips: Array = art["drips"]
	var drip_sides: PackedInt32Array = art["drip_sides"]
	var drip_colours: PackedStringArray = art["drip_colours"]
	for i in drips.size():
		var drip: Dictionary = (styles[drip_sides[i]] as Dictionary)["drip"]
		var points: PackedVector2Array = drips[i]
		var source := MoteSource.new()
		source.kind = StringName(drip["kind"])
		source.rate = _tenths(maxf(0.1, _length(points, false) / 100.0 * float(drip["per_100px"])))
		source.from = MoteSource.From.LINE
		source.colours = _names([drip_colours[i]])
		_add_line(ground, "Drip%d" % (i + 1), points, false, source)


static func _add_line(ground: Node, line_name: String, points: PackedVector2Array, closed: bool, source: MoteSource) -> void:
	var line := Line2D.new()
	line.name = line_name
	line.visible = false
	line.closed = closed
	line.points = points
	line.set_meta(MoteSource.META, source)
	line.add_to_group(MoteSource.GROUP, true)
	ground.add_child(line)


## A texture of `rgba` (w by h), marked `detail` art pixels a world pixel (ArtDetail).
static func _texture(rgba: PackedByteArray, w: int, h: int, detail: int = 1) -> ImageTexture:
	var texture := ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba))
	if detail > 1:
		ArtDetail.mark(texture, detail)
	return texture


static func _length(points: PackedVector2Array, closed: bool) -> float:
	var total: float = 0.0
	var count: int = points.size() if closed else points.size() - 1
	for k in count:
		var a: Vector2 = points[k]
		var b: Vector2 = points[(k + 1) % points.size()]
		total += NoiseScript.length_of(float(b.x) - float(a.x), float(b.y) - float(a.y))
	return total


## A rate as the baked scene writes it: to a tenth.
static func _tenths(rate: float) -> float:
	return ("%.1f" % rate).to_float()


static func _names(list: Array) -> Array[StringName]:
	var found: Array[StringName] = []
	for item: Variant in list:
		found.append(StringName(item))
	return found
