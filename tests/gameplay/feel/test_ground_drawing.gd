extends "res://tests/support/suite.gd"
## The ground drawn at layout (connected biomes CB4, gameplay/feel/ground/): drawn again from a room's
## shape, unmirrored, it is the art `tools/ground_shape.py` baked, pixel for pixel (every room drawn
## at layout and the hub's, by the native module when it is loaded; one room by the GDScript too), its
## rims and drips the baked scene's lines; the native module gives the GDScript's bytes in every
## mirroring (two small fixture shapes that reach what no room uses yet, a wall's top and face, an
## island's outline, cracks from it, patches and strokes, and a room with pits), and the GDScript draws
## those fixtures as the tool does (its hashes, `ground_fixtures.json`); and a mirrored room
## is drawn again, not flipped: the floor a body stands on is the exact mirror of the unmirrored
## one, its art differs, and its rock face still hangs below its edges. The 2x art (ArtDetail; ART3)
## is held to the baked @2x files and the tool's hashes the same way, and is opaque exactly where
## its 1x pixel is.
##
## A baked PNG is read from its file (its import fills the colour of clear pixels, `fix_alpha_border`):
## every pixel's alpha must be the same, and the colour of every pixel that is not clear.
##
## Without the native module the native comparisons only say so (SPELLMERGE_NATIVE=required fails it).
# unit-test-alone
const ShapeScript := preload("res://gameplay/feel/ground/ground_shape.gd")
const NativeScript := preload("res://core/native/native.gd")
const HubShape := preload("res://content/rooms/hub/hub.shape.json")
const HubScene := preload("res://content/rooms/hub/hub.tscn")
const Hall := preload("res://tests/gameplay/feel/fixtures/ground_hall.shape.json")
const Island := preload("res://tests/gameplay/feel/fixtures/ground_island.shape.json")
## The fixtures' drawing by tools/ground_shape.py, as hashes (`--fixtures`).
const FixtureHashes := preload("res://tests/gameplay/feel/fixtures/ground_fixtures.json")
const RegistryScript := preload("res://core/registry/registry.gd")

const ROOMS: StringName = &"rooms"
## The baked art's sprites, by what the drawing calls them.
## The rock face and the walls' art are baked at 2x only; the floor at 1x (its texture) and 2x (`Detail`).
const SPRITES: Dictionary = {"floor": ".", "fine_floor": "Detail", "glow": "Glow", "fine_under": "Underside", "fine_wall": "WallArt"}
const MIRRORINGS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]


func _registry() -> RegistryScript:
	return root.get_node("/root/Registry") as RegistryScript


## Every room drawn at layout (a room naming its `ground_shape`), and the hub, whose baked ground
## stays: {id, shape, scene}.
func _rooms() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Resource in _registry().get_all(ROOMS):
		var room := item as RoomBase
		if room != null and room.ground_shape != null:
			found.append({"id": room.id, "shape": room.ground_shape.data, "scene": room.scene})
	found.append({"id": &"hub", "shape": HubShape.data, "scene": HubScene})
	return found


func _spec(shape: Dictionary, scene: PackedScene, mirror: Vector2i = Vector2i.ZERO) -> Dictionary:
	return ShapeScript.spec(shape, scene, _registry(), mirror)


func _native_or_say() -> bool:
	if NativeScript.loaded():
		# A module built before GroundKernel would draw by the GDScript and compare it with itself.
		var has_kernel: bool = NativeScript.ground_kernel() != null
		check(has_kernel, "the native module is loaded but has no GroundKernel (build it again: ci/build/native.sh)")
		return has_kernel
	check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
	return false


func test_every_room_drawn_from_a_shape_is_drawn_at_layout() -> void:
	# A room whose ground was drawn from a shape names that shape, so it is drawn again as it is laid
	# (the hub keeps its baked art for now, the plan's CB4).
	for item: Resource in _registry().get_all(ROOMS):
		var room := item as RoomBase
		if room == null or room.scene == null or room.id == &"hub":
			continue
		var layout: Node = room.scene.instantiate()
		var ground: Node = layout.get_node_or_null("Floor")
		if ground != null and ground.has_meta(&"ground_inputs"):
			check(room.ground_shape != null, "%s: its ground is drawn from a shape, so its .tres names it (ground_shape)" % room.id)
			if room.ground_shape != null:
				check(room.ground_shape.resource_path == room.scene.resource_path.get_basename() + ".shape.json",
					"%s: it names its own shape, beside its scene" % room.id)
		layout.free()
	check(_rooms().size() > 1, "rooms are drawn at layout")


func test_the_native_drawing_is_the_baked_art() -> void:
	if not _native_or_say():
		return
	for room: Dictionary in _rooms():
		var spec: Dictionary = _spec(room["shape"], room["scene"])
		_check_baked(room, spec, ShapeScript.draw(spec, true))


func test_the_gdscript_drawing_is_the_baked_art() -> void:
	var antechamber: RoomBase = _registry().get_resource(ROOMS, &"arena_01")
	var room: Dictionary = {"id": antechamber.id, "shape": antechamber.ground_shape.data, "scene": antechamber.scene}
	var spec: Dictionary = _spec(room["shape"], room["scene"])
	_check_baked(room, spec, ShapeScript.draw(spec, false))
	# A corner walkway (connected biomes CB13): its outline a polygon (`points`) and an area of one.
	var corner: RoomBase = _registry().get_resource(ROOMS, &"crypt_corner_256x384")
	var turn: Dictionary = {"id": corner.id, "shape": corner.ground_shape.data, "scene": corner.scene}
	var turn_spec: Dictionary = _spec(turn["shape"], turn["scene"])
	_check_baked(turn, turn_spec, ShapeScript.draw(turn_spec, false))


## `art` against the baked art of `room`: each image, and the rims' and drips' lines.
func _check_baked(room: Dictionary, spec: Dictionary, art: Dictionary) -> void:
	var baked: Node = (room["scene"] as PackedScene).instantiate()
	var ground := baked.get_node("Floor") as Sprite2D
	for kind: String in SPRITES:
		var sprite := (ground if SPRITES[kind] == "." else ground.find_child(SPRITES[kind], true, false)) as Sprite2D
		var drawn: PackedByteArray = art[kind]
		if sprite == null:
			check(drawn.is_empty() or kind != "fine_wall", "%s: no wall art baked, none drawn" % room["id"])
			continue
		var image := Image.new()
		image.load_png_from_buffer(FileAccess.get_file_as_bytes(sprite.texture.resource_path))
		image.convert(Image.FORMAT_RGBA8)
		var why: String = _differs(drawn, image.get_data())
		check(why == "", "%s: the drawn %s is the baked art (%s)" % [room["id"], kind, why])
	var drawn_ground := ground.duplicate() as Sprite2D
	ShapeScript.apply(drawn_ground, art, spec)
	check_equal(_lines(drawn_ground), _lines(ground), "%s: the drawn rims and drips are the baked scene's" % room["id"])
	drawn_ground.free()
	baked.free()


## Where two RGBA images part ("" when every alpha is the same, and every colour that is not clear).
func _differs(got: PackedByteArray, want: PackedByteArray) -> String:
	if got.size() != want.size():
		return "%d bytes, not %d" % [got.size(), want.size()]
	var count: int = 0
	var first: int = -1
	for i in range(0, got.size(), 4):
		if got[i + 3] != want[i + 3] or (got[i + 3] != 0 and (got[i] != want[i] or got[i + 1] != want[i + 1] or got[i + 2] != want[i + 2])):
			count += 1
			if first < 0:
				first = i / 4
	return "" if count == 0 else "%d pixels differ, the first the %dth" % [count, first]


## A ground's mote lines as data: name, closed, points, and its source's kind, rate, colours, bands.
func _lines(ground: Node) -> Array:
	var found: Array = []
	for child: Node in ground.get_children():
		if not (child is Line2D and child.is_in_group(MoteSource.GROUP)):
			continue
		var line := child as Line2D
		var source: MoteSource = MoteSource.of(line)
		found.append([String(line.name), line.closed, line.points, source.kind, snappedf(source.rate, 0.01), source.from,
			source.colours, source.band_length])
	return found


func test_the_fixtures_are_drawn_as_the_tool_draws_them() -> void:
	# What no room uses yet (a wall's top, face and foot, an outline, a hole void, cracks from an
	# outline, patches and strokes), held to tools/ground_shape.py by its hashes of the same shapes.
	var expected: Dictionary = FixtureHashes.data
	for case: Array in [["ground_hall", Hall], ["ground_island", Island]]:
		var art: Dictionary = ShapeScript.draw(_spec((case[1] as JSON).data, null), false)
		var want: Dictionary = expected[case[0]]
		for kind: String in ["floor", "under", "glow", "wall", "fine_floor", "fine_under", "fine_wall"]:
			check_equal(_sha(art[kind]), want[kind], "%s: the %s is the tool's" % [case[0], kind])
		var lines := PackedStringArray()
		for points: PackedVector2Array in (art["rims"] as Array) + (art["drips"] as Array):
			var texts := PackedStringArray()
			for at: Vector2 in points:
				texts.append("%.1f,%.1f" % [at.x, at.y])
			lines.append(";".join(texts))
		check_equal(_sha("|".join(lines).to_utf8_buffer()), want["lines"], "%s: the rims and drips are the tool's" % case[0])


func _sha(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if not data.is_empty():
		context.update(data)
	return context.finish().hex_encode()


func test_the_native_drawing_is_the_gdscript_in_every_mirroring() -> void:
	if not _native_or_say():
		return
	var cases: Array[Dictionary] = [{"id": "hall", "shape": Hall.data, "scene": null}, {"id": "island", "shape": Island.data, "scene": null}]
	for mirror: Vector2i in [Vector2i.ZERO] + MIRRORINGS:
		for case: Dictionary in cases:
			_check_twins("%s %s" % [case["id"], mirror], _spec(case["shape"], case["scene"], mirror))
	# A room with pits, cracks from them and two edge styles, mirrored both ways.
	var room: RoomBase = _registry().get_resource(ROOMS, &"arena_02")
	_check_twins("arena_02 (1, 1)", _spec(room.ground_shape.data, room.scene, Vector2i(1, 1)))
	# A corner walkway's polygon outline and area (connected biomes CB13), in every mirroring.
	var corner: RoomBase = _registry().get_resource(ROOMS, &"crypt_corner_256x384")
	for mirror: Vector2i in [Vector2i.ZERO] + MIRRORINGS:
		_check_twins("crypt_corner_256x384 %s" % mirror, _spec(corner.ground_shape.data, corner.scene, mirror))


func _check_twins(what: String, spec: Dictionary) -> void:
	var native: Dictionary = ShapeScript.draw(spec, true)
	var plain: Dictionary = ShapeScript.draw(spec, false)
	for key: String in plain:
		if plain[key] is Array:
			var a: Array = native[key]
			var b: Array = plain[key]
			var same: bool = a.size() == b.size()
			for i in mini(a.size(), b.size()):
				same = same and a[i] == b[i]
			check(same, "%s: the native %s are the GDScript's" % [what, key])
		else:
			check(native[key] == plain[key], "%s: the native %s is the GDScript's" % [what, key])
	check(not (plain["wall"] as PackedByteArray).is_empty() or what.begins_with("island") or what.begins_with("arena") or what.begins_with("crypt"), "%s: a hall's walls are drawn" % what)
	check(not (plain["drips"] as Array).is_empty() or not what.begins_with("island"), "%s: an island's rock face drips" % what)


func test_a_mirrored_room_is_drawn_again_not_flipped() -> void:
	var native: bool = NativeScript.loaded()
	var cases: Array[Dictionary] = [{"id": "hall", "shape": Hall.data, "scene": null}, {"id": "island", "shape": Island.data, "scene": null}]
	if native:
		for room: Dictionary in _rooms():
			if room["id"] != &"hub":
				cases.append(room)
	for case: Dictionary in cases:
		var plain: Dictionary = ShapeScript.draw(_spec(case["shape"], case["scene"]), native)
		var w: int = plain["width"]
		var h: int = plain["height"]
		for mirror: Vector2i in MIRRORINGS:
			var what: String = "%s %s" % [case["id"], mirror]
			var art: Dictionary = ShapeScript.draw(_spec(case["shape"], case["scene"], mirror), native)
			var solid: PackedByteArray = art["solid"]
			check(solid == _mirrored(plain["solid"], w, h, mirror, 1), "%s: the floor a body stands on is the unmirrored one's mirror" % what)
			var floor_art: PackedByteArray = art["floor"]
			var opaque: bool = true
			for p in w * h:
				opaque = opaque and floor_art[p * 4 + 3] == (255 if solid[p] != 0 else 0)
			check(opaque, "%s: the floor art is opaque exactly where a body stands" % what)
			check(floor_art != _mirrored(plain["floor"], w, h, mirror, 4), "%s: the floor is drawn again, not flipped" % what)
			check(_hangs_below(art["under"], solid, w, h), "%s: the rock face hangs below the floor's edges (lit from above)" % what)
			var d: int = art["detail"]
			var fine_solid: PackedByteArray = _upsampled(solid, w, h, d)
			var fine_floor: PackedByteArray = art["fine_floor"]
			var fine_opaque: bool = fine_floor.size() == fine_solid.size() * 4
			for p in fine_solid.size() if fine_opaque else 0:
				fine_opaque = fine_opaque and fine_floor[p * 4 + 3] == (255 if fine_solid[p] != 0 else 0)
			check(fine_opaque, "%s: the 2x floor is opaque exactly where its 1x pixel is" % what)
			check(_hangs_below(art["fine_under"], fine_solid, w * d, h * d), "%s: the 2x rock face hangs below the floor's edges" % what)


## `mask` (w by h) with every value `d` by `d` times.
func _upsampled(mask: PackedByteArray, w: int, h: int, d: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * d * h * d)
	for y in h * d:
		for x in w * d:
			out[y * w * d + x] = mask[(y / d) * w + x / d]
	return out


## Whether every pixel of the rock face `under` hangs from solid ground above it in its column.
func _hangs_below(under: PackedByteArray, solid: PackedByteArray, w: int, h: int) -> bool:
	var drawn: int = 0
	for x in w:
		for y in h:
			if under[(y * w + x) * 4 + 3] == 0:
				continue
			drawn += 1
			var up: int = y - 1
			while up >= 0 and under[(up * w + x) * 4 + 3] != 0:
				up -= 1
			if up < 0 or solid[up * w + x] == 0:
				return false
	if drawn > 0:
		return true
	# No rock face: only right when the floor has no south edge inside the frame (a north-south
	# walkway runs to the template's edge at both ends, connected biomes CB11).
	for x in w:
		for y in h - 1:
			if solid[y * w + x] != 0 and solid[(y + 1) * w + x] == 0:
				return false
	return true


## `data` (`stride` bytes a pixel) mirrored as `mirror` says.
func _mirrored(data: PackedByteArray, w: int, h: int, mirror: Vector2i, stride: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(data.size())
	for y in h:
		var from_y: int = h - 1 - y if mirror.y != 0 else y
		for x in w:
			var from: int = (from_y * w + (w - 1 - x if mirror.x != 0 else x)) * stride
			for k in stride:
				out[(y * w + x) * stride + k] = data[from + k]
	return out


func test_the_2x_floor_is_put_on_a_floor_that_has_no_detail_yet() -> void:
	# A floor with no `Detail` child (a ground scene from before ART3): `apply` makes one, the
	# floor's first child, the 2x art at half its size over the 1x texture the floor keeps.
	var spec: Dictionary = _spec(Hall.data, null)
	var art: Dictionary = ShapeScript.draw(spec, false)
	var ground := Sprite2D.new()
	ground.centered = false
	var glow := Sprite2D.new()
	glow.name = "Glow"
	ground.add_child(glow)
	ShapeScript.apply(ground, art, spec)
	var detail := ground.get_node_or_null(NodePath(ShapeScript.DETAIL)) as Sprite2D
	check(detail != null and detail.get_index() == 0, "a Detail sprite, the floor's first child (under its glow)")
	if detail != null:
		check_equal(ArtDetail.of(detail.texture), 2, "its texture marked at 2x")
		check(detail.scale.is_equal_approx(Vector2(0.5, 0.5)) and not detail.centered, "drawn at half its size from the floor's corner")
		check_equal(Vector2i(detail.texture.get_size()), Vector2i(ground.texture.get_size()) * 2, "twice the floor's pixels each way")
	ground.free()
