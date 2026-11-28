extends RefCounted
## The body table's check (perf plan change 2, C1; core/actors/README.md, "The body table"): what of
## the actor table's rows is not what the nodes say. The body tests' (tests/gameplay/actor/
## test_body_table.gd, tests/core/test_body_table_game.gd).

const ActorsScript := preload("res://core/actors/actors.gd")


## The flags the node of `body` says its row has (`Actors.FLAG_*`).
static func flags_of(body: Actor) -> int:
	var flags: int = ActorsScript.FLAG_BODY
	if body.is_down():
		flags |= ActorsScript.FLAG_DOWN
	if body.is_dying():
		flags |= ActorsScript.FLAG_DYING
	if body.is_spawning():
		flags |= ActorsScript.FLAG_SPAWNING
	if body.is_falling():
		flags |= ActorsScript.FLAG_FALLING
	return flags


## Every row that is not as it should be, one line each: an open body's row is what its node says
## (place, velocity, radius against the walls, flags); every other row (an id not open, or open with
## no Actor, a plain Combat body) is empty.
static func rows_wrong(table: ActorsScript) -> PackedStringArray:
	var wrong: PackedStringArray = PackedStringArray()
	for id in ActorsScript.ACTORS:
		var body: Actor = table.node_of(id) as Actor
		if body == null:
			if table.places[id] != Vector2.ZERO or table.velocities[id] != Vector2.ZERO or table.radii[id] != 0.0 or table.body_flags[id] != 0:
				wrong.append("%d: a row with no body" % id)
			continue
		if table.places[id] != body.global_position:
			wrong.append("%d (%s): place %s, node %s" % [id, body.name, table.places[id], body.global_position])
		if table.velocities[id] != body.velocity:
			wrong.append("%d (%s): velocity %s, node %s" % [id, body.name, table.velocities[id], body.velocity])
		if table.radii[id] != body.wall_radius():
			wrong.append("%d (%s): radius %s, node %s" % [id, body.name, table.radii[id], body.wall_radius()])
		if table.body_flags[id] != flags_of(body):
			wrong.append("%d (%s): flags %d, node %d" % [id, body.name, table.body_flags[id], flags_of(body)])
	return wrong
