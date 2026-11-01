extends "res://tests/support/suite.gd"
## The AI knows a card only by what it does (owner, 2026-11-01; docs/milestones/M2-enemy-ai.md):
## no script of the AI's decisions or of the test bot names a card or a carrier, so no code like
## "if the next cast is a dash, dash" can creep in. It reads `CastSense` instead.
##
## godot --headless --path . --script res://tests/core/test_ai_names_no_card.gd

const RegistryScript := preload("res://core/registry/registry.gd")

## The AI's own scripts: every script under the AI's folder, and the test bot's. `entities.gd`
## keeps the decoys and familiars the cards make (their kinds are its data, not a decision) and is
## left out; the bots' other scripts are tests that build staffs on purpose.
const FOLDERS: Array[String] = ["res://gameplay/ai"]
const FILES: Array[String] = ["res://tests/bots/bot.gd"]
const LEFT_OUT: Array[String] = ["res://gameplay/ai/entities.gd"]


func test_no_ai_script_names_a_card_or_a_carrier() -> void:
	var registry := RegistryScript.new()
	registry.call("scan")
	var names: Dictionary = {}
	for card: Variant in registry.call("get_all", "spells"):
		if card is SpellComponent:
			names[String((card as SpellComponent).id)] = true
	for id: StringName in Carriers.ids():
		names[String(id)] = true
	registry.free()
	check(names.size() > 20, "the cards and carriers are found: %d" % names.size())
	var literal := RegEx.create_from_string("&?\"([a-z_]+)\"")
	var scripts: Array[String] = []
	for folder: String in FOLDERS:
		_collect(folder, scripts)
	scripts.append_array(FILES)
	check(scripts.size() > 3, "the AI's scripts are found: %d" % scripts.size())
	for path: String in scripts:
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for at in lines.size():
			var line: String = lines[at]
			var comment: int = line.find("#")
			if comment >= 0:
				line = line.substr(0, comment)
			for found: RegExMatch in literal.search_all(line):
				var word: String = found.get_string(1)
				check(not names.has(word), "%s:%d names the card or carrier \"%s\": read CastSense instead" % [path, at + 1, word])


func _collect(folder: String, out: Array[String]) -> void:
	for file_name: String in DirAccess.get_files_at(folder):
		var path: String = folder.path_join(file_name)
		if file_name.ends_with(".gd") and not LEFT_OUT.has(path):
			out.append(path)
	for sub: String in DirAccess.get_directories_at(folder):
		_collect(folder.path_join(sub), out)
