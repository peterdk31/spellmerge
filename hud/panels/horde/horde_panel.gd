extends Control
## The horde HUD (docs/milestones/horde.md, H5): node Root/Horde of `panels.tscn`, in every
## build, showing nothing outside a horde run. It hears only events and sends one request:
##
## - **Status** (top middle, between the two top corner panels): "03:12  Kills 140  Level 4" and
##   the experience bar with "XP 12/30", from `horde_status`; shown on `horde_started`, hidden
##   on `horde_ended`.
## - **The build break** (owner, 2026-10-31: in Horde the game pauses until every player is
##   ready). A level-up pauses the whole game (the director, `horde_break_changed(true)`); this
##   node and the builders run while paused (the HUD is PROCESS_MODE_ALWAYS). One box per seat
##   (`horde_pick.gd`), beside that seat's corner panel toward the middle, in the seat's colour,
##   walks the seat through it with its own device, read here from `core/input` press counts:
##   1. **Pick:** on `horde_picks_offered(seat, card_ids)` up to three cards (icon, name, kind
##      word and colour). The d-pad's left and right (`kind_prev`, `kind_next`; PgUp and PgDn)
##      move the choice and `accept` (A; Enter) sends `horde_pick_requested(seat, choice)`; P1
##      on the keyboard also points with the mouse and clicks (the left button, `staff_2`).
##      A queued offer comes right after the pick.
##   2. **Build, then ready:** with no offer open and the seat not ready, the box says "Build,
##      then ready" with `back` (B; Tab, E) "Build" and `accept` (A; Enter) "Ready". B opens the
##      seat's builder as in play (`hud/panels` reads it, also while paused); the box hides while
##      the builder is open, since the builder owns `accept`, and shows again when it closes
##      (B or Start). `accept` on the box sends `horde_ready_requested(seat)`.
##   3. **Ready:** on `horde_ready_changed(seat, true)` the box says "Ready" until the break ends.
##   Under the status, a hammer and "Waiting for P2, P3" name the seats not ready yet (from
##   `horde_ready_changed`, `player_left`), until `horde_break_changed(false)`. Since the game is
##   paused, nothing walks or casts meanwhile: the d-pad and the click take nothing else.
##   Outside a break an offer works the same way (it does not happen in play: offers come with
##   a break). While the seat has a menu open (its builder, or the pause menu it works) its box
##   hides and reads nothing; while the pause menu is open (anyone's: `pause_open`) or the game
##   is paused outside a break, no box reads anything; nor at the first poll after a menu
##   closed or the game resumed, so the `accept` that closed a menu never takes a card or says
##   ready.
## - **The end** (the middle of the view): "The horde won" with the time, kills and level from
##   `horde_over`, until the next `horde_started` (or `horde_ended`).
##
## Nothing here allocates per frame: the texts change only on events (status four times a
## second).

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const HordePickScript := preload("res://hud/panels/horde/horde_pick.gd")
const HammerIconScript := preload("res://hud/widgets/hammer_icon.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")

const SEATS: int = 4
const EDGE: float = 4.0
## A pick box sits this far from the screen's side: beside the 112 px corner panel, like the
## list builder.
const PICK_SIDE: float = 118.0
const STATUS_WIDTH: float = 156.0
const XP_BAR_SIZE: Vector2 = Vector2(96.0, 4.0)
const BREAK_FONT_SIZE: int = 12
## The buttons read per seat: choose left, right, take (also ready), click.
const READ_ACTIONS: Array[StringName] = [
	HordePickScript.PREV_ACTION, HordePickScript.NEXT_ACTION, HordePickScript.TAKE_ACTION, &"staff_2",
]
const OVER_TITLE: String = "The horde won"
const WAITING_TEXT: String = "Waiting for %s"

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _input: InputManagerScript = null
var _spells: SpellsScript = null
## Where P1's mouse is, in the view's pixels; a Callable so tests can point.
var mouse_position: Callable = _mouse_position
## True while the pause menu is open (set by `panels.gd`); it stops every box.
var pause_open: Callable = _no_pause

var _column: VBoxContainer = null
var _status: PanelContainer = null
var _status_label: Label = null
var _xp_bar: ProgressBar = null
var _xp_label: Label = null
var _break_row: PanelContainer = null
var _break_label: Label = null
## True during a build break; per seat, whether the break waits for it (joined, not ready).
var _break_on: bool = false
var _waiting: Array[bool] = [false, false, false, false]
var _summary: PanelContainer = null
var _summary_label: Label = null
var _picks: Array[HordePickScript] = []
## Per seat and action in READ_ACTIONS (seat * READ_ACTIONS.size() + action): the press count at
## the last poll, and this poll's new presses (one array each, reused every frame).
var _seen: PackedInt64Array = PackedInt64Array()
var _presses: PackedInt64Array = PackedInt64Array()
## Per seat: whether its picks were blocked (a menu of its own, the game paused) at the last poll.
var _blocked: Array[bool] = [true, true, true, true]
## The last numbers shown, so a status that did not change sets no text.
var _shown_status: PackedInt64Array = PackedInt64Array([-1, -1, -1, -1, -1])


func _init() -> void:
	name = "Horde"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_column = VBoxContainer.new()
	_column.name = "Top"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", 2)
	_column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_column.offset_top = EDGE
	add_child(_column)
	_build_status()
	_build_break()
	_build_summary()
	for seat in SEATS:
		var pick: HordePickScript = HordePickScript.new()
		pick.name = "Pick%d" % (seat + 1)
		pick.seat = seat
		var right: bool = seat % 2 == 1
		var bottom: bool = seat >= 2
		pick.anchor_left = 1.0 if right else 0.0
		pick.anchor_right = pick.anchor_left
		pick.anchor_top = 1.0 if bottom else 0.0
		pick.anchor_bottom = pick.anchor_top
		pick.offset_left = -PICK_SIDE if right else PICK_SIDE
		pick.offset_right = pick.offset_left
		pick.offset_top = -EDGE if bottom else EDGE
		pick.offset_bottom = pick.offset_top
		pick.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
		pick.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
		add_child(pick)
		_picks.append(pick)
	_seen.resize(SEATS * READ_ACTIONS.size())
	_presses.resize(READ_ACTIONS.size())


func _build_status() -> void:
	_status = PanelContainer.new()
	_status.name = "Status"
	_status.visible = false
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.custom_minimum_size = Vector2(STATUS_WIDTH, 0.0)
	_status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(_status)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	_status.add_child(box)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.theme_type_variation = &"BuilderLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_status_label)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	_xp_bar = ProgressBar.new()
	_xp_bar.name = "XpBar"
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = XP_BAR_SIZE
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_xp_bar)
	_xp_label = Label.new()
	_xp_label.name = "XpLabel"
	_xp_label.theme_type_variation = &"BuilderHint"
	_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_xp_label)
	_show_status(0.0, 0, 1, 0, 1)


func _build_break() -> void:
	_break_row = PanelContainer.new()
	_break_row.name = "BreakRow"
	_break_row.visible = false
	_break_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_break_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(_break_row)
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_break_row.add_child(box)
	var hammer: Control = HammerIconScript.new()
	hammer.name = "Hammer"
	hammer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(hammer)
	_break_label = Label.new()
	_break_label.name = "BreakLabel"
	_break_label.add_theme_font_size_override("font_size", BREAK_FONT_SIZE)
	_break_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_break_label)


func _build_summary() -> void:
	_summary = PanelContainer.new()
	_summary.name = "Summary"
	_summary.visible = false
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_summary)
	_summary.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_summary.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_summary.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	_summary.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.text = OVER_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", RadialScript.WARN)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	_summary_label = Label.new()
	_summary_label.name = "Numbers"
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_summary_label)


## Connect to the event bus, the focus service, the input manager and the spell runtime (the
## cards' names, icons and kinds). Called once by `panels.gd`.
func bind(events: EventsScript, ui_focus: UIFocusScript, spells: SpellsScript, input: InputManagerScript) -> void:
	_events = events
	_ui_focus = ui_focus
	_spells = spells
	_input = input
	for pick in _picks:
		pick.bind(input)
	if _events != null:
		_events.horde_started.connect(_on_started)
		_events.horde_ended.connect(_on_ended)
		_events.horde_status.connect(_on_status)
		_events.horde_picks_offered.connect(_on_picks_offered)
		_events.horde_pick_taken.connect(_on_pick_taken)
		_events.horde_break_changed.connect(_on_break_changed)
		_events.horde_ready_changed.connect(_on_ready_changed)
		_events.horde_over.connect(_on_over)
		_events.player_left.connect(_on_player_left)


func _process(_delta: float) -> void:
	poll()


## Read every seat's new presses and work its box, as the top of this file says. Called every
## frame (also while paused); tests call it directly. One seat's presses never touch another
## seat's box.
func poll() -> void:
	var stopped: bool = _stopped()
	for seat in SEATS:
		var pick: HordePickScript = _picks[seat]
		_read_presses(seat)
		var menu: bool = _ui_focus != null and _ui_focus.is_open(seat)
		var mode: HordePickScript.Mode = pick.mode()
		pick.visible = mode != HordePickScript.Mode.HIDDEN and not menu
		var blocked: bool = menu or stopped or (mode != HordePickScript.Mode.OFFER and mode != HordePickScript.Mode.PROMPT)
		var was_blocked: bool = _blocked[seat]
		_blocked[seat] = blocked
		if blocked or was_blocked:
			continue
		if mode == HordePickScript.Mode.PROMPT:
			if _presses[2] > 0 and _events != null:
				_events.horde_ready_requested.emit(seat)
			continue
		var clicks: int = 0
		if _uses_mouse(seat):
			var under: int = pick.card_at(mouse_position.call())
			if under != HordePickScript.NONE:
				pick.choose(under)
				clicks = _presses[3]
		pick.step_choice(_presses[1] - _presses[0])
		if _presses[2] + clicks > 0 and pick.choice() != HordePickScript.NONE and _events != null:
			_events.horde_pick_requested.emit(seat, pick.choice())


## `seat`'s new presses of READ_ACTIONS since the last read, into `_presses`.
func _read_presses(seat: int) -> void:
	var base: int = seat * READ_ACTIONS.size()
	for at in READ_ACTIONS.size():
		var count: int = _input.get_press_count(seat, READ_ACTIONS[at]) if _input != null else 0
		_presses[at] = maxi(count - _seen[base + at], 0)
		_seen[base + at] = count


func _uses_mouse(seat: int) -> bool:
	return seat == 0 and _input != null and _input.device_of(0) == InputManagerScript.KEYBOARD


func _mouse_position() -> Vector2:
	return get_global_mouse_position()


func _no_pause() -> bool:
	return false


## True while no box may read: the pause menu is open, or the game is paused outside a break.
func _stopped() -> bool:
	if bool(pause_open.call()):
		return true
	return is_inside_tree() and get_tree().paused and not _break_on


func _on_started(_world: Node2D) -> void:
	_end_break()
	_summary.visible = false
	_show_status(0.0, 0, 1, 0, 1)
	_status.visible = true


func _on_ended() -> void:
	_end_break()
	_summary.visible = false
	_status.visible = false


func _on_status(seconds: float, kills: int, _alive: int, level: int, xp: int, xp_next: int) -> void:
	_show_status(seconds, kills, level, xp, xp_next)


func _show_status(seconds: float, kills: int, level: int, xp: int, xp_next: int) -> void:
	var whole: int = maxi(int(seconds), 0)
	if whole != _shown_status[0] or kills != _shown_status[1] or level != _shown_status[2]:
		_status_label.text = "%s  Kills %d  Level %d" % [clock(seconds), kills, level]
	if xp != _shown_status[3] or xp_next != _shown_status[4]:
		_xp_bar.max_value = maxi(xp_next, 1)
		_xp_bar.value = clampi(xp, 0, maxi(xp_next, 1))
		_xp_label.text = "XP %d/%d" % [xp, xp_next]
	_shown_status[0] = whole
	_shown_status[1] = kills
	_shown_status[2] = level
	_shown_status[3] = xp
	_shown_status[4] = xp_next


## `seconds` as minutes and seconds, "03:12" (whole seconds, rounded down).
static func clock(seconds: float) -> String:
	var whole: int = maxi(int(seconds), 0)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [whole / 60, whole % 60]


func _on_picks_offered(seat: int, card_ids: Array[StringName]) -> void:
	if seat < 0 or seat >= SEATS:
		return
	var pick: HordePickScript = _picks[seat]
	if card_ids.is_empty():
		_show_after_picks(seat)
		return
	pick.offer(card_ids, _spells)
	_freshen(seat)


## After the box of `seat` changed: presses from before take nothing (the counts start now), and
## it shows unless the seat has a menu open.
func _freshen(seat: int) -> void:
	_read_presses(seat)
	var menu: bool = _ui_focus != null and _ui_focus.is_open(seat)
	_picks[seat].visible = _picks[seat].mode() != HordePickScript.Mode.HIDDEN and not menu
	_blocked[seat] = menu or _stopped()


func _on_pick_taken(seat: int, _card_id: StringName) -> void:
	if seat < 0 or seat >= SEATS:
		return
	# A queued offer follows at once (`horde_picks_offered`); otherwise the seat builds.
	_show_after_picks(seat)


## The box of `seat` with no offer open: the prompt while the break waits for it, else nothing.
func _show_after_picks(seat: int) -> void:
	var pick: HordePickScript = _picks[seat]
	if _break_on and _waiting[seat]:
		pick.show_prompt()
	else:
		pick.clear()
	_freshen(seat)


func _on_player_left(seat: int) -> void:
	if seat < 0 or seat >= SEATS:
		return
	_waiting[seat] = false
	_picks[seat].clear()
	_freshen(seat)
	_show_waiting()


func _on_break_changed(on: bool) -> void:
	if on:
		_break_on = true
		_show_waiting()
	else:
		_end_break()


func _on_ready_changed(seat: int, on: bool) -> void:
	if seat < 0 or seat >= SEATS or not _break_on:
		return
	_waiting[seat] = not on
	var pick: HordePickScript = _picks[seat]
	if on:
		pick.show_ready()
		_freshen(seat)
	elif not pick.has_offer():
		_show_after_picks(seat)
	_show_waiting()


## The break is over (or the run): every box closes, the waiting line goes.
func _end_break() -> void:
	_break_on = false
	for seat in SEATS:
		_waiting[seat] = false
		_picks[seat].clear()
		_freshen(seat)
	_show_waiting()


## "Waiting for P2, P3" under the status while the break waits for someone; hidden otherwise.
func _show_waiting() -> void:
	var names: PackedStringArray = PackedStringArray()
	for seat in SEATS:
		if _break_on and _waiting[seat]:
			names.append("P%d" % (seat + 1))
	_break_row.visible = not names.is_empty()
	if not names.is_empty():
		_break_label.text = WAITING_TEXT % ", ".join(names)


func _on_over(seconds: float, kills: int, level: int) -> void:
	_end_break()
	_summary_label.text = "Time %s  Kills %d  Level %d" % [clock(seconds), kills, level]
	_summary.visible = true


# --- For tests and screenshots ------------------------------------------------------------

func get_status() -> PanelContainer:
	return _status


func status_text() -> String:
	return _status_label.text


func xp_text() -> String:
	return _xp_label.text


func xp_bar() -> ProgressBar:
	return _xp_bar


func get_break_row() -> PanelContainer:
	return _break_row


## The waiting line's words ("Waiting for P2, P3").
func break_text() -> String:
	return _break_label.text


## True while a build break is on.
func in_break() -> bool:
	return _break_on


func get_summary() -> PanelContainer:
	return _summary


func summary_text() -> String:
	return _summary_label.text


func get_pick(seat: int) -> HordePickScript:
	return _picks[seat] if seat >= 0 and seat < SEATS else null
