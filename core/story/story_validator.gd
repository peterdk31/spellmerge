class_name StoryValidator
extends RefCounted
## The validator for the game's words (M2 part 23). It holds no state and reads nothing from
## disk: hand it what to check and it returns the problems, so a test, the registry in a debug
## build and a contributor's agent get the same answer.
##
## A problem is a Dictionary with `rule`, `file`, `field` and `fix`, like `SpellValidator`.
## `format()` turns one into a line.
##
## A line players read (`check_line`) is one line of at most `MAX_LORE_CHARS` characters. The
## cards' descriptions are checked with it by `SpellValidator.check_descriptions` (only
## `core/spells` reads a card's fields), and the enemies' lore by `check_lore`. What a boss says
## in its intro (`BossIntro.lines`, docs/milestones/boss-intro.md) is speech (`check_speech`): one
## line each of at most `MAX_SPEECH_CHARS`, at most `BossIntro.MAX_LINES` of them.

const MAX_LORE_CHARS: int = 60
## The speech limit of docs/STORY.md: a line a boss says in its intro (`check_speech`).
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


## The problem with an enemy's line of lore (`EnemyBase.lore`, in the file `file`), or none: a boss
## with none (`missing-lore`, which only warns, as a card's missing description), or a line that is not
## a short line (`check_line`). A stray needs none.
static func check_lore(file: String, lore: String, boss: bool) -> Array[Dictionary]:
	if lore.is_empty():
		if not boss:
			return [] as Array[Dictionary]
		return [_problem("missing-lore", file, "lore", "Give the boss its line of lore: why it fights, one line of at most %d characters." % MAX_LORE_CHARS)] as Array[Dictionary]
	return check_line(file, "lore", lore)


## The problems with what a boss says in its intro (`BossIntro.lines`, in the file `file`), or none:
## more than `BossIntro.MAX_LINES` lines (`too-many-lines`), or a line that is empty, longer than
## `MAX_SPEECH_CHARS` or not one line (each named by its number, `lines[0]`).
static func check_speech(file: String, lines: Array[String]) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	if lines.size() > BossIntro.MAX_LINES:
		problems.append(_problem("too-many-lines", file, "boss_intro.lines", "Keep at most %d lines; it has %d." % [BossIntro.MAX_LINES, lines.size()]))
	for at in lines.size():
		var line: String = lines[at]
		var field: String = "boss_intro.lines[%d]" % at
		if line.strip_edges().is_empty():
			problems.append(_problem("empty-text", file, field, "Write what the boss says, or take the line out."))
		elif line.length() > MAX_SPEECH_CHARS:
			problems.append(_problem("speech-too-long", file, field, "Cut it from %d to at most %d characters." % [line.length(), MAX_SPEECH_CHARS]))
		elif line != line.strip_edges() or line.contains("\n"):
			problems.append(_problem("text-not-a-line", file, field, "Keep it one line, with no spaces or breaks at either end."))
	return problems


static func format(problem: Dictionary) -> String:
	return "%s: %s: %s: %s" % [problem["rule"], problem["file"], problem["field"], problem["fix"]]


static func _problem(rule: String, file: String, field: String, fix: String) -> Dictionary:
	return {"rule": rule, "file": file, "field": field, "fix": fix}
