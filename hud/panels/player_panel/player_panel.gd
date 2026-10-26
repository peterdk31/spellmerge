extends PanelContainer
## One player's corner panel: "P<n>" in the player's colour, a health bar and a
## mana bar with their numbers, and a word when the player is down ("DOWN") or has
## their overlay open ("MENU"). The word means the state is never shown by colour
## alone.
##
## It only shows what it is told: `set_stats` and `set_menu_open` are called by
## `hud/panels/panels.gd`, which hears the events. The panel takes no input and
## listens to nothing itself, so it is the same for any player index 0-3. Colours
## come from the shared theme (type variations PlayerPanel1-4, PlayerLabel1-4,
## HealthBar and ManaBar); nothing is styled by hand here. Updating only changes
## text when a number changed, so a frame with no change allocates nothing.

const PLAYER_COUNT: int = 4
const DOWN_TEXT: String = "DOWN"
const MENU_TEXT: String = "MENU"
## The four staffs by index, named by their buttons (staffs A6a).
const STAFF_NAMES: Array[String] = ["1", "2", "3", "4"]
## No staff cast yet.
const NO_STAFF: int = -1

## The player index 0-3. Set before adding the node to the tree.
@export var index: int = 0

var _health: int = -1
var _mana: int = -1
var _downed: bool = false
var _menu_open: bool = false
var _active_staff: int = NO_STAFF

@onready var _name: Label = %Name
@onready var _spell: Label = %Spell
@onready var _status: Label = %Status
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_value: Label = %HealthValue
@onready var _mana_bar: ProgressBar = %ManaBar
@onready var _mana_value: Label = %ManaValue


func _ready() -> void:
	var player: int = clampi(index, 0, PLAYER_COUNT - 1)
	theme_type_variation = StringName("PlayerPanel%d" % (player + 1))
	_name.theme_type_variation = StringName("PlayerLabel%d" % (player + 1))
	_name.text = "P%d" % (player + 1)
	_refresh_spell()
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


## Show or hide the "MENU" word: this player's overlay is open.
func set_menu_open(open: bool) -> void:
	if open != _menu_open:
		_menu_open = open
		_refresh_status()


## Show which staff the player cast last, by its number: 1 is "Staff 2".
func set_active_staff(staff: int) -> void:
	if staff != _active_staff and staff >= 0 and staff < STAFF_NAMES.size():
		_active_staff = staff
		_refresh_spell()


## The staff shown (0 A to 3 B), `NO_STAFF` before the first cast.
func active_staff() -> int:
	return _active_staff


## The staff word in the header, for example "Staff 2" (empty before the first cast).
func spell_text() -> String:
	return _spell.text


## Back to the empty state (no numbers, not down, no menu word, no staff), for a player who
## left or a run that ended. The next `player_stats_changed` fills it again.
func reset() -> void:
	_active_staff = NO_STAFF
	_refresh_spell()
	_health = -1
	_mana = -1
	_downed = false
	_menu_open = false
	_health_bar.value = 0
	_mana_bar.value = 0
	_health_value.text = ""
	_mana_value.text = ""
	_refresh_status()


## The health shown, or -1 before any numbers arrived.
func health() -> int:
	return _health


func is_downed() -> bool:
	return _downed


## The word in the corner of the panel; empty when nothing special.
func status_text() -> String:
	return _status.text


func _refresh_spell() -> void:
	_spell.text = "" if _active_staff == NO_STAFF else " Staff %s" % STAFF_NAMES[_active_staff]


func _refresh_status() -> void:
	if _downed:
		_status.text = DOWN_TEXT
	elif _menu_open:
		_status.text = MENU_TEXT
	else:
		_status.text = ""
