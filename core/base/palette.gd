class_name Palette
extends RefCounted
## The game's palette by name (docs/STYLE.md, "Palette"): the outline colour and the materials of
## three shades each, so data can name a colour as the art guide does (`&"fire"`) instead of writing
## its numbers. `tests/core/test_palette.gd` holds this table to the guide's, so they never part.
## Static only.
##
## A mote's ramp from a material (`ramp_of`) is white-hot first (Bone light, as every mote's white
## heat), then the material's light, base and shadow: the four shades a mote cools through.

## The outline colour, also the deepest shadow.
const OUTLINE: Color = Color("14121f")
## The white heat every ramp starts from: Bone light.
const WHITE_HOT: Color = Color("f4f1ea")

## Each material's shades, shadow, base, light (docs/STYLE.md's columns), by its name in lower case.
const MATERIALS: Dictionary[StringName, Array] = {
	&"stone": [Color("2b2840"), Color("4a4663"), Color("7a7694")],
	&"bone": [Color("a39fb8"), Color("d4d0e0"), Color("f4f1ea")],
	&"fire": [Color("8f2d2a"), Color("e0592f"), Color("ffa23c")],
	&"spark": [Color("b8801f"), Color("f2c230"), Color("fff3a6")],
	&"wood": [Color("3d2a2e"), Color("7a4a35"), Color("b27a4a")],
	&"skin": [Color("8a5a44"), Color("d99a74"), Color("f5cfa8")],
	&"ice": [Color("1f7080"), Color("4fd6dc"), Color("c4f6f2")],
	&"void": [Color("4a1450"), Color("a0309a"), Color("e08ad8")],
	&"arc": [Color("3f6b10"), Color("b4e82a"), Color("eeffa6")],
	&"blight": [Color("4d3f12"), Color("a68a2a"), Color("e3cf6b")],
	&"player_1": [Color("1d3a6b"), Color("3b73c9"), Color("7fc0f0")],
	&"player_2": [Color("7a2347"), Color("d9477a"), Color("f59ab8")],
	&"player_3": [Color("1f4a3a"), Color("3f8f4f"), Color("8fd46a")],
	&"player_4": [Color("4a2a6b"), Color("8a4fc4"), Color("c99af0")],
}
## The materials that belong to someone (docs/STYLE.md: the players' own, and Blight the enemies'
## spells): the world's art and its motes never use them.
const OWNED: Array[StringName] = [&"blight", &"player_1", &"player_2", &"player_3", &"player_4"]


## True when `material` is one of the palette's materials.
static func has(material: StringName) -> bool:
	return MATERIALS.has(material)


## The shades of `material`: shadow, base, light (empty for a name the palette does not have).
static func shades_of(material: StringName) -> PackedColorArray:
	return PackedColorArray(MATERIALS.get(material, []))


## The ramp a mote of `material` cools through: white-hot, then its light, base and shadow; empty for
## a name the palette does not have.
static func ramp_of(material: StringName) -> PackedColorArray:
	var shades: PackedColorArray = shades_of(material)
	if shades.size() != 3:
		return PackedColorArray()
	return PackedColorArray([WHITE_HOT, shades[2], shades[1], shades[0]])


## Every colour of the palette (the outline and each material's shades), as lower-case hex with '#'.
static func hex_colours() -> PackedStringArray:
	var found := PackedStringArray(["#" + OUTLINE.to_html(false)])
	for material: StringName in MATERIALS:
		for shade: Color in shades_of(material):
			found.append("#" + shade.to_html(false))
	return found


## What is wrong with naming `materials` for the world's colours, one line each: a name the palette
## does not have, or one that belongs to the players or the enemies' spells.
static func world_problems(materials: Array[StringName], owner: String) -> PackedStringArray:
	var found := PackedStringArray()
	for material in materials:
		if not has(material):
			found.append("%s: '%s' is no palette material (%s)" % [owner, material, ", ".join(PackedStringArray(MATERIALS.keys()))])
		elif OWNED.has(material):
			found.append("%s: '%s' belongs to the players or the enemies' spells (docs/STYLE.md)" % [owner, material])
	return found
