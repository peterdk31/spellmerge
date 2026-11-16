extends "res://tests/support/suite.gd"
## The runs and what they are made of (run generation RG1, docs/milestones/run-generation.md): every
## run definition's rules can make a map from the content there is, every room kind and every room
## template is sound, and the crypt run is found with the crypt's rooms and enemies. Deleting a
## room, an enemy or a boss keeps this passing while the run can still be made, and names what is
## missing when it cannot (`Registry.validate_runs`).
const RegistryScript := preload("res://core/registry/registry.gd")

var _registry: RegistryScript = null


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()


func test_every_run_can_be_made_from_the_content() -> void:
	check(not _registry.get_all(&"runs").is_empty(), "at least one run is defined")
	check_equal(_registry.validate_runs(), PackedStringArray(), "every run, room kind and template is sound")


func test_the_crypt_run_has_fights_in_every_row_it_keeps() -> void:
	var crypt := _registry.get_resource(&"runs", &"crypt") as RunDefinition
	check(crypt != null and crypt.biomes.size() == 1, "the crypt run, one biome")
	if crypt == null or crypt.biomes.is_empty():
		return
	var rules: MapRules = crypt.biomes[0]
	var content: RunContent = _registry.run_content()
	check(not content.templates_for(rules.biome, &"fight").is_empty(), "the crypt has fight rooms")
	for depth in range(rules.depth_min, rules.depth_max + 1):
		var rows: Array[int] = rules.kept_rows(content, depth)
		check(rows.size() >= depth - 1, "%d rows deep: every row but at most the boss's is kept (%s)" % [depth, rows])
		check(rows.has(0), "%d rows deep: the first room is kept" % depth)


func test_rooms_for_no_run_host_no_kind() -> void:
	for id: StringName in [&"hub", &"sandbox"]:
		var room := _registry.get_resource(&"rooms", id) as RoomBase
		check(room != null and room.kinds.is_empty(), "%s is offered for no run" % id)


func test_the_room_kinds_are_not_rooms() -> void:
	# Room kinds have a folder of their own, so a list of rooms never holds one.
	for item: Resource in _registry.get_all(&"rooms"):
		check(item is RoomBase, "%s under rooms is a room" % item.resource_path)
	check(_registry.get_resource(&"room_kinds", &"fight") is RoomKind, "the fight kind is found")
	check(_registry.get_resource(&"room_kinds", &"boss") is RoomKind, "the boss kind is found")
