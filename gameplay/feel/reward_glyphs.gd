extends RefCounted
## A reward room's type as the view draws it (the owner's ask of 2026-11-19: "make the reward rooms
## state which card type they contain"): small glyphs beside the room's kind symbol (`kind_symbol.gd`),
## on its mouths' signs (`mouth_symbols.gd`) and on the held map (`party_map_view.gd`). One glyph a
## level the type names (`RewardType`): its item kind (a card, a potion, coins) in bone; a card's
## kind in that kind's own light (the HUD's colours for the kinds, hud/widgets/card_kinds.gd); an
## element as a gem in its element's light (the palette material nearest `ElementBase.tint`). Whole
## pixels with a dark edge, drawn by `kind_symbol.gd` and rising by rows with the symbol (Smooth:
## SIDE frames). Pictures of SIDE rows of SIDE ('#' lit, '+' base, '.' none). View only.

const KindSymbolScript := preload("res://gameplay/feel/kind_symbol.gd")

## A glyph's side and the gap between two glyphs, in pixels (a symbol pixel each).
const SIDE: int = 5
const GAP: int = 2
## The registry folder the element cards are in.
const CARD_FOLDER: StringName = &"spells"

## Each item kind's glyph, in bone; an item kind with none shows UNKNOWN.
const ITEM_LIGHT: StringName = &"bone"
const ITEM_PICTURES: Dictionary = {
	&"card": ".###.\n.#+#.\n.#+#.\n.#+#.\n.###.",
	&"potion": "..#..\n..#..\n.#+#.\n#+++#\n.###.",
	&"coin": ".###.\n#+++#\n#+#+#\n#+++#\n.###.",
}
const UNKNOWN: String = ".###.\n...#.\n..#..\n.....\n..#.."
## Each card kind's glyph and light.
const KIND_PICTURES: Dictionary = {
	&"carrier": "..#..\n.###.\n#+#+#\n..#..\n..#..",
	&"modifier": "..#..\n..#..\n#####\n..#..\n..#..",
	&"element": "..#..\n.#+#.\n#+++#\n#+++#\n.###.",
	&"trigger": "..#..\n..#..\n..#..\n.....\n..#..",
	&"multicast": "#...#\n.....\n..#..\n.....\n#...#",
}
const KIND_LIGHTS: Dictionary = {
	&"carrier": &"fire", &"modifier": &"ice", &"element": &"arc", &"trigger": &"void", &"multicast": &"bone",
}
## An element's glyph, in its element's light.
const ELEMENT_PICTURE: String = "..#..\n.#+#.\n#+#+#\n.#+#.\n..#.."


## The glyphs of `type` (null: none) into `pixels` and `shades` (cleared first), in order: its item
## kind's, its card kind's, its element's; `element` the element card (null: the spark's light).
static func glyphs_of(type: RewardType, element: Resource, pixels: Array[PackedByteArray], shades: Array[PackedColorArray]) -> void:
	pixels.clear()
	shades.clear()
	if type == null or type.is_any():
		return
	pixels.append(pixels_of(str(ITEM_PICTURES.get(type.item, UNKNOWN))))
	shades.append(Palette.shades_of(ITEM_LIGHT))
	if type.card_kind != &"":
		pixels.append(pixels_of(str(KIND_PICTURES.get(type.card_kind, UNKNOWN))))
		shades.append(Palette.shades_of(KIND_LIGHTS.get(type.card_kind, ITEM_LIGHT)))
	if type.element != &"":
		pixels.append(pixels_of(ELEMENT_PICTURE))
		shades.append(element_shades(element as ElementBase))


## The shades of the palette material nearest `element`'s tint (the spark's with none).
static func element_shades(element: ElementBase) -> PackedColorArray:
	if element == null:
		return Palette.shades_of(KindSymbolScript.DEFAULT_LIGHT)
	var best: StringName = KindSymbolScript.DEFAULT_LIGHT
	var nearest: float = INF
	for material: StringName in Palette.MATERIALS:
		var ramp: PackedColorArray = Palette.shades_of(material)
		# A player's own colours, and the owned ones, are never a room's (docs/STYLE.md).
		if ramp.size() != 3 or Palette.OWNED.has(material):
			continue
		for shade: Color in ramp:
			var away: float = Vector3(shade.r - element.tint.r, shade.g - element.tint.g, shade.b - element.tint.b).length_squared()
			if away < nearest:
				nearest = away
				best = material
	return Palette.shades_of(best)


## A picture's pixels, row by row (KindSymbol's values: RoomKind.SYMBOL_NONE, _BASE, _LIT).
static func pixels_of(picture: String) -> PackedByteArray:
	var out := PackedByteArray()
	for line in picture.split("\n"):
		for at in SIDE:
			var pixel: String = line.substr(at, 1)
			out.append(RoomKind.SYMBOL_LIT if pixel == "#" else (RoomKind.SYMBOL_BASE if pixel == "+" else RoomKind.SYMBOL_NONE))
	return out


## The width of `count` glyphs in a row (pixels at size 1).
static func row_width(count: int) -> int:
	return count * SIDE + maxi(count - 1, 0) * GAP


## Where glyph `index` stands from the first's corner: along a row (`across`) or down a column.
static func offset_of(index: int, across: bool, size: int = 1) -> Vector2:
	var step: int = (SIDE + GAP) * index * size
	return Vector2(step, 0) if across else Vector2(0, step)


## Draw `pixels`' glyphs (with `shades`) on `canvas` from `at`, along a row (`across`) or down a
## column, `rows` of each shown (0 none ... SIDE all), `size` screen pixels a glyph pixel.
static func draw(canvas: CanvasItem, pixels: Array[PackedByteArray], shades: Array[PackedColorArray], at: Vector2, across: bool, rows: int, size: int = 1) -> void:
	if rows <= 0:
		return
	for index in pixels.size():
		KindSymbolScript.draw(canvas, pixels[index], shades[index], at + offset_of(index, across, size), mini(rows, SIDE), size, SIDE)
