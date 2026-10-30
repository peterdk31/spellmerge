extends PanelContainer
## One seat's level-up pick (horde, H5): "Level up!" in the seat's colour, up to three cards
## (`pick_card.gd`) and a hint row with the buttons that choose and take. It sits beside the
## seat's corner panel, toward the middle, in the seat's border colour (`PlayerPanel1-4`).
## Display and choice only: `horde_panel.gd` reads the seat's input and sends the request.

const PickCardScript := preload("res://hud/panels/horde/pick_card.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

const MAX_CARDS: int = 3
const NONE: int = -1
const TITLE: String = "Level up!"
const CHOOSE_VERB: String = "Choose"
const TAKE_VERB: String = "Take"
## The buttons: the d-pad's left and right (`kind_prev`, `kind_next`; PgUp, PgDn) and `accept`
## (A; Enter). P1's mouse points and clicks too.
const PREV_ACTION: StringName = &"kind_prev"
const NEXT_ACTION: StringName = &"kind_next"
const TAKE_ACTION: StringName = &"accept"

## The seat 0-3. Set before adding the node to the tree.
var seat: int = 0

var _cards: Array[PickCardScript] = []
var _ids: Array[StringName] = []
var _choice: int = NONE
var _title: Label = null
var _glyphs: Array[ActionGlyphScript] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	_title = Label.new()
	_title.name = "Title"
	_title.text = TITLE
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)
	for at in MAX_CARDS:
		var card: PickCardScript = PickCardScript.new()
		card.name = "Card%d" % (at + 1)
		card.visible = false
		column.add_child(card)
		_cards.append(card)
	var hints := HBoxContainer.new()
	hints.name = "Hints"
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", 2)
	column.add_child(hints)
	for action in [PREV_ACTION, NEXT_ACTION]:
		hints.add_child(_glyph(String(action)))
	hints.add_child(_verb(CHOOSE_VERB))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(4.0, 0.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_child(gap)
	hints.add_child(_glyph(String(TAKE_ACTION)))
	hints.add_child(_verb(TAKE_VERB))


func _glyph(glyph_name: String) -> ActionGlyphScript:
	var glyph: ActionGlyphScript = ActionGlyphScript.new()
	glyph.name = "Glyph_" + glyph_name
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_glyphs.append(glyph)
	return glyph


func _verb(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"BuilderHint"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## Take the seat's colours and its buttons' glyphs from `input` (null: the "PlayerInput"
## autoload). Called once by `horde_panel.gd`.
func bind(input: InputManagerScript) -> void:
	theme_type_variation = StringName("PlayerPanel%d" % (seat + 1))
	_title.theme_type_variation = StringName("PlayerLabel%d" % (seat + 1))
	var actions: Array[StringName] = [PREV_ACTION, NEXT_ACTION, TAKE_ACTION]
	for at in _glyphs.size():
		_glyphs[at].bind(input)
		_glyphs[at].show_action(seat, actions[at])


## Show the offer `card_ids` (the first MAX_CARDS), named and drawn by `spells` (null: the ids),
## with the first card chosen.
func offer(card_ids: Array[StringName], spells: SpellsScript) -> void:
	_ids.clear()
	for at in mini(card_ids.size(), MAX_CARDS):
		_ids.append(card_ids[at])
	for at in MAX_CARDS:
		var card: PickCardScript = _cards[at]
		card.visible = at < _ids.size()
		if not card.visible:
			continue
		var id: StringName = _ids[at]
		var shown: String = spells.component_name(id) if spells != null else ""
		if shown == "":
			shown = String(id).capitalize()
		var icon: Texture2D = spells.component_icon(id) if spells != null else null
		var kind: StringName = spells.component_kind(id) if spells != null else &""
		card.show_card(id, shown, icon, kind)
	_choice = NONE
	choose(0)


## Drop the offer: nothing shown, nothing chosen.
func clear() -> void:
	_ids.clear()
	_choice = NONE
	for card in _cards:
		card.visible = false
		card.set_chosen(false)


func has_offer() -> bool:
	return not _ids.is_empty()


func offered() -> Array[StringName]:
	return _ids.duplicate()


## Choose card `at` (0 to the offer's size - 1; out of range does nothing).
func choose(at: int) -> void:
	if at < 0 or at >= _ids.size():
		return
	_choice = at
	for index in MAX_CARDS:
		_cards[index].set_chosen(index == at)


## Move the choice by `step`, wrapping round.
func step_choice(step: int) -> void:
	if _ids.is_empty() or step == 0:
		return
	choose(posmod(_choice + step, _ids.size()))


## The chosen card's place in the offer, or NONE.
func choice() -> int:
	return _choice


## The card under `point` (global, in the view's pixels), or NONE.
func card_at(point: Vector2) -> int:
	if not is_visible_in_tree():
		return NONE
	for at in _ids.size():
		if _cards[at].get_global_rect().has_point(point):
			return at
	return NONE


func card(at: int) -> PickCardScript:
	return _cards[at] if at >= 0 and at < MAX_CARDS else null
