extends RefCounted
## The words for playing online (online lobby L5b, docs/milestones/online-lobby.md): what
## `online_changed` says as a reason's name and its facts (`OnlineWhy`), and the facts of
## `online_line_changed`, as sentences for a player. The one place they are worded: whatever links
## the machines never writes a sentence for the screen, so another way to link them (a
## platform's own lobbies) says the same names and the words stay here.
##
## A name with no words here still says something (`UNKNOWN`), and a fact that is missing or of
## another kind is worded as nothing: what comes over the bus is never trusted to be whole.

const UNKNOWN: String = "It did not work."

## A sentence for each of `OnlineWhy.ALL`; `%d` and `%s` take the fact named in `FACT_OF`.
const WORDS: Dictionary[StringName, String] = {
	OnlineWhy.CANNOT_LINK: "This build cannot link two machines.",
	OnlineWhy.NOT_NOW: "That cannot be done right now.",
	OnlineWhy.SETUP_FAILED: "This machine could not start a link.",
	OnlineWhy.NO_ADDRESS: "This machine found no network address to be reached at.",
	OnlineWhy.BAD_CODE: "That is not a code of this game.",
	OnlineWhy.HOSTS_CODE: "That is a host's code; the host needs the code the joining player got back.",
	OnlineWhy.JOINERS_CODE: "That is a joining player's code; Join needs the host's.",
	OnlineWhy.BAD_ROOM_CODE: "A room's code is %d letters and digits.",
	OnlineWhy.NO_SERVER: "The room server could not be reached.",
	OnlineWhy.SERVER_FAILED: "The room server closed the connection.",
	OnlineWhy.NO_ROOM: "No room has the code %s.",
	OnlineWhy.ROOM_FULL: "The room %s is full.",
	OnlineWhy.ROOM_CLOSED: "The room is closed.",
	OnlineWhy.HOST_CODE_REFUSED: "The host's machine sent a code this game cannot use (is it the same build?).",
	OnlineWhy.HOST_NOT_FOUND: "The host's machine was not found in time.",
	OnlineWhy.NO_LINK: "The two machines could not reach each other.",
	OnlineWhy.LINK_REFUSED: "The link was closed: the other machine sent something this game does not take.",
	OnlineWhy.SILENT: "Nothing was heard from the other machine for %d seconds.",
	OnlineWhy.OTHER_BUILD: "The host plays another build of the game.",
	OnlineWhy.FELL_BEHIND: "A machine fell too far behind and was let go; it may join again.",
	OnlineWhy.NOT_READY: "The other machine was not ready within %d seconds.",
	OnlineWhy.LEFT: "The other player left.",
	OnlineWhy.TURNED_AWAY: "The host left, or its party cannot be joined right now (a party is joined in its hub only).",
	OnlineWhy.OUT_OF_HUB: "A machine came while the party was out of the hub; joining is in the hub only.",
	OnlineWhy.SEAT_HELD: "Seat %d is held by a device of this machine.",
	OnlineWhy.GUEST_LEFT: "The other player left; the run plays on here.",
	OnlineWhy.HOST_LEFT: "The host left; the run plays on here, alone.",
	OnlineWhy.PARTY_LEFT_OPEN: "The other machines left; the room is still open.",
	OnlineWhy.PARTY_LEFT_CLOSED: "The other machines left, and the room is closed; the party plays on here.",
}
## The fact a name's sentence takes, and its kind.
const FACT_OF: Dictionary[StringName, StringName] = {
	OnlineWhy.BAD_ROOM_CODE: OnlineWhy.LENGTH,
	OnlineWhy.NO_ROOM: OnlineWhy.ROOM,
	OnlineWhy.ROOM_FULL: OnlineWhy.ROOM,
	OnlineWhy.SILENT: OnlineWhy.SECONDS,
	OnlineWhy.NOT_READY: OnlineWhy.SECONDS,
	OnlineWhy.SEAT_HELD: OnlineWhy.SEAT,
}
## NO_LINK: how it failed, and why as far as the two machines' codes told (`OnlineWhy.CAUSES`).
const NO_LINK_TRIED: String = "The two machines could not reach each other"
const NO_LINK_IN_TIME: String = "The two machines did not find each other in time"
const CAUSES: Dictionary[StringName, String] = {
	OnlineWhy.CAUSE_RELAY: "not even through the relay (a firewall may block it, or the relay is down)",
	OnlineWhy.CAUSE_HIDDEN_HERE: "this machine never learnt its address as seen from outside, so only a machine on its own network can reach it (a firewall may be in the way)",
	OnlineWhy.CAUSE_HIDDEN_THERE: "the other machine never learnt its address as seen from outside, so only a machine on its own network can reach it (a firewall there may be in the way)",
	OnlineWhy.CAUSE_ONE_NETWORK: "both seem to be on one network, where these two do not see each other; use the same browser on both, or the desktop build",
	OnlineWhy.CAUSE_TWO_NETWORKS: "they are on two networks with no direct way between them; only a relay gets through that",
}
## NO_LINK, when this machine's code was made before its address from outside had come.
const LATE: String = "This machine's address as seen from outside came too late for its code, or never; trying again may do."


## The sentence for `reason` with its `facts`; "" for no reason.
static func said(reason: StringName, facts: Dictionary) -> String:
	if reason == &"":
		return ""
	if reason == OnlineWhy.NO_LINK:
		return _no_link(facts)
	var words: String = WORDS.get(reason, UNKNOWN)
	if FACT_OF.has(reason):
		var fact: Variant = facts.get(FACT_OF[reason])
		if words.contains("%d"):
			words = words % _number(fact)
		else:
			words = words % _room(fact)
	# Why the others' link closed, after a run that played on.
	var after: Variant = facts.get(OnlineWhy.AFTER)
	if after is StringName and after != reason and after != &"":
		var rest: Dictionary = facts.duplicate()
		rest.erase(OnlineWhy.AFTER)
		words = "%s (%s)" % [words, said(after, rest)]
	return words


## The online line: what `facts` say of the run (`OnlineWhy`'s LINE_ keys), then its `counters`
## as they came. "" with nothing to say.
static func line(facts: Dictionary, counters: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var room: String = _room(facts.get(OnlineWhy.LINE_ROOM))
	if room != "":
		if facts.has(OnlineWhy.LINE_JOINED):
			parts.append("Room %s, %d machine(s) joined." % [room, _number(facts.get(OnlineWhy.LINE_JOINED))])
		else:
			parts.append("Online room %s: the code other machines join by." % room)
	if facts.get(OnlineWhy.LINE_CATCHING_UP) is bool and facts[OnlineWhy.LINE_CATCHING_UP]:
		parts.append("Catching up with the host.")
	if facts.has(OnlineWhy.LINE_PARTED_TICK):
		var areas: Variant = facts.get(OnlineWhy.LINE_PARTED_AREAS)
		var where: String = " (%s)" % ", ".join(areas as PackedStringArray) if areas is PackedStringArray and not (areas as PackedStringArray).is_empty() else ""
		parts.append("PARTED at tick %d%s." % [_number(facts.get(OnlineWhy.LINE_PARTED_TICK)), where])
	if counters != "":
		parts.append(counters)
	return " ".join(parts)


static func _no_link(facts: Dictionary) -> String:
	var in_time: bool = facts.get(OnlineWhy.IN_TIME) is bool and facts[OnlineWhy.IN_TIME]
	var words: String = NO_LINK_IN_TIME if in_time else NO_LINK_TRIED
	var cause: Variant = facts.get(OnlineWhy.CAUSE)
	if cause is StringName and CAUSES.has(cause):
		words += ": " + CAUSES[cause]
	if facts.has(OnlineWhy.MINE_OWN):
		words += " (addresses: this machine %d own, %d outside, %d relay; the other %d own, %d outside, %d relay)" % [
			_number(facts.get(OnlineWhy.MINE_OWN)), _number(facts.get(OnlineWhy.MINE_OUTSIDE)), _number(facts.get(OnlineWhy.MINE_RELAY)),
			_number(facts.get(OnlineWhy.THEIRS_OWN)), _number(facts.get(OnlineWhy.THEIRS_OUTSIDE)), _number(facts.get(OnlineWhy.THEIRS_RELAY)),
		]
	words += "."
	# Only where no address from outside is in this machine's code: one that came in time is.
	if facts.get(OnlineWhy.LATE) is bool and facts[OnlineWhy.LATE] and _number(facts.get(OnlineWhy.MINE_OUTSIDE)) == 0:
		words += " " + LATE
	return words


static func _number(fact: Variant) -> int:
	return fact if fact is int else 0


## A room's code as it may be shown (`OnlineWhy.room_code`).
static func _room(fact: Variant) -> String:
	return OnlineWhy.room_code(fact)
