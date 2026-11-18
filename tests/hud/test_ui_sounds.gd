extends "res://tests/support/suite.gd"
## Tests for the menus' sounds (sound plan AU8, docs/milestones/sound.md; `hud/widgets/ui_sounds.gd`):
## the HUD opens its menus and the `ui_sound_requested` it sends are counted. One press is one
## sound: a move of the focus is `ui_move`, a row chosen `ui_choose`, `back` `ui_back`; opening a
## menu and the focus a menu moves in answer to a choice or a back say nothing more. Every id the
## HUD sends has its baked sound, a UI sound, and no HUD script plays a sound itself.
## The builder's and the inventory's sounds are tested beside their other behaviour
## (test_radial_builder.gd, test_inventory_menu.gd).

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload.
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const HudScript := preload("res://hud/panels/panels.gd")
const PauseMenuScript := preload("res://hud/menus/pause/pause_menu.gd")
const SAVE_PATH: String = "user://test_ui_sounds_save.cfg"

var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
## Every sound the HUD asked for, in order.
var _sounds: Array[StringName] = []


func before_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_sounds.clear()
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_bus.ui_sound_requested.connect(func(id: StringName) -> void: _sounds.append(id))
	_input.add_virtual_device(0)
	_hud = own((load(HUD_SCENE_PATH) as PackedScene).instantiate()) as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.save = SaveFile.new(SAVE_PATH)
	root.add_child(_hud)
	_bus.player_joined.emit(0)
	_bus.room_entered.emit(&"test_room", 0)


func after_each() -> void:
	if _hud != null and is_instance_valid(_hud) and _hud.is_inside_tree():
		_hud.get_parent().remove_child(_hud)
	paused = false
	DirAccess.remove_absolute(SAVE_PATH)


## `action` tapped by player 0, then a frame (the frame's marks cleared after it, as `_process` does).
func _do(action: StringName) -> void:
	_input.send_virtual(0, action, 1.0)
	_input.send_virtual(0, action, 0.0)
	_hud.poll()
	_focus.poll()
	_hud.get_ui_sounds().end_frame()


## What was asked since the last call, and forget it.
func _heard() -> Array[StringName]:
	var out: Array[StringName] = _sounds.duplicate()
	_sounds.clear()
	return out


func _menu() -> PauseMenuScript:
	return _hud.get_pause_menu()


func test_the_pause_menu_sounds_one_press_at_a_time() -> void:
	_do(&"pause")
	check(_menu().is_open(), "Start opened the pause menu")
	check_equal(_heard(), [] as Array[StringName], "opening says nothing (its first row's focus is no move)")
	_do(&"move_down")
	check_equal(_heard(), [UiSounds.MOVE], "down: a move")
	_do(&"move_up")
	check_equal(_heard(), [UiSounds.MOVE], "up: a move")
	_focus.focus(0, _menu().button("Settings"))
	_heard()
	_do(&"accept")
	check(_menu().page == PauseMenuScript.Page.SETTINGS, "on Settings")
	check_equal(_heard(), [UiSounds.CHOOSE], "Settings chosen: one choice, its first row's focus no move")
	_do(&"page_next")
	check_equal(_heard(), [UiSounds.MOVE], "RB: the next tab, one move")
	_do(&"back")
	check(_menu().page == PauseMenuScript.Page.MAIN, "back on the main page")
	check_equal(_heard(), [UiSounds.BACK], "back: one back, its Settings row's focus no move")
	_do(&"back")
	check(not _menu().is_open(), "back on the main page closed it")
	check_equal(_heard(), [UiSounds.BACK], "and was a back")


func test_a_slider_step_is_a_move_and_accept_a_choice() -> void:
	_do(&"pause")
	_focus.focus(0, _menu().button("Settings"))
	_do(&"accept")
	_do(&"page_next")
	_do(&"page_next")
	check_equal(PauseMenuScript.TAB_NAMES[_menu().tab], "Audio", "on Audio")
	_heard()
	_do(&"move_left")
	check_equal(_menu().volume(PauseMenuScript.Volume.MUSIC), 90, "left stepped the music down")
	check_equal(_heard(), [UiSounds.MOVE], "a slider's step is a move")
	_do(&"accept")
	check_equal(_heard(), [UiSounds.CHOOSE], "accept on a slider is a choice")


func test_a_slider_at_its_end_says_nothing() -> void:
	_do(&"pause")
	_focus.focus(0, _menu().button("Settings"))
	_do(&"accept")
	_do(&"page_next")
	_do(&"page_next")
	_heard()
	_do(&"move_right")
	check_equal(_menu().volume(PauseMenuScript.Volume.MUSIC), 100, "the music stays at the top")
	check_equal(_heard(), [] as Array[StringName], "nothing moved, so nothing is heard")


func test_the_map_pages_back_row_is_a_back() -> void:
	var links: Array[PackedInt32Array] = [PackedInt32Array([1]), PackedInt32Array()]
	_bus.run_map_changed.emit(PackedInt32Array([0, 1]), [&"fight", &"boss"] as Array[StringName], links, 0)
	_do(&"pause")
	_focus.focus(0, _menu().button("Map"))
	_do(&"accept")
	check(_menu().page == PauseMenuScript.Page.MAP, "on the Map page")
	_heard()
	_focus.focus(0, _menu().button("MapBack"))
	_heard()
	_do(&"accept")
	check(_menu().page == PauseMenuScript.Page.MAIN, "Back went to the main page")
	check_equal(_heard(), [UiSounds.BACK], "a back, not a choice")


func test_rb_on_the_main_page_says_nothing() -> void:
	_do(&"pause")
	_heard()
	_do(&"page_next")
	check_equal(_heard(), [] as Array[StringName], "LB and RB page nothing on the main page, so nothing is heard")


func test_a_focus_moved_by_the_menu_alone_in_a_later_frame_is_a_move() -> void:
	_do(&"pause")
	_heard()
	_focus.focus(0, _menu().button("Settings"))
	check_equal(_heard(), [UiSounds.MOVE], "a focus moved after the press's frame is a move")


func test_every_id_has_its_baked_ui_sound() -> void:
	for id: StringName in UiSounds.IDS:
		var path: String = "res://audio/sfx/%s/%s.tres" % [id, id]
		var stream := load(path) as AudioStreamRandomizer
		check(stream != null, "%s: %s is its variants' randomizer" % [id, path])
		if stream == null:
			continue
		check(stream.streams_count >= 2, "%s: the ui family's variants" % id)
		check(FileAccess.file_exists("res://audio/sfx/%s/%s.sound.json" % [id, id]), "%s: its recipe beside it" % id)
		check(FileAccess.file_exists("res://audio/sfx/%s/assets.json" % id), "%s: its manifest beside it" % id)
		var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://audio/sfx/%s/%s.sound.json" % [id, id]))
		check(recipe is Dictionary and recipe.get("kind") == "ui" and recipe.get("family") == "ui", "%s: a ui sound of the ui family" % id)


func test_the_hud_never_plays_a_sound_itself() -> void:
	var found: Array[String] = []
	_scan("res://hud", found)
	check_equal(found, [] as Array[String], "no HUD script makes a player or calls Audio: it sends ui_sound_requested")


## Every `.gd` under `folder` that names a player, the audio server or the Audio service, into `found`.
func _scan(folder: String, found: Array[String]) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_scan(folder.path_join(sub), found)
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var text: String = FileAccess.get_file_as_string(folder.path_join(file))
		for banned: String in ["AudioStreamPlayer", "AudioServer", "/root/Audio", "play_ui(", "play_over("]:
			if text.contains(banned):
				found.append("%s: %s" % [folder.path_join(file), banned])
