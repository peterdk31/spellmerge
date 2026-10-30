extends PanelContainer
## One seat's box in the horde's build break (horde, H5), beside the seat's corner panel toward
## the middle, in the seat's border colour (`PlayerPanel1-4`). It shows one of three things
## (`mode()`):
## - **OFFER:** "Level up!" in the seat's colour, up to three cards (`pick_card.gd`) and a hint
##   row with the buttons that choose and take.
## - **PROMPT** (every pick taken, the seat not ready): "Build, then ready" and a hint row with
##   `back` (B) "Build" and `accept` (A) "Ready".
## - **READY:** "Ready" alone, while the others finish.
## Display and choice only: `horde_panel.gd` reads the seat's input and sends the requests.

const PickCardScript := preload("res://hud/panels/horde/pick_card.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

const MAX_CARDS: int = 3
const NONE: int = -1
enum Mode { HIDDEN, OFFER, PROMPT, READY }
const TITLE: String = "Level up!"
const PROMPT_TITLE: String = "Build, then ready"
const READY_TITLE: String = "Ready"
const CHOOSE_VERB: String = "Choose"
const TAKE_VERB: String = "Take"
const BUILD_VERB: String = "Build"
const READY_VERB: String = "Ready"
## The buttons: the d-pad's left and right (`kind_prev`, `kind_next`; PgUp, PgDn) and `accept`
## (A; Enter). P1's mouse points and clicks too.
const PREV_ACTION: StringName = &"kind_prev"
const NEXT_ACTION: StringName = &"kind_next"
const TAKE_ACTION: StringName = &"accept"
## The prompt's buttons: `back` (B; Tab, E) opens the builder (`hud/panels`), `accept` (A; Enter)
## says ready.
const BUILD_ACTION: StringName = &"back"
const READY_ACTION: StringName = &"accept"

## The seat 0-3. Set before adding the node to the tree.
var seat: int = 0

var _cards: Array[PickCardScript] = []
var _ids: Array[StringName] = []
var _choice: int = NONE
var _mode: Mode = Mode.HIDDEN
var _title: Label = null
var _hints: HBoxContainer = null
var _prompt_hints: HBoxContainer = null
var _glyphs: Array[ActionGlyphScript] = []
## The action of each glyph in `_glyphs`, in order.
var _glyph_actions: Array[StringName] = []


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
	_hints = _hint_row("Hints")
	column.add_child(_hints)
	for action: StringName in [PREV_ACTION, NEXT_ACTION]:
		_hints.add_child(_glyph(action))
	_hints.add_child(_verb(CHOOSE_VERB))
	_hints.add_child(_gap())
	_hints.add_child(_glyph(TAKE_ACTION))
	_hints.add_child(_verb(TAKE_VERB))
	_prompt_hints = _hint_row("PromptHints")
	column.add_child(_prompt_hints)
	_prompt_hints.add_child(_glyph(BUILD_ACTION))
	_prompt_hints.add_child(_verb(BUILD_VERB))
	_prompt_hints.add_child(_gap())
	_prompt_hints.add_child(_glyph(READY_ACTION))
	_prompt_hints.add_child(_verb(READY_VERB))
	_show_mode(Mode.HIDDEN)


func _hint_row(row_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 2)
	return row


func _gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(4.0, 0.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _glyph(action: StringName) -> ActionGlyphScript:
	var glyph: ActionGlyphScript = ActionGlyphScript.new()
	glyph.name = "Glyph_" + String(action)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_glyphs.append(glyph)
	_glyph_actions.append(action)
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
	for at in _glyphs.size():
		_glyphs[at].bind(input)
		_glyphs[at].show_action(seat, _glyph_actions[at])


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
	_show_mode(Mode.OFFER)
	choose(0)


## Drop the offer: nothing shown, nothing chosen.
func clear() -> void:
	_ids.clear()
	_choice = NONE
	for card in _cards:
		card.visible = false
		card.set_chosen(false)
	_show_mode(Mode.HIDDEN)


## Every pick taken: ask the seat to build and say ready (drops an offer).
func show_prompt() -> void:
	clear()
	_show_mode(Mode.PROMPT)


## The seat is ready (drops an offer).
func show_ready() -> void:
	clear()
	_show_mode(Mode.READY)


## What the box shows now.
func mode() -> Mode:
	return _mode


func _show_mode(next: Mode) -> void:
	_mode = next
	match next:
		Mode.OFFER:
			_title.text = TITLE
		Mode.PROMPT:
			_title.text = PROMPT_TITLE
		Mode.READY:
			_title.text = READY_TITLE
	_hints.visible = next == Mode.OFFER
	_prompt_hints.visible = next == Mode.PROMPT


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
