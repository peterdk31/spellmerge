extends "res://tests/support/suite.gd"
## The combo catalogue in content/spells/combos/ (M2 part 14; one file per combo since staffs
## A2): every named combo is built from the real components, cast in the test arena
## (`combo_arena.gd`: real registry, spell runtime, projectile manager and combat, with imps)
## and must do what it promises. One data-driven test per check kind runs over every combo, so
## a new combo file is covered without a new test.
##
## A combo file: `id` (also the file name), `name`, `does` (plain words), `casts` (`staff`,
## `cards`: one card id per slot, read as a staff reads them; optional `at` seconds, `player`, `dir` [x, y] to cast toward), `imps` ([x, y] from the caster at (0, 0), aiming
## along +x), optional `mates` ([x, y, player]: a teammate's body that shots hit, for `relay`), optional `walls` ([x, y, width, height] rects), optional `pushed` (true: imps move with the push combat gives them, for `magnet`), optional `guard` (true: the caster's own body stands at (0, 0), so a barrier on it works) and `foes` ([x, y] each: an enemy shot sent from there at the caster, which needs a `guard`), optional `allies` ([x, y, player]: a teammate's wizard body that heals and damage reach), `hurt` (health each wizard body, the `guard` and the `allies`, has lost before the casts, so a heal has room) and `seconds` and `checks`. Check kinds: `damaged` (imps), `status` (imps, status),
## `status_count` (status, min), `lost_at_least` (imps, min: health lost in all), `keeps_burning` (imp), `reaction` (reaction), `max_shots` (max),
## `caster_moved` (mode: a card moved its caster, for example a dash), `blocked` (min: enemy shots a barrier or a shielded shot stopped), `healed` (min: health heals gave wizard bodies), `lost_at_most` (imps, max: health each imp lost, for a hit that should barely hurt).
##
## godot --headless --path . --script res://tests/content/spells/test_combos.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")
const MIN_COMBOS: int = 20
const CHECK_KINDS: Array[String] = ["damaged", "status", "status_count", "keeps_burning", "reaction", "max_shots", "caster_moved", "lost_at_least", "blocked", "healed", "lost_at_most", "killed"]

var _combos: Array = []
## Files of the catalogue that are not a JSON object.
var _unreadable: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_unreadable = PackedStringArray()
	_combos = ComboFiles.read_all(ComboFiles.FOLDER, _unreadable)


## Builds the arena for `combo`, casts it as the row says and runs it. The caller frees it.
## With `quiet`, a staff that casts nothing or a cast that is refused is not a failure (the
## control runs below drop a card on purpose).
func _play(combo: Dictionary, quiet: bool = false) -> ArenaScript:
	var arena := ArenaScript.new(root)
	arena.pushable = bool(combo.get("pushed", false))
	for at: Array in combo.get("imps", []):
		arena.add_imp(Vector2(float(at[0]), float(at[1])), int(at[2]) if at.size() > 2 else ArenaScript.IMP_HEALTH)
	for mate: Array in combo.get("mates", []):
		arena.add_mate(Vector2(float(mate[0]), float(mate[1])), int(mate[2]))
	for rect: Array in combo.get("walls", []):
		arena.add_wall(Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])))
	if bool(combo.get("guard", false)):
		arena.add_guard(0, Vector2.ZERO)
	for ally: Array in combo.get("allies", []):
		arena.add_guard(int(ally[2]), Vector2(float(ally[0]), float(ally[1])))
	for body: Node2D in arena.bodies:
		arena.hurt(body, int(combo.get("hurt", 0)))
	for foe: Array in combo.get("foes", []):
		arena.shoot_at(Vector2(float(foe[0]), float(foe[1])), Vector2.ZERO)
	var casts: Array = (combo.get("casts", []) as Array).duplicate()
	for entry: Dictionary in casts:
		var built: CompiledStaff = arena.install_cards(int(entry.get("player", 0)), int(entry["staff"]), entry["cards"] as Array)
		if not quiet:
			check(not built.is_empty(), "%s: the staff casts something" % combo["id"])
	casts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))
	var seconds: float = float(combo.get("seconds", 1.0))
	for entry: Dictionary in casts:
		var at: float = float(entry.get("at", 0.0))
		if at > arena.time:
			arena.run(at - arena.time)
		var dir: Array = entry.get("dir", [1, 0])
		var made: bool = arena.cast(int(entry.get("player", 0)), int(entry["staff"]), Vector2(float(dir[0]), float(dir[1])))
		if not quiet:
			check(made, "%s: the cast of staff %d is made" % [combo["id"], int(entry["staff"])])
	arena.run(maxf(seconds - arena.time, 0.0))
	return arena


## Every combo's failures for one check, as text; empty when it holds.
func _problem_with(arena: ArenaScript, check_row: Dictionary) -> String:
	var kind: String = check_row["kind"]
	match kind:
		"damaged":
			for index: int in check_row["imps"]:
				if arena.lost(arena.imps[index]) <= 0:
					return "imp %d was not hurt" % index
		"status":
			for index: int in check_row["imps"]:
				if not arena.was_given(arena.imps[index], StringName(check_row["status"])):
					return "imp %d never got %s" % [index, check_row["status"]]
		"status_count":
			var count: int = 0
			for imp in arena.imps:
				if arena.was_given(imp, StringName(check_row["status"])):
					count += 1
			if count < int(check_row["min"]):
				return "%d imps got %s, wanted %d" % [count, check_row["status"], int(check_row["min"])]
		"lost_at_least":
			for index: int in check_row["imps"]:
				var lost: int = arena.lost(arena.imps[index])
				if lost < int(check_row["min"]):
					return "imp %d lost %d, wanted %d" % [index, lost, int(check_row["min"])]
		"keeps_burning":
			var imp: Node2D = arena.imps[int(check_row["imp"])]
			var at_hit: int = arena.lost_when_given(imp, &"burn")
			if at_hit < 0:
				return "the imp never burned"
			if arena.lost(imp) <= at_hit:
				return "the imp lost nothing after the hit (%d)" % at_hit
		"reaction":
			if not arena.reaction_ids().has(StringName(check_row["reaction"])):
				return "no %s reaction, saw %s" % [check_row["reaction"], arena.reaction_ids()]
		"max_shots":
			if arena.peak_shots > int(check_row["max"]):
				return "%d shots at once, over %d" % [arena.peak_shots, int(check_row["max"])]
		"caster_moved":
			var moved: bool = false
			for move: Array in arena.caster_moves:
				moved = moved or move[1] == StringName(check_row["mode"])
			if not moved:
				return "no %s moved the caster, saw %s" % [check_row["mode"], arena.caster_moves]
		"healed":
			if arena.healed() < int(check_row["min"]):
				return "heals gave %d health, wanted %d" % [arena.healed(), int(check_row["min"])]
		"lost_at_most":
			for index: int in check_row["imps"]:
				var lost_most: int = arena.lost(arena.imps[index])
				if lost_most > int(check_row["max"]):
					return "imp %d lost %d, over %d" % [index, lost_most, int(check_row["max"])]
		"killed":
			for index: int in check_row["imps"]:
				if not arena.died(arena.imps[index]):
					return "imp %d is still alive" % index
		"blocked":
			if arena.blocks.size() < int(check_row["min"]):
				return "%d enemy shots blocked, wanted %d" % [arena.blocks.size(), int(check_row["min"])]
		_:
			return "unknown check kind %s" % kind
	return ""


# --- The catalogue ----------------------------------------------------------

func test_the_catalogue_has_twenty_combos() -> void:
	check(_combos.size() >= MIN_COMBOS, "at least %d combos (got %d)" % [MIN_COMBOS, _combos.size()])


func test_every_component_is_in_two_combos() -> void:
	var uses: Dictionary = {}
	for combo: Dictionary in _combos:
		var in_combo: Dictionary = {}
		for entry: Dictionary in combo["casts"]:
			for id: StringName in _card_ids(entry):
				in_combo[id] = true
		for id: StringName in in_combo:
			uses[id] = int(uses.get(id, 0)) + 1
	# Every component the registry finds, so a new card folder is checked with no list to edit.
	var arena := ArenaScript.new(root)
	var known: Array[StringName] = arena.registry.call("get_ids", &"spells")
	arena.free_all()
	check(known.size() > 0, "the registry finds the spell components")
	for component: StringName in known:
		var count: int = int(uses.get(component, 0))
		check(count >= 2, "%s is in at least two combos (got %d): add combo files for it in content/spells/combos/" % [component, count])


func test_every_combo_file_is_an_object_named_like_its_id() -> void:
	check(_unreadable.is_empty(), "every combo file is a JSON object (not: %s)" % ", ".join(_unreadable))
	var ids: PackedStringArray = ComboFiles.file_ids()
	check_equal(ids.size(), _combos.size() + _unreadable.size(), "one combo per file")
	for combo: Dictionary in _combos:
		var id: String = str(combo.get("id", ""))
		check(ids.has(id), "the combo %s is in content/spells/combos/%s.json" % [id, id])


func test_every_row_has_its_fields_and_an_unseen_id() -> void:
	var seen: Dictionary = {}
	for combo: Dictionary in _combos:
		var id: String = combo.get("id", "")
		check(id != "", "a combo has an id")
		check(not seen.has(id), "%s: the id is used once" % id)
		seen[id] = true
		check(str(combo.get("name", "")) != "", "%s has a name" % id)
		check(str(combo.get("does", "")) != "", "%s says what it does" % id)
		check((combo.get("casts", []) as Array).size() > 0, "%s has a cast" % id)
		check((combo.get("checks", []) as Array).size() > 0, "%s has a check" % id)
		for row: Dictionary in combo.get("checks", []):
			check(CHECK_KINDS.has(str(row.get("kind", ""))), "%s: check kind %s is known" % [id, row.get("kind")])
			for index: Variant in row.get("imps", []):
				check(int(index) >= 0 and int(index) < (combo.get("imps", []) as Array).size(), "%s: check imp %s is one of the combo's imps" % [id, index])
		if combo.has("hurt"):
			check(bool(combo.get("guard", false)) or (combo.get("allies", []) as Array).size() > 0, "%s: hurt needs a guard or allies to apply to" % id)


func test_every_staff_casts_something() -> void:
	var arena := ArenaScript.new(root)
	for combo: Dictionary in _combos:
		for entry: Dictionary in combo["casts"]:
			var ids: Array[StringName] = _card_ids(entry)
			var compiled: CompiledStaff = arena.spells.compile_staff(ids, ArenaScript.plain_staff(ids.size()))
			check(not compiled.is_empty(), "%s: the staff casts something" % combo["id"])
	arena.free_all()


func test_the_card_ids_are_real_cards() -> void:
	var arena := ArenaScript.new(root)
	for combo: Dictionary in _combos:
		for entry: Dictionary in combo["casts"]:
			for id in _card_ids(entry):
				check(arena.registry.call("get_resource", &"spells", id) != null, "%s: the registry knows %s" % [combo["id"], id])
	arena.free_all()


## The card ids of one cast entry, empty slots left out.
func _card_ids(entry: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: Variant in entry.get("cards", []):
		if str(id) != "":
			ids.append(StringName(str(id)))
	return ids


# --- Each combo does what it promises ---------------------------------------

func test_every_combo_does_what_it_promises() -> void:
	for combo: Dictionary in _combos:
		var arena: ArenaScript = _play(combo)
		for row: Dictionary in combo["checks"]:
			var problem: String = _problem_with(arena, row)
			check(problem == "", "%s (%s): %s" % [combo["id"], combo["does"], problem])
		arena.free_all()


## Rows whose point is one card: with it dropped, some check of the row must fail.
const CONTROLS: Dictionary = {
	"storm_mine": "chain",
	"frost_carousel": "pierce",
	"quick_shock_ring": "faster",
	"seeking_frost_burst": "on_expire",
	"echo_double_tap": "echo",
	"echo_timer_nova": "echo",
	"burst_triple_bolt": "burst",
	"burst_nova_pulse": "burst",
	"scatter_nova_flurry": "scatter",
	"scatter_kindle_flurry": "scatter",
	"mirror_back_guard": "mirror",
	"mirror_frost_pincer": "mirror",
	"rain_nova_drop": "rain",
	"rain_frost_field": "rain",
	"fissure_fire_line": "fissure",
	"fissure_hit_nova": "fissure",
	"wall_fire_barrier": "wall",
	"wall_frost_row": "wall",
	"relay_teammate_frost": "relay",
	"relay_teammate_fire": "relay",
	"shield_dash": "shield",
	"shield_teleport": "shield",
	"hook_pull": "hook",
	"hook_and_fire": "hook",
	"shield_wall_fire": "shield",
	"shield_orbit_ring": "shield",
	"blast_rocket": "blast",
	"blast_wall_burst": "blast",
	"mend_blast_self": "mend",
	"mend_pierce_party": "mend",
}


## The cards with every copy of `card` taken out (its slots dropped, so the rest reads as before).
func _without(cards: Array, card: String) -> Array:
	var out: Array = []
	for id: Variant in cards:
		if str(id) != card:
			out.append(id)
	return out


func test_a_combo_row_fails_without_the_component_it_is_for() -> void:
	for combo: Dictionary in _combos:
		if not CONTROLS.has(combo["id"]):
			continue
		var plain: Dictionary = combo.duplicate(true)
		for entry: Dictionary in plain["casts"]:
			entry["cards"] = _without(entry["cards"] as Array, CONTROLS[combo["id"]])
		var arena: ArenaScript = _play(plain, true)
		var failed: bool = false
		for row: Dictionary in combo["checks"]:
			failed = failed or _problem_with(arena, row) != ""
		check(failed, "%s: its checks fail without %s" % [combo["id"], CONTROLS[combo["id"]]])
		arena.free_all()
	for id: String in CONTROLS:
		var found: bool = false
		for combo: Dictionary in _combos:
			found = found or combo["id"] == id
		check(found, "the control row %s exists" % id)


func test_a_combo_check_that_fails_is_reported() -> void:
	# The checks themselves can fail: an imp no shot reaches is not hurt.
	var arena := ArenaScript.new(root)
	arena.add_imp(Vector2(100.0, 400.0))
	arena.install_cards(0, 0, ["bolt"])
	arena.cast(0, 0)
	arena.run(1.5)
	check(_problem_with(arena, {"kind": "damaged", "imps": [0]}) != "", "a missed imp fails the damaged check")
	check(_problem_with(arena, {"kind": "reaction", "reaction": "shatter"}) != "", "no reaction fails the reaction check")
	check(_problem_with(arena, {"kind": "frobnicate"}) != "", "an unknown check kind fails")
	arena.free_all()


func test_a_plain_fan_misses_what_the_homing_fan_reaches() -> void:
	var arena := ArenaScript.new(root)
	var up: Node2D = arena.add_imp(Vector2(110.0, -60.0))
	var down: Node2D = arena.add_imp(Vector2(110.0, 60.0))
	arena.install_cards(0, 0, ["split", "bolt"])
	check(arena.cast(0, 0), "the plain fan is cast")
	arena.run(1.5)
	check_equal(arena.lost(up) + arena.lost(down), 0, "without homing the fan flies past both imps")
	arena.free_all()


func test_two_players_cast_their_combos_at_the_same_time() -> void:
	var arena := ArenaScript.new(root)
	var left: Node2D = arena.add_imp(Vector2(-100.0, 0.0))
	var right: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	arena.install_cards(0, 0, ["fire", "bolt"])
	arena.install_cards(1, 0, ["frost", "bolt"])
	check(arena.cast(0, 0, Vector2.RIGHT), "player 0 casts")
	check(arena.cast(1, 0, Vector2.LEFT), "player 1 casts")
	arena.run(1.0)
	check(arena.was_given(right, &"burn"), "player 0's fire reached the imp on the right")
	check(arena.was_given(left, &"chill"), "player 1's frost reached the imp on the left")
	check(not arena.was_given(left, &"burn") and not arena.was_given(right, &"chill"), "and nobody got the other player's element")
	arena.free_all()
