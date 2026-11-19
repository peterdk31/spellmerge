extends "res://tests/support/screenshot.gd"
## Screenshots of the crypt's walkways and of a whole map in each map style (connected biomes CB13,
## docs/milestones/connected-biomes.md: "a screenshot of each template and each map style"), drawn
## by the game's own ground drawing (gameplay/feel/ground: what Feel lays as a room is placed), so the
## art is the game's, drawn again in each mirroring, never flipped. The rooms that host a kind have
## their own shots, as the game plays them (shot_rooms.gd).
##
## Shots: `walkway_<id>`, every walkway the registry finds (found by folder), in its four mirrorings
## side by side, twice the size; `biome_map_<style>`, a crypt map made in each of its styles (the
## first seed that makes one; for a style that closes loops, the first that closes one), every room
## and walkway drawn at its place and mirroring, a quarter the size.

const RegistryScript := preload("res://core/registry/registry.gd")
const ShapeScript := preload("res://gameplay/feel/ground/ground_shape.gd")
## The dark the pieces are drawn over (the void's).
const VOID := Color(0.055, 0.047, 0.094)
## How far apart the mirrorings of a walkway are drawn, in pixels.
const GAP: int = 16
## The most seeds tried for a style's map.
const SEEDS: int = 40


func take() -> void:
	if not need(["Registry"]):
		return
	var registry := root.get_node("Registry") as RegistryScript
	var walkways: int = 0
	for item: Resource in registry.get_all(&"rooms"):
		var room := item as RoomBase
		if room != null and room.walkway and room.ground_shape != null:
			walkways += 1
			_walkway(registry, room)
	if walkways == 0:
		fail("no walkway was found")
		return
	var crypt := registry.get_resource(&"runs", &"crypt") as RunDefinition
	var rules := crypt.biomes[0] as MapRules
	for style: MapStyle in rules.styles:
		_map_of_style(registry, crypt, style)


## A walkway in its four mirrorings, side by side.
func _walkway(registry: RegistryScript, room: RoomBase) -> void:
	var pieces: Array[Image] = []
	for mirror: int in PieceShape.MIRRORINGS:
		pieces.append(_drawn(registry, room, mirror, true))
	var w: int = 0
	var h: int = 0
	for piece: Image in pieces:
		w += piece.get_width() + GAP
		h = maxi(h, piece.get_height())
	var sheet := Image.create(w - GAP, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.3, 0.3, 0.3))
	var x: int = 0
	for piece: Image in pieces:
		sheet.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i(x, 0))
		x += piece.get_width() + GAP
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	save(sheet, "walkway_%s" % room.id)


## A crypt map made in `style`, every piece drawn at its place.
func _map_of_style(registry: RegistryScript, crypt: RunDefinition, style: MapStyle) -> void:
	var rules := (crypt.biomes[0] as MapRules).duplicate() as MapRules
	rules.styles = [style] as Array[MapStyle]
	var definition := crypt.duplicate() as RunDefinition
	definition.biomes = [rules] as Array[MapRules]
	var content: RunContent = registry.run_content()
	var shapes: Dictionary = registry.piece_shapes(&"crypt")
	var map: BiomeMap = null
	for seed_value in SEEDS:
		var made: BiomeMap = BiomeGenerator.generate(definition, content, shapes, Sim.seeded(seed_value))
		if not made.is_made():
			continue
		if map == null:
			map = made
		if style.loops == 0 or made.bridges() >= made.rooms():
			map = made
			break
	if map == null:
		fail("no %s map of the crypt was made" % style.id)
		return
	var pieces: Array = []  # [template, place, mirror]
	for room in map.rooms():
		pieces.append([map.room_templates[room], map.room_places[room], map.room_mirrors[room]])
	for bridge in map.bridges():
		pieces.append([map.bridge_templates[bridge], map.bridge_places[bridge], map.bridge_mirrors[bridge]])
	var size := Vector2i.ZERO
	var drawn: Array[Image] = []
	for piece: Array in pieces:
		var image: Image = _drawn(registry, registry.get_resource(&"rooms", piece[0]) as RoomBase, piece[2], false)
		drawn.append(image)
		size = size.max(Vector2i(piece[1]) + image.get_size())
	var whole := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	whole.fill(VOID)
	for i in pieces.size():
		var image: Image = drawn[i]
		whole.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(pieces[i][1]))
	whole.resize(maxi(1, size.x / 4), maxi(1, size.y / 4), Image.INTERPOLATE_BILINEAR)
	save(whole, "biome_map_%s" % style.id)


## `room`'s ground as the game draws it in `mirror`: its rock face under its floor, over the void's
## dark when `backed` (else clear where nothing is drawn, so on a map a piece leaves its neighbours be).
func _drawn(registry: RegistryScript, room: RoomBase, mirror: int, backed: bool) -> Image:
	var flip := Vector2i(1 if mirror & PieceShape.MIRROR_X else 0, 1 if mirror & PieceShape.MIRROR_Y else 0)
	var spec: Dictionary = ShapeScript.spec(room.ground_shape.data, room.scene, registry, flip)
	var art: Dictionary = ShapeScript.draw(spec)
	var w: int = art["width"]
	var h: int = art["height"]
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, art["under"])
	var floor := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, art["floor"])
	image.blend_rect(floor, Rect2i(0, 0, w, h), Vector2i.ZERO)
	if not backed:
		return image
	var dark := Image.create(w, h, false, Image.FORMAT_RGBA8)
	dark.fill(VOID)
	dark.blend_rect(image, Rect2i(0, 0, w, h), Vector2i.ZERO)
	return dark
