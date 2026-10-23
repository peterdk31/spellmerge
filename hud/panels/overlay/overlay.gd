extends PanelContainer
## One player's overlay: a small menu beside that player's corner panel, opened
## and closed by their `overlay` action (the toggle is in `hud/panels/panels.gd`).
## It never pauses the game and never blocks another player: opening it only
## captures its owner's gameplay input through `core/ui_focus`, so the wizard
## stands still while the other three carry on.
##
## Input comes only through UIFocus: up/left and down/right move between the
## controls, `cast` activates, `dodge` goes back. Every UIFocus signal carries a
## player index and this overlay ignores all but its own, so it is the same for
## any index 0-3. The focused control is marked with "> " in front of its text,
## so the focus is never shown by colour alone.
##
## "Build" asks for this player's spell builder: it only sends the local signal
## `build_pressed(player)`, and `hud/panels/panels.gd` opens the builder (which takes the
## player's focus over from this overlay). The overlay sends no event for it.
##
## "Bag" (M2 part 18; it was "Drop component") is the quick action that works in combat too:
## it lists the bag components that fit a free slot of the active spell (the empty element
## slot, the first free modifier slot; `hud/widgets/drop_choices.gd`) and activating one sends
## `build_change_requested(player, [active spell], slot, id)`. What it offers follows
## `recipe_changed`, `bag_changed` and `active_spell_changed`, so a refused or answered change
## shows up as the list changing; the overlay never changes a recipe itself. `dodge` on a
## component goes back to "Bag", anywhere else it closes the overlay.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const DropChoicesScript := preload("res://hud/widgets/drop_choices.gd")

const PLAYER_COUNT: int = 4
const SPELL_COUNT: int = 2
const RESUME_TEXT: String = "Resume"
const BUILD_TEXT: String = "Build"
const DROP_TEXT: String = "Bag"
## The title word while the list of components to drop is shown.
const DROP_TITLE: String = "Drop"
## The title word while the three buttons are shown.
const MENU_TITLE: String = "MENU"
const FOCUS_MARK: String = "> "
## The look of the drop list: the BuilderButton theme variation (10 px).
const ROW_VARIATION: StringName = &"BuilderButton"
const ROW_WIDTH: float = 54.0
const ROW_HEIGHT: float = 14.0
## The meta key that keeps a button's text without the focus mark.
const BASE_TEXT_META: StringName = &"base_text"

## The owner activated "Build". Carries the index of this overlay.
signal build_pressed(player: int)

## The player index 0-3. Set before adding the node to the tree.
@export var index: int = 0

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _spells: SpellsScript = null
var _open: bool = false
var _focused: Control = null
## Mirrors of what the player announced.
var _recipes: Array[Dictionary] = [{}, {}]
var _bag: Array[StringName] = []
var _active: int = 0
## The drop list is shown; the component and free slot each shown row asks for.
var _dropping: bool = false
var _rows: Array[Button] = []
var _row_ids: Array[StringName] = []
var _row_slots: Array[int] = []
var _can_drop: bool = false
## How many controls UIFocus was given, and whether we are giving them again (not a real close).
var _synced_controls: int = 0
var _reopening: bool = false
var _controls: Array[Control] = []
var _grid: GridContainer = null

@onready var _title: Label = %Title
@onready var _resume: Button = %Resume
@onready var _build: Button = %Build
@onready var _drop: Button = %Drop


func _set_title(word: String) -> void:
	_title.text = "P%d %s" % [clampi(index, 0, PLAYER_COUNT - 1) + 1, word]


func _ready() -> void:
	var player: int = clampi(index, 0, PLAYER_COUNT - 1)
	theme_type_variation = StringName("PlayerPanel%d" % (player + 1))
	_title.theme_type_variation = StringName("PlayerLabel%d" % (player + 1))
	_set_title(MENU_TITLE)
	_set_text(_resume, RESUME_TEXT)
	_set_text(_build, BUILD_TEXT)
	_set_text(_drop, DROP_TEXT)
	# The drop list: two columns of rows, shown in place of the three buttons, so a list of ten
	# components stays inside this player's quarter of the screen.
	_grid = GridContainer.new()
	_grid.name = "DropList"
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	_grid.visible = false
	get_node("Rows").add_child(_grid)
	visible = false
	_refresh()


## Connect to the event bus and the focus service (called once by `panels.gd`); `spells`
## gives the kinds and names of components for the drop list.
func bind(events: EventsScript, ui_focus: UIFocusScript, spells: SpellsScript = null) -> void:
	_events = events
	_ui_focus = ui_focus
	_spells = spells
	if _events != null:
		_events.recipe_changed.connect(_on_recipe_changed)
		_events.bag_changed.connect(_on_bag_changed)
		_events.active_spell_changed.connect(_on_active_spell_changed)
	if _ui_focus != null:
		_ui_focus.closed.connect(_on_closed)
		_ui_focus.activated.connect(_on_activated)
		_ui_focus.cancelled.connect(_on_cancelled)
		_ui_focus.focus_changed.connect(_on_focus_changed)


func is_open() -> bool:
	return _open


## Open the overlay for its owner. False if the owner has no device or their
## panel is already taken by something else.
func open_overlay() -> bool:
	if _open or _ui_focus == null or _ui_focus.is_open(index):
		return false
	_dropping = false
	_focused = null
	_refresh()
	# Visible first: UIFocus only focuses controls that are shown.
	visible = true
	if not _ui_focus.open(index, _controls):
		visible = false
		return false
	_open = true
	_synced_controls = _controls.size()
	_focused = _ui_focus.focused(index)
	_mark_focus()
	return true


## Close the overlay if it is open.
func close_overlay() -> bool:
	if not _open or _ui_focus == null:
		return false
	return _ui_focus.close(index)


## Open if closed, close if open: what the `overlay` action does.
func toggle() -> void:
	if _open:
		close_overlay()
	else:
		open_overlay()


## The "Bag" button (for tests and screenshots).
func drop_button() -> Button:
	return _drop


## The drop list rows now shown, in order.
func shown_rows() -> Array[Button]:
	var shown: Array[Button] = []
	for row in _row_ids.size():
		shown.append(_rows[row])
	return shown


## The component ids the shown drop rows ask for, in order.
func row_ids() -> Array[StringName]:
	return _row_ids.duplicate()


## The slot each shown drop row asks for, in order.
func row_slots() -> Array[int]:
	return _row_slots.duplicate()


func is_dropping() -> bool:
	return _dropping


func _set_text(button: Button, text: String) -> void:
	button.set_meta(BASE_TEXT_META, text)
	button.text = (FOCUS_MARK if button == _focused else "") + text


func _mark_focus() -> void:
	for control in _controls:
		var button := control as Button
		button.text = (FOCUS_MARK if button == _focused else "") + str(button.get_meta(BASE_TEXT_META, ""))


## Make the drop rows and the list of controls from what the player announced.
func _refresh() -> void:
	var node: Dictionary = _recipes[_active]
	var offered: Dictionary = DropChoicesScript.choices(node, _bag, _spells)
	_row_ids.assign(offered["ids"])
	_row_slots.assign(offered["slots"])
	_can_drop = not _row_ids.is_empty()
	if not _can_drop:
		_dropping = false
	if not _dropping:
		_row_ids.clear()
		_row_slots.clear()
	while _rows.size() < _row_ids.size():
		var row := Button.new()
		row.name = "Row%d" % _rows.size()
		row.theme_type_variation = ROW_VARIATION
		row.focus_mode = Control.FOCUS_NONE
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.visible = false
		row.custom_minimum_size = Vector2(ROW_WIDTH, ROW_HEIGHT)
		_grid.add_child(row)
		_rows.append(row)
	for at in _rows.size():
		var button: Button = _rows[at]
		button.visible = at < _row_ids.size()
		if at < _row_ids.size():
			var id: StringName = _row_ids[at]
			var shown: String = _spells.component_name(id) if _spells != null else ""
			_set_text(button, shown if shown != "" else String(id))
	_drop.disabled = not _can_drop
	_resume.visible = not _dropping
	_build.visible = not _dropping
	_drop.visible = not _dropping
	_grid.visible = _dropping
	_set_title(DROP_TITLE if _dropping else MENU_TITLE)
	_controls.clear()
	_controls.append(_resume)
	_controls.append(_build)
	_controls.append(_drop)
	for row in _rows:
		_controls.append(row)
	_mark_focus()


## UIFocus keeps its own copy of the controls: after more rows were made, hand it the new list.
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
	_mark_focus()


## Move this player's focus to `target` by single steps (the focus service has no jump).
func _focus_control(target: Control) -> void:
	if _ui_focus == null:
		return
	for _step in _controls.size():
		if _ui_focus.focused(index) == target:
			return
		_ui_focus.move_focus(index, 1)


func _on_recipe_changed(player: int, slot: int, recipe: Dictionary) -> void:
	if player != index or slot < 0 or slot >= SPELL_COUNT:
		return
	_recipes[slot] = recipe.duplicate(true)
	_refresh()


func _on_bag_changed(player: int, bag: Array[StringName]) -> void:
	if player != index:
		return
	_bag = bag.duplicate()
	_refresh()
	_resync_focus()


func _on_active_spell_changed(player: int, slot: int) -> void:
	if player != index or slot < 0 or slot >= SPELL_COUNT:
		return
	_active = slot
	_dropping = false
	_refresh()
	if _open:
		_focus_control(_drop if _can_drop else _resume)


func _on_closed(player: int) -> void:
	if player != index or _reopening:
		return
	_open = false
	_focused = null
	_dropping = false
	visible = false


func _on_focus_changed(player: int, control: Control) -> void:
	if player == index and _open:
		_focused = control
		_mark_focus()


func _on_activated(player: int, control: Control) -> void:
	if player != index or not _open:
		return
	if control == _resume:
		close_overlay()
	elif control == _build:
		build_pressed.emit(index)
	elif control == _drop:
		_dropping = true
		_refresh()
		_resync_focus()
		_focus_control(_rows[0] if not _row_ids.is_empty() else _resume)
	elif _rows.has(control as Button):
		var at: int = _rows.find(control as Button)
		if at < _row_ids.size() and _events != null:
			_events.build_change_requested.emit(index, PackedInt32Array([_active]), _row_slots[at], _row_ids[at])
			# The answer (`recipe_changed`) came before this line and rebuilt the list: stay
			# in it while there is something left to drop, else go back to the button.
			if not _can_drop:
				_focus_control(_resume)
			elif _row_ids.is_empty():
				_focus_control(_drop)
			else:
				_focus_control(_rows[mini(at, _row_ids.size() - 1)])


func _on_cancelled(player: int) -> void:
	if player != index or not _open:
		return
	if _dropping and _rows.has(_focused as Button):
		_dropping = false
		_refresh()
		_focus_control(_drop)
	else:
		close_overlay()
