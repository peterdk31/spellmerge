extends Control
## Placeholder main menu for M0: the name, the tagline and the build version.
## The real menu (play, contribute, credits) arrives with the game in M1.

@onready var _version: Label = %Version


func _ready() -> void:
	_version.text = BuildInfo.describe()
	print("Spellmerge %s: main menu ready" % BuildInfo.describe())
