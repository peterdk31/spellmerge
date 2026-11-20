extends RefCounted
## The bots' starting builds (the owner, 2026-11-20, on #883: the test bots get more powerful
## staffs, and one carries a mend staff to heal its teammates). A bot's own profile, beside
## `bot_profile.tres`: no player content names these.
##
## A build is what a person would set in the builder before the first fight: by staff number (the
## inventory's, the two starter staffs a wizard of Play holds, RB's and RT's, 6 slots each), the
## cards of that staff, slot by slot. A bot sends each staff as one `staff_cards_requested`, as the
## builder does (`bot.gd`, `build_drawn`), from its card bag, so the bag must hold them: a run the bots
## play with these builds starts with `bag()` as Play's bag (`stock`, the runners').
##
## - **Fighters** (`FIGHTERS`): a strong attack staff on RT and a dash on RB, so the brain dodges
##   with RB (it taps whichever staff's next cast moves its caster) and fights with RT. Each bot's is
##   drawn from the run's dice (`Sim.chance_int`, purpose PURPOSE, its seat the key, its one roll the
##   counter 0): the same run seed, the same builds, on every machine and every replay.
## - **The mender** (`MENDER`): in a team of two or more, the bot at MEND_SEAT carries a mend staff
##   on RB (mend on a plain bolt, which stops at the first body it hits: a mend heals whatever it
##   hits, friend or foe, content/spells/elements/mend, so a shot that ends at the first body is the
##   one a bot can aim at a teammate) and a fighter's staff on RT. Its brain heals the most hurt
##   teammate it reaches along a clear line (the AI's `heal ally` behaviour, gameplay/ai/
##   behaviours/heal_ally.gd), and the bot holds the heal while a foe stands near its line of fire
##   (`bot.gd`, `foe_in_line`): it never aims a heal at a foe.
##
## Every build is valid by the card rules (tests/bots/test_bot_builds.gd: no card wasted, one cast
## a staff, the attack hurts, the dash moves its caster, the mend heals and hurts nobody).

## The roll's purpose (`Sim.chance_int`).
const PURPOSE: StringName = &"bot_build"
## The seat of the mender in a team of MEND_TEAM or more: P2, a fighter in every run the bots play
## (the 4-bot smoke test's idler is P4).
const MEND_SEAT: int = 1
const MEND_TEAM: int = 2

## The fighters' builds: a name (for the report lines) and the cards of each staff by number.
const FIGHTERS: Array[Dictionary] = [
	{"name": "seeker", "staffs": [[&"dash"], [&"homing", &"bigger", &"bolt"]]},
	{"name": "fan", "staffs": [[&"dash"], [&"homing", &"split", &"bolt"]]},
	{"name": "lance", "staffs": [[&"dash"], [&"faster", &"overcharge", &"bolt"]]},
	{"name": "beam", "staffs": [[&"dash"], [&"beam"]]},
]
## The mender's build: the heal on RB, the fight on RT.
const MENDER: Dictionary = {"name": "mender", "staffs": [[&"mend", &"overcharge", &"faster", &"bolt"], [&"homing", &"bigger", &"bolt"]]}


## True when the bot at `seat` mends, in a team of `team` bots that fight.
static func mends(seat: int, team: int) -> bool:
	return team >= MEND_TEAM and seat == MEND_SEAT


## The build of the bot at `seat` in a team of `team`, drawn from `sim`'s dice (the run's).
static func pick(sim: Sim, seat: int, team: int) -> Dictionary:
	if mends(seat, team):
		return MENDER
	return FIGHTERS[sim.chance_int(PURPOSE, seat, 0, FIGHTERS.size())]


## Every build in the table: the fighters' and the mender's.
static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = FIGHTERS.duplicate()
	out.append(MENDER)
	return out


## The cards of `build`'s staff `number` (empty past its last staff).
static func cards_of(build: Dictionary, number: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var staffs: Array = build["staffs"]
	if number < 0 or number >= staffs.size():
		return out
	for id: StringName in staffs[number]:
		out.append(id)
	return out


## A card bag that builds any one build of the table: each card as many times as one build uses it
## at most, one entry a copy (as `Flow.play_bag`).
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
