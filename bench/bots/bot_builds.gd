extends RefCounted
## The bots' starting builds (the owner, 2026-11-20, on #883: the test bots get more powerful
## staffs, and one carries a mend staff to heal its teammates). A bot's own profile, beside
## `bot_profile.tres`: no player content names these.
##
## A build is what a person would set up in the hub before a run (the owner, 2026-11-20, after #886:
## the bots' runs start in the hub): the rack staff it takes (`rack`, a premade staff of the hub's
## rack, content/items/staffs; none for most) and, by hand (button: RB, RT, then LB, where a taken
## staff goes, `Inventory.free_hand`), the cards of the staff on it, slot by slot. A hand past the
## build's list keeps its cards (a rack staff used as it is). A bot sends each staff as one
## `staff_cards_requested`, as the builder does (`bot.gd`, `send_build`), from its card bag, so the
## bag must hold them: a run the bots play with these builds starts with `bag()` as Play's bag, which
## the hub hands out too (`stock`, the runners'). The run from the hub's stone takes the whole player
## along, the rack staff and the builds with it.
##
## - **Fighters** (`FIGHTERS`): a strong attack staff on RT and a dash on RB, so the brain dodges
##   with RB (it taps whichever staff's next cast moves its caster) and fights with RT. Each bot's is
##   drawn from the run's dice (`Sim.chance_int`, purpose PURPOSE, its seat the key, its one roll the
##   counter 0; the hub's run, where it is set): the same replay seed, the same builds, on every
##   machine and every replay. P1 and P3 also take a normal rack staff (`FIGHTER_RACKS`: the Frost
##   seeker and the Twin bolt), used as it lies on LB, a third attack.
## - **The mender** (`MENDER`): in a team of two or more, the bot at MEND_SEAT carries three staffs
##   (the owner, on #886 and 2026-11-20: heal, dash and attack): the mend on RB (mend on a plain
##   bolt, which stops at the first body it hits: a mend heals whatever it hits, friend or foe,
##   content/spells/elements/mend, so a shot that ends at the first body is the one a bot can aim at
##   a teammate), the dash on RT, and the hub rack's Firebolt on LB as its attack (fire on a bolt:
##   a normal premade staff; the owner, 2026-11-20, on #891: bots never take a dev staff or the
##   Wild star). Its brain picks the staff it needs, as every
##   bot's does (it reads what each staff casts next, never a button): it heals the most hurt
##   teammate it reaches along a clear line (the AI's `heal ally` behaviour, gameplay/ai/
##   behaviours/heal_ally.gd), taps the dash to get away, and fights with the attack; the bot holds
##   the heal while a foe stands near its line of fire (`bot.gd`, `foe_in_line`): it never aims a
##   heal at a foe.
##
## Every build is valid by the card rules (tests/bots/test_bot_builds.gd: no card wasted, one cast
## a staff, the attack hurts, the dash moves its caster, the mend heals and hurts nobody).

const FlowScript := preload("res://gameplay/flow/flow.gd")

## The roll's purpose (`Sim.chance_int`).
const PURPOSE: StringName = &"bot_build"
## The seat of the mender in a team of MEND_TEAM or more: P2, a fighter in every run the bots play
## (the 4-bot smoke test's idler is P4).
const MEND_SEAT: int = 1
const MEND_TEAM: int = 2

## The fighters' builds: a name (for the report lines) and the cards of each staff by hand.
const FIGHTERS: Array[Dictionary] = [
	{"name": "seeker", "staffs": [[&"dash"], [&"homing", &"bigger", &"bolt"]]},
	{"name": "fan", "staffs": [[&"dash"], [&"homing", &"plus_two", &"bolt"]]},
	{"name": "lance", "staffs": [[&"dash"], [&"faster", &"overcharge", &"bolt"]]},
	{"name": "beam", "staffs": [[&"dash"], [&"beam"]]},
]
## The hands a wizard starts with (RB and RT); a rack staff goes on the next.
const START_HANDS: int = FlowScript.START_HANDS
## The rack staff the mender takes: the hub's Firebolt (fire on a bolt, on the moon staff, a
## starter's numbers), used as it is: its attack. Bots take only the rack's normal staffs, never a
## dev staff or the Wild star (the owner, 2026-11-20, on #891).
const RACK_STAFF: StaffItem = preload("res://content/items/staffs/firebolt/firebolt.tres")
## The rack staff a fighter takes, by seat (none past the list, nor at the mender's seat): the
## rack's other two normal staffs, each used as it lies on LB (a third attack: the sweep and the
## playtests of 2026-11-20 lost fewer fights with them).
const FIGHTER_RACKS: Array[StaffItem] = [
	preload("res://content/items/staffs/frost_seeker/frost_seeker.tres"),
	null,
	preload("res://content/items/staffs/twin_bolt/twin_bolt.tres"),
]
## The mender's build: the heal on RB, the dash on RT, and the rack's Firebolt on LB as it is (a
## hand past the build's list keeps its cards).
const MENDER: Dictionary = {"name": "mender", "rack": RACK_STAFF, "staffs": [[&"mend", &"overcharge", &"faster", &"bolt"], [&"dash"]]}

## True when the bot at `seat` mends, in a team of `team` bots that fight.
static func mends(seat: int, team: int) -> bool:
	return team >= MEND_TEAM and seat == MEND_SEAT


## The build of the bot at `seat` in a team of `team`, drawn from `sim`'s dice (the run's).
static func pick(sim: Sim, seat: int, team: int) -> Dictionary:
	if mends(seat, team):
		return MENDER
	var drawn: Dictionary = FIGHTERS[sim.chance_int(PURPOSE, seat, 0, FIGHTERS.size())]
	var rack: StaffItem = FIGHTER_RACKS[seat] if seat >= 0 and seat < FIGHTER_RACKS.size() else null
	if rack == null:
		return drawn
	var out: Dictionary = drawn.duplicate()
	out["rack"] = rack
	return out


## Every build in the table: the fighters' and the mender's (a fighter's as drawn, before its seat's
## rack staff).
static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = FIGHTERS.duplicate()
	out.append(MENDER)
	return out


## The cards of `build`'s staff on hand `hand` (empty past its last staff).
static func cards_of(build: Dictionary, hand: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var staffs: Array = build["staffs"]
	if hand < 0 or hand >= staffs.size():
		return out
	for id: StringName in staffs[hand]:
		out.append(id)
	return out


## How many hands `build` sets the cards of.
static func hands_of(build: Dictionary) -> int:
	return (build["staffs"] as Array).size()


## How many hands hold a staff of `build`: the start hands, and the rack staff's past them.
static func held_hands(build: Dictionary) -> int:
	return START_HANDS + (1 if rack_of(build) != null else 0)


## The cards hand `hand` holds once `build` is set: the build's for that hand, else (past its list)
## the rack staff's as it lay on the rack, else none.
static func cards_held(build: Dictionary, hand: int) -> Array[StringName]:
	if hand < hands_of(build):
		return cards_of(build, hand)
	var out: Array[StringName] = []
	var rack: StaffItem = rack_of(build)
	if rack != null and hand == START_HANDS:
		out.assign(rack.cards)
	return out


## The rack staff `build` takes in the hub, or null for none.
static func rack_of(build: Dictionary) -> StaffItem:
	return build.get("rack", null) as StaffItem


## A card bag that builds any one build of the table: each card as many times as one build uses it
## at most, one entry a copy (as `Flow.play_bag`). It does not count the start cards already on the
## staffs (Play's `dash` and `bolt`), nor a rack staff's own (given back to the bag as it is
## rebuilt), so a wizard keeps a spare or two: simpler, and harmless.
static func bag() -> Array[StringName]:
	var most: Dictionary = {}
	for build: Dictionary in all():
		var uses: Dictionary = {}
		for staff: Array in build["staffs"]:
			for id: StringName in staff:
				uses[id] = int(uses.get(id, 0)) + 1
		for id: StringName in uses:
			most[id] = maxi(int(most.get(id, 0)), int(uses[id]))
	var out: Array[StringName] = []
	for id: StringName in most:
		for _copy in int(most[id]):
			out.append(id)
	return out


## Make `flow`'s Play bag `bag()` for the runs it starts next; returns the bag it had, which the
## caller puts back (`flow.set("play_bag", ...)`) when its runs are over.
static func stock(flow: Node) -> Array[StringName]:
	var had: Array[StringName] = []
	had.assign(flow.get(&"play_bag"))
	flow.set(&"play_bag", bag())
	return had
