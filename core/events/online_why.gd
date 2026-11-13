class_name OnlineWhy
extends RefCounted
## Why something of playing online stands as it does (online lobby L5b,
## docs/milestones/online-lobby.md): the names `online_changed` carries as its `reason`, each with
## the few facts that go with it. Whatever links the machines says one of these names and never a
## sentence; the HUD alone words them (`hud/widgets/online_words.gd`), so another way to find the
## other machines (a platform's own lobbies) fails by the same names with no change to the HUD.
##
## A fact is a number, a yes or no, one of the names here, or a room's code as the room's
## handshake read it (letters and digits of a fixed length). Never text off the wire.

# --- Before anything connects ---------------------------------------------------
## This build cannot link two machines at all.
const CANNOT_LINK: StringName = &"cannot_link"
## Asked for something that cannot be done now (begun already, a code given already, this
## machine's own code not made yet).
const NOT_NOW: StringName = &"not_now"
## This machine could not start a link, or make its code.
const SETUP_FAILED: StringName = &"setup_failed"
## This machine found no network address to be reached at.
const NO_ADDRESS: StringName = &"no_address"

# --- A code a player typed or pasted ----------------------------------------------
## What was given is no code of this game.
const BAD_CODE: StringName = &"bad_code"
## A host's code given where the joining player's was wanted, and the other way round.
const HOSTS_CODE: StringName = &"hosts_code"
const JOINERS_CODE: StringName = &"joiners_code"
## What was typed is no room's code. Fact: LENGTH.
const BAD_ROOM_CODE: StringName = &"bad_room_code"

# --- The room server --------------------------------------------------------------
## The room server was not reached, or did not answer.
const NO_SERVER: StringName = &"no_server"
## The room server closed the connection, or said what makes no sense.
const SERVER_FAILED: StringName = &"server_failed"
## No room has that code. Fact: ROOM.
const NO_ROOM: StringName = &"no_room"
## The room takes no more machines. Fact: ROOM.
const ROOM_FULL: StringName = &"room_full"
## The room is closed (its host closed it, or the server did).
const ROOM_CLOSED: StringName = &"room_closed"
## The host's code, as the room server brought it, is none this game can use.
const HOST_CODE_REFUSED: StringName = &"host_code_refused"
## Put in the room, this machine never found the host's.
const HOST_NOT_FOUND: StringName = &"host_not_found"

# --- No link between two machines -------------------------------------------------
## The two machines made no link. Facts: CAUSE (one of `CAUSES`), IN_TIME (false: they tried
## and failed; true: nothing came within the time allowed), LATE (this machine's code was made
## before its address as seen from outside had come), and how many addresses each machine's code
## held: MINE_OWN, MINE_OUTSIDE, MINE_RELAY, THEIRS_OWN, THEIRS_OUTSIDE, THEIRS_RELAY.
const NO_LINK: StringName = &"no_link"

# --- A link that was there --------------------------------------------------------
## The link was closed because the other machine sent what this game does not take.
const LINK_REFUSED: StringName = &"link_refused"
## Nothing was heard from the other machine. Fact: SECONDS.
const SILENT: StringName = &"silent"
## The host plays another build of the game.
const OTHER_BUILD: StringName = &"other_build"
## A machine was too far behind a run that began anew.
const FELL_BEHIND: StringName = &"fell_behind"
## The other machine was not ready to play within the time allowed. Fact: SECONDS.
const NOT_READY: StringName = &"not_ready"
## The other machine left before the run began.
const LEFT: StringName = &"left"
## The host's link closed before the run began: it left, or turned this machine away.
const TURNED_AWAY: StringName = &"turned_away"
## A machine came while the party was out of the hub; joining is in the hub only.
const OUT_OF_HUB: StringName = &"out_of_hub"
## The seat the other machine's player would take is held by a device here. Fact: SEAT (from 1).
const SEAT_HELD: StringName = &"seat_held"

# --- A run that played ------------------------------------------------------------
## The run plays on here without the others. Fact, for each: AFTER (why their link closed, one of
## the names above, with its own facts beside it; absent when they just left).
## The joining player left a run of two.
const GUEST_LEFT: StringName = &"guest_left"
## The host left.
const HOST_LEFT: StringName = &"host_left"
## Every joining machine left a party; its room is still open, or closed.
const PARTY_LEFT_OPEN: StringName = &"party_left_open"
const PARTY_LEFT_CLOSED: StringName = &"party_left_closed"

## Every name above.
const ALL: Array[StringName] = [
	CANNOT_LINK, NOT_NOW, SETUP_FAILED, NO_ADDRESS,
	BAD_CODE, HOSTS_CODE, JOINERS_CODE, BAD_ROOM_CODE,
	NO_SERVER, SERVER_FAILED, NO_ROOM, ROOM_FULL, ROOM_CLOSED, HOST_CODE_REFUSED, HOST_NOT_FOUND,
	NO_LINK,
	LINK_REFUSED, SILENT, OTHER_BUILD, FELL_BEHIND, NOT_READY, LEFT, TURNED_AWAY, OUT_OF_HUB, SEAT_HELD,
	GUEST_LEFT, HOST_LEFT, PARTY_LEFT_OPEN, PARTY_LEFT_CLOSED,
]

# --- The facts' keys ----------------------------------------------------------------
const LENGTH: StringName = &"length"
const ROOM: StringName = &"room"
const SECONDS: StringName = &"seconds"
const SEAT: StringName = &"seat"
const AFTER: StringName = &"after"
const CAUSE: StringName = &"cause"
const IN_TIME: StringName = &"in_time"
const LATE: StringName = &"late"
const MINE_OWN: StringName = &"mine_own"
const MINE_OUTSIDE: StringName = &"mine_outside"
const MINE_RELAY: StringName = &"mine_relay"
const THEIRS_OWN: StringName = &"theirs_own"
const THEIRS_OUTSIDE: StringName = &"theirs_outside"
const THEIRS_RELAY: StringName = &"theirs_relay"

# --- NO_LINK's causes, as far as the two machines' codes tell -----------------------
## Not even through the relay.
const CAUSE_RELAY: StringName = &"relay"
## This machine, or the other, never learnt its address as seen from outside.
const CAUSE_HIDDEN_HERE: StringName = &"hidden_here"
const CAUSE_HIDDEN_THERE: StringName = &"hidden_there"
## Both seem to be on one network, where they do not see each other.
const CAUSE_ONE_NETWORK: StringName = &"one_network"
## Two networks with no direct way between them.
const CAUSE_TWO_NETWORKS: StringName = &"two_networks"
## Not known (the codes were not both there).
const CAUSE_UNKNOWN: StringName = &"unknown"
const CAUSES: Array[StringName] = [CAUSE_RELAY, CAUSE_HIDDEN_HERE, CAUSE_HIDDEN_THERE, CAUSE_ONE_NETWORK, CAUSE_TWO_NETWORKS, CAUSE_UNKNOWN]

# --- The online line's facts (`online_line_changed`) --------------------------------
## An open room's code (text), and the machines that joined its run (absent: no run plays yet).
const LINE_ROOM: StringName = &"room"
const LINE_JOINED: StringName = &"joined"
## This machine plays what the host recorded before it came, to catch up.
const LINE_CATCHING_UP: StringName = &"catching_up"
## The machines' games parted: the tick of the first check that failed, and, on the host only,
## the areas that differed (a PackedStringArray of the game's own area names, as this machine
## hashed them; a joining machine was told them over the wire, so its line has none).
const LINE_PARTED_TICK: StringName = &"parted_tick"
const LINE_PARTED_AREAS: StringName = &"parted_areas"


## The most characters of a room's code shown (a room's code is short; nothing longer is one).
const MAX_ROOM_CHARS: int = 16


## A room's code as it may be shown on the screen: text, short, letters and digits only; "" for
## anything else (a machine's own long code by hand, something that is no text).
static func room_code(fact: Variant) -> String:
	if not (fact is String) or (fact as String).length() > MAX_ROOM_CHARS:
		return ""
	for at in (fact as String).length():
		var c: int = (fact as String).unicode_at(at)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)):
			return ""
	return fact
