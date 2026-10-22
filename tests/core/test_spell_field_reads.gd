extends "res://tests/support/suite.gd"
## No script outside content/spells, core/base and core/spells reads a spell component's or a
## compiled spell's fields (M2 part 11 widened the M1 scan to the component classes). Players,
## bots and the HUD only call `Spells` and answer to its events, so a component can change its
## numbers without touching them.
##
## The scan is a text heuristic: it cannot see a spell reached through an untyped variable, a
## call result (`get_spell().damage`) or `get()`, so reviews still look for those.
##
## godot --headless --path . --script res://tests/core/test_spell_field_reads.gd

## Fields that only a spell has: any receiver counts. (`burst.lifetime` is a CPUParticles2D
## property in gameplay/feel, and is dropped before the scan.)
const UNIQUE_FIELDS: String = "(mana_cost|cooldown|lifetime|display_name|base_damage|damage_scale|orbit_radius|ray_length|shot_mult|damage_mult|speed_mult|radius_mult|cooldown_mult|mana_mult|extra_pierce|behaviour_strength|max_fires|chain_jumps|homing_turn|trigger_interval|trigger_max_fires|trigger_event|shots_requested|shots_clamped|element_name|form_name)"
## Fields with common names (`HitProfile` has some of them, and `gameplay/combat` may read that):
## only a variable named like a spell, or declared as a spell class.
const COMMON_FIELDS: String = "(id|demo|damage|speed|complexity|shots|radius|pierce|tint|motion|spread|icon|event|interval|status_id|status_duration|status_strength|element_id|form_id|trigger_id|behaviour)"
## The classes a variable may be declared as. `HitProfile` is left out on purpose: `gameplay/combat`
## reads it, which is what it is for.
const SPELL_CLASSES: String = "(SpellComponent|FormBase|ElementBase|ModifierBase|TriggerBase|CompiledSpell)"
## Folders that are not game scripts, and the three that may read spell fields.
const SKIPPED_DIRS: PackedStringArray = [".git", ".github", ".godot", "addons", "build", "ci", "docs", "content/spells", "core/base", "core/spells"]


func test_the_scanner_catches_field_reads() -> void:
	var bad: PackedStringArray = [
		"var cost: float = spell.mana_cost",
		"if player_spell.cooldown > 0.0:",
		"x = _spell.damage",
		"label.text = bolt.display_name",
		"var left = something.cooldown",
		"var life := s.lifetime",
		"var scale: float = element.damage_scale",
		"n = spell.complexity",
		"var path: int = recipe_spell.shots",
		"if x.max_fires > 1:",
	]
	for line in bad:
		check(_reads_field(line), "caught: " + line)
	var good: PackedStringArray = [
		"spells.cast(index, slot, global_position, aim, mana)",
		"events.spell_cast.emit(index, form_id, pos, aim)",
		"var speed: float = 3.0",
		"data.id",
		"spells.cast(0, 0, a, b, 1.0)  # reads spell.damage later",
		"@export var cooldown: float = 0.0",
		"if component.kind() != SLOT_KINDS[slot]:",
		"var text: String = compiled.description",
		"if not compiled.valid:",
		"var wait: float = spells.cooldown_left(0, 1)",
	]
	for line in good:
		check(not _reads_field(line), "not flagged: " + line)


func test_the_scanner_catches_fields_of_declared_variables() -> void:
	var names: PackedStringArray = _typed_names("var pick: FormBase = null\nfunc f(other: CompiledSpell, e: ElementBase) -> void:\nvar p: HitProfile")
	check_equal(names, PackedStringArray(["pick", "other", "e"]), "typed names are found")
	check(_reads_field("var d: int = pick.base_damage", names), "caught: a unique field on a declared variable")
	check(_reads_field("var d: int = other.shots", names), "caught: a common field on a variable declared CompiledSpell")
	check(_reads_field("if e.status_id != &\"\":", names), "caught: a status id on an element")
	check(not _reads_field("pick.kind()", names), "not flagged: kind() on a declared variable")
	check(not _reads_field("var d: int = p.damage", names), "not flagged: a HitProfile field")


func test_no_script_reads_spell_fields() -> void:
	var offenders: PackedStringArray = PackedStringArray()
	var checked: int = _scan_dir("res://", offenders)
	# Dozens of scripts remain after the skipped folders; far fewer means the walk broke.
	check(checked > 25, "the scan looked at the scripts (%d)" % checked)
	check(offenders.is_empty(), "scripts read spell fields: " + ", ".join(offenders))


## True when a line reads a spell field: a unique field name on any receiver, or a common one
## on a variable named like a spell or one of `typed_names` (variables the file declares as a
## spell class). Comments and declarations do not count.
func _reads_field(line: String, typed_names: PackedStringArray = PackedStringArray()) -> bool:
	var code: String = line.get_slice("#", 0)
	var named := RegEx.new()
	named.compile("(?i)\\w*spell\\w*\\s*\\.\\s*" + COMMON_FIELDS + "\\b")
	if named.search(code) != null:
		return true
	for typed_name in typed_names:
		var typed := RegEx.new()
		typed.compile("\\b" + typed_name + "\\s*\\.\\s*(" + UNIQUE_FIELDS.trim_prefix("(").trim_suffix(")") + "|" + COMMON_FIELDS.trim_prefix("(").trim_suffix(")") + ")\\b")
		if typed.search(code) != null:
			return true
	var unique := RegEx.new()
	unique.compile("[\\w\\)\\]]\\s*\\.\\s*" + UNIQUE_FIELDS + "\\b")
	return unique.search(code.replace("burst.lifetime", "")) != null


## Names of the variables, parameters and loop variables a script declares as a spell class.
func _typed_names(text: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var declared := RegEx.new()
	declared.compile("(\\w+)\\s*:\\s*" + SPELL_CLASSES + "\\b")
	for found in declared.search_all(text):
		var declared_name: String = found.get_string(1)
		if not names.has(declared_name):
			names.append(declared_name)
	return names


## Scan every .gd below `path` except the skipped folders and the test_*.gd files (tests may
## set fields to build their fixtures). Returns the count scanned.
func _scan_dir(path: String, offenders: PackedStringArray) -> int:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return 0
	var count: int = 0
	for sub in dir.get_directories():
		var sub_path: String = path.path_join(sub)
		if _is_skipped(sub_path):
			continue
		count += _scan_dir(sub_path, offenders)
	for file_name in dir.get_files():
		if file_name.get_extension() != "gd" or file_name.begins_with("test_"):
			continue
		var file_path: String = path.path_join(file_name)
		count += 1
		var number: int = 0
		var text: String = FileAccess.get_file_as_string(file_path)
		var typed_names: PackedStringArray = _typed_names(text)
		for line in text.split("\n"):
			number += 1
			if _reads_field(line, typed_names):
				offenders.append("%s:%d" % [file_path, number])
	return count


func _is_skipped(path: String) -> bool:
	return SKIPPED_DIRS.has(path.trim_prefix("res://"))
