extends PanelContainer
## One player's corner panel, in the player's border colour, kept small (owner, 2026-11-19): a
## thin red health line with a small number beside it, a word in the number's place when the
## player is down ("DOWN") or has their overlay open ("MENU"), and under it one row per staff that has cards
## (`staff_row.gd`: the staff's button glyph, its cast sequence, its delay and a thin blue line of
## its own mana, `set_staff_mana`). There is no panel-wide mana bar: every staff has its own pool,
## and its row shows it. The word means the state is never shown by colour alone. The lines ease
## by whole pixels (`hud/widgets/meter_line.gd`), and the line keeps one length: the number and the
## word share one fixed cell beside it, so neither reflows it. The room the bars took holds the
## run's purse (coins and rewards to pick) and, with M3, its relics. There is no "P1" or "Staff 2" line (owner,
## 2026-10-27): the corner and the border say whose panel it is, and the rows say more than the
## staff cast last did.
##
## It only shows what it is told: `set_stats`, `set_menu_open`, `set_online` (a small "ONLINE" over
## the line of a seat played on another machine), `set_purse` (a small line under the health line
## with the seat's coins and its unspent rewards, connected biomes CB10; hidden while both are 0),
## `set_keys` (the shown body's keys before the coins, on the same row: `key_count.gd`, Smooth; hidden
## while there are none), `set_rerolls` (its reward rerolls after the keys, a `key_count.gd` of its
## own picture, the same way; the owner, 2026-11-19),
## `set_staff_plan`, `set_staff_mana`,
## `set_staff_timing` and the dev switch `set_reload_style` are called by `hud/panels/panels.gd`,
## which hears the events and reads the staffs' timing from `Spells`. The panel takes no input and listens to nothing itself, so it is
## the same for any player index 0-3. Colours come from the shared theme (type variations
## PlayerPanel1-4) and the lines' own. Updating only changes text when a number changed, and
## a row only redraws when its timing changed, so a frame with no change allocates nothing.
##
## Beside the staff rows, the seat's four quick-use slots (`set_quick`; `hud/widgets/quick_cross.gd`, a
## small d-pad cross with each bound item's icon and count, the owner's of 2026-11-20): it always
## shows, its arms empty cells before anything is bound (the owner, 2026-11-20).
##
## While the player has a menu open the staff rows hide: the builder shows the staffs, and the
## radial builder's column takes the space under the panel.

const StaffRowScript := preload("res://hud/panels/player_panel/staff_row.gd")
const MeterScript := preload("res://hud/widgets/meter_line.gd")
const KeyCountScript := preload("res://hud/widgets/key_count.gd")
const QuickCrossScript := preload("res://hud/widgets/quick_cross.gd")

const PLAYER_COUNT: int = 4
const STAFF_COUNT: int = 4
const DOWN_TEXT: String = "DOWN"
const MENU_TEXT: String = "MENU"
## The word of a seat played on another machine (`set_online`).
const ONLINE_TEXT: String = "ONLINE"
## The purse line's words (`set_purse`): the coins, and the rewards waiting (A opens the oldest).
const COINS_TEXT: String = "%d coins"
const UNSPENT_TEXT: String = "%d to pick"
## A seat that joined while the run could not be joined (`set_join_held`; the owner, 2026-11-19):
## the word in the health number's place, and the line under it that says why.
const WAIT_TEXT: String = "WAIT"
const JOIN_HELD_TEXT: String = "Joins after this run:\nthe party left the start room"

## The player index 0-3. Set before adding the node to the tree.
@export var index: int = 0

var _health: float = -1.0
var _downed: bool = false
var _menu_open: bool = false
var _join_held: bool = false
## The line that says why a seat waits to join (`set_join_held`), made in `_ready`.
var _held_note: Label = null
var _rows: Array[StaffRowScript] = []
## Per staff: whether its plan has a card (an empty staff shows no row).
var _has_cards: Array[bool] = [false, false, false, false]
## The purse line (`set_purse`), made in `_ready` under the health line, and what it shows.
var _purse: Label = null
## The purse's row (the purse line, then the shown body's keys) and its key count (`set_keys`).
var _purse_row: HBoxContainer = null
var _keys: KeyCountScript = null
var _reward_rerolls: KeyCountScript = null
var _coins: int = 0
var _unspent: int = 0
## The staff rows and the quick-use cross beside them (`set_quick`).
var _lower: HBoxContainer = null
var _quick: QuickCrossScript = null

@onready var _seat_row: Control = %SeatRow
@onready var _seat: Label = %Seat
@onready var _status: Label = %Status
@onready var _health_line: MeterScript = %HealthLine
@onready var _health_value: Label = %HealthValue
@onready var _staffs: VBoxContainer = %Staffs


func _ready() -> void:
	var player: int = clampi(index, 0, PLAYER_COUNT - 1)
	theme_type_variation = StringName("PlayerPanel%d" % (player + 1))
	for staff in STAFF_COUNT:
		var row := StaffRowScript.new()
		row.name = "StaffRow%d" % (staff + 1)
		row.player = player
		row.staff = staff
		row.visible = false
		_staffs.add_child(row)
		_rows.append(row)
	_purse = Label.new()
	_purse.name = "Purse"
	_purse.visible = false
	_purse.theme_type_variation = StringName("PlayerLabel%d" % (player + 1))
	# In the panel's small font, as the health number (owner, 2026-11-19: a smaller HUD).
	_purse.add_theme_font_size_override(&"font_size", 8)
	_purse_row = HBoxContainer.new()
	_purse_row.name = "PurseRow"
	_purse_row.add_theme_constant_override(&"separation", 4)
	_purse_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The keys first: their left edge never moves, and their room grows by whole pixels (key_count.gd).
	_keys = KeyCountScript.new()
	_keys.name = "Keys"
	_keys.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_purse_row.add_child(_keys)
	_reward_rerolls = _count_of("RewardRerolls", KeyCountScript.REWARD_REROLL, &"void")
	_purse_row.add_child(_purse)
	_staffs.get_parent().add_child(_purse_row)
	_staffs.get_parent().move_child(_purse_row, _staffs.get_index())
	# The staff rows and, on their right, the quick-use cross.
	_lower = HBoxContainer.new()
	_lower.name = "Lower"
	_lower.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lower.add_theme_constant_override(&"separation", 3)
	var rows_box: Node = _staffs.get_parent()
	rows_box.add_child(_lower)
	rows_box.move_child(_lower, _staffs.get_index())
	_staffs.reparent(_lower, false)
	_staffs.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_staffs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quick = QuickCrossScript.new()
	_quick.name = "QuickCross"
	_quick.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_lower.add_child(_quick)
	_held_note = Label.new()
	_held_note.name = "JoinHeld"
	_held_note.visible = false
	_held_note.text = JOIN_HELD_TEXT
	_held_note.theme_type_variation = StringName("PlayerLabel%d" % (player + 1))
	_held_note.add_theme_font_size_override(&"font_size", 8)
	rows_box.add_child(_held_note)
	rows_box.move_child(_held_note, _purse_row.get_index())
	_align_rows()
	_refresh_status()


## Show the health. A player with no health left is shown as down. Mana is not shown here: each
## staff row shows its own (`set_staff_mana`).
func set_stats(health: float, max_health: float) -> void:
	if health != _health:
		_health = health
		_health_line.set_value(health, maxf(max_health, 1.0))
		# Rounded up: a wizard with part of a point left reads 1, never 0 (which is down).
		_health_value.text = str(ceili(health))
		var downed: bool = health <= 0.0
		if downed != _downed:
			_downed = downed
			_refresh_status()


## Show staff `staff`'s whole mana `mana` of its pool `most` on its row's line (a mana not finite:
## not told yet, the line hides).
func set_staff_mana(staff: int, mana: float, most: float) -> void:
	if staff >= 0 and staff < STAFF_COUNT:
		_rows[staff].set_mana(mana, most)


## The health line (for tests and screenshots).
func health_line() -> MeterScript:
	return _health_line


## Show or hide the "MENU" word: this player's overlay is open. The staff rows hide meanwhile.
func set_menu_open(open: bool) -> void:
	if open != _menu_open:
		_menu_open = open
		_refresh_status()
		_refresh_rows()


## Say that this seat is played on another machine (`on`), with a small word at the panel's top;
## a seat played here says nothing (online lobby L5c). Told by `panels.gd`; nothing changes for
## what it shows already.
func set_online(on: bool) -> void:
	if _seat_row.visible != on:
		_seat.text = ONLINE_TEXT
		_seat_row.visible = on


## The seat joined while the run could not be joined (`held`), or no more: "WAIT" in the health
## number's place and the line that says why (the owner, 2026-11-19).
func set_join_held(held: bool) -> void:
	_join_held = held
	_held_note.visible = held
	_refresh_status()


## True while the panel says its seat waits to join (for tests).
func is_join_held() -> bool:
	return _join_held


## Show the seat's coins and how many rewards wait to be picked (the unspent icon, DESIGN rule 4):
## one line under the bars, "12 coins  1 to pick", hidden while both are 0. Text changes only when
## a number did.
func set_purse(coins: int, unspent: int) -> void:
	if coins == _coins and unspent == _unspent:
		return
	_coins = coins
	_unspent = unspent
	var words := PackedStringArray()
	if coins != 0:
		words.append(COINS_TEXT % coins)
	if unspent > 0:
		words.append(UNSPENT_TEXT % unspent)
	_purse.text = "  ".join(words)
	_purse.visible = not words.is_empty()


## Show the keys the seat's shown body holds before the coins (`key_count.gd`: played in by whole
## pixels; `at_once`: drawn as it stands).
func set_keys(count: int, at_once: bool) -> void:
	_keys.set_count(count, at_once)


## Show the reward rerolls the seat's shown body holds, after its keys (played in by whole pixels as
## the keys are; `at_once`: drawn as they stand).
func set_rerolls(reward: int, at_once: bool) -> void:
	_reward_rerolls.set_count(reward, at_once)


## The reward reroll count it shows (its widget, for tests).
func reward_reroll_count() -> KeyCountScript:
	return _reward_rerolls


## A count of one currency on the purse row, after those before it.
func _count_of(named: String, picture: PackedStringArray, shades: StringName) -> KeyCountScript:
	var made: KeyCountScript = KeyCountScript.new()
	made.name = named
	made.picture = picture
	made.material_name = shades
	made.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_purse_row.add_child(made)
	return made


## The key count it shows (its widget, for tests).
func key_count() -> KeyCountScript:
	return _keys


## The purse line's words ("" while it hides).
func purse_text() -> String:
	return _purse.text if _purse.visible else ""


## The seat's word shown ("" for a seat played here).
func seat_text() -> String:
	return _seat.text if _seat_row.visible else ""


## Show quick-use slot `slot` (a d-pad arm: 0 up, 1 right, 2 down, 3 left) bound to `icon` (null:
## nothing) with `count` of it held (0: greyed, the binding kept); `at_once` draws it as it stands.
func set_quick(slot: int, icon: Texture2D, count: int, at_once: bool = false) -> void:
	_quick.set_slot(slot, icon, count, at_once)


## The quick-use cross (for tests and screenshots).
func quick_cross() -> QuickCrossScript:
	return _quick


## Show staff `staff` (0-3) as the plan of `staff_changed` says (`Spells.staff_view`), with
## `icons` the icon of each card by slot. A staff with no card hides its row.
func set_staff_plan(staff: int, plan: Dictionary, icons: Array[Texture2D]) -> void:
	if staff < 0 or staff >= STAFF_COUNT:
		return
	var has_cards: bool = false
	for id: Variant in plan.get("cards", []):
		if StringName(id) != &"":
			has_cards = true
			break
	_has_cards[staff] = has_cards
	_rows[staff].set_plan(plan, icons)
	_refresh_rows()


## The staff's next cast and the seconds of its delay left (`Spells.cast_index`,
## `Spells.cooldown_left`), whether it winds up (`is_winding`) and the cast a press would fire
## with its mana (`firing_cast`; `StaffRow.set_timing`). Called every frame for a shown row;
## allocates nothing.
func set_staff_timing(staff: int, cursor: int, left: float, winding: bool = false, firing: int = StaffRowScript.FIRING_UNKNOWN) -> void:
	if staff >= 0 and staff < STAFF_COUNT and _rows[staff].visible:
		_rows[staff].set_timing(cursor, left, winding, firing)
	if staff == STAFF_COUNT - 1:
		# Once a frame: a glyph that changed width (another device) lines the rows up again.
		var widest: float = 0.0
		for row in _rows:
			widest = maxf(widest, row.glyph_room())
		if not is_equal_approx(widest, _rows[0].cards_left):
			_align_rows()


## A press of staff `staff` found no cast its mana pays: its row flashes (`StaffRow.fizzle`).
func staff_fizzled(staff: int) -> void:
	if staff >= 0 and staff < STAFF_COUNT and _rows[staff].visible:
		_rows[staff].fizzle()


## How every row shows its staff's delay: on the button glyph (the default) or on the next cast
## (`StaffRowScript.Style`; the pause menu's Settings page switches it, owner 2026-10-27).
func set_reload_style(style: StaffRowScript.Style) -> void:
	for row in _rows:
		row.style = style


## The row of staff `staff`, or null for a bad index (for tests and screenshots).
func staff_row(staff: int) -> StaffRowScript:
	return _rows[staff] if staff >= 0 and staff < STAFF_COUNT else null


## How many staff rows show.
func shown_rows() -> int:
	var shown: int = 0
	for row in _rows:
		if row.visible:
			shown += 1
	return shown


## Forget every staff: no rows until the next `staff_changed` (a player who left, a run that
## ended).
func clear_staffs() -> void:
	var none: Array[Texture2D] = []
	for staff in STAFF_COUNT:
		_has_cards[staff] = false
		_rows[staff].set_plan({}, none)
	_refresh_rows()


## Back to the empty state (no numbers, not down, no menu word, no mana lines), for a player who
## left or a run that ended. The next `player_stats_changed` fills it again. The staffs stay until
## `clear_staffs`, since a wizard announces them once, when it appears.
func reset() -> void:
	_health = -1
	_downed = false
	_menu_open = false
	_health_line.reset()
	_health_value.text = ""
	for row in _rows:
		row.set_mana(INF, 0.0)
	_refresh_status()
	_refresh_rows()


## The next numbers are another body's (items I8: the seat shows the body it drives): the health
## shown stays until they come, but is no longer what a drop in health is measured from.
func forget_health() -> void:
	_health = -1


## The health shown, or -1 before any numbers arrived.
func health() -> float:
	return _health


func is_downed() -> bool:
	return _downed


## The word in the number's place; empty when nothing special.
func status_text() -> String:
	return _status.text


## Start every row's cards at the same x: past the widest button glyph of the four (a key name
## like "Space" is wider than a shoulder glyph), so the casts read as columns.
func _align_rows() -> void:
	var widest: float = 0.0
	for row in _rows:
		widest = maxf(widest, row.glyph_room())
	for row in _rows:
		row.cards_left = widest


func _refresh_rows() -> void:
	for staff in STAFF_COUNT:
		_rows[staff].visible = _has_cards[staff] and not _menu_open
	_staffs.visible = not _menu_open and _has_cards.has(true)
	# The cross always shows, an empty one too; while a menu is open the whole row hides with the
	# staff rows.
	_lower.visible = not _menu_open


func _refresh_status() -> void:
	if _join_held:
		_status.text = WAIT_TEXT
	elif _downed:
		_status.text = DOWN_TEXT
	elif _menu_open:
		_status.text = MENU_TEXT
	else:
		_status.text = ""
	# The word takes the number's place in the same cell, so the line never changes length.
	_status.visible = _status.text != ""
	_health_value.visible = not _status.visible
