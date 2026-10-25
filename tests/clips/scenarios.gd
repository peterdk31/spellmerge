extends RefCounted
## The clip scenarios (#245), read from the content so a new row or component is a new clip
## with no code change: one per row of `content/spells/combos.json`, one per component (a form,
## an element, a modifier or a trigger alone), one per element reaction in `reactions.tres`,
## and a co-op version of each reaction with two players.
##
## A scenario is a Dictionary: `id` (the clip's folder name, `^[a-z0-9_]{1,60}$`), `kind` (one
## of the kinds in ci/smbot/clips.py), `title`, `imps` (Vector2s, from the caster at (0, 0)),
## `casts` (each `player`, `slot`, `recipe`, `at` seconds, `origin` and `aim`) and `seconds`.
## Ids: `combo_<id>`, `<kind>_<id>` for a component (`element_fire`), `reaction_<id>` and
## `reaction_<id>_coop`. The kind prefix keeps the combo "shatter" and the reaction "shatter"
## apart.

const COMBOS: String = "res://content/spells/combos.json"
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


## Every scenario for `registry` (a scanned Registry), `spells` (a Spells node that knows it:
## component names and kinds are asked of it, never read from the components), `combos` (the
## rows of combos.json) and `table` (the ReactionTable), in a stable order.
static func build(registry: Node, spells: Node, combos: Array, table: ReactionTable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for combo: Dictionary in combos:
		out.append(_combo(combo))
	for id: StringName in registry.call("get_ids", &"spells"):
		out.append(_component(id, spells.call("component_kind", id) as StringName, spells.call("component_name", id) as String))
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


## The combo rows of the catalogue file (empty when it can't be read).
static func read_combos() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(COMBOS))
	if parsed is Dictionary and (parsed as Dictionary).get("combos") is Array:
		return (parsed as Dictionary)["combos"] as Array
	return []


## True when `id` is a folder name the pipeline accepts.
static func valid_id(id: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile(ID_PATTERN)
	return pattern.search(id) != null


static func _combo(combo: Dictionary) -> Dictionary:
	var imps: Array[Vector2] = []
	for at: Array in combo.get("imps", []):
		imps.append(Vector2(float(at[0]), float(at[1])))
	var casts: Array[Dictionary] = []
	for entry: Dictionary in combo.get("casts", []):
		casts.append(_cast(int(entry.get("player", 0)), int(entry["slot"]), entry["recipe"] as Dictionary, float(entry.get("at", 0.0))))
	return _scenario("combo_" + str(combo["id"]), "combo", str(combo.get("name", combo["id"])), imps, casts, float(combo.get("seconds", 1.0)))


static func _component(id: StringName, kind: StringName, title: String) -> Dictionary:
	var recipe: Dictionary = {"form": &"bolt"}
	match kind:
		&"form":
			recipe = {"form": id}
		&"element":
			recipe["element"] = id
		&"modifier":
			recipe["modifiers"] = [id]
		&"trigger":
			recipe["trigger"] = id
			recipe["held"] = {"form": &"nova"}
	var casts: Array[Dictionary] = [_cast(0, 0, recipe, 0.0)]
	return _scenario("%s_%s" % [kind, id], str(kind), title if title != "" else String(id), SPREAD_IMPS, casts, COMPONENT_SECONDS)


## A reaction made by two real bolts: the first (of element `first`) puts the status on, the
## second (of the row's element) sets it off. In co-op the two bolts come from two players.
static func _reaction(row: ReactionRow, first: StringName, coop: bool) -> Dictionary:
	var recipes: Array[Dictionary] = [{"form": &"bolt", "element": first}, {"form": &"bolt", "element": row.element_id}]
	var casts: Array[Dictionary] = []
	for i in 2:
		var entry: Dictionary = _cast(i if coop else 0, i, recipes[i], float(i) * REACTION_GAP)
		if coop:
			entry["origin"] = COOP_ORIGINS[i]
			entry["aim"] = (SPREAD_IMPS[0] - COOP_ORIGINS[i]).normalized()
		casts.append(entry)
	var name: String = String(row.reaction_id).capitalize()
	var id: String = "reaction_" + String(row.reaction_id) + ("_coop" if coop else "")
	return _scenario(id, "reaction", name + (" (co-op)" if coop else ""), SPREAD_IMPS, casts, REACTION_SECONDS)


static func _cast(player: int, slot: int, recipe: Dictionary, at: float) -> Dictionary:
	return {"player": player, "slot": slot, "recipe": recipe, "at": at, "origin": Vector2.ZERO, "aim": Vector2.RIGHT}


static func _scenario(id: String, kind: String, title: String, imps: Array[Vector2], casts: Array[Dictionary], seconds: float) -> Dictionary:
	return {"id": id, "kind": kind, "title": title, "imps": imps, "casts": casts, "seconds": clampf(seconds, 0.5, MAX_SECONDS)}
