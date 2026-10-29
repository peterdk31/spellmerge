extends RefCounted
## The clip scenarios (#245), read from the content so a new row or component is a new clip
## with no code change: one per combo file in `content/spells/combos/`, one per component (a form,
## an element, a modifier or a trigger alone), one per element reaction in `reactions.tres`,
## and a co-op version of each reaction with two players.
##
## A scenario is a Dictionary: `id` (the clip's folder name, `^[a-z0-9_]{1,60}$`), `kind` (one
## of the kinds in ci/smbot/clips.py), `title`, `imps` (Vector2s, from the caster at (0, 0)),
## `casts` (each `player`, `staff`, `cards`: card ids by slot, `at` seconds, `origin` and `aim`)
## and `seconds`.
## Ids: `combo_<id>`, `<kind>_<id>` for a component (`element_fire`), `reaction_<id>` and
## `reaction_<id>_coop`. The kind prefix keeps the combo "shatter" and the reaction "shatter"
## apart.

const ComboFiles := preload("res://tests/support/combo_files.gd")
const REACTIONS: String = "res://content/spells/reactions.tres"
const ID_PATTERN: String = "^[a-z0-9_]{1,60}$"
## The longest a clip runs, in seconds (the recorder's frame cap follows from it).
const MAX_SECONDS: float = 8.0
## Where the imps stand for a component or a reaction: one in front and two behind it, so a
## chain, a split or a spread has something to reach.
const SPREAD_IMPS: Array[Vector2] = [Vector2(100.0, 0.0), Vector2(135.0, -38.0), Vector2(135.0, 38.0)]
const COMPONENT_SECONDS: float = 2.5
const REACTION_SECONDS: float = 1.6
## Seconds between the bolt that puts a status on and the one that sets the reaction off.
const REACTION_GAP: float = 0.3
## Where the two players of a co-op clip stand; both aim at the first imp.
const COOP_ORIGINS: Array[Vector2] = [Vector2(0.0, -28.0), Vector2(0.0, 28.0)]
## The four-player clips: where the wizards stand, the cards they all cast, how often and how long.
const FOUR_ORIGINS: Array[Vector2] = [Vector2(0.0, -42.0), Vector2(0.0, -14.0), Vector2(0.0, 14.0), Vector2(0.0, 42.0)]
const FOUR_PLAYER_CARDS: Array = [&"fire", &"frost", &"bigger", &"bolt"]
const CROWD_CARDS: Array = [&"fire", &"frost", &"lightning", &"split", &"nova"]
## The card a trigger's clip puts on its bolt, for a trigger whose event needs one (otherwise the
## compiler lists it as wasted, rules R2b).
const TRIGGER_NEEDS: Dictionary = {&"on_block": &"shield", &"on_reaction": &"fire"}
const FOUR_PLAYER_ROUNDS: int = 3
const FOUR_PLAYER_GAP: float = 0.6
const FOUR_PLAYER_SECONDS: float = 3.0


## Every scenario for `registry` (a scanned Registry), `spells` (a Spells node that knows it:
## component names and kinds are asked of it, never read from the components), `combos` (the
## combo rows, `read_combos()`) and `table` (the ReactionTable), in a stable order.
static func build(registry: Node, spells: Node, combos: Array, table: ReactionTable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for combo: Dictionary in combos:
		out.append(_combo(combo))
	for id: StringName in registry.call("get_ids", &"spells"):
		out.append(_component(id, spells.call("component_kind", id) as StringName, spells.call("component_name", id) as String))
	out.append(_four_players(FOUR_PLAYER_CARDS, "combo_four_players", "Four players, one card"))
	out.append(_four_players(CROWD_CARDS, "combo_spark_crowd", "Four players, a crowd of sparks"))
	var rows: Dictionary = {}
	for row in table.rows:
		if row != null:
			if not rows.has(row.reaction_id):
				rows[row.reaction_id] = []
			(rows[row.reaction_id] as Array).append(row)
	for reaction: StringName in rows:
		var pair: Array = rows[reaction]
		if pair.size() < 2:
			continue
		# A pair of elements reacts both ways: the other row's element puts the status on.
		var first: StringName = (pair[1] as ReactionRow).element_id
		out.append(_reaction(pair[0] as ReactionRow, first, false))
		out.append(_reaction(pair[0] as ReactionRow, first, true))
	return out


## Four wizards in a column, all aiming at the first imp, each casting the same cards twice
## (staffs B6b): a shot's look is told apart by its player at 1x (pillar 4), and a crowd of
## looked shots is where the spark pool thins the trails first.
static func _four_players(cards: Array, id: String, title: String) -> Dictionary:
	var casts: Array[Dictionary] = []
	for round_index in FOUR_PLAYER_ROUNDS:
		for player in 4:
			var entry: Dictionary = _cast(player, 0, cards, float(round_index) * FOUR_PLAYER_GAP)
			entry["origin"] = FOUR_ORIGINS[player]
			entry["aim"] = (SPREAD_IMPS[0] - FOUR_ORIGINS[player]).normalized()
			casts.append(entry)
	return _scenario(id, "combo", title, SPREAD_IMPS, casts, FOUR_PLAYER_SECONDS)


## The combo rows of the catalogue, one file each (empty when none can be read).
static func read_combos() -> Array:
	return ComboFiles.read_all()


static var _id_regex: RegEx = null


## True when `id` is a folder name the pipeline accepts.
static func valid_id(id: String) -> bool:
	if _id_regex == null:
		_id_regex = RegEx.new()
		_id_regex.compile(ID_PATTERN)
	return _id_regex.search(id) != null


static func _combo(combo: Dictionary) -> Dictionary:
	var imps: Array[Vector2] = []
	for at: Array in combo.get("imps", []):
		imps.append(Vector2(float(at[0]), float(at[1])))
	var casts: Array[Dictionary] = []
	for entry: Dictionary in combo.get("casts", []):
		casts.append(_cast(int(entry.get("player", 0)), int(entry["staff"]), entry["cards"] as Array, float(entry.get("at", 0.0))))
	return _scenario("combo_" + str(combo["id"]), "combo", str(combo.get("name", combo["id"])), imps, casts, float(combo.get("seconds", 1.0)))


static func _component(id: StringName, kind: StringName, title: String) -> Dictionary:
	# The card on a bolt: alone for a carrier, before the bolt for the others; a trigger fires a
	# nova (with the card its event needs on the bolt: a shield to block, an infusion to react),
	# a multicast pulls three bolts.
	var cards: Array = [id, &"bolt"]
	match kind:
		&"form":
			cards = [id]
		&"trigger":
			cards = [id, &"bolt", &"nova"]
			if TRIGGER_NEEDS.has(id):
				cards.insert(1, TRIGGER_NEEDS[id])
		&"multicast":
			cards = [id, &"bolt", &"bolt", &"bolt"]
	var casts: Array[Dictionary] = [_cast(0, 0, cards, 0.0)]
	return _scenario("%s_%s" % [kind, id], str(kind), title if title != "" else String(id), SPREAD_IMPS, casts, COMPONENT_SECONDS)


## A reaction made by two real bolts: the first (of element `first`) puts the status on, the
## second (of the row's element) sets it off. In co-op the two bolts come from two players.
static func _reaction(row: ReactionRow, first: StringName, coop: bool) -> Dictionary:
	var rows: Array = [[first, &"bolt"], [row.element_id, &"bolt"]]
	var casts: Array[Dictionary] = []
	for i in 2:
		var entry: Dictionary = _cast(i if coop else 0, i, rows[i] as Array, float(i) * REACTION_GAP)
		if coop:
			entry["origin"] = COOP_ORIGINS[i]
			entry["aim"] = (SPREAD_IMPS[0] - COOP_ORIGINS[i]).normalized()
		casts.append(entry)
	var name: String = String(row.reaction_id).capitalize()
	var id: String = "reaction_" + String(row.reaction_id) + ("_coop" if coop else "")
	return _scenario(id, "reaction", name + (" (co-op)" if coop else ""), SPREAD_IMPS, casts, REACTION_SECONDS)


static func _cast(player: int, staff: int, cards: Array, at: float) -> Dictionary:
	return {"player": player, "staff": staff, "cards": cards, "at": at, "origin": Vector2.ZERO, "aim": Vector2.RIGHT}


static func _scenario(id: String, kind: String, title: String, imps: Array[Vector2], casts: Array[Dictionary], seconds: float) -> Dictionary:
	return {"id": id, "kind": kind, "title": title, "imps": imps, "casts": casts, "seconds": clampf(seconds, 0.5, MAX_SECONDS)}
