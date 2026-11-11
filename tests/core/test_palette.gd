extends "res://tests/support/suite.gd"
## The palette by name (core/base/palette.gd) is the style guide's (docs/STYLE.md, "Palette"):
## every material with its three shades and the outline, nothing more; a mote's ramp from a
## material; the world's colours may not name a player's or Blight.

const STYLE: String = "res://docs/STYLE.md"


## The guide's table: {material name in lower case (spaces as `_`): [shadow, base, light]}, and the
## outline's colour under "outline".
func _guide() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(STYLE)
	var start: int = text.find("## Palette")
	var end: int = text.find("\n## ", start + 1)
	var found: Dictionary = {}
	var row := RegEx.create_from_string("^\\| \\*\\*([A-Za-z0-9 ]+)\\*\\*[^|]*\\|([^|]*)\\|([^|]*)\\|([^|]*)\\|")
	var hex := RegEx.create_from_string("#[0-9a-f]{6}")
	for line: String in text.substr(start, end - start).split("\n"):
		var match: RegExMatch = row.search(line)
		if match == null:
			continue
		var shades := PackedStringArray()
		for column in [2, 3, 4]:
			var colour: RegExMatch = hex.search(match.get_string(column))
			if colour != null:
				shades.append(colour.get_string())
		found[match.get_string(1).strip_edges().to_lower().replace(" ", "_")] = shades
	return found


func test_the_palette_is_the_style_guides() -> void:
	var guide: Dictionary = _guide()
	check(guide.size() >= 15, "the guide's table is read (%d rows)" % guide.size())
	check_equal(guide.get("outline"), PackedStringArray(["#" + Palette.OUTLINE.to_html(false)]), "the outline")
	for name: String in guide:
		if name == "outline":
			continue
		check(Palette.has(StringName(name)), "%s is a material by name" % name)
		var shades := PackedStringArray()
		for shade: Color in Palette.shades_of(StringName(name)):
			shades.append("#" + shade.to_html(false))
		check_equal(shades, guide[name], "%s's shadow, base and light" % name)
	check_equal(Palette.MATERIALS.size(), guide.size() - 1, "no material the guide lacks")
	check_equal(Palette.hex_colours().size(), 43, "43 colours, as the guide says")


func test_a_ramp_is_white_hot_then_light_base_shadow() -> void:
	check_equal(Palette.ramp_of(&"fire"), PackedColorArray([Color("f4f1ea"), Color("ffa23c"), Color("e0592f"), Color("8f2d2a")]), "fire's")
	check_equal(Palette.ramp_of(&"nothing"), PackedColorArray(), "no such material: none")


func test_the_worlds_colours_name_no_owned_material() -> void:
	check(Palette.world_problems([&"fire", &"stone"], "x").is_empty(), "fire and stone are the world's")
	check(Palette.world_problems([&"player_2"], "x")[0].contains("belongs to the players"), "a player's colour is not")
	check(Palette.world_problems([&"blight"], "x")[0].contains("belongs to"), "nor Blight")
	check(Palette.world_problems([&"teal"], "x")[0].contains("no palette material"), "an unknown name")
