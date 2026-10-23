extends Control
## The first screen: the game's name and the build version. The harness's web smoke test waits
## for the ready line this prints ("ready" in tests/exported_runs.json); keep it when this is replaced.


@onready var _version: Label = %Version


func _ready() -> void:
	_version.text = BuildInfo.describe()
	print("{{GAME}} %s: main menu ready" % BuildInfo.describe())
