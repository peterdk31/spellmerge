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
## Order: the spell tabs (A, B), the six slots (form, element, three modifiers, trigger),
## "< Up" and "Held >" (the spell a trigger holds, at most two levels down), the bag rows
## and "Close". Activating a slot selects it and moves focus to the bag row list, which
## shows only the components that fit the slot (plus "None" to empty a filled slot);
## activating a row sends the request. `dodge` on a bag row goes back to its slot, and
## anywhere else closes the builder. The focused control is marked with "> " and the
## selected slot is shown in brackets, so nothing is shown by colour alone.
##
## Every UIFocus signal carries a player index and this node ignores all but its own, so it
## is the same for any index 0-3. Buttons are made once; opening and activating only change
## their text and visibility (the bag rows grow, once, if the bag needs more of them).

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

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
const SLOT_NAMES: Array[String] = ["F", "E", "M1", "M2", "M3", "T"]
## A trigger may hold a spell that holds another: two levels below the cast.
const MAX_LEVEL: int = 2
const SPELL_COUNT: int = 2
const SPELL_NAMES: Array[String] = ["A", "B"]
const NO_COMPONENT: StringName = &""

const NONE_TEXT: String = "None"
const EMPTY_SLOT_TEXT: String = "-"
const FOCUS_MARK: String = "> "
const CURRENT_MARK: String = " *"
## The look of every control: the BuilderButton theme variation.
const BUTTON_VARIATION: StringName = &"BuilderButton"
const ROW_HEIGHT: float = 18.0
const LEFT_WIDTH: float = 100.0
const RIGHT_WIDTH: float = 80.0
## The meta key that keeps a button's text without the focus mark.
const BASE_TEXT_META: StringName = &"base_text"

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

var _open: bool = false
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
var _rows: Array[Button] = []
## The component id each shown bag row asks for, in row order (`NO_COMPONENT` is "None").
var _row_ids: Array[StringName] = []
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
	right.custom_minimum_size = Vector2(RIGHT_WIDTH, 0.0)
	right.add_theme_constant_override("separation", 2)
	columns.add_child(right)

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
	levels.add_theme_constant_override("separation", 2)
	left.add_child(levels)
	_up = _make_button(levels, "Up")
	_up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_held = _make_button(levels, "Held")
	_held.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visible = false
	_render()


## Connect to the event bus, the focus service and the spell runtime, which gives names, icons
## and kinds (called once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript, spells: SpellsScript) -> void:
	_events = events
	_ui_focus = ui_focus
	_spells = spells
	if _events != null:
		_events.recipe_changed.connect(_on_recipe_changed)
		_events.bag_changed.connect(_on_bag_changed)
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
	_viewed = 0
	_level = 0
	_slot = SLOT_FORM
	_focused = null
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
	_apply_marks()
	return true


## Close the builder if it is open.
func close_builder() -> bool:
	if not _open or _ui_focus == null:
		return false
	return _ui_focus.close(index)


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
	var holder: Node = get_node("Columns/Bag")
	while _rows.size() < count:
		var row: Button = _make_button(holder, "Row%d" % _rows.size())
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
	_title.text = title
	for spell in SPELL_COUNT:
		_set_text(_tabs[spell], SPELL_NAMES[spell] if spell != _viewed else "[%s]" % SPELL_NAMES[spell])
	_set_text(_close, "Close")
	for slot in SLOT_COUNT:
		var id: StringName = _id_in(node, slot)
		var text: String = "%s: %s" % [SLOT_NAMES[slot], _name_of(id) if id != NO_COMPONENT else EMPTY_SLOT_TEXT]
		_set_text(_slots[slot], "[%s]" % text if slot == _slot else text)
		_slots[slot].disabled = not _slot_usable(node, slot)
	_up.disabled = _level == 0
	_set_text(_up, "< Up")
	_held.disabled = _level >= MAX_LEVEL or _id_in(node, SLOT_TRIGGER) == NO_COMPONENT
	_set_text(_held, "Held >")
	_render_rows(node)
	_rebuild_controls()
	_apply_marks()


func _render_rows(node: Dictionary) -> void:
	var current: StringName = _id_in(node, _slot)
	_row_ids.clear()
	if current != NO_COMPONENT and _slot != SLOT_FORM:
		_row_ids.append(NO_COMPONENT)
	for id in _bag:
		if _kind_of(id) == SLOT_KINDS[_slot]:
			_row_ids.append(id)
	_grow_rows(_row_ids.size())
	for row in _rows.size():
		var button: Button = _rows[row]
		if row >= _row_ids.size():
			button.visible = false
			continue
		var id: StringName = _row_ids[row]
		button.visible = true
		if id == NO_COMPONENT:
			button.icon = null
			_set_text(button, NONE_TEXT)
		else:
			button.icon = _spells.component_icon(id) if _spells != null else null
			_set_text(button, _name_of(id) + (CURRENT_MARK if id == current else ""))


func _rebuild_controls() -> void:
	_controls.clear()
	for tab in _tabs:
		_controls.append(tab)
	for slot_button_node in _slots:
		_controls.append(slot_button_node)
	_controls.append(_up)
	_controls.append(_held)
	for row in _rows:
		_controls.append(row)
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


func _ask(slot: int, id: StringName) -> void:
	if _events != null:
		_events.build_change_requested.emit(index, spell_path(), slot, id)


func _on_recipe_changed(player: int, slot: int, recipe: Dictionary) -> void:
	if player != index or slot < 0 or slot >= SPELL_COUNT:
		return
	_recipes[slot] = recipe.duplicate(true)
	_render()


func _on_bag_changed(player: int, bag: Array[StringName]) -> void:
	if player != index:
		return
	_bag = bag.duplicate()
	_render()
	_resync_focus()


## UIFocus keeps its own copy of the controls: when a bigger bag made more rows, give it the new
## list and put focus back where it was.
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


func _on_cancelled(player: int) -> void:
	if player != index or not _open:
		return
	if _rows.has(_focused as Button):
		_focus_control(_slots[_slot])
	else:
		close_builder()


func _on_activated(player: int, control: Control) -> void:
	if player != index or not _open:
		return
	if control == _close:
		close_builder()
	elif _tabs.has(control as Button):
		_viewed = _tabs.find(control as Button)
		_level = 0
		_slot = SLOT_FORM
		_render()
	elif _slots.has(control as Button):
		_slot = _slots.find(control as Button)
		_render()
		_focus_control(_first_row())
	elif control == _up:
		_level -= 1
		_slot = SLOT_FORM
		_render()
	elif control == _held:
		_level += 1
		_slot = SLOT_FORM
		_render()
	elif _rows.has(control as Button):
		var row: int = _rows.find(control as Button)
		if row < _row_ids.size():
			var chosen: StringName = _row_ids[row]
			_ask(_slot, chosen)
			_keep_focus_on(chosen)


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
		_focus_control(_slots[_slot])


## The first bag row shown, or the selected slot if the bag has nothing for it.
func _first_row() -> Control:
	return _rows[0] if not _row_ids.is_empty() else _slots[_slot]


## Move this player's focus to `target` by single steps (the focus service has no jump).
func _focus_control(target: Control) -> void:
	if _ui_focus == null:
		return
	for _step in _controls.size():
		if _ui_focus.focused(index) == target:
			return
		_ui_focus.move_focus(index, 1)
