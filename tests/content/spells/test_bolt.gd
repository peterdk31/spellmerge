extends SceneTree
## Tests for the fire bolt (content/spells/forms/bolt): it loads on SpellBase, fires through
## core/projectiles, hits and kills the ember imp through Combat, works for players 0-3, and
## no script outside content/spells and core/base reads a spell field.
##
## godot --headless --path . --script res://tests/content/spells/test_bolt.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const BoltResource := preload("res://content/spells/forms/bolt/bolt.tres")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

const STEP: float = 0.0625
## Spell fields no script outside the allowed folders may read.
const FIELD_PATTERN: String = "(id|demo|display_name|mana_cost|cooldown|damage|speed|lifetime)"
## Folders that are not game scripts, and the two that may read spell fields.
const SKIPPED_DIRS: PackedStringArray = [".git", ".github", ".godot", "addons", "ci", "docs", "content/spells", "core/base"]

var _failures: Array[String] = []
var _bus: Node
var _projectiles: Node
var _combat: Node
var _registry: Node
var _nodes: Array[Node] = []
var _deaths: Array = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_resource_is_a_spell()
	_test_cast_spawns_one_shot_with_mana_and_cooldown()
	_test_bolt_kills_the_imp()
	_test_four_players_each_land_hits()
	_test_missing_manager_refuses_the_cast()
	_test_combat_learns_the_profile_from_the_event()
	_test_shared_resource_cooldowns_reset()
	_test_zero_direction_fires_right()
	_test_player_casts_the_bolt()
	_test_registry_finds_the_bolt()
	_test_scanner_catches_field_reads()
	_test_no_script_reads_spell_fields()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: content/spells/forms/bolt (fire bolt, hits, no field reads)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup() -> void:
	_teardown()
	_bus = EventsScript.new()
	_projectiles = ProjectileManagerScript.new()
	_projectiles.events = _bus
	_registry = RegistryScript.new()
	_registry.scan()
	_combat = CombatScript.new()
	_combat.events = _bus
	_combat.projectiles = _projectiles
	_combat.registry = _registry
	_combat._ready()
	_bus.enemy_died.connect(_on_enemy_died)


func _teardown() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	for node: Node in [_combat, _projectiles, _bus, _registry]:
		if node != null:
			node.free()
	_registry = null
	_combat = null
	_projectiles = null
	_bus = null
	_deaths.clear()


func _on_enemy_died(player: int, enemy: Node) -> void:
	_deaths.append([player, enemy])


## A fresh bolt (own cooldowns) wired to this test's manager and Combat.
func _bolt() -> SpellBase:
	var bolt: SpellBase = BoltResource.duplicate() as SpellBase
	bolt.set("projectiles", _projectiles)
	return bolt


## Cast like a wizard does: cast(), then send `spell_cast` when it fired. That event is
## how Combat learns what the bolt's hits do.
func _cast(spell: SpellBase, player: int, origin: Vector2, direction: Vector2) -> float:
	var spent: float = spell.cast(player, origin, direction, 100.0)
	if spent != SpellBase.REFUSED:
		_bus.spell_cast.emit(player, spell.spell_id(), origin, direction)
	return spent


func _enemy(health: int, at: Vector2) -> Node2D:
	var enemy := Node2D.new()
	enemy.position = at
	_nodes.append(enemy)
	_combat.register_enemy(enemy, health, 10.0)
	return enemy


func _run(count: int) -> void:
	for i in count:
		_projectiles.step(STEP)
		_combat.step(STEP)


# --- Tests ------------------------------------------------------------------

func _test_resource_is_a_spell() -> void:
	var spell: SpellBase = BoltResource as SpellBase
	_check(spell != null, "bolt.tres loads as a SpellBase")
	_check(spell.spell_id() == &"bolt", "the id is bolt")
	_check(spell.demo and spell.mana_cost > 0.0 and spell.cooldown > 0.0, "demo, with a cost and a cooldown")
	_check(spell.damage > 0 and spell.speed > 0.0 and spell.lifetime > 0.0, "damage, speed and lifetime are set")
	_check(ceili(float(ImpData.max_health) / float(spell.damage)) <= 8, "an imp dies in a handful of bolts")


func _test_cast_spawns_one_shot_with_mana_and_cooldown() -> void:
	_setup()
	var bolt: SpellBase = _bolt()
	var spent: float = bolt.cast(1, Vector2.ZERO, Vector2.RIGHT, 100.0)
	_check(spent == bolt.mana_cost, "cast returns the mana cost")
	_check(_projectiles.get_count() == 1 and _projectiles.get_count_for(1) == 1, "one shot, owned by player 1")
	_check(bolt.cast(1, Vector2.ZERO, Vector2.RIGHT, 100.0) == SpellBase.REFUSED, "the cooldown refuses a second cast")
	_check(_projectiles.get_count() == 1, "a refused cast spawns nothing")
	_check(bolt.cast(1, Vector2.ZERO, Vector2.RIGHT, 1.0) == SpellBase.REFUSED, "too little mana is refused")
	bolt.tick(1, 10.0)
	_check(bolt.cast(1, Vector2.ZERO, Vector2.RIGHT, 100.0) == bolt.mana_cost, "after the cooldown it fires again")
	_check(_projectiles.get_count() == 2, "two shots now")


func _test_bolt_kills_the_imp() -> void:
	_setup()
	var bolt: SpellBase = _bolt()
	var imp := _enemy(ImpData.max_health, Vector2(80.0, 0.0))
	var needed: int = ceili(float(ImpData.max_health) / float(bolt.damage))
	# Exactly `needed` casts, each landing before the next is fired: no timing involved.
	for shot in needed:
		_check(_combat.is_enemy(imp), "the imp is alive before bolt %d lands" % (shot + 1))
		bolt.tick(0, 10.0)
		_check(_cast(bolt, 0, Vector2.ZERO, Vector2.RIGHT) == bolt.mana_cost, "bolt %d is fired" % (shot + 1))
		_run(24)
	_check(not _combat.is_enemy(imp), "%d bolts kill the imp" % needed)
	_check(_deaths.size() == 1 and _deaths[0][0] == 0 and _deaths[0][1] == imp, "enemy_died names player 0 and the imp")


func _test_four_players_each_land_hits() -> void:
	_setup()
	var damage: Array = []
	_bus.damage_dealt.connect(func(player: int, _target: Node, amount: int) -> void: damage.append([player, amount]))
	for index in 4:
		var bolt: SpellBase = _bolt()
		var imp := _enemy(100, Vector2(80.0, 40.0 * index))
		_cast(bolt, index, Vector2(0.0, 40.0 * index), Vector2.RIGHT)
		_check(imp != null, "enemy %d exists" % index)
	_run(24)
	_check(damage.size() == 4, "four hits, one per player")
	for index in 4:
		_check(damage.any(func(entry: Array) -> bool: return entry[0] == index), "player %d is credited" % index)


func _test_missing_manager_refuses_the_cast() -> void:
	var bolt: SpellBase = BoltResource.duplicate() as SpellBase
	# No Projectiles autoload in this test's tree, so nothing can be fired.
	_check(bolt.cast(0, Vector2.ZERO, Vector2.RIGHT, 100.0) == SpellBase.REFUSED, "no manager: the cast is refused, no mana")
	_setup()
	bolt.set("projectiles", _projectiles)
	_check(bolt.cast(0, Vector2.ZERO, Vector2.RIGHT, 100.0) == bolt.mana_cost, "no cooldown was started by the refused cast")


## Combat learns the profile from `spell_cast` only: no event, no damage; the bolt never calls Combat.
func _test_combat_learns_the_profile_from_the_event() -> void:
	_setup()
	var bolt: SpellBase = _bolt()
	var imp := _enemy(100, Vector2(40.0, 0.0))
	bolt.cast(0, Vector2.ZERO, Vector2.RIGHT, 100.0)
	_run(24)
	_check(_combat.get_health(imp) == 100, "without spell_cast Combat has no profile, so the hit does nothing")
	bolt.tick(0, 10.0)
	_cast(bolt, 0, Vector2.ZERO, Vector2.RIGHT)
	_run(24)
	_check(_combat.get_health(imp) == 100 - bolt.damage, "after spell_cast the hit deals the bolt's damage")


## One resource is shared by every holder (the registry hands out one), so a run's leftover
## cooldown blocks the next run's first cast until `reset_cooldowns()`.
func _test_shared_resource_cooldowns_reset() -> void:
	_setup()
	var shared: SpellBase = _bolt()
	_check(_cast(shared, 0, Vector2.ZERO, Vector2.RIGHT) != SpellBase.REFUSED, "first holder casts")
	_check(shared.cast(0, Vector2.ZERO, Vector2.RIGHT, 100.0) == SpellBase.REFUSED, "a second holder of the same resource is blocked while it cools down")
	_check(shared.cast(1, Vector2.ZERO, Vector2.RIGHT, 100.0) == shared.mana_cost, "another player index is not blocked")
	shared.reset_cooldowns()
	_check(shared.cast(0, Vector2.ZERO, Vector2.RIGHT, 100.0) == shared.mana_cost, "after reset_cooldowns() the first cast of a new run fires")


func _test_zero_direction_fires_right() -> void:
	_setup()
	var bolt: SpellBase = _bolt()
	_cast(bolt, 0, Vector2.ZERO, Vector2.ZERO)
	_run(2)
	var slot: int = 0
	while slot < 8 and not _projectiles.is_alive(slot):
		slot += 1
	_check(slot < 8 and _projectiles.get_position_of(slot).x > 0.0, "a zero direction fires to the right")


func _test_player_casts_the_bolt() -> void:
	_setup()
	var imps: Array[Node2D] = []
	var wizards: Array[PlayerScript] = []
	for index in 4:
		# Each wizard has its own lane, far from the others, and an imp one bolt from death.
		imps.append(_enemy(BoltResource.damage, Vector2(60.0, 500.0 * index)))
		var wizard := PlayerScript.new()
		wizard.index = index
		wizard.events = _bus
		wizard.spell = _bolt()
		wizard.facing = Vector2.RIGHT
		root.add_child(wizard)
		_nodes.append(wizard)
		wizard.position = Vector2(0.0, 500.0 * index)
		wizards.append(wizard)
	_check(wizards[0].cast(), "the wizard casts the bolt through cast()")
	_check(is_equal_approx(wizards[0].mana, PlayerScript.MAX_MANA - BoltResource.mana_cost), "the wizard paid the mana the cast returned")
	_run(24)
	_check(_deaths.size() == 1 and _deaths[0][0] == 0 and _deaths[0][1] == imps[0], "only player 0's bolt landed, on player 0's imp")
	for index in range(1, 4):
		_check(_combat.is_enemy(imps[index]), "player %d's imp is untouched by the other lanes" % index)
		_check(wizards[index].cast(), "player %d casts too" % index)
	_run(24)
	_check(_deaths.size() == 4, "all four imps died")
	for index in 4:
		_check(_deaths.any(func(entry: Array) -> bool: return entry[0] == index and entry[1] == imps[index]), "player %d killed their own imp" % index)


func _test_registry_finds_the_bolt() -> void:
	var registry: Node = RegistryScript.new()
	registry.call("scan")
	var found: Resource = registry.call("get_resource", &"spells", &"bolt") as Resource
	_check(found is SpellBase and (found as SpellBase).spell_id() == &"bolt", "Registry finds the bolt under spells/forms/bolt")
	registry.free()


## The scanner must catch what it is there to catch, or the real scan proves nothing.
func _test_scanner_catches_field_reads() -> void:
	var bad: PackedStringArray = [
		"var cost: float = spell.mana_cost",
		"if player_spell.cooldown > 0.0:",
		"x = _spell.damage",
		"label.text = bolt.display_name",
		"var left = something.cooldown",
		"var life := s.lifetime",
	]
	for line in bad:
		_check(_line_reads_spell_field(line), "caught: " + line)
	var good: PackedStringArray = [
		"spell.cast(index, global_position, facing, mana)",
		"events.spell_cast.emit(index, spell.spell_id(), pos, facing)",
		"var speed: float = 3.0",
		"data.id",
		"spell.tick(index, delta)  # reads spell.damage later",
		"@export var cooldown: float = 0.0",
	]
	for line in good:
		_check(not _line_reads_spell_field(line), "not flagged: " + line)
	var names: PackedStringArray = _spell_typed_names("var pick: SpellBase = null\nfunc f(other: SpellBase) -> void:")
	_check(names == PackedStringArray(["pick", "other"]), "typed names are found")
	_check(_line_reads_spell_field("var d: int = pick.damage", names), "caught: a field on a variable typed SpellBase")
	_check(not _line_reads_spell_field("pick.cast(0, a, b, 1.0)", names), "not flagged: cast on a typed variable")


func _test_no_script_reads_spell_fields() -> void:
	var offenders: PackedStringArray = PackedStringArray()
	var checked: int = _scan_dir("res://", offenders)
	_check(checked > 20, "the scan looked at the scripts (%d)" % checked)
	_check(offenders.is_empty(), "scripts read spell fields: " + ", ".join(offenders))


# --- The field-read scan ------------------------------------------------------

## True when a line reads a spell field: a variable named like a spell followed by a
## field, or one of the four field names that nothing else uses (`.mana_cost`,
## `.cooldown`, `.lifetime`, `.display_name`), or a field on any variable the file declares
## as `SpellBase` (`typed_names`). Comments and declarations do not count. It is only a
## text heuristic: it cannot see a spell reached through an untyped variable, a call result
## (`get_spell().damage`) or `get()`, so reviews still look for those.
func _line_reads_spell_field(line: String, typed_names: PackedStringArray = PackedStringArray()) -> bool:
	var code: String = line.get_slice("#", 0)
	var named := RegEx.new()
	named.compile("(?i)\\w*spell\\w*\\s*\\.\\s*" + FIELD_PATTERN + "\\b")
	if named.search(code) != null:
		return true
	for typed_name in typed_names:
		var typed := RegEx.new()
		typed.compile("\\b" + typed_name + "\\s*\\.\\s*" + FIELD_PATTERN + "\\b")
		if typed.search(code) != null:
			return true
	var unique := RegEx.new()
	unique.compile("[\\w\\)\\]]\\s*\\.\\s*(mana_cost|cooldown|lifetime|display_name)\\b")
	# `burst.lifetime` is a CPUParticles2D property (gameplay/feel), not a spell field.
	return unique.search(code) != null and not code.contains("burst.lifetime")


## Names of the variables, parameters and loop variables a script types as `SpellBase`.
func _spell_typed_names(text: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var declared := RegEx.new()
	declared.compile("(\\w+)\\s*:\\s*SpellBase\\b")
	for found in declared.search_all(text):
		var declared_name: String = found.get_string(1)
		if not names.has(declared_name):
			names.append(declared_name)
	return names


## Scan every .gd below `path` except the skipped folders and the test_*.gd files
## (tests may set fields to build their fixtures). Returns the count scanned.
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
		var typed_names: PackedStringArray = _spell_typed_names(text)
		for line in text.split("\n"):
			number += 1
			if _line_reads_spell_field(line, typed_names):
				offenders.append("%s:%d" % [file_path, number])
	return count


func _is_skipped(path: String) -> bool:
	var relative: String = path.trim_prefix("res://")
	for skipped in SKIPPED_DIRS:
		if relative == skipped:
			return true
	return false
