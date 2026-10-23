extends HBoxContainer
## One line that says what a button does: the glyph of the button, then the verb ("[X] Use").
## A second pair can follow ("[B] back"). Display only.
##
##     line.show_hint(player, &"cast", "Use", &"dodge", "back")
##     line.show_hint(player, &"cast", "Close")    # one pair
##     line.show_hint(player, &"", "")             # nothing: the line is empty
##
## The glyphs follow the player's controller live (`action_glyph.gd`).

const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

## The theme variation of the verbs.
const VERB_VARIATION: StringName = &"BuilderHint"
const GLYPH_GAP: int = 2

var _glyphs: Array[Control] = []
var _verbs: Array[Label] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", GLYPH_GAP)
	for pair in 2:
		var glyph: Control = ActionGlyphScript.new()
		glyph.name = "Glyph%d" % pair
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		glyph.visible = false
		add_child(glyph)
		_glyphs.append(glyph)
		var verb := Label.new()
		verb.name = "Verb%d" % pair
		verb.theme_type_variation = VERB_VARIATION
		verb.visible = false
		add_child(verb)
		_verbs.append(verb)


## Use this input manager for the glyphs; null uses the "PlayerInput" autoload.
func bind(input: InputManagerScript) -> void:
	for glyph in _glyphs:
		glyph.bind(input)


## Show `verb` with the glyph of `action` for `player`, then optionally `second_verb` with
## `second_action`. An empty verb hides the pair.
func show_hint(player: int, action: StringName, verb: String, second_action: StringName = &"", second_verb: String = "") -> void:
	_show_pair(0, player, action, verb)
	_show_pair(1, player, second_action, second_verb)


## The words of the hint, the verbs joined by a comma ("Use, back"); "" when empty.
func text() -> String:
	var words: Array[String] = []
	for verb in _verbs:
		if verb.visible:
			words.append(verb.text)
	return ", ".join(words)


## The action shown by pair 0 or 1 (`&""` when hidden).
func action_of(pair: int) -> StringName:
	return (_glyphs[pair] as ActionGlyphScript).action() if _glyphs[pair].visible else &""


func glyph_node(pair: int) -> Control:
	return _glyphs[pair]


func _show_pair(pair: int, player: int, action: StringName, verb: String) -> void:
	var shown: bool = verb != "" and action != &""
	_glyphs[pair].visible = shown
	_verbs[pair].visible = shown
	_verbs[pair].text = verb
	if shown:
		(_glyphs[pair] as ActionGlyphScript).show_action(player, action)
