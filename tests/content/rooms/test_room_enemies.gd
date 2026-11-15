extends "res://tests/support/suite.gd"
## A room's fight (boss OB2a, docs/milestones/boss-old-broom.md, decision 31): every room's lines
## (`RoomBase.enemies`) name an enemy or a boss the registry has (`EnemyBase.FOLDERS`), each at least
## once, and a room that lists any has enemy spawns to stand them at. Deleting an enemy or a boss
## together with the rooms that list it keeps this passing.

const RegistryScript := preload("res://core/registry/registry.gd")


func test_every_rooms_enemies_are_in_the_registry() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var listing: int = 0
	for item: Resource in registry.get_all(&"rooms"):
		var room := item as RoomBase
		if room == null or room.enemies.is_empty():
			continue
		listing += 1
		check(not room.places().enemy_spawns.is_empty(), "%s lists enemies and has enemy spawns" % room.id)
		for line: RoomEnemies in room.enemies:
			check(line != null, "%s: no empty line" % room.id)
			if line == null:
				continue
			check(line.count >= 1, "%s: '%s' stands at least once" % [room.id, line.enemy])
			var found: bool = false
			for folder: StringName in EnemyBase.FOLDERS:
				found = found or registry.get_resource(folder, line.enemy) is EnemyBase
			check(found, "%s: '%s' is an enemy or a boss of the registry" % [room.id, line.enemy])
	check(listing >= 1, "at least one room has a fight (%d)" % listing)
