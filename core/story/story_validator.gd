class_name StoryValidator
extends RefCounted
## The validator for story files (M2 part 23). It holds no state and reads nothing from
## disk: hand it the parsed JSON of each file and it returns the problems, so a test, the
## registry in a debug build and a contributor's agent get the same answer.
##
## A problem is a Dictionary with `rule`, `file`, `field` and `fix`, like `SpellValidator`.
## `format()` turns one into a line.
##
## Lore about a component (`content/story/lore/components/<id>.json`) has exactly the keys
## `id` (equal to the file name), `about` (`"component"`) and `text` (one non-empty line of
## at most `MAX_LORE_CHARS` characters). `check_component_lore()` also wants a file for every
## spell component id it is given.

const MAX_LORE_CHARS: int = 60
## The speech limit of docs/STORY.md. No dialogue file exists yet; its validator comes with them.
const MAX_SPEECH_CHARS: int = 60
const ABOUT_COMPONENT: String = "component"
const LORE_KEYS: PackedStringArray = ["id", "about", "text"]


## Problems in one lore file. `data` is what `JSON.parse_string` gave (null when it did not parse).
static func check_lore(file: String, data: Variant) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	if not (data is Dictionary):
		problems.append(_problem("not-an-object", file, "(file)", "Make the file one JSON object with the keys id, about and text."))
		return problems
	var entry: Dictionary = data
	for key: Variant in entry:
		if not LORE_KEYS.has(str(key)):
			problems.append(_problem("unknown-key", file, str(key), "Remove it. The keys are id, about and text."))
	for key: String in LORE_KEYS:
		if not entry.has(key):
			problems.append(_problem("missing-field", file, key, "Add `%s`." % key))
		elif not (entry[key] is String):
			problems.append(_problem("wrong-type", file, key, "Make `%s` a string." % key))
	var id: Variant = entry.get("id")
	if id is String and id != file.get_file().get_basename():
		problems.append(_problem("id-not-file", file, "id", "Set `id` to `%s`, the file name." % file.get_file().get_basename()))
	var about: Variant = entry.get("about")
	if about is String and about != ABOUT_COMPONENT:
		problems.append(_problem("unknown-about", file, "about", "Use \"%s\"." % ABOUT_COMPONENT))
	var text: Variant = entry.get("text")
	if text is String:
		var line: String = text
		if line.strip_edges().is_empty():
			problems.append(_problem("empty-text", file, "text", "Write one sentence."))
		elif line.length() > MAX_LORE_CHARS:
			problems.append(_problem("text-too-long", file, "text", "Cut it from %d to at most %d characters." % [line.length(), MAX_LORE_CHARS]))
		elif line != line.strip_edges() or line.contains("\n"):
			problems.append(_problem("text-not-a-line", file, "text", "Keep it one line, with no spaces or breaks at either end."))
	return problems


## Problems across all component lore files (`entries`: file path -> parsed data): each file
## by itself, no id twice, and a file for every id in `component_ids`.
static func check_component_lore(entries: Dictionary, component_ids: Array[StringName]) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	var seen: Dictionary = {}
	var files: Array = entries.keys()
	files.sort()
	for file: String in files:
		problems.append_array(check_lore(file, entries[file]))
		var data: Variant = entries[file]
		if data is Dictionary and (data as Dictionary).get("id") is String:
			var id: String = (data as Dictionary)["id"]
			if seen.has(id):
				problems.append(_problem("duplicate-id", file, "id", "`%s` is also in %s. Keep one." % [id, seen[id]]))
			else:
				seen[id] = file
	for id: StringName in component_ids:
		if not seen.has(String(id)):
			problems.append(_problem("missing-lore", "content/story/lore/components/%s.json" % id, "(file)", "Add a description for the component `%s`." % id))
	return problems


static func format(problem: Dictionary) -> String:
	return "%s: %s: %s: %s" % [problem["rule"], problem["file"], problem["field"], problem["fix"]]


static func _problem(rule: String, file: String, field: String, fix: String) -> Dictionary:
	return {"rule": rule, "file": file, "field": field, "fix": fix}
