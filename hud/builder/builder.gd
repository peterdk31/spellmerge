extends PanelContainer
## One player's staff builder (staffs A6a, docs/milestones/M2-staffs.md, "The builder"): the
## corner panel expanded toward the middle of the screen, with the four staffs as tabs, the
## shown staff's slots on the left and the bag on the right. Opened by its owner's `back` button
## (B; Tab or E on the keyboard) in play, at any time, waves included (there is no quick view;
## `hud/panels/panels.gd` opens it), closed by its owner, never pausing the game.
##
## What it shows comes only from events: `staff_changed` (each staff's cards and its cast plan,
## the plain view of `Spells.staff_view`), `bag_changed` (the ids the player may build with) and
## `build_refused`; names, icons and descriptions come from `Spells`. What it asks for goes out
## as `staff_change_requested(player, staff, slot, card id)`; the player answers with a new
## `staff_changed`, so this node never changes a staff itself. Nothing here reads the player or
## another player's builder.
##
## Controls (through `core/ui_focus`, so only the owner's device works them), laid out in two
## dimensions (staffs B8): the staff tabs (1 to 4: RB, RT, LB, LT on a pad) and "Close" in a row on top, the slots of
## the shown staff on the left, the bag on the right. Left and right move along the tabs and
## between the slots and the bag, up and down within a list and from its top to the tabs, so
## every slot is reached with the d-pad alone; LB and RB (`page_prev`, `page_next`) show the
## previous or next staff from anywhere.
##
## Pick and place: `accept` on a slot with a card picks it up (marked "^"); `accept` on another
## slot, of this staff or another, places it there, swapping with what is there
## (`card_move_requested`); `accept` on a bag row while holding sends it back to the bag; `back`
## drops it where it was. `alternate` on a slot sends its card back to the bag. With nothing held,
## `accept` on an empty slot selects it and moves to the bag, and `accept` on a bag card puts it
## in the selected slot and selects the next slot, so a staff is still built left to right by
## picking cards one after another ("Empty" clears the slot). `back` on a bag row goes back to
## the slot; anywhere else it closes the builder. Player 1 can also use the mouse: a click works
## as `accept`, and dragging a card onto a slot (or onto the bag) moves it there.
##
## The focused control is marked with "> ", the selected slot is shown in brackets and a held
## card with "^", so nothing is shown by colour alone; a card that does nothing where it is (a
## wasted card) has a "!" (no words: the mark is enough, owner 2026-10-30). Links: each modifier, infusion and trigger shows
## where it goes ("> 4" for the carrier in slot 4, "> you" for the caster, "> aim" for the aim
## point) and each carrier its cast ("#1"); the cards linked to the focused one are marked "<".
##
## The info panel (`Info`, in the free strip of the player's quarter) shows the cast plan, one
## line per cast of the staff's cycle with its live numbers (its mana and delay in its words,
## then its damage if every shot lands once), and a note: the refusal reason,
## else where it goes and the description of the card in focus; and a hint line with what
## `accept` (and `back` or `alternate`) do on the focused control.
##
## Every UIFocus signal carries a player index and this node ignores all but its own, so it
## is the same for any index 0-3. Buttons are made once and only grow; the slot and bag lists sit
## in clipping windows that slide to follow the focus.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const HintLineScript := preload("res://hud/widgets/hint_line.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")
const RowWindowScript := preload("res://hud/widgets/row_window.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

const PLAYER_COUNT: int = 4
const STAFF_COUNT: int = 4
## The staffs by index, named by number (their buttons differ per device: RB, RT, LB, LT on a
## pad, Space, the mouse buttons and Q on the keyboard).
const STAFF_NAMES: Array[String] = ["1", "2", "3", "4"]
const NO_CARD: StringName = &""

const EMPTY_TEXT: String = "Empty"
const EMPTY_SLOT_TEXT: String = "-"
const FOCUS_MARK: String = "> "
const CURRENT_MARK: String = " *"
const WASTED_MARK: String = " !"
const HELD_MARK: String = "^"
const LINK_MARK: String = " <"
## `card_move_requested`'s staff for the bag, and "nothing held".
const BAG: int = -1
const NOTHING: int = -2
## The look of every control, and of the control in focus (brighter, with a bright border; the
## "> " mark stays, so it is never colour alone).
const BUTTON_VARIATION: StringName = &"BuilderButton"
const FOCUS_VARIATION: StringName = &"BuilderButtonFocus"
const LABEL_VARIATION: StringName = &"BuilderLabel"
## Rows are 8 px text in 12 px rows, so a 20-slot staff and the whole bag scroll inside the
## player's quarter of the screen, `LIST_LINES` rows at a time.
const ROW_HEIGHT: float = 12.0
const ROW_FONT: int = 8
const LIST_LINES: int = 8
const LEFT_WIDTH: float = 92.0
const RIGHT_WIDTH: float = 84.0
## The meta key that keeps a button's text without the focus mark.
const BASE_TEXT_META: StringName = &"base_text"

## The info panel sits in the strip of the player's quarter under (P1, P2) or over (P3, P4) the
## corner panel, so it covers nothing the builder or another player uses.
const INFO_WIDTH: float = 112.0
const INFO_HEIGHT: float = 112.0
const INFO_EDGE: float = 4.0
## Height of the corner panel plus its gap: where the strip starts.
const INFO_CORNER: float = 59.0
const PLAN_LINES: int = 5
const NOTE_LINES: int = 3
const HINT_HEIGHT: float = 10.0
const HINT_SLOT: String = "Pick a card"
const HINT_PICK: String = "Pick up"
const HINT_PLACE: String = "Place"
const HINT_TO_BAG: String = "To bag"
const HINT_DROP: String = "Drop"
const HINT_ROW: String = "Put in"
const HINT_BACK: String = "back"
const HINT_TAB: String = "Show staff"
const HINT_CLOSE: String = "Close"
const HINT_ACTION: StringName = &"accept"
const HINT_BACK_ACTION: StringName = &"back"
const HINT_BAG_ACTION: StringName = &"alternate"
const REFUSED_PREFIX: String = "Refused: "

## The player index 0-3. Set before adding the node to the tree.
@export var index: int = 0

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _spells: SpellsScript = null
## How many controls UIFocus was given, and whether we are giving them again (not a real close).
var _synced_controls: int = 0
var _reopening: bool = false

## Mirrors of what the player announced: each staff's view (`Spells.staff_view`), the bag.
var _plans: Array[Dictionary] = [{}, {}, {}, {}]
var _bag: Array[StringName] = []
## The reason the player gave for the last refused change (cleared by the next request or change).
var _reason: String = ""

var _open: bool = false
## The staff shown (0 A to 3 B) and its selected slot.
var _viewed: int = 1
var _slot: int = 0
var _focused: Control = null
## The card picked up: its staff (BAG never; NOTHING when none) and slot.
var _held_staff: int = NOTHING
var _held_slot: int = -1
## The shown staff's links: slot -> the carrier's slot (or a StaffCompiler TARGET_*), and
## carrier slot -> its cast number (1 up).
var _links: Dictionary = {}
var _cast_of: Dictionary = {}
## Player 1's mouse: the control a press started on, or null.
var _pressed: Control = null

var _title: Label = null
var _tabs: Array[Button] = []
## The staff button each tab shows (`staff_1` to `staff_4`), laid out inside the tab.
var _tab_glyphs: Array[ActionGlyphScript] = []
## The text before the glyph (the focus mark and "[") and after it ("]") on each tab.
var _tab_leads: Array[Label] = []
var _tab_tails: Array[Label] = []
var _close: Button = null
var _slots: Array[Button] = []
var _slots_window: Control = null
var _slots_holder: VBoxContainer = null
var _slots_first: int = 0
var _rows: Array[Button] = []
var _rows_window: Control = null
var _rows_holder: VBoxContainer = null
var _rows_first: int = 0
## The card each shown bag row puts in (`NO_CARD` is "Empty").
var _row_ids: Array[StringName] = []
var _info: PanelContainer = null
var _plan: Label = null
var _note: Label = null
var _hint: HintLineScript = null
## The controls given to UIFocus, in order.
var _controls: Array[Control] = []


func _ready() -> void:
	var player: int = clampi(index, 0, PLAYER_COUNT - 1)
	theme_type_variation = StringName("PlayerPanel%d" % (player + 1))
	custom_minimum_size = Vector2(LEFT_WIDTH + RIGHT_WIDTH + 4.0 + 8.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = StringName("PlayerLabel%d" % (player + 1))
	column.add_child(_title)
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 2)
	column.add_child(tabs)
	for staff in STAFF_COUNT:
		var tab: Button = _make_button(tabs, "Tab%s" % STAFF_NAMES[staff])
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.append(tab)
		tab.tooltip_text = "Staff %s" % STAFF_NAMES[staff]
		var content := HBoxContainer.new()
		content.name = "Content"
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 0)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tab.add_child(content)
		var lead := Label.new()
		lead.name = "Lead"
		lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(lead)
		var glyph := ActionGlyphScript.new()
		glyph.name = "Glyph"
		content.add_child(glyph)
		var tail := Label.new()
		tail.name = "Tail"
		tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(tail)
		_tab_glyphs.append(glyph)
		_tab_leads.append(lead)
		_tab_tails.append(tail)
		# A wider key or mark changes the content's size only now and then: the tab follows.
		content.minimum_size_changed.connect(_fit_tab.bind(staff))
	_close = _make_button(tabs, "Close")
	_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lists := HBoxContainer.new()
	lists.name = "Lists"
	lists.add_theme_constant_override("separation", 4)
	column.add_child(lists)
	_slots_holder = VBoxContainer.new()
	_slots_holder.name = "Slots"
	_slots_holder.custom_minimum_size = Vector2(LEFT_WIDTH, 0.0)
	_slots_holder.add_theme_constant_override("separation", 0)
	_slots_window = RowWindowScript.make_window("SlotsWindow", _slots_holder, LEFT_WIDTH)
	lists.add_child(_slots_window)
	_rows_holder = VBoxContainer.new()
	_rows_holder.name = "Rows"
	_rows_holder.custom_minimum_size = Vector2(RIGHT_WIDTH, 0.0)
	_rows_holder.add_theme_constant_override("separation", 0)
	_rows_window = RowWindowScript.make_window("RowsWindow", _rows_holder, RIGHT_WIDTH)
	lists.add_child(_rows_window)
	_make_info(player)
	visible = false
	_render()


## Connect to the event bus, the focus service and the spell runtime, which gives names, icons
## and descriptions (called once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript, spells: SpellsScript, input: InputManagerScript = null) -> void:
	_hint.bind(input)
	for staff in STAFF_COUNT:
		_tab_glyphs[staff].bind(input)
		_tab_glyphs[staff].show_action(index, StringName("staff_%d" % (staff + 1)))
	_events = events
	_ui_focus = ui_focus
	_spells = spells
	if _events != null:
		_events.staff_changed.connect(_on_staff_changed)
		_events.bag_changed.connect(_on_bag_changed)
		_events.build_refused.connect(_on_build_refused)
	if _ui_focus != null:
		_ui_focus.closed.connect(_on_closed)
		_ui_focus.activated.connect(_on_activated)
		_ui_focus.cancelled.connect(_on_cancelled)
		_ui_focus.focus_changed.connect(_on_focus_changed)
		_ui_focus.alternate.connect(_on_alternate)
		_ui_focus.paged.connect(_on_paged)


func is_open() -> bool:
	return _open


## Open the builder for its owner (replacing any other panel of theirs that is open). False if the owner
## has no device. Starts on the staff last shown, on its first slot.
func open_builder() -> bool:
	if _open or _ui_focus == null:
		return false
	_slot = 0
	_focused = null
	_reason = ""
	_held_staff = NOTHING
	_place_info()
	_render()
	# Close any other panel of the owner's first: its `closed` would hide this node if it came during open.
	_ui_focus.close(index)
	# Visible before opening: UIFocus only focuses controls that are shown.
	visible = true
	if not _ui_focus.open(index, _controls):
		visible = false
		return false
	_open = true
	_synced_controls = _controls.size()
	_ui_focus.set_navigator(index, _navigate)
	_focused = _ui_focus.focused(index)
	if not _slots.is_empty():
		_focus_control(_slots[0])
	_apply_marks()
	return true


## Close the builder if it is open.
func close_builder() -> bool:
	if not _open or _ui_focus == null:
		return false
	return _ui_focus.close(index)


## The staff shown, 0 (A) to 3 (B).
func viewed_staff() -> int:
	return _viewed


## The selected slot of the shown staff.
func selected_slot() -> int:
	return _slot


## The staff and slot of the card picked up, or [NOTHING, -1].
func held() -> Array[int]:
	return [_held_staff, _held_slot] as Array[int] if _held_staff != NOTHING else [NOTHING, -1] as Array[int]


## The card ids of a staff as the player announced them, by slot (a copy).
func cards_of(staff: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if staff >= 0 and staff < STAFF_COUNT:
		out.assign(_plans[staff].get("cards", []))
	return out


func slot_button(slot: int) -> Button:
	return _slots[slot]


## How many slot buttons the shown staff uses.
func slot_count() -> int:
	return cards_of(_viewed).size()


func tab_button(staff: int) -> Button:
	return _tabs[staff]


## The glyph drawn on staff `staff`'s tab.
func tab_glyph(staff: int) -> ActionGlyphScript:
	return _tab_glyphs[staff]


## The marks around staff `staff`'s glyph: the focus mark and "[" before it, "]" after it.
func tab_marks(staff: int) -> String:
	return _tab_leads[staff].text + _tab_tails[staff].text


func close_button() -> Button:
	return _close


## The bag rows now shown, in order, and the card each puts in (`&""` is "Empty").
func shown_rows() -> Array[Button]:
	var shown: Array[Button] = []
	for row in _row_ids.size():
		shown.append(_rows[row])
	return shown


func row_ids() -> Array[StringName]:
	return _row_ids.duplicate()


## The controls UIFocus walks, in order.
func controls() -> Array[Control]:
	return _controls.duplicate()


## The cast plan as shown, one line per cast.
func plan_text() -> String:
	return _plan.text


## The refusal reason or the description in focus ("" if none).
func note_text() -> String:
	return _note.text


## The hint line under the note: what `accept` does on the focused control.
func hint_text() -> String:
	return _hint.text()


func refusal_reason() -> String:
	return _reason


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
	column.add_theme_constant_override("separation", 1)
	_info.add_child(column)
	_plan = _make_info_label(column, "Plan", PLAN_LINES)
	_note = _make_info_label(column, "Note", NOTE_LINES)
	_hint = HintLineScript.new()
	_hint.name = "Hint"
	_hint.custom_minimum_size = Vector2(0.0, HINT_HEIGHT)
	column.add_child(_hint)


func _make_info_label(parent: Node, node_name: String, lines: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = LABEL_VARIATION
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = lines
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", ROW_FONT)
	label.custom_minimum_size = Vector2(0.0, float(lines) * 9.0)
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


func _make_button(parent: Node, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.theme_type_variation = BUTTON_VARIATION
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.clip_text = true
	if index == 0:
		# Player 1 may use the mouse (the keyboard player; see the top).
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.gui_input.connect(_on_mouse.bind(button))
	parent.add_child(button)
	return button


func _make_row(parent: Node, node_name: String) -> Button:
	var row: Button = _make_button(parent, node_name)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.add_theme_font_size_override("font_size", ROW_FONT)
	row.visible = false
	return row


func _name_of(id: StringName) -> String:
	var shown: String = _spells.component_name(id) if _spells != null else ""
	return shown if shown != "" else String(id)


## Slot -> why its card does nothing, for the shown staff.
func _wasted() -> Dictionary:
	var wasted: Variant = _plans[_viewed].get("wasted", {})
	return wasted as Dictionary if wasted is Dictionary else {}


func _render() -> void:
	var cards: Array[StringName] = cards_of(_viewed)
	_slot = clampi(_slot, 0, maxi(cards.size() - 1, 0))
	_title.text = "P%d Staff %s" % [index + 1, STAFF_NAMES[_viewed]]
	_render_tabs()
	_set_text(_close, "Close")
	while _slots.size() < cards.size():
		_slots.append(_make_row(_slots_holder, "Slot%d" % _slots.size()))
	var wasted: Dictionary = _wasted()
	_read_links()
	var linked: Array[int] = _linked_to(_slots.find(_focused as Button))
	for slot in _slots.size():
		var button: Button = _slots[slot]
		button.visible = slot < cards.size()
		if not button.visible:
			continue
		var id: StringName = cards[slot]
		var text: String = "%d %s" % [slot + 1, _name_of(id) if id != NO_CARD else EMPTY_SLOT_TEXT]
		if _held_staff == _viewed and _held_slot == slot:
			text = HELD_MARK + text
		if wasted.has(slot):
			text += WASTED_MARK
		elif _links.has(slot):
			text += " >" + _target_word(int(_links[slot]))
		elif _cast_of.has(slot):
			text += " #%d" % int(_cast_of[slot])
		if linked.has(slot):
			text += LINK_MARK
		_set_text(button, "[%s]" % text if slot == _slot else text)
	_render_rows(cards[_slot] if _slot < cards.size() else NO_CARD)
	_rebuild_controls()
	_apply_marks()
	_scroll_lists()
	_render_plan()


func _render_rows(current: StringName) -> void:
	_row_ids.clear()
	_row_ids.append(NO_CARD)
	_row_ids.append_array(_bag)
	while _rows.size() < _row_ids.size():
		_rows.append(_make_row(_rows_holder, "Row%d" % _rows.size()))
	for row in _rows.size():
		var button: Button = _rows[row]
		button.visible = row < _row_ids.size()
		if not button.visible:
			continue
		var id: StringName = _row_ids[row]
		if id == NO_CARD:
			button.icon = null
			_set_text(button, EMPTY_TEXT)
		else:
			button.icon = _spells.component_icon(id) if _spells != null else null
			_set_text(button, _name_of(id) + (CURRENT_MARK if id == current else ""))


## The plan of the shown staff: one line per cast of its cycle, with its live numbers.
func _render_plan() -> void:
	var lines: PackedStringArray = PackedStringArray()
	var casts: Variant = _plans[_viewed].get("casts", [])
	if casts is Array:
		var number: int = 1
		for cast: Variant in casts:
			if cast is Dictionary:
				var row: Dictionary = cast
				var said: String = str(row.get("text", "")).trim_suffix(".")
				lines.append("%d: %s (%s)" % [number, said, _numbers(row)])
				number += 1
	_plan.text = "\n".join(lines) if not lines.is_empty() else "Empty: put cards in the slots."
	_render_note()


## The refusal reason, else the description of what the player points at.
func _render_note() -> void:
	var at_slot: int = _slots.find(_focused as Button)
	if _reason != "":
		_note.text = REFUSED_PREFIX + _reason
	else:
		var link: String = _link_sentence(at_slot)
		var description: String = _description_in_focus()
		_note.text = link + (" " if link != "" and description != "" else "") + description
	var verb: String = _hint_in_focus()
	if _held_staff != NOTHING:
		_hint.show_hint(index, HINT_ACTION, verb, HINT_BACK_ACTION, HINT_DROP)
	elif verb == HINT_PICK:
		_hint.show_hint(index, HINT_ACTION, verb, HINT_BAG_ACTION, HINT_TO_BAG)
	else:
		_hint.show_hint(index, HINT_ACTION, verb, HINT_BACK_ACTION, HINT_BACK if verb == HINT_ROW else "")


func _hint_in_focus() -> String:
	var button := _focused as Button
	if button == null:
		return ""
	if _rows.has(button):
		return HINT_TO_BAG if _held_staff != NOTHING else HINT_ROW
	if _slots.has(button):
		if _held_staff != NOTHING:
			return HINT_PLACE
		var slot: int = _slots.find(button)
		var cards: Array[StringName] = cards_of(_viewed)
		return HINT_PICK if slot < cards.size() and cards[slot] != NO_CARD else HINT_SLOT
	if _tabs.has(button):
		return HINT_TAB
	if button == _close:
		return HINT_CLOSE
	return ""


## The description of the bag card in focus, else of the card in the focused (or selected) slot.
func _description_in_focus() -> String:
	if _spells == null:
		return ""
	var id: StringName = NO_CARD
	var row: int = _rows.find(_focused as Button)
	var cards: Array[StringName] = cards_of(_viewed)
	var at_slot: int = _slots.find(_focused as Button)
	if row >= 0 and row < _row_ids.size():
		id = _row_ids[row]
	elif at_slot >= 0 and at_slot < cards.size():
		id = cards[at_slot]
	elif _slot < cards.size():
		id = cards[_slot]
	return _spells.component_description(id) if id != NO_CARD else ""


## Keep the focused slot and the focused bag row in view: each list shows `LIST_LINES` rows at
## most and slides to follow the focus.
func _scroll_lists() -> void:
	var slots: int = cards_of(_viewed).size()
	var at_slot: int = _slots.find(_focused as Button)
	_slots_first = RowWindowScript.first_line_for(at_slot if at_slot >= 0 else _slot, _slots_first, LIST_LINES, slots)
	RowWindowScript.apply(_slots_window, _slots_holder, _row_step(_slots), slots, LIST_LINES, _slots_first)
	var rows: int = _row_ids.size()
	var at_row: int = _rows.find(_focused as Button)
	_rows_first = RowWindowScript.first_line_for(at_row if at_row >= 0 else _rows_first, _rows_first, LIST_LINES, rows)
	RowWindowScript.apply(_rows_window, _rows_holder, _row_step(_rows), rows, LIST_LINES, _rows_first)


## A row can be taller than `ROW_HEIGHT` (the theme's margins), so the step is its own.
func _row_step(rows: Array[Button]) -> float:
	return maxf(ROW_HEIGHT, rows[0].get_combined_minimum_size().y) if not rows.is_empty() else ROW_HEIGHT


func _rebuild_controls() -> void:
	_controls.clear()
	for tab in _tabs:
		_controls.append(tab)
	# Close is drawn right of the tabs, so it is reached right after them.
	_controls.append(_close)
	for slot in cards_of(_viewed).size():
		_controls.append(_slots[slot])
	for row in _row_ids.size():
		_controls.append(_rows[row])


## A tab holds its glyph between its marks, which the layout places: "[" and "]" on the shown
## staff, so it is not told by colour alone, and the focus mark before them on the focused tab.
func _render_tabs() -> void:
	for staff in STAFF_COUNT:
		var shown: bool = staff == _viewed
		var lead: Label = _tab_leads[staff]
		var tail: Label = _tab_tails[staff]
		lead.text = (FOCUS_MARK if _tabs[staff] == _focused else "") + ("[" if shown else "")
		tail.text = "]" if shown else ""
		lead.visible = not lead.text.is_empty()
		tail.visible = shown


## The tab is at least as wide as its content (a key wider than a pad button, and the marks).
func _fit_tab(staff: int) -> void:
	var tab: Button = _tabs[staff]
	var content: Control = _tab_glyphs[staff].get_parent() as Control
	# An empty button has no text height of its own, so the content gives both sizes.
	tab.custom_minimum_size = content.get_combined_minimum_size() + tab.get_theme_stylebox("normal").get_minimum_size()


func _set_text(button: Button, text: String) -> void:
	button.set_meta(BASE_TEXT_META, text)
	button.text = (FOCUS_MARK if button == _focused else "") + text


## Show the focus mark on the focused control only (a tab shows it in its own lead label).
func _apply_marks() -> void:
	for control in _controls:
		var button := control as Button
		if not _tabs.has(button):
			var base: String = str(button.get_meta(BASE_TEXT_META, ""))
			button.text = (FOCUS_MARK if button == _focused else "") + base
		button.theme_type_variation = FOCUS_VARIATION if button == _focused else BUTTON_VARIATION
	_render_tabs()
	# The note and the hint follow the focus, however it moved.
	_render_note()


func _on_staff_changed(player: int, staff: int, plan: Dictionary) -> void:
	if player != index or staff < 0 or staff >= STAFF_COUNT:
		return
	_plans[staff] = plan.duplicate(true)
	_reason = ""
	_render()
	_resync_focus()


## The player refused a change: show why, as words.
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


## UIFocus keeps its own copy of the controls: when the lists changed size, give it the new list
## and put focus back where it was.
func _resync_focus() -> void:
	if not _open or _controls.size() == _synced_controls:
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
	if keep != null and _controls.has(keep):
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
		# The slot rows show what is linked to the focused card, so they are drawn again.
		_render()


func _on_cancelled(player: int) -> void:
	if player != index or not _open:
		return
	if _held_staff != NOTHING:
		_drop()
	elif _rows.has(_focused as Button) and _slot < _slots.size():
		_focus_control(_slots[_slot])
	else:
		close_builder()


func _on_activated(player: int, control: Control) -> void:
	if player != index or not _open:
		return
	if control == _close:
		close_builder()
	elif _tabs.has(control as Button):
		_show_staff(_tabs.find(control as Button))
		if not _slots.is_empty():
			_focus_control(_slots[0])
	elif _slots.has(control as Button):
		var slot: int = _slots.find(control as Button)
		var cards: Array[StringName] = cards_of(_viewed)
		if _held_staff != NOTHING:
			_move(_held_staff, _held_slot, _viewed, slot)
			_drop()
		elif slot < cards.size() and cards[slot] != NO_CARD:
			_held_staff = _viewed
			_held_slot = slot
			_slot = slot
			_render()
		else:
			_slot = slot
			_render()
			_focus_control(_rows[0] if not _rows.is_empty() else control)
	elif _rows.has(control as Button):
		var row: int = _rows.find(control as Button)
		if _held_staff != NOTHING:
			_move(_held_staff, _held_slot, BAG, 0)
			_drop()
		elif row < _row_ids.size():
			_ask(_slot, _row_ids[row])
			# Build left to right: the next pick goes to the next slot.
			if _row_ids[row] != NO_CARD and _slot + 1 < cards_of(_viewed).size():
				_slot += 1
				_render()
			_focus_control(control)


## `alternate`: the card in the focused slot goes back to the bag.
func _on_alternate(player: int, control: Control) -> void:
	if player != index or not _open or not _slots.has(control as Button):
		return
	var slot: int = _slots.find(control as Button)
	var cards: Array[StringName] = cards_of(_viewed)
	if slot < cards.size() and cards[slot] != NO_CARD:
		if _held_staff == _viewed and _held_slot == slot:
			_held_staff = NOTHING
		_move(_viewed, slot, BAG, 0)


## LB and RB: the previous or next staff, focus kept on the same kind of control.
func _on_paged(player: int, step: int) -> void:
	if player != index or not _open:
		return
	var at_slot: int = _slots.find(_focused as Button)
	_show_staff(posmod(_viewed + step, STAFF_COUNT))
	if at_slot >= 0:
		var cards: int = cards_of(_viewed).size()
		if cards > 0:
			_focus_control(_slots[mini(at_slot, cards - 1)])


## Where a d-pad press goes from `from` (see the top): always an answer, so the focus service
## never falls back to walking the controls in a line.
func _navigate(from: Control, direction: Vector2i) -> Control:
	var button := from as Button
	var cards: int = cards_of(_viewed).size()
	var tab_row: Array[Button] = _tabs.duplicate()
	tab_row.append(_close)
	if button == null:
		return _slots[_slot] if _slot < cards else _tabs[_viewed]
	var at_tab: int = tab_row.find(button)
	if at_tab >= 0:
		if direction == Vector2i.LEFT:
			return tab_row[maxi(at_tab - 1, 0)]
		if direction == Vector2i.RIGHT:
			return tab_row[mini(at_tab + 1, tab_row.size() - 1)]
		if direction == Vector2i.DOWN and cards > 0:
			return _slots[clampi(_slot, 0, cards - 1)]
		return button
	var at_slot: int = _slots.find(button)
	if at_slot >= 0:
		if direction == Vector2i.UP:
			return _slots[at_slot - 1] if at_slot > 0 else _tabs[_viewed]
		if direction == Vector2i.DOWN:
			return _slots[mini(at_slot + 1, cards - 1)]
		if direction == Vector2i.RIGHT and not _row_ids.is_empty():
			return _rows[_row_for(at_slot)]
		return button
	var at_row: int = _rows.find(button)
	if at_row >= 0:
		if direction == Vector2i.UP:
			return _rows[at_row - 1] if at_row > 0 else _tabs[_viewed]
		if direction == Vector2i.DOWN:
			return _rows[mini(at_row + 1, _row_ids.size() - 1)]
		if direction == Vector2i.LEFT and cards > 0:
			return _slots[clampi(_slot, 0, cards - 1)]
		return button
	return button


## The bag row to move right to from `slot`: the row of the card in it, else the first row.
func _row_for(slot: int) -> int:
	var cards: Array[StringName] = cards_of(_viewed)
	if slot >= 0 and slot < cards.size():
		var at: int = _row_ids.find(cards[slot])
		if at >= 0:
			return at
	return 0


func _show_staff(staff: int) -> void:
	_viewed = staff
	_slot = 0
	_render()
	_resync_focus()


func _drop() -> void:
	_held_staff = NOTHING
	_held_slot = -1
	_render()


## Ask the player to move a card (BAG as `to_staff` sends it back to the bag; as `from_staff`,
## `from_slot` is the bag index).
func _move(from_staff: int, from_slot: int, to_staff: int, to_slot: int) -> void:
	_reason = ""
	if _events != null:
		_events.card_move_requested.emit(index, from_staff, from_slot, to_staff, to_slot)


func _ask(slot: int, id: StringName) -> void:
	_reason = ""
	if _events != null:
		_events.staff_change_requested.emit(index, _viewed, slot, id)


## Read the shown staff's links from its plan (see `_links` and `_cast_of`).
func _read_links() -> void:
	_links.clear()
	_cast_of.clear()
	var casts: Variant = _plans[_viewed].get("casts", [])
	if not casts is Array:
		return
	var number: int = 1
	for cast: Variant in casts:
		if not cast is Dictionary:
			continue
		var targets: Dictionary = (cast as Dictionary).get("targets", {}) as Dictionary
		for slot: Variant in targets:
			if not _links.has(int(slot)):
				_links[int(slot)] = int(targets[slot])
			var target: int = int(targets[slot])
			if target >= 0 and not _cast_of.has(target):
				_cast_of[target] = number
		var read: Variant = (cast as Dictionary).get("slots", PackedInt32Array())
		var wasted: Dictionary = (cast as Dictionary).get("wasted", {}) as Dictionary
		for slot: Variant in read:
			if not targets.has(slot) and not wasted.has(slot) and not _cast_of.has(int(slot)):
				_cast_of[int(slot)] = number
		number += 1


## The slots linked to `slot`: its carrier, or the cards that go into it.
func _linked_to(slot: int) -> Array[int]:
	var out: Array[int] = []
	if slot < 0:
		return out
	if _links.has(slot) and int(_links[slot]) >= 0:
		out.append(int(_links[slot]))
	for other: Variant in _links:
		if int(_links[other]) == slot:
			out.append(int(other))
	return out


func _target_word(target: int) -> String:
	if target == StaffCompiler.TARGET_CASTER:
		return "you"
	if target == StaffCompiler.TARGET_POINT:
		return "aim"
	return str(target + 1)


## Where the card in `slot` goes, in words, or "".
func _link_sentence(slot: int) -> String:
	if slot < 0:
		return ""
	if _links.has(slot):
		var target: int = int(_links[slot])
		if target == StaffCompiler.TARGET_CASTER:
			return "Goes on you."
		if target == StaffCompiler.TARGET_POINT:
			return "Goes where you aim."
		var cards: Array[StringName] = cards_of(_viewed)
		var carrier: String = _name_of(cards[target]) if target < cards.size() else ""
		return "Goes into %s (slot %d)." % [carrier, target + 1]
	if _cast_of.has(slot):
		return "Cast %d." % int(_cast_of[slot])
	return ""


## The live number the cast's own words leave out: its damage if every shot lands once (the
## words already give its mana and delay).
func _numbers(cast: Dictionary) -> String:
	return "%s dmg" % SpellsScript._short(float(cast.get("damage", 0.0)))


## Player 1's mouse on `button`: a press focuses it; a release on the same control works as
## `accept`, on another slot (or the bag) moves the card there.
func _on_mouse(event: InputEvent, button: Button) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT or not _open:
		return
	if click.pressed:
		_pressed = button
		if _ui_focus != null:
			_ui_focus.focus(index, button)
		return
	var from: Control = _pressed
	_pressed = null
	if from == null:
		return
	var to: Control = _control_at(click.global_position)
	if to == null:
		return
	if to == from:
		_on_activated(index, from)
		return
	var from_slot: int = _slots.find(from as Button)
	var to_slot: int = _slots.find(to as Button)
	var from_row: int = _rows.find(from as Button)
	if from_slot >= 0 and to_slot >= 0:
		_move(_viewed, from_slot, _viewed, to_slot)
	elif from_slot >= 0 and _rows.has(to as Button):
		_move(_viewed, from_slot, BAG, 0)
	elif from_row >= 0 and to_slot >= 0 and from_row < _row_ids.size():
		if _row_ids[from_row] == NO_CARD:
			_slot = to_slot
			_ask(to_slot, NO_CARD)
		else:
			_move(BAG, _bag.find(_row_ids[from_row]), _viewed, to_slot)
	if _held_staff != NOTHING:
		_drop()
	if _ui_focus != null:
		_ui_focus.focus(index, to)


## The shown tab, slot or bag row under the screen point `at`, or null.
func _control_at(at: Vector2) -> Control:
	for control in _controls:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(at):
			return control
	return null


## Move this player's focus to `target`.
func _focus_control(target: Control) -> void:
	if _ui_focus != null:
		_ui_focus.focus(index, target)
