extends "res://tests/support/suite.gd"
## Every room template a run's map can pick (a room that hosts a kind: run generation RG3,
## content/rooms/README.md) can hold what the map puts in it: a fight's enemies and a boss stand at
## its enemy spawns, so it has some, and the party at its player spawns, one a seat. A room with
## none would stand nothing and be won as it starts. Found by folder: a new template is covered the
## day it lands.

const RegistryScript := preload("res://core/registry/registry.gd")

## The seats a room must have a player spawn for.
const SEATS: int = 4


func test_every_template_has_enemy_and_player_spawns() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var templates: int = 0
	var content: RunContent = registry.run_content()
	for room: RoomBase in content.rooms:
		if room.kinds.is_empty():
			continue
		templates += 1
		var places: RoomPlaces = room.places()
		# A room no fight stands in (a biome's start room, connected biomes CB8; a shop, a fountain,
		# CB11) needs no enemy spawn.
		var fought: bool = false
		for kind_id: StringName in room.kinds:
			var kind: RoomKind = content.kind(kind_id)
			fought = fought or (kind != null and (kind.fills_with_enemies() or kind.fill == RoomKind.FILL_BOSS))
		if fought:
			check(places.enemy_spawns.size() >= 1, "%s hosts %s: it has enemy spawns" % [room.id, room.kinds])
		check(places.player_spawns.size() >= SEATS, "%s hosts %s: a player spawn for each of %d seats (%d)" % [room.id, room.kinds, SEATS, places.player_spawns.size()])
	check(templates >= 1, "it finds the templates (%d)" % templates)
