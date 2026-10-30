extends "res://tests/support/suite.gd"
## The spell fuzz test (staffs A6b; M2 part 20 before it): a few hundred seeded random staffs,
## card rows drawn from every card the registry has, are compiled, built and cast in the test
## arena (`combo_arena.gd`: the real registry, spell runtime, projectile manager and combat, with
## imps standing in the way). Every arrangement of cards is legal (docs/milestones/M2-staffs.md),
## so nothing is refused; the test fails on
##  - an error line in the log (`push_error`, a script error, a line starting `ERROR:`),
##  - a cycle that is not finite (more casts than slots, or more compiled spells than a tag
##    holds), and
##  - a staff whose cards include a carrier but that never casts.
## There are no build limits any more, so a staff may fill the projectile pool: the manager then
## drops the oldest shots (an engine safeguard). That is counted and reported on the FUZZ line,
## with the costliest staffs, not failed; the stress run and the emergent combo report (staffs
## D1) say whether a limit is needed. Slow steps only warn (a line starting `FUZZ WARNING`): a
## shared runner's speed is not a spell.
## A failure names the seed and the staff, so it can be replayed: change `SEED` or `STAFFS`, or
## build the staff by hand in the arena.
##
## godot --headless --path . --script res://tests/bots/test_spell_fuzz.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const FuzzerScript := preload("res://tests/bots/staff_fuzzer.gd")
const ErrorLogScript := preload("res://tests/smoke/error_log.gd")

const SEED: int = 20261026
## Random staffs tried.
const STAFFS: int = 600
## Cards in a random staff at most.
const SLOTS: int = 10
## Seconds each staff is cast and run for.
const SECONDS: float = 2.0
## Mean step time and single step time above which a warning is printed (not a failure).
const MEAN_LIMIT_MS: float = 5.0
const STEP_LIMIT_MS: float = 100.0
## Staffs the run must include per feature, so the rare shapes are really reached.
const MIN_COVERAGE: Dictionary = {"payload": 20, "multicast": 10, "fallback": 10, "wrapped": 20, "wasted": 20}
## The costliest staffs named on the FUZZ line.
const COSTLIEST: int = 3
## Staffs named on each REPORT line of the emergent combo report.
const REPORT_TOP: int = 5
## Health of the imps in this run: low enough that a good staff kills some within `SECONDS`.
const IMP_HEALTH: float = 60.0

var _log: Logger = ErrorLogScript.new()


func _bag(arena: ArenaScript) -> Array[StringName]:
	var bag: Array[StringName] = []
	bag.assign(arena.registry.call("get_ids", &"spells"))
	return bag


func _fuzzer(arena: ArenaScript) -> FuzzerScript:
	return FuzzerScript.new(_bag(arena), func(id: StringName) -> StringName: return arena.spells.component_kind(id))


## True when the registry has a card of `kind`.
func _has_kind(kind: StringName) -> bool:
	var arena := ArenaScript.new(root)
	var found: bool = false
	for id in _bag(arena):
		found = found or arena.spells.component_kind(id) == kind
	arena.free_all()
	return found


## Imps in a ring and a line, so straight, orbit, still and chaining spells all meet some.
func _populate(arena: ArenaScript) -> void:
	for at: Vector2 in [Vector2(60, 0), Vector2(110, 20), Vector2(110, -20), Vector2(160, 0), Vector2(-50, 30), Vector2(0, 70), Vector2(0, -70)]:
		arena.add_imp(at, IMP_HEALTH)


## Which features a compiled staff has (0 or 1 each), under the keys of MIN_COVERAGE.
func _coverage(staff: CompiledStaff) -> Dictionary:
	var out: Dictionary = {"payload": 0, "multicast": 0, "fallback": 0, "wrapped": 0, "wasted": 0 if staff.wasted.is_empty() else 1}
	for cast in staff.casts:
		out["wrapped"] = maxi(int(out["wrapped"]), 1 if cast.wrapped else 0)
		if cast.group.spells.size() > 1:
			out["multicast"] = 1
	for spell in staff.nodes:
		if spell.payload != null:
			out["payload"] = 1
		if spell.fallback != CompiledSpell.FALLBACK_NONE:
			out["fallback"] = 1
	return out


func test_random_staffs_compile_and_cast_without_errors() -> void:
	OS.add_logger(_log)
	var arena := ArenaScript.new(root)
	var fuzzer: FuzzerScript = _fuzzer(arena)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var slowest_mean: float = 0.0
	var slowest_step: float = 0.0
	var peak: int = 0
	var dropped: int = 0
	var slow: Array[String] = []
	var coverage: Dictionary = {}
	## [peak live shots, label] of every staff, for the costliest.
	var costs: Array = []
	## One row per staff for the report (see `_report_row`).
	var rows: Array[Dictionary] = []
	for number in STAFFS:
		var cards: Array[StringName] = fuzzer.random_cards(rng, SLOTS)
		var label: String = "seed %d, staff %d %s" % [SEED, number, str(cards)]
		var staff: CompiledStaff = arena.spells.compile_staff(cards, ArenaScript.plain_staff(cards.size()))
		check(staff.casts.size() <= cards.size() + 1, "%s: %d casts from %d slots, the cycle runs away" % [label, staff.casts.size(), cards.size()])
		check(staff.nodes.size() <= SpellTag.NODE_MASK + 1, "%s: %d compiled spells, more than a tag holds" % [label, staff.nodes.size()])
		var fresh := ArenaScript.new(root)
		_populate(fresh)
		fresh.install_cards(0, 0, cards)
		check(fresh.cast(0, 0) or staff.casts[0].group.is_empty(), "%s: the first cast was refused" % label)
		var total: float = 0.0
		var steps: int = int(ceilf(SECONDS / ArenaScript.STEP))
		for i in steps:
			var started: int = Time.get_ticks_usec()
			fresh.run(ArenaScript.STEP)
			var took: float = float(Time.get_ticks_usec() - started) / 1000.0
			total += took
			slowest_step = maxf(slowest_step, took)
			if took > STEP_LIMIT_MS:
				slow.append("%s: a step took %.1f ms" % [label, took])
			if i % 10 == 0:
				fresh.cast(0, 0)
		var mean: float = total / float(steps)
		slowest_mean = maxf(slowest_mean, mean)
		if mean > MEAN_LIMIT_MS:
			slow.append("%s: a step took %.2f ms on average" % [label, mean])
		peak = maxi(peak, fresh.peak_shots)
		dropped += fresh.projectiles.dropped
		rows.append(_report_row(number, fresh, staff, label, mean))
		costs.append([fresh.peak_shots, label])
		var counted: Dictionary = _coverage(staff)
		for key: String in counted:
			coverage[key] = int(coverage.get(key, 0)) + int(counted[key])
		fresh.free_all()
	OS.remove_logger(_log)
	arena.free_all()
	for key: String in MIN_COVERAGE:
		# Multicast is only reached once a multicast card exists (the cards of staffs C).
		if key == "multicast" and not _has_kind(&"multicast"):
			continue
		check(int(coverage.get(key, 0)) >= int(MIN_COVERAGE[key]), "only %d staffs with %s (want %d); the fuzzer misses it" % [int(coverage.get(key, 0)), key, int(MIN_COVERAGE[key])])
	var lines: Array[String] = _log.call("get_lines")
	for line in lines:
		check(false, "the log has an error: " + line.trim_prefix("ERROR:").strip_edges())
	for line in slow:
		print("FUZZ WARNING (time depends on the machine, not a failure): " + line)
	costs.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	for i in mini(COSTLIEST, costs.size()):
		print("FUZZ COSTLY: %d live shots: %s" % [int(costs[i][0]), costs[i][1]])
	_print_report(rows)
	print("FUZZ:%d staffs, slowest mean step %.3f ms, slowest step %.3f ms, most live shots %d, shots dropped at the pool %d" % [STAFFS, slowest_mean, slowest_step, peak, dropped])


## The numbers of one staff's run for the report: its name (the first cast's, from its cards),
## the imps it killed, the reactions it set off (and how many kinds), its peak live shots, the
## shots the pool dropped and its mean step time.
func _report_row(number: int, arena: ArenaScript, staff: CompiledStaff, label: String, mean: float) -> Dictionary:
	var kills: int = 0
	for imp in arena.imps:
		kills += 1 if arena.died(imp) else 0
	var kinds: Dictionary = {}
	for id in arena.reaction_ids():
		kinds[id] = true
	var title: String = ""
	for cast in staff.casts:
		if not cast.spell_name.is_empty():
			title = cast.spell_name
			break
	return {"index": number, "label": label, "name": title, "kills": kills, "reactions": arena.reactions.size(), "kinds": kinds.size(), "shots": arena.peak_shots, "dropped": arena.projectiles.dropped, "safeguard": arena.projectiles.dropped * 1000 + arena.peak_shots, "mean": mean}


## The first `REPORT_TOP` of `rows` by `key`, biggest first. A tie goes to the lower staff
## `index`, so the order is total and a run repeats (`sort_custom` is not stable).
func _top(rows: Array[Dictionary], key: String) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	ranked.assign(rows)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a[key]) != float(b[key]):
			return float(a[key]) > float(b[key])
		return int(a["index"]) < int(b["index"]))
	return ranked.slice(0, REPORT_TOP)


## The emergent combo report (staffs D1): the best random staffs by kills and by reactions, the
## costliest by frame time and by shots dropped at the pool (the safeguard). A run's lines go
## into docs/LOG.md; frame times depend on the machine, the rest does not. Each line starts with
## the ranked value, then the staff's name and cards, then the other numbers.
func _print_report(rows: Array[Dictionary]) -> void:
	var views: Array = [
		["kills", "REPORT BEST BY KILLS", "%d kills"],
		["reactions", "REPORT BEST BY REACTIONS", "%d reactions"],
		["mean", "REPORT COSTLIEST BY FRAME TIME", "%.2f ms"],
		["safeguard", "REPORT COSTLIEST BY SAFEGUARDS", "%d (dropped x 1000 + peak shots)"],
	]
	for view: Array in views:
		var key: String = view[0]
		for row in _top(rows, key):
			var value: String = (view[2] as String) % (float(row[key]) if key == "mean" else int(row[key]))
			var title: String = row["name"] if not (row["name"] as String).is_empty() else "(unnamed)"
			print("%s: %s | %s | %s | %d kills, %d reactions (%d kinds), %d peak shots, %d dropped, %.2f ms" % [view[1], value, title, row["label"], int(row["kills"]), int(row["reactions"]), int(row["kinds"]), int(row["shots"]), int(row["dropped"]), float(row["mean"])])
	if not rows.is_empty() and int(_top(rows, "kills")[0]["kills"]) == 0:
		print("REPORT WARNING: no staff killed an imp; the imps' health (%s) may be too high for the cards" % IMP_HEALTH)


## The same seed gives the same staffs, which is what makes a failure replayable.
func test_same_seed_same_staffs() -> void:
	var arena := ArenaScript.new(root)
	var fuzzer: FuzzerScript = _fuzzer(arena)
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 7
	second.seed = 7
	for i in 20:
		check(fuzzer.random_cards(first, SLOTS) == fuzzer.random_cards(second, SLOTS), "staff %d repeats with the same seed" % i)
	arena.free_all()


## A random staff always holds a carrier when the bag has one, so a bot's staff fires.
func test_a_random_staff_has_a_carrier() -> void:
	var arena := ArenaScript.new(root)
	var fuzzer: FuzzerScript = _fuzzer(arena)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in 50:
		var has_form: bool = false
		for id in fuzzer.random_cards(rng, SLOTS):
			has_form = has_form or arena.spells.component_kind(id) == &"form"
		check(has_form, "staff %d has a carrier" % i)
	check(not FuzzerScript.new([&"fire"] as Array[StringName], func(_id: StringName) -> StringName: return &"element").can_build(), "no carrier in the bag, no build")
	arena.free_all()


## More tied staffs than the report holds: the lowest indexes are named, in order, however the rows come.
func test_report_ties_are_total() -> void:
	var rows: Array[Dictionary] = []
	for i in 40:
		rows.append({"index": 39 - i, "kills": 0, "label": str(39 - i)})
	var top: Array[Dictionary] = _top(rows, "kills")
	for i in REPORT_TOP:
		check(int(top[i]["index"]) == i, "tied staffs are named by index: place %d is staff %d" % [i, int(top[i]["index"])])


## The report ranks biggest first, breaks a tie by the lower staff index and names at most REPORT_TOP.
func test_report_ranking() -> void:
	var rows: Array[Dictionary] = []
	for i in 8:
		rows.append({"index": i, "kills": i % 3, "label": str(i)})
	var top: Array[Dictionary] = _top(rows, "kills")
	check(top.size() == REPORT_TOP, "the report names %d staffs" % REPORT_TOP)
	check(top[0]["label"] == "2" and top[1]["label"] == "5", "ties keep the staff order")
	check(int(top[REPORT_TOP - 1]["kills"]) >= 1, "the smallest are left out")
