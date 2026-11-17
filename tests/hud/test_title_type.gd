extends "res://tests/support/suite.gd"
## The title type (docs/milestones/boss-intro.md, rule 7; BI3): `art/ui/fonts/title.svg`, a
## bitmap face on a 12×16 grid drawn from `title.grid.json` by tools/pixel_grid.py and imported
## by Godot's image font importer, loads as a font with a glyph for every printable ASCII
## character, a cell wide each, at whole-number scales only; the title theme's `TitleLabel` draws it
## at 2×, and the boss intro wears that theme; every boss's shown name has a glyph for each of its
## characters; and the project theme names no file at all, as it is loaded before the first import.

const RegistryScript := preload("res://core/registry/registry.gd")
const TitleTheme := preload("res://hud/theme/title_theme.tres")
const BossIntroScript := preload("res://hud/panels/boss/boss_intro.gd")
const PROJECT_THEME_PATH: String = "res://hud/theme/spellmerge_theme.tres"
const TITLE_FONT_PATH: String = "res://art/ui/fonts/title.svg"
## The face's cell (rule 7) and the scale a boss's name is drawn at.
const CELL := Vector2i(12, 16)
const NAME_SCALE: int = 2
## Printable ASCII, space to tilde.
const FIRST_CHAR: int = 0x20
const LAST_CHAR: int = 0x7e


static func _title_font() -> FontFile:
	return load(TITLE_FONT_PATH) as FontFile


static func _missing(font: Font, text: String) -> String:
	var missing: String = ""
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		if not font.has_char(code) and not missing.contains(char(code)):
			missing += char(code)
	return missing


func test_it_loads_as_a_bitmap_font() -> void:
	var font: FontFile = _title_font()
	check(font != null, "%s loads as a FontFile (its .import is the image font importer's)" % TITLE_FONT_PATH)
	if font == null:
		return
	check_equal(font.fixed_size, CELL.y, "a bitmap face, as tall as its cell")
	check_equal(font.fixed_size_scale_mode, TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY, "drawn at whole-number scales only")
	check_equal(font.get_height(CELL.y), float(CELL.y), "its line is its cell")


func test_every_printable_ascii_character_has_a_glyph_a_cell_wide() -> void:
	var font: FontFile = _title_font()
	if font == null:
		check(false, "no title font to check")
		return
	for code: int in range(FIRST_CHAR, LAST_CHAR + 1):
		check(font.has_char(code), "a glyph for '%s' (%d)" % [char(code), code])
		check_equal(font.get_char_size(code, CELL.y).x, float(CELL.x), "'%s' is a cell wide" % char(code))
	check(not font.has_char(0xe9), "nothing past ASCII: a name with 'é' is caught by the names' test")


func test_title_label_draws_it_at_twice_its_size() -> void:
	var theme: Theme = TitleTheme
	check_equal(theme.get_type_variation_base(&"TitleLabel"), &"Label", "TitleLabel is a Label's look")
	check(theme.get_font(&"font", &"TitleLabel") == _title_font(), "TitleLabel uses the title type")
	check_equal(theme.get_font_size(&"font_size", &"TitleLabel"), CELL.y * NAME_SCALE, "a boss's name at 2×")
	check_equal(theme.get_constant(&"outline_size", &"TitleLabel"), 0, "a bitmap face has no outline: its shadow stands for it")
	var label := own(Label.new()) as Label
	label.theme = theme
	label.theme_type_variation = &"TitleLabel"
	label.text = "Broom"
	root.add_child(label)
	check_equal(label.get_minimum_size().x, float(CELL.x * NAME_SCALE * label.text.length()), "five letters, each a doubled cell")


func test_the_boss_intro_draws_the_name_in_the_title_type() -> void:
	var intro := own(BossIntroScript.new()) as BossIntroScript
	root.add_child(intro)
	check(intro.get_theme_font(&"font", &"TitleLabel") == _title_font(), "the intro finds TitleLabel's font through its own theme")
	check(intro.get_theme_font(&"font", &"Label") != _title_font(), "its other text keeps the project theme's font")


## Regression (the preview build, from BI3 on): the engine loads the project theme at its start,
## before the first scan, so on a fresh checkout an imported file it names is not there yet and the
## import step logs errors. A look that needs one (the title type) is a theme of its own.
func test_the_project_theme_names_no_file() -> void:
	check_equal(ProjectSettings.get_setting("gui/theme/custom"), PROJECT_THEME_PATH, "the project theme is the one checked here")
	check_equal(ResourceLoader.get_dependencies(PROJECT_THEME_PATH), PackedStringArray(), "the project theme depends on nothing: it loads before any import")


func test_every_boss_name_has_its_glyphs() -> void:
	var font: FontFile = _title_font()
	if font == null:
		check(false, "no title font to check")
		return
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var bosses: int = 0
	for folder: StringName in EnemyBase.FOLDERS:
		for res: Resource in registry.get_all(folder):
			var data := res as EnemyBase
			if data == null or not data.boss:
				continue
			bosses += 1
			var shown: String = data.shown_name()
			check_equal(_missing(font, shown), "", "%s's name '%s' has a glyph for each character" % [data.id, shown])
	check(bosses > 0, "the scan found the bosses (the old broom at least)")


func test_a_name_past_the_face_is_caught() -> void:
	var font: FontFile = _title_font()
	if font == null:
		check(false, "no title font to check")
		return
	check_equal(_missing(font, "The Old Broom"), "", "a plain name is covered")
	check_equal(_missing(font, "Café Ghöst"), "éö", "each character with no glyph, once")
