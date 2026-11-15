extends RoomBase
## A room template made up by a test, with no scene (run generation): it says how many exits it has
## (`exits`, run generation RG4) instead of placing them, so a test's made-up content leads on as far
## as the test wants. MOST_EXITS by default: as many ways as any map rules allow.
##
##     var room := MadeUpRoom.new()
##     room.exits = 1

const MOST_EXITS: int = 8

var exits: int = MOST_EXITS


func exit_count() -> int:
	return exits
