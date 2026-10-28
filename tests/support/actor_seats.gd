extends RefCounted
## Actor tables for tests (actors G3): core casts by actor id, and an actor's team, ramp, seat
## and budget come from the table (`core/actors`), so a test that casts as a wizard opens one.
##
##     _mgr.actors = own(ActorSeats.table()) as ActorsScript   # wizards at ids 0-3, seats 0-3
##     var table: ActorsScript = own(ActorSeats.table(2, 5)) as ActorsScript   # ids 5 and 6
##
## `table(count, first)` makes a new table with `count` wizards seated 0 to count - 1 at the ids
## `first` and up (the ids below `first` are taken by unseated enemies first, so no code can take
## an id for a seat). The caller owns the table (it is a Node: free it, or hand it to `own`).
## Services that are not given a table use the `Actors` autoload: `seat_wizards` fills that one
## the same way (`Actors.clear()` empties it again).

const ActorsScript := preload("res://core/actors/actors.gd")


## A new table: `first` unseated enemies (ids 0 to first - 1), then `count` wizards seated 0 to
## count - 1 (ids first to first + count - 1).
static func table(count: int = 4, first: int = 0) -> ActorsScript:
	var made: ActorsScript = ActorsScript.new()
	seat_wizards(made, count, first)
	return made


## Opens in `actors` (cleared first) `first` unseated enemies, then `count` seated wizards, and
## returns the wizards' ids by seat.
static func seat_wizards(actors: ActorsScript, count: int = 4, first: int = 0) -> PackedInt32Array:
	actors.clear()
	for i in first:
		actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	var ids := PackedInt32Array()
	for seat in count:
		ids.append(actors.open(ActorsScript.TEAM_WIZARDS, seat, seat))
	return ids


## An enemy (the enemies' team and ramp, no seat) opened in `actors`; its id.
static func enemy(actors: ActorsScript) -> int:
	return actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)


## The `Actors` autoload of the running tree, or null.
static func autoload() -> ActorsScript:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"Actors") as ActorsScript if tree != null else null
