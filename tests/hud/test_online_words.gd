extends "res://tests/support/suite.gd"
## The words for playing online (online lobby L5b; hud/widgets/online_words.gd): every reason
## `OnlineWhy` names has a sentence here, with its facts in it, and what is no name or no fact
## is worded as nothing a player could be fooled by.

const OnlineWords := preload("res://hud/widgets/online_words.gd")


func test_every_reason_has_words() -> void:
	for reason in OnlineWhy.ALL:
		var said: String = OnlineWords.said(reason, {})
		check(said != "" and said != OnlineWords.UNKNOWN and said.ends_with("."), "%s is a sentence (%s)" % [reason, said])
		check(not said.contains("%"), "%s takes its fact, or none (%s)" % [reason, said])
	for reason: StringName in OnlineWords.WORDS:
		check(OnlineWhy.ALL.has(reason), "%s is a reason there is" % reason)
	for reason: StringName in OnlineWords.FACT_OF:
		check(OnlineWords.WORDS[reason].contains("%"), "%s's sentence takes the fact named for it" % reason)
	for cause in OnlineWhy.CAUSES:
		check(cause == OnlineWhy.CAUSE_UNKNOWN or OnlineWords.CAUSES.has(cause), "the cause %s has words" % cause)
	check_equal(OnlineWords.said(&"", {}), "", "no reason: nothing")
	check_equal(OnlineWords.said(&"never heard of", {}), OnlineWords.UNKNOWN, "a name with no words says it did not work, never the name")


func test_the_facts_are_in_the_words() -> void:
	check_equal(OnlineWords.said(OnlineWhy.NO_ROOM, {OnlineWhy.ROOM: "AB2DE"}), "No room has the code AB2DE.", "a room's code")
	check_equal(OnlineWords.said(OnlineWhy.BAD_ROOM_CODE, {OnlineWhy.LENGTH: 5}), "A room's code is 5 letters and digits.", "a number")
	check_equal(OnlineWords.said(OnlineWhy.SEAT_HELD, {OnlineWhy.SEAT: 2}), "Seat 2 is held by a device of this machine.", "a seat")
	check_equal(OnlineWords.said(OnlineWhy.GUEST_LEFT, {}), "The other player left; the run plays on here.", "who left")
	check_equal(OnlineWords.said(OnlineWhy.GUEST_LEFT, {OnlineWhy.AFTER: OnlineWhy.LINK_REFUSED}), "The other player left; the run plays on here. (The link was closed: the other machine sent something this game does not take.)", "and why its link closed, after")
	check_equal(OnlineWords.said(OnlineWhy.HOST_LEFT, {OnlineWhy.AFTER: OnlineWhy.HOST_LEFT}), "The host left; the run plays on here, alone.", "a reason after itself is said once")


func test_no_link_says_how_and_why_and_how_many_addresses() -> void:
	var facts: Dictionary = {
		OnlineWhy.CAUSE: OnlineWhy.CAUSE_HIDDEN_HERE, OnlineWhy.IN_TIME: true, OnlineWhy.LATE: false,
		OnlineWhy.MINE_OWN: 2, OnlineWhy.MINE_OUTSIDE: 0, OnlineWhy.MINE_RELAY: 0,
		OnlineWhy.THEIRS_OWN: 1, OnlineWhy.THEIRS_OUTSIDE: 1, OnlineWhy.THEIRS_RELAY: 0,
	}
	var said: String = OnlineWords.said(OnlineWhy.NO_LINK, facts)
	check(said.begins_with("The two machines did not find each other in time: this machine never learnt its address as seen from outside"), "how, and why (%s)" % said)
	check(said.contains("(addresses: this machine 2 own, 0 outside, 0 relay; the other 1 own, 1 outside, 0 relay)"), "the counts: what a screen with no log shows (%s)" % said)
	check(not said.contains("too late"), "nothing of a late answer when there was none")
	facts[OnlineWhy.LATE] = true
	check(OnlineWords.said(OnlineWhy.NO_LINK, facts).ends_with(OnlineWords.LATE), "a code made before the address from outside came says so")
	facts[OnlineWhy.MINE_OUTSIDE] = 1
	facts[OnlineWhy.CAUSE] = OnlineWhy.CAUSE_TWO_NETWORKS
	check(not OnlineWords.said(OnlineWhy.NO_LINK, facts).contains("too late"), "but not where the address did come in time")
	facts[OnlineWhy.IN_TIME] = false
	facts[OnlineWhy.CAUSE] = OnlineWhy.CAUSE_RELAY
	check(OnlineWords.said(OnlineWhy.NO_LINK, facts).begins_with("The two machines could not reach each other: not even through the relay"), "tried and failed, through a relay")
	check_equal(OnlineWords.said(OnlineWhy.NO_LINK, {OnlineWhy.CAUSE: OnlineWhy.CAUSE_UNKNOWN}), "The two machines could not reach each other.", "nothing known: only that")


func test_what_is_no_fact_is_worded_as_nothing() -> void:
	check_equal(OnlineWords.said(OnlineWhy.NO_ROOM, {OnlineWhy.ROOM: "<b>look here</b>"}), "No room has the code .", "text that is no room's code is not shown")
	check_equal(OnlineWords.said(OnlineWhy.NO_ROOM, {OnlineWhy.ROOM: "A".repeat(200)}), "No room has the code .", "nor a long one")
	check_equal(OnlineWords.said(OnlineWhy.SILENT, {OnlineWhy.SECONDS: "many"}), "Nothing was heard from the other machine for 0 seconds.", "a number that is none is 0")
	check_equal(OnlineWords.said(OnlineWhy.NO_LINK, {OnlineWhy.CAUSE: "%s %d", OnlineWhy.IN_TIME: 1}), "The two machines could not reach each other.", "a cause that is no name is left out")
	check_equal(OnlineWords.line({OnlineWhy.LINE_ROOM: 7, OnlineWhy.LINE_PARTED_TICK: "x", OnlineWhy.LINE_PARTED_AREAS: 3}, ""), "PARTED at tick 0.", "the line's facts alike")
	check_equal(OnlineWords.line({}, ""), "", "an empty line is empty")
