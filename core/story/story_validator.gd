class_name StoryValidator
extends RefCounted
## The validator for the game's words (M2 part 23). It holds no state and reads nothing from
## disk: hand it what to check and it returns the problems, so a test, the registry in a debug
## build and a contributor's agent get the same answer.
##
## A problem is a Dictionary with `rule`, `file`, `field` and `fix`, like `SpellValidator`.
## `format()` turns one into a line.
##
## A card's description (`SpellComponent.description`, in the card's own `.tres`) is one line of
## at most `MAX_LORE_CHARS` characters. A card with none is reported as `missing-lore`, which only
## warns (docs/DECISIONS.md: a card PR is not blocked by its words).

const MAX_LORE_CHARS: int = 60
## The speech limit of docs/STORY.md. No dialogue file exists yet; its validator comes with them.
const MAX_SPEECH_CHARS: int = 60


## The problem with one line of text shown to players (`file`, `field` say where it is), or none.
static func check_line(file: String, field: String, line: String) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	if line.strip_edges().is_empty():
		problems.append(_problem("empty-text", file, field, "Write one sentence."))
	elif line.length() > MAX_LORE_CHARS:
		problems.append(_problem("text-too-long", file, field, "Cut it from %d to at most %d characters." % [line.length(), MAX_LORE_CHARS]))
	elif line != line.strip_edges() or line.contains("\n"):
		problems.append(_problem("text-not-a-line", file, field, "Keep it one line, with no spaces or breaks at either end."))
	return problems


## Problems in the descriptions of these cards: one with none (`missing-lore`, a warning), and a
## description that is not one short line.
static func check_descriptions(cards: Array[SpellComponent]) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	for card: SpellComponent in cards:
		if card.description.is_empty():
			problems.append(_problem("missing-lore", card.resource_path, "description", "Add a description for the component `%s`: one line, at most %d characters." % [card.id, MAX_LORE_CHARS]))
		else:
			problems.append_array(check_line(card.resource_path, "description", card.description))
	return problems


static func format(problem: Dictionary) -> String:
	return "%s: %s: %s: %s" % [problem["rule"], problem["file"], problem["field"], problem["fix"]]


static func _problem(rule: String, file: String, field: String, fix: String) -> Dictionary:
	return {"rule": rule, "file": file, "field": field, "fix": fix}
