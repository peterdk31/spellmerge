extends Control
## The main menu: the name, the tagline, the build version and the Play button.
## Play only sends the intent event `play_requested`; `gameplay/flow` hears it and
## starts the arena. The menu never calls flow and never changes the scene itself.

const EventsScript := preload("res://core/events/events.gd")

## The player index sent with `play_requested`: the menu is used by P1 (the mouse
## and keyboard, or the gamepad that joined first).
const MENU_PLAYER: int = 0

## The event bus. Only tests set this, before adding the node; otherwise the
## "Events" autoload is used.
var events: EventsScript = null

@onready var _version: Label = %Version
@onready var _play: Button = %Play


func _ready() -> void:
	_version.text = BuildInfo.describe()
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	_play.pressed.connect(_on_play_pressed)
	_play.grab_focus()
	print("Spellmerge %s: main menu ready" % BuildInfo.describe())


func _on_play_pressed() -> void:
	if events == null:
		push_warning("Main menu: the Events autoload is missing, so Play does nothing.")
		return
	events.play_requested.emit(MENU_PLAYER)
