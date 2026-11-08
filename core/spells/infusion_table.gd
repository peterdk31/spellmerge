class_name InfusionTable
extends RefCounted
## Every infusion's colour by its look layer (the owner, 2026-11-08: a carrier with several infusions
## should show each of them, "for all carriers/cards", "enabled by default"). A shot's look bits
## (`ProjectileManager.pack_look`) already say which cards it carries, an infusion's by its
## `ElementBase.look_layer` (fire 1, frost 2, ...); this table turns the infusion layers among them
## into colours, so anything drawn with a look knows every infusion on it with nothing more handed
## per shot:
##
## - **The shaders** read it as the global uniform `infusion_tints` (project.godot, `[shader_globals]`),
##   a LAYERS x 1 texture: `shot_look.gdshaderinc` weaves a look of several infusions out of their
##   ramps, so every card shader and flash that includes it shows them (`publish`, from Spells at start).
## - **The motes** take their colours from it (`Motes.set_infusions`): a mote of an infusion's own
##   kind is in that infusion's colours, any other mote of a spell of several takes them in turn.
##
## Made from the cards, so a new infusion shows with no edit. An infusion's texel has alpha MARK
## (not 1): a texture never published reads white or black everywhere, and neither is an infusion.

## Look layers the table covers (a look's bits: `ProjectileManager.LOOK_COUNT` is less).
const LAYERS: int = 32
## The global shader uniform it is published as, and the alpha that marks an infusion's texel
## (the shader's INFUSION_MARK).
const PARAMETER: StringName = &"infusion_tints"
const MARK: float = 128.0 / 255.0
## The registry folder the cards are in.
const SPELL_FOLDER: StringName = &"spells"


## The table of the infusion cards among `cards`: LAYERS colours, an infusion's layer its tint
## (alpha 1), every other transparent. Two infusions of one layer: the first by id keeps it (a test
## names them: an infusion's layer is how it is known).
static func of_cards(cards: Array) -> PackedColorArray:
	var table := PackedColorArray()
	table.resize(LAYERS)
	table.fill(Color(0.0, 0.0, 0.0, 0.0))
	var infusions: Array[ElementBase] = []
	for card: Variant in cards:
		var element := card as ElementBase
		if element != null and element.look_layer > 0 and element.look_layer < LAYERS:
			infusions.append(element)
	infusions.sort_custom(func(a: ElementBase, b: ElementBase) -> bool: return String(a.id) < String(b.id))
	for element in infusions:
		if table[element.look_layer].a <= 0.0:
			table[element.look_layer] = Color(element.tint.r, element.tint.g, element.tint.b, 1.0)
	return table


## The table of the cards in `registry` (anything with `get_all(folder)`; null: none).
static func of_registry(registry: Object) -> PackedColorArray:
	if registry == null or not registry.has_method(&"get_all"):
		return of_cards([])
	return of_cards(registry.call(&"get_all", SPELL_FOLDER))


## The look bits of the table's infusions (layer n is bit n - 1, as in a look).
static func mask(table: PackedColorArray) -> int:
	var bits: int = 0
	for layer in range(1, mini(table.size(), LAYERS)):
		if table[layer].a > 0.0:
			bits |= 1 << (layer - 1)
	return bits


## The table as the shaders read it: a LAYERS x 1 texture, an infusion's texel its tint with
## alpha MARK, every other transparent.
static func texture(table: PackedColorArray) -> ImageTexture:
	var image: Image = Image.create_empty(LAYERS, 1, false, Image.FORMAT_RGBA8)
	for layer in mini(table.size(), LAYERS):
		var tint: Color = table[layer]
		image.set_pixel(layer, 0, Color(tint.r, tint.g, tint.b, MARK) if tint.a > 0.0 else Color(0.0, 0.0, 0.0, 0.0))
	return ImageTexture.create_from_image(image)


## Hand the table to every shader that reads it (the global uniform PARAMETER). Once, at start
## (`Spells.register_bodies`); again only if the cards change.
static func publish(table: PackedColorArray) -> void:
	RenderingServer.global_shader_parameter_set(PARAMETER, texture(table))
