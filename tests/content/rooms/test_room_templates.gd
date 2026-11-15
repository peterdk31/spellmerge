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
	for room: RoomBase in registry.run_content().rooms:
		if room.kinds.is_empty():
			continue
		templates += 1
		var places: RoomPlaces = room.places()
		check(places.enemy_spawns.size() >= 1, "%s hosts %s: it has enemy spawns" % [room.id, room.kinds])
		check(places.player_spawns.size() >= SEATS, "%s hosts %s: a player spawn for each of %d seats (%d)" % [room.id, room.kinds, SEATS, places.player_spawns.size()])
	check(templates >= 1, "it finds the templates (%d)" % templates)
