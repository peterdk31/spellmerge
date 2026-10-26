extends PanelContainer
## One player's spell builder (M2 part 16): the corner panel expanded toward the middle
## of the screen, with the slot chain on the left and the bag on the right. Opened from
## the player's overlay ("Build"), closed by its owner, never pausing the game.
##
## What it shows comes only from events: `recipe_changed` (the two prepared spells as
## recipes of component ids) and `bag_changed` (the ids the player may build with); the
## names and icons come from `Spells`. What it asks for goes out as
## `build_change_requested(player, spell path, slot, component id)`; the player checks the
## request and answers with a new `recipe_changed` (or refuses), so this node never changes
## a recipe itself. Nothing here reads the player or any other player's builder.
##
## Controls (through `core/ui_focus`, so only the owner's device works them): up/left and
## down/right move through the controls in order, `cast` activates and `dodge` goes back.
## Order: the spell tabs (A, B), "Close" (drawn beside them), the six slots (form, element,
## three modifiers, trigger), "< Up" and "Held >" (the spell a trigger holds, at most two
## levels down) and the bag rows. It opens on the form slot; a tab, "< Up" and "Held >" put
## focus on the form slot of the spell they show. Activating a slot selects it and moves focus
## to the bag row list, which shows only the components that fit the slot (plus "None" to
## empty a filled slot); activating a row sends the request, and a form or element that went
## into an empty slot moves on to the next slot's bag (so form + element is four presses).
## `dodge` on a bag row goes back to its slot, and anywhere else closes the builder. The focused control is marked
## with "> " and the selected slot is shown in brackets, so nothing is shown by colour alone.
##
## The quick view (M2 part 18): when a wave starts (`set_quick(true)`, called by `panels.gd`) an
## open builder folds into the quick view, and one opened during a wave starts as it. It keeps the
## slot chain of the active spell on show (read only), hides the tabs, the held levels, the bag
## and the info panel, and offers "Bag" and "Close". "Bag" opens a list titled "Drop" of the bag
## components that fit a free slot (the empty element slot, the first free modifier slot; see
## `hud/widgets/drop_choices.gd`) and activating one asks for it with `build_change_requested`
## like the full builder. When the wave is cleared (`set_quick(false)`) it unfolds again. The
## choices so far are kept, since they live in the player's recipes, not here.
##
## Part 17 adds an info panel (`Info`, in the free strip of the player's quarter): the complexity
## bar, the stats and a mini-preview of the spell shown (from `Spells.builder_view`), and a text
## line with the refusal reason (from `build_refused`) or the focused component's description.
##
## Every UIFocus signal carries a player index and this node ignores all but its own, so it
## is the same for any index 0-3. Buttons are made once; opening and activating only change
## their text and visibility (the bag rows grow, once, if the bag needs more of them).

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const SpellPreviewScript := preload("res://hud/builder/spell_preview.gd")
const DropChoicesScript := preload("res://hud/widgets/drop_choices.gd")
const HintLineScript := preload("res://hud/widgets/hint_line.gd")
const RowWindowScript := preload("res://hud/widgets/row_window.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

const PLAYER_COUNT: int = 4
## The slot numbers of `build_change_requested` (the contract of `gameplay/player`).
const SLOT_FORM: int = 0
const SLOT_ELEMENT: int = 1
const SLOT_FIRST_MODIFIER: int = 2
const SLOT_TRIGGER: int = 5
const SLOT_COUNT: int = 6
const SLOT_KINDS: Array[StringName] = [&"form", &"element", &"modifier", &"modifier", &"modifier", &"trigger"]
## Short on purpose: the slot column is narrow and the component name must stay readable
## with the focus mark and brackets added.
const SLOT_NAMES: Array[String] = ["Form", "Elem", "Mod 1", "Mod 2", "Mod 3", "Trig"]
## A trigger may hold a spell that holds another: two levels below the cast.
const MAX_LEVEL: int = 2
const SPELL_COUNT: int = 2
const SPELL_NAMES: Array[String] = ["A", "B"]
const NO_COMPONENT: StringName = &""

const DROP_TEXT: String = "Bag"
## The title while the quick view's list of components to drop is shown.
const DROP_TITLE: String = "Drop"
const NONE_TEXT: String = "None"
const EMPTY_SLOT_TEXT: String = "-"
const FOCUS_MARK: String = "> "
const CURRENT_MARK: String = " *"
## The look of every control: the BuilderButton theme variation.
const BUTTON_VARIATION: StringName = &"BuilderButton"
## The look of the control in focus: brighter, with a bright border (the "> " mark stays, so it
## is never colour alone).
const FOCUS_VARIATION: StringName = &"BuilderButtonFocus"
const ROW_HEIGHT: float = 18.0
## The quick view's drop list lists every element and modifier at once (11 with five
## elements), so its rows are lower and in a smaller font (8 px, as the hint line) to stay
## inside the builder's quarter of the screen. A row is the font's height plus 2 px of margin.
const QUICK_ROW_HEIGHT: float = 12.0
const QUICK_ROW_FONT: int = 8
const LEFT_WIDTH: float = 100.0
const RIGHT_WIDTH: float = 80.0
## The meta key that keeps a button's text without the focus mark.
const BASE_TEXT_META: StringName = &"base_text"

## The info panel (stats, complexity bar, mini-preview, refusal reason, description) sits in
## the strip of the player's quarter under (P1, P2) or over (P3, P4) the corner panel, so it
## covers nothing the builder or another player uses.
const INFO_WIDTH: float = 112.0
const INFO_HEIGHT: float = 112.0
const INFO_EDGE: float = 4.0
## Height of the corner panel plus its gap: where the strip starts.
const INFO_CORNER: float = 59.0
const PREVIEW_HEIGHT: float = 14.0
const NOTE_HEIGHT: float = 36.0
const COMPLEXITY_HEIGHT: float = 12.0
## Lines the note shows before it trims with an ellipsis (112 px wide, about 20 characters a line); a description must fit them
## (`test_builder.gd` checks every real one, and `StoryValidator.MAX_LORE_CHARS` caps the length).
const NOTE_LINES: int = 3
const LABEL_VARIATION: StringName = &"BuilderLabel"
const BAR_VARIATION: StringName = &"ComplexityBar"
## What the focused control does, one short line under the note: the glyph of `cast` (the
## button that activates) and this verb. A bag row also says what `dodge` does, with `HINT_BACK`.
const HINT_SLOT: String = "Pick a part"
const HINT_ROW: String = "Use"
const HINT_BACK: String = "back"
const HINT_TAB: String = "Show spell"
const HINT_CLOSE: String = "Close"
const HINT_UP: String = "Back up"
const HINT_HELD: String = "Held spell"
const HINT_DROP: String = "List parts"
const HINT_ACTION: StringName = &"cast"
const HINT_BACK_ACTION: StringName = &"dodge"
const HINT_HEIGHT: float = 10.0
const REFUSED_PREFIX: String = "Refused: "
const NO_STATS_TEXT: String = "-"

## The player index 0-3. Set before adding the node to the tree.
@export var index: int = 0

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
## How many controls UIFocus was given, and whether we are giving them again (not a real close).
var _synced_controls: int = 0
var _reopening: bool = false
var _spells: SpellsScript = null

## Mirrors of what the player announced.
var _recipes: Array[Dictionary] = [{}, {}]
var _bag: Array[StringName] = []
## The reason the player gave for the last refused change (cleared by the next request or change).
var _reason: String = ""

var _open: bool = false
## The quick view is on (a wave is in progress), and its "Bag" list is shown.
var _quick: bool = false
var _dropping: bool = false
## Whether the bag has a component that fits a free slot of the spell shown (quick view only).
var _can_drop: bool = false
## The active prepared spell of the player (from `active_spell_changed`), which the quick view shows.
var _active: int = 0
## The prepared spell shown (0 is A), how many held spells below it, the selected slot.
var _viewed: int = 0
var _level: int = 0
var _slot: int = SLOT_FORM
var _focused: Control = null

var _title: Label = null
var _tabs: Array[Button] = []
var _close: Button = null
var _slots: Array[Button] = []
var _up: Button = null
var _held: Button = null
var _drop: Button = null
var _levels_row: Control = null
var _bag_column: Control = null
## The bag rows sit in a list inside a clipping window, which scrolls in the quick view.
var _rows_window: Control = null
var _rows_holder: VBoxContainer = null
## The first drop row in view, and the title before the row count is added.
var _rows_first: int = 0
var _base_title: String = ""
## The left column; tighter in the quick view to make room for its hint line.
var _chain_column: Control = null
var _info: PanelContainer = null
var _complexity_label: Label = null
var _complexity_bar: ProgressBar = null
var _stats: Label = null
var _preview: SpellPreviewScript = null
var _note: Label = null
var _hint: HintLineScript = null
## The same hint in the quick view, where the info panel is hidden.
var _quick_hint: HintLineScript = null
var _rows: Array[Button] = []
## The component id each shown bag row asks for, in row order (`NO_COMPONENT` is "None").
var _row_ids: Array[StringName] = []
## The slot each shown bag row asks for: the selected slot, or in the drop list the free slot.
var _row_slots: Array[int] = []
## The controls given to UIFocus, in order.
var _controls: Array[Control] = []


func _ready() -> void:
	var player: int = clampi(index, 0, PLAYER_COUNT - 1)
	theme_type_variation = StringName("PlayerPanel%d" % (player + 1))
	custom_minimum_size = Vector2(LEFT_WIDTH + RIGHT_WIDTH + 4.0 + 8.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.add_theme_constant_override("separation", 4)
	add_child(columns)
	var left := VBoxContainer.new()
	left.name = "Chain"
	left.custom_minimum_size = Vector2(LEFT_WIDTH, 0.0)
	left.add_theme_constant_override("separation", 2)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.name = "Bag"
	_bag_column = right
	_chain_column = left
	right.custom_minimum_size = Vector2(RIGHT_WIDTH, 0.0)
	right.add_theme_constant_override("separation", 2)
	columns.add_child(right)
	_rows_holder = VBoxContainer.new()
	_rows_holder.name = "Rows"
	_rows_holder.custom_minimum_size = Vector2(RIGHT_WIDTH, 0.0)
	_rows_window = RowWindowScript.make_window("RowsWindow", _rows_holder, RIGHT_WIDTH)
	right.add_child(_rows_window)

	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = StringName("PlayerLabel%d" % (player + 1))
	left.add_child(_title)
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 2)
	left.add_child(tabs)
	for spell in SPELL_COUNT:
		var tab: Button = _make_button(tabs, "Tab%s" % SPELL_NAMES[spell])
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.append(tab)
	_close = _make_button(tabs, "Close")
	_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for slot in SLOT_COUNT:
		var button: Button = _make_button(left, "Slot%d" % slot)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_slots.append(button)
	var levels := HBoxContainer.new()
	levels.name = "Levels"
	_levels_row = levels
	levels.add_theme_constant_override("separation", 2)
	left.add_child(levels)
	_up = _make_button(levels, "Up")
	_up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_held = _make_button(levels, "Held")
	_held.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop = _make_button(left, "Drop")
	_drop.visible = false
	_quick_hint = HintLineScript.new()
	_quick_hint.name = "QuickHint"
	_quick_hint.visible = false
	left.add_child(_quick_hint)
	_make_info(player)
	visible = false
	_render()


## Connect to the event bus, the focus service and the spell runtime, which gives names, icons
## and kinds (called once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript, spells: SpellsScript, input: InputManagerScript = null) -> void:
	_hint.bind(input)
	_quick_hint.bind(input)
	_events = events
	_ui_focus = ui_focus
	_spells = spells
	if _events != null:
		_events.recipe_changed.connect(_on_recipe_changed)
		_events.bag_changed.connect(_on_bag_changed)
		_events.build_refused.connect(_on_build_refused)
		_events.active_spell_changed.connect(_on_active_spell_changed)
	if _ui_focus != null:
		_ui_focus.closed.connect(_on_closed)
		_ui_focus.activated.connect(_on_activated)
		_ui_focus.cancelled.connect(_on_cancelled)
		_ui_focus.focus_changed.connect(_on_focus_changed)


func is_open() -> bool:
	return _open


## Open the builder for its owner (replacing their overlay if it is open). False if the
## owner has no device. Starts on spell A, level 0, the form slot.
func open_builder() -> bool:
	if _open or _ui_focus == null:
		return false
	_viewed = _active if _quick else 0
	_level = 0
	_slot = SLOT_FORM
	_dropping = false
	_focused = null
	_reason = ""
	_place_info()
	_grow_rows(_most_rows())
	_render()
	# Close the overlay's panel first: its `closed` would hide this node if it came during open.
	_ui_focus.close(index)
	# Visible before opening: UIFocus only focuses controls that are shown.
	visible = true
	if not _ui_focus.open(index, _controls):
		visible = false
		return false
	_open = true
	_synced_controls = _controls.size()
	_focused = _ui_focus.focused(index)
	# A normal visit is "pick a slot": start on the form slot, not on the tabs.
	if not _quick:
		_focus_control(_slots[_slot])
	_apply_marks()
	return true


## Close the builder if it is open.
func close_builder() -> bool:
	if not _open or _ui_focus == null:
		return false
	return _ui_focus.close(index)


## Fold into the quick view (`true`, a wave is in progress) or unfold into the full builder
## (`false`). An open builder keeps its focus on the nearest control that still exists.
func set_quick(quick: bool) -> void:
	if quick == _quick:
		return
	_quick = quick
	_dropping = false
	_level = 0
	_slot = SLOT_FORM
	if quick:
		_viewed = _active
	# The mark must not stay on a slot the quick view stops listing: it is cleared by the render
	# and set again on the control that takes the focus.
	_focused = null
	_render()
	if _open:
		_resync_focus(true)
		_focus_control(_quick_focus_target() if quick else _slots[_slot])
		_apply_marks()


func is_quick() -> bool:
	return _quick


## Whether the quick view's "Bag" list is shown.
func is_dropping() -> bool:
	return _dropping


func drop_button() -> Button:
	return _drop


## The slot each shown bag row asks for, in order.
func row_slots() -> Array[int]:
	return _row_slots.duplicate()


## The prepared spell shown: 0 (A) or 1 (B).
func viewed_spell() -> int:
	return _viewed


## How many held spells below the prepared spell are shown (0 is the spell itself).
func level() -> int:
	return _level


## The selected slot, 0 to 5.
func selected_slot() -> int:
	return _slot


## The path of the spell shown, as `build_change_requested` takes it: `[spell]`, then a 0 per level.
func spell_path() -> PackedInt32Array:
	var path := PackedInt32Array([_viewed])
	for _step in _level:
		path.append(0)
	return path


## The slot button, tab, bag row and so on, by role, for tests and screenshots.
func slot_button(slot: int) -> Button:
	return _slots[slot]


func tab_button(spell: int) -> Button:
	return _tabs[spell]


func close_button() -> Button:
	return _close


func up_button() -> Button:
	return _up


func held_button() -> Button:
	return _held


## The bag rows now shown, in order.
func shown_rows() -> Array[Button]:
	var shown: Array[Button] = []
	for row in _row_ids.size():
		shown.append(_rows[row])
	return shown


## The component ids the shown bag rows ask for, in order (`&""` is "None").
func row_ids() -> Array[StringName]:
	return _row_ids.duplicate()


## The mirrored recipe of a prepared spell (a copy).
func recipe_of(spell: int) -> Dictionary:
	return _recipes[spell].duplicate(true) if spell >= 0 and spell < SPELL_COUNT else {}


## The controls UIFocus walks, in order.
func controls() -> Array[Control]:
	return _controls.duplicate()


## The text of the info panel, as shown now (for tests and screenshots).
func stats_text() -> String:
	return _stats.text


func complexity_text() -> String:
	return _complexity_label.text


## The complexity bar's value and its largest value (the limit).
func complexity_value() -> float:
	return _complexity_bar.value


func complexity_limit() -> float:
	return _complexity_bar.max_value


## The refusal reason or, with none, the description of the component in focus ("" if neither).
func note_text() -> String:
	return _note.text


## The hint line under the note: what `cast` does on the focused control.
func hint_text() -> String:
	return _hint.text()


## How many lines `text` takes in the note at its real width and font (the note shows at most
## `NOTE_LINES`; more is trimmed).
func note_lines_for(text: String) -> int:
	var font: Font = _note.get_theme_font("font")
	var font_size: int = _note.get_theme_font_size("font_size")
	var wrapped: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, _note.size.x, font_size)
	return ceili(wrapped.y / font.get_height(font_size))


## The reason the last refused change gave, "" after the next request or change.
func refusal_reason() -> String:
	return _reason


func preview_pattern() -> String:
	return _preview.pattern()


func info_panel() -> PanelContainer:
	return _info


func _make_info(player: int) -> void:
	_info = PanelContainer.new()
	_info.name = "Info"
	_info.theme_type_variation = StringName("PlayerPanel%d" % (player + 1))
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.top_level = true
	_info.custom_minimum_size = Vector2(INFO_WIDTH, INFO_HEIGHT)
	add_child(_info)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 0)
	_info.add_child(column)
	# The words sit on the bar (one row), which leaves room for the hint line below the note.
	_complexity_bar = ProgressBar.new()
	_complexity_bar.name = "ComplexityBar"
	_complexity_bar.theme_type_variation = BAR_VARIATION
	_complexity_bar.show_percentage = false
	_complexity_bar.min_value = 0.0
	_complexity_bar.max_value = float(SpellLimits.MAX_COMPLEXITY)
	_complexity_bar.step = 1.0
	_complexity_bar.custom_minimum_size = Vector2(0.0, COMPLEXITY_HEIGHT)
	_complexity_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_complexity_bar)
	_complexity_label = _make_info_label(_complexity_bar, "Complexity")
	_complexity_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_complexity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stats = _make_info_label(column, "Stats")
	_stats.custom_minimum_size = Vector2(0.0, 24.0)
	_preview = SpellPreviewScript.new()
	_preview.name = "Preview"
	_preview.custom_minimum_size = Vector2(0.0, PREVIEW_HEIGHT)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_preview)
	_note = _make_info_label(column, "Note")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.max_lines_visible = NOTE_LINES
	_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_note.custom_minimum_size = Vector2(0.0, NOTE_HEIGHT)
	_hint = HintLineScript.new()
	_hint.name = "Hint"
	_hint.custom_minimum_size = Vector2(0.0, HINT_HEIGHT)
	column.add_child(_hint)


func _make_info_label(parent: Node, node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = LABEL_VARIATION
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Put the info panel in the free strip of this player's quarter: the screen's left edge for
## P1 and P3, the right edge for P2 and P4, under the corner panel at the top and over it at
## the bottom.
func _place_info() -> void:
	var view: Vector2 = get_viewport_rect().size
	var x: float = INFO_EDGE if index % 2 == 0 else view.x - INFO_EDGE - INFO_WIDTH
	var y: float = INFO_CORNER + INFO_EDGE if index < 2 else view.y - INFO_CORNER - INFO_EDGE - INFO_HEIGHT
	_info.position = Vector2(x, y)
	_info.size = Vector2(INFO_WIDTH, INFO_HEIGHT)


## The stats, the bar and the preview of the spell shown, from `Spells.builder_view`.
func _render_info() -> void:
	var view: Dictionary = {}
	if _spells != null:
		view = _spells.builder_view(_recipes[_viewed], _level)
	var complexity: int = int(view.get("complexity", 0))
	_complexity_label.text = "Complexity %d/%d" % [complexity, SpellLimits.MAX_COMPLEXITY]
	_complexity_bar.value = float(complexity)
	_preview.show_view(view)
	if not bool(view.get("shown", false)):
		_stats.text = NO_STATS_TEXT
	else:
		var shots: String = "Ray" if bool(view["ray"]) else str(view["shots"])
		_stats.text = "Dmg %d  Shots %s\nCool %s s  Mana %s" % [int(view["damage"]), shots, String.num(float(view["cooldown"]), 2), String.num(float(view["mana"]), 1)]
	_render_note()


## The refusal reason, else the description of what the player points at.
func _render_note() -> void:
	if _reason != "":
		_note.text = REFUSED_PREFIX + _reason
	else:
		_note.text = _description_in_focus()
	var verb: String = _hint_in_focus()
	var back: String = HINT_BACK if verb == HINT_ROW else ""
	_hint.show_hint(index, HINT_ACTION, verb, HINT_BACK_ACTION, back)
	_quick_hint.show_hint(index, HINT_ACTION, verb, HINT_BACK_ACTION, back)
	_quick_hint.visible = _quick


## What `cast` does on the focused control (and `dodge`, on a bag row).
func _hint_in_focus() -> String:
	var button := _focused as Button
	if button == null:
		return ""
	if _rows.has(button):
		return HINT_ROW
	if _slots.has(button):
		return HINT_SLOT
	if _tabs.has(button):
		return HINT_TAB
	if button == _close:
		return HINT_CLOSE
	if button == _up:
		return HINT_UP
	if button == _held:
		return HINT_HELD
	if button == _drop:
		return HINT_DROP
	return ""


## The one-line description of the component the player points at: the bag row in focus, else
## the component in the selected slot.
func _description_in_focus() -> String:
	if _spells == null:
		return ""
	var id: StringName = NO_COMPONENT
	var at: int = _rows.find(_focused as Button)
	if at >= 0 and at < _row_ids.size():
		id = _row_ids[at]
	else:
		id = _id_in(_node_at(_level), _slot)
	return _spells.component_description(id) if id != NO_COMPONENT else ""


func _make_button(parent: Node, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.theme_type_variation = BUTTON_VARIATION
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.clip_text = true
	parent.add_child(button)
	return button


## How many bag rows the bag could need: the biggest group of one kind, plus "None".
func _most_rows() -> int:
	var counts: Dictionary = {}
	var most: int = 0
	for id in _bag:
		var kind: StringName = _kind_of(id)
		counts[kind] = int(counts.get(kind, 0)) + 1
		most = maxi(most, int(counts[kind]))
	return most + 1


func _grow_rows(count: int) -> void:
	while _rows.size() < count:
		var row: Button = _make_button(_rows_holder, "Row%d" % _rows.size())
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
		row.visible = false
		_rows.append(row)


func _kind_of(id: StringName) -> StringName:
	return _spells.component_kind(id) if _spells != null else &""


func _name_of(id: StringName) -> String:
	var shown: String = _spells.component_name(id) if _spells != null else ""
	return shown if shown != "" else String(id)


## The recipe of the spell shown at `level` (empty if there is none there).
func _node_at(level: int) -> Dictionary:
	var node: Dictionary = _recipes[_viewed]
	for _step in level:
		var held: Variant = node.get("held")
		node = held as Dictionary if held is Dictionary else {}
	return node


func _modifiers_of(node: Dictionary) -> Array:
	var modifiers: Variant = node.get("modifiers")
	return modifiers as Array if modifiers is Array else []


## The id in `slot` of `node`, or `NO_COMPONENT`.
func _id_in(node: Dictionary, slot: int) -> StringName:
	var value: Variant = null
	if slot == SLOT_FORM:
		value = node.get("form")
	elif slot == SLOT_ELEMENT:
		value = node.get("element")
	elif slot == SLOT_TRIGGER:
		value = node.get("trigger")
	else:
		var modifiers: Array = _modifiers_of(node)
		var at: int = slot - SLOT_FIRST_MODIFIER
		if at < modifiers.size():
			value = modifiers[at]
	return StringName(str(value)) if value != null else NO_COMPONENT


## Whether the slot can be filled now: a modifier only goes in the first free place.
func _slot_usable(node: Dictionary, slot: int) -> bool:
	if slot == SLOT_TRIGGER:
		# The compiler refuses a trigger on the deepest level, so it is not offered there.
		return _level < MAX_LEVEL
	if slot < SLOT_FIRST_MODIFIER:
		return true
	return slot - SLOT_FIRST_MODIFIER <= _modifiers_of(node).size()


## Keep the shown level and slot valid after the recipes changed.
func _clamp_view() -> void:
	while _level > 0 and _id_in(_node_at(_level - 1), SLOT_TRIGGER) == NO_COMPONENT:
		_level -= 1
	var node: Dictionary = _node_at(_level)
	if not _slot_usable(node, _slot):
		_slot = SLOT_FORM if _slot == SLOT_TRIGGER else SLOT_FIRST_MODIFIER +_modifiers_of(node).size()


func _render() -> void:
	_clamp_view()
	var node: Dictionary = _node_at(_level)
	var title: String = "P%d Spell %s" % [index + 1, SPELL_NAMES[_viewed]]
	if _level > 0:
		title += " held %d" % _level
	if _quick and _dropping:
		title = "P%d %s" % [index + 1, DROP_TITLE]
	_base_title = title
	_title.text = title
	for spell in SPELL_COUNT:
		_set_text(_tabs[spell], SPELL_NAMES[spell] if spell != _viewed else "[%s]" % SPELL_NAMES[spell])
		_tabs[spell].visible = not _quick
	_levels_row.visible = not _quick
	_info.visible = not _quick
	_drop.visible = _quick
	_set_text(_drop, DROP_TEXT)
	_set_text(_close, "Close")
	for slot in SLOT_COUNT:
		var id: StringName = _id_in(node, slot)
		var text: String = "%s: %s" % [SLOT_NAMES[slot], _name_of(id) if id != NO_COMPONENT else EMPTY_SLOT_TEXT]
		_set_text(_slots[slot], "[%s]" % text if slot == _slot else text)
		_slots[slot].disabled = _quick or not _slot_usable(node, slot)
	_up.disabled = _level == 0
	_set_text(_up, "< Up")
	_held.disabled = _level >= MAX_LEVEL or _id_in(node, SLOT_TRIGGER) == NO_COMPONENT
	_set_text(_held, "Held >")
	_render_rows(node)
	_bag_column.visible = not _quick or _dropping
	_bag_column.add_theme_constant_override("separation", 0 if _quick else 2)
	_rows_holder.add_theme_constant_override("separation", 0 if _quick else 2)
	_chain_column.add_theme_constant_override("separation", 0 if _quick else 2)
	_drop.disabled = _quick and not _can_drop
	_rebuild_controls()
	_apply_marks()
	_scroll_rows()
	_render_info()
	_fit_size()


func _render_rows(node: Dictionary) -> void:
	var current: StringName = _id_in(node, _slot)
	_row_ids.clear()
	_row_slots.clear()
	if _quick:
		current = NO_COMPONENT
		var offered: Dictionary = DropChoicesScript.choices(node, _bag, _spells)
		_row_ids.assign(offered["ids"])
		_row_slots.assign(offered["slots"])
		# Nothing left to drop: the list is over, whatever caused it.
		_can_drop = not _row_ids.is_empty()
		if not _can_drop:
			_dropping = false
		if not _dropping:
			_row_ids.clear()
			_row_slots.clear()
	else:
		if current != NO_COMPONENT and _slot != SLOT_FORM:
			_row_ids.append(NO_COMPONENT)
			_row_slots.append(_slot)
		for id in _bag:
			if _kind_of(id) == SLOT_KINDS[_slot]:
				_row_ids.append(id)
				_row_slots.append(_slot)
	_grow_rows(_row_ids.size())
	for row in _rows.size():
		var button: Button = _rows[row]
		if row >= _row_ids.size():
			button.visible = false
			continue
		var id: StringName = _row_ids[row]
		button.visible = true
		# The quick view's list can hold every element and modifier at once, so its rows have no
		# icon and are lower, to stay inside the builder's quarter of the screen.
		button.custom_minimum_size = Vector2(0.0, QUICK_ROW_HEIGHT if _quick else ROW_HEIGHT)
		if _quick:
			button.add_theme_font_size_override("font_size", QUICK_ROW_FONT)
		else:
			button.remove_theme_font_size_override("font_size")
		if id == NO_COMPONENT:
			button.icon = null
			_set_text(button, NONE_TEXT)
		else:
			button.icon = _spells.component_icon(id) if _spells != null and not _quick else null
			_set_text(button, _name_of(id) + (CURRENT_MARK if id == current else ""))


## Keep the focused drop row in view. The quick view's list shows at most
## `RowWindowScript.QUICK_MAX_LINES` rows and slides to follow the focus (UIFocus walks all of
## them); the title then shows the focused row ("Drop 3/14") and arrows show hidden rows. The
## full builder's bag list is as high as it is.
func _scroll_rows() -> void:
	if not _quick:
		_rows_first = 0
		_rows_window.custom_minimum_size.y = _rows_holder.get_combined_minimum_size().y
		_rows_holder.position = Vector2.ZERO
		return
	var total: int = _row_ids.size()
	var most: int = RowWindowScript.QUICK_MAX_LINES
	var focus_at: int = _rows.find(_focused as Button)
	_rows_first = RowWindowScript.first_line_for(focus_at if focus_at >= 0 else _rows_first, _rows_first, most, total)
	# A row can be taller than `QUICK_ROW_HEIGHT` (the theme's margins), so the step is its own.
	var step: float = maxf(QUICK_ROW_HEIGHT, _rows[0].get_combined_minimum_size().y) if not _rows.is_empty() else QUICK_ROW_HEIGHT
	RowWindowScript.apply(_rows_window, _rows_holder, step, total, most, _rows_first)
	_title.text = _base_title
	if _dropping and total > most and focus_at >= 0 and focus_at < total:
		_title.text = "%s %d/%d" % [_base_title, focus_at + 1, total]


## The quick view is narrower until its drop list is shown. The offsets of the builder make its
## base size zero (`panels.gd`), so it follows the minimum size, its anchored corner staying put.
func _fit_size() -> void:
	var width: float = LEFT_WIDTH + 8.0 if _quick and not _dropping else LEFT_WIDTH + RIGHT_WIDTH + 4.0 + 8.0
	if custom_minimum_size.x != width:
		custom_minimum_size = Vector2(width, 0.0)


func _rebuild_controls() -> void:
	_controls.clear()
	if _quick:
		_controls.append(_drop)
	else:
		for tab in _tabs:
			_controls.append(tab)
		# Close is drawn right of the tabs, so it is reached right after them.
		_controls.append(_close)
		for slot_button_node in _slots:
			_controls.append(slot_button_node)
		_controls.append(_up)
		_controls.append(_held)
	for row in _rows:
		_controls.append(row)
	if _quick:
		_controls.append(_close)


func _set_text(button: Button, text: String) -> void:
	button.set_meta(BASE_TEXT_META, text)
	button.text = (FOCUS_MARK if button == _focused else "") + text


## Show the focus mark on the focused control only.
func _apply_marks() -> void:
	for control in _controls:
		var button := control as Button
		var base: String = str(button.get_meta(BASE_TEXT_META, ""))
		button.text = (FOCUS_MARK if button == _focused else "") + base
		button.theme_type_variation = FOCUS_VARIATION if button == _focused else BUTTON_VARIATION
	# The note and the hint follow the focus, however it moved (opening and folding included).
	_render_note()


func _ask(slot: int, id: StringName) -> void:
	_reason = ""
	if _events != null:
		_events.build_change_requested.emit(index, spell_path(), slot, id)


func _on_recipe_changed(player: int, slot: int, recipe: Dictionary) -> void:
	if player != index or slot < 0 or slot >= SPELL_COUNT:
		return
	_recipes[slot] = recipe.duplicate(true)
	_reason = ""
	_render()


## The player refused a change: show why, as words (the picture itself stays as it was).
func _on_build_refused(player: int, reason: String) -> void:
	if player != index:
		return
	_reason = reason
	_render_note()


func _on_bag_changed(player: int, bag: Array[StringName]) -> void:
	if player != index:
		return
	_bag = bag.duplicate()
	_render()
	_resync_focus()


## UIFocus keeps its own copy of the controls: when a bigger bag made more rows, give it the new
## list and put focus back where it was.
func _resync_focus(force: bool = false) -> void:
	if not _open or (_controls.size() == _synced_controls and not force):
		return
	var keep: Control = _focused
	_reopening = true
	var again: bool = _ui_focus.open(index, _controls)
	_reopening = false
	if not again:
		_open = false
		_focused = null
		visible = false
		return
	_synced_controls = _controls.size()
	_focused = _ui_focus.focused(index)
	if keep != null:
		_focus_control(keep)
	_apply_marks()


func _on_closed(player: int) -> void:
	if player != index or _reopening:
		return
	_open = false
	_focused = null
	visible = false


func _on_focus_changed(player: int, control: Control) -> void:
	if player == index and _open:
		_focused = control
		_apply_marks()
		_scroll_rows()


func _on_cancelled(player: int) -> void:
	if player != index or not _open:
		return
	if _rows.has(_focused as Button):
		if _quick:
			_stop_dropping()
		else:
			_focus_control(_slots[_slot])
	else:
		close_builder()


## Leave the quick view's drop list and put focus back on "Bag".
func _stop_dropping() -> void:
	_dropping = false
	_render()
	_focus_control(_quick_focus_target())


func _on_active_spell_changed(player: int, slot: int) -> void:
	if player != index or slot < 0 or slot >= SPELL_COUNT:
		return
	_active = slot
	if _quick and _viewed != slot:
		_viewed = slot
		_dropping = false
		_render()
		if _open:
			_focus_control(_quick_focus_target())


func _on_activated(player: int, control: Control) -> void:
	if player != index or not _open:
		return
	if control == _close:
		close_builder()
	elif control == _drop:
		_dropping = true
		_render()
		_focus_control(_first_row())
	elif _tabs.has(control as Button):
		_viewed = _tabs.find(control as Button)
		_level = 0
		_slot = SLOT_FORM
		_render()
		_focus_control(_slots[_slot])
	elif _slots.has(control as Button):
		_slot = _slots.find(control as Button)
		_render()
		_focus_control(_first_row())
	elif control == _up:
		_level -= 1
		_slot = SLOT_FORM
		_render()
		_focus_control(_slots[_slot])
	elif control == _held:
		_level += 1
		_slot = SLOT_FORM
		_render()
		_focus_control(_slots[_slot])
	elif _rows.has(control as Button):
		var row: int = _rows.find(control as Button)
		if row < _row_ids.size():
			var chosen: StringName = _row_ids[row]
			var asked: int = _row_slots[row]
			var was_empty: bool = _id_in(_node_at(_level), asked) == NO_COMPONENT
			_ask(asked, chosen)
			if not _advance_after(asked, chosen, was_empty):
				_keep_focus_on(chosen)


## After a form or an element went into an empty slot (and the player took it), move on to the
## next slot, so a normal spell is a form, an element and a few modifiers without walking back
## to the chain each time. A refused or replaced choice stays where it is, for a second try.
## Returns whether it moved.
func _advance_after(slot: int, id: StringName, was_empty: bool) -> bool:
	if _quick or not was_empty or id == NO_COMPONENT or slot > SLOT_ELEMENT:
		return false
	if _id_in(_node_at(_level), slot) != id:
		return false
	_slot = slot + 1
	if _slot == SLOT_FIRST_MODIFIER:
		# The first free modifier slot, or the last one when all are filled.
		_slot = mini(SLOT_FIRST_MODIFIER + _modifiers_of(_node_at(_level)).size(), SLOT_TRIGGER - 1)
	_render()
	_focus_control(_first_row())
	return true


## After a choice the rows may have shifted ("None" appears or goes): put focus back on the row
## of the component just chosen, or on the first row if that row is gone.
func _keep_focus_on(id: StringName) -> void:
	if not _open:
		return
	var at: int = _row_ids.find(id)
	if at >= 0:
		_focus_control(_rows[at])
	elif not _row_ids.is_empty():
		_focus_control(_rows[0])
	else:
		_focus_control(_first_row())


## The first bag row shown, or (with no rows) the selected slot, or in the quick view "Drop
## component" (or "Close" when nothing is left to drop).
func _first_row() -> Control:
	if not _row_ids.is_empty():
		return _rows[0]
	if _quick:
		return _quick_focus_target()
	return _slots[_slot]


## In the quick view: "Bag", or "Close" when nothing is left to drop.
func _quick_focus_target() -> Control:
	return _drop if not _drop.disabled else _close


## Move this player's focus to `target` by single steps (the focus service has no jump).
func _focus_control(target: Control) -> void:
	if _ui_focus == null:
		return
	for _step in _controls.size():
		if _ui_focus.focused(index) == target:
			return
		_ui_focus.move_focus(index, 1)
