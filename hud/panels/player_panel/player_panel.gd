extends PanelContainer
## One player's corner panel, in the player's border colour: a health bar and a mana bar with
## their numbers, a word over the health bar when the player is down ("DOWN") or has their
## overlay open ("MENU"), and under the mana bar one row per staff that has cards
## (`staff_row.gd`: the staff's button glyph, its cast sequence and its delay). The word means
## the state is never shown by colour alone. There is no "P1" or "Staff 2" line (owner,
## 2026-10-27): the corner and the border say whose panel it is, and the rows say more than the
## staff cast last did.
##
## It only shows what it is told: `set_stats`, `set_menu_open`, `set_staff_plan` and
## `set_staff_timing` are called by `hud/panels/panels.gd`, which hears the events and reads the
## staffs' timing from `Spells`. The panel takes no input and listens to nothing itself, so it is
## the same for any player index 0-3. Colours come from the shared theme (type variations
## PlayerPanel1-4, HealthBar and ManaBar). Updating only changes text when a number changed, and
## a row only redraws when its timing changed, so a frame with no change allocates nothing.
##
## While the player has a menu open the staff rows hide: the builder shows the staffs, and the
## radial builder's column takes the space under the panel.

const StaffRowScript := preload("res://hud/panels/player_panel/staff_row.gd")

const PLAYER_COUNT: int = 4
const STAFF_COUNT: int = 4
const DOWN_TEXT: String = "DOWN"
const MENU_TEXT: String = "MENU"

## The player index 0-3. Set before adding the node to the tree.
@export var index: int = 0

var _health: int = -1
var _mana: int = -1
var _downed: bool = false
var _menu_open: bool = false
var _rows: Array[StaffRowScript] = []
## Per staff: whether its plan has a card (an empty staff shows no row).
var _has_cards: Array[bool] = [false, false, false, false]

@onready var _status: Label = %Status
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_value: Label = %HealthValue
@onready var _mana_bar: ProgressBar = %ManaBar
@onready var _mana_value: Label = %ManaValue
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
	_align_rows()
	_refresh_status()


## Show these numbers. A player with no health left is shown as down.
func set_stats(health: int, max_health: int, mana: float, max_mana: float) -> void:
	var whole_mana: int = floori(mana)
	if health != _health:
		_health = health
		_health_bar.max_value = maxi(max_health, 1)
		_health_bar.value = health
		_health_value.text = str(health)
		var downed: bool = health <= 0
		if downed != _downed:
			_downed = downed
			_refresh_status()
	if whole_mana != _mana:
		_mana = whole_mana
		_mana_bar.max_value = maxf(max_mana, 1.0)
		_mana_bar.value = mana
		_mana_value.text = str(whole_mana)


## Show or hide the "MENU" word: this player's overlay is open. The staff rows hide meanwhile.
func set_menu_open(open: bool) -> void:
	if open != _menu_open:
		_menu_open = open
		_refresh_status()
		_refresh_rows()


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
## `Spells.cooldown_left`). Called every frame for a shown row; allocates nothing.
func set_staff_timing(staff: int, cursor: int, left: float) -> void:
	if staff >= 0 and staff < STAFF_COUNT and _rows[staff].visible:
		_rows[staff].set_timing(cursor, left)
	if staff == STAFF_COUNT - 1:
		# Once a frame: a glyph that changed width (another device) lines the rows up again.
		var widest: float = 0.0
		for row in _rows:
			widest = maxf(widest, row.glyph_room())
		if not is_equal_approx(widest, _rows[0].cards_left):
			_align_rows()


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


## Back to the empty state (no numbers, not down, no menu word), for a player who left or a run
## that ended. The next `player_stats_changed` fills it again. The staffs stay until
## `clear_staffs`, since a wizard announces them once, when it appears.
func reset() -> void:
	_health = -1
	_mana = -1
	_downed = false
	_menu_open = false
	_health_bar.value = 0
	_mana_bar.value = 0
	_health_value.text = ""
	_mana_value.text = ""
	_refresh_status()
	_refresh_rows()


## The health shown, or -1 before any numbers arrived.
func health() -> int:
	return _health


func is_downed() -> bool:
	return _downed


## The word over the health bar; empty when nothing special.
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


func _refresh_status() -> void:
	if _downed:
		_status.text = DOWN_TEXT
	elif _menu_open:
		_status.text = MENU_TEXT
	else:
		_status.text = ""
