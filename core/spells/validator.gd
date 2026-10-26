class_name SpellValidator
extends RefCounted
## The content validator for spell components and the reaction table (M2 part 9). It reads
## nothing from disk except the art manifest and holds no state: hand it the components
## the registry found and it returns the problems, so a test, the registry in a debug
## build and a contributor's agent all get the same answer.
##
## A problem is a Dictionary with the same four parts as `tools/check.sh`: `rule` (a short
## slug), `file` (the resource path), `field` (what is wrong in it) and `fix` (what to do).
## `format()` turns one into a line.
##
##     var problems: Array[Dictionary] = SpellValidator.check_all(
##             Registry.get_all(&"spells"), reactions, SpellValidator.load_manifest())
##     for problem in problems:
##         push_warning(SpellValidator.format(problem))
##
## What it checks, per component: `id` set and equal to the folder name; a name; an icon that
## is listed in the art manifest; every number inside `ranges()` (which keeps a component's
## `complexity` to 1-4, well inside the whole-spell budget); and the fields its kind needs (a form's speed, orbit radius or ray
## length for its motion; an element's known status and duration; a modifier's strength
## for its behaviour; a timer trigger's interval). Across the list: no id twice. For the
## reaction table: each row names a known status, an existing element and a real effect,
## has the numbers its effect uses, and no pair of status and element is listed twice.

## The art manifest, whose `assets[].path` lists every icon.
const MANIFEST_PATH: String = "res://art/manifest.json"

## The statuses an element may put on a target. `freeze` is not here: three stacks of chill
## make it, no element sets it. `tests/content/spells/test_validators.gd` checks this list
## against the ones `gameplay/combat` implements.
const KNOWN_STATUSES: Array[StringName] = [&"burn", &"chill", &"shock", &"hex", &"static"]

## Allowed numbers of a reaction row, {field: Vector2(min, max)}, both ends included.
const REACTION_RANGES: Dictionary = {
	"damage": Vector2(0, 200),
	"radius": Vector2(0.0, 256.0),
	"duration": Vector2(0.0, 30.0),
	"strength": Vector2(0.0, 100.0),
	"pull": Vector2(0.0, 2000.0),
	# The last effect; test_validators.gd fails when an effect is added after it.
	"effect": Vector2(0, ReactionRow.Effect.SPREAD),
}


## The `path` of every asset in the manifest, as {path: true}. Empty when the file is missing
## or is not a manifest, so every icon then reports as unlisted.
static func load_manifest(path: String = MANIFEST_PATH) -> Dictionary:
	var listed: Dictionary = {}
	if not FileAccess.file_exists(path):
		return listed
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return listed
	var assets: Variant = (parsed as Dictionary).get("assets")
	if not (assets is Array):
		return listed
	for asset: Variant in assets:
		if asset is Dictionary and (asset as Dictionary).get("path") is String:
			listed[(asset as Dictionary)["path"]] = true
	return listed


## Every problem in `resources` (resources that are not spell components are skipped), in `reactions` (null skips the table), and in the duplicate
## ids the registry reported while scanning (`duplicates`: one line each, naming the id and
## both files).
static func check_all(resources: Array[Resource], reactions: ReactionTable, manifest: Dictionary, duplicates: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var components: Array[SpellComponent] = []
	for resource in resources:
		if resource is SpellComponent:
			components.append(resource as SpellComponent)
	var problems: Array[Dictionary] = check_components(components, manifest)
	for duplicate in duplicates:
		problems.append(_problem("unique-id", "content/spells", "id", "Duplicate id (%s). Ids are unique across forms, elements, modifiers and triggers; rename one." % duplicate))
	if reactions != null:
		var element_ids: Array[StringName] = []
		for component in components:
			if component is ElementBase and component.id != &"":
				element_ids.append(component.id)
		problems.append_array(check_reactions(reactions, element_ids))
	return problems


## The problems of each component and the ids used twice in the list. The registry keeps
## only the first file per id, so in the game duplicates arrive through `check_all`'s
## `duplicates` instead; this check is for a list that holds both.
static func check_components(components: Array[SpellComponent], manifest: Dictionary) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	var seen: Dictionary = {}
	for component in components:
		problems.append_array(check_component(component, manifest))
		if component.id == &"":
			continue
		if seen.has(component.id):
			problems.append(_problem("unique-id", component.resource_path, "id", "'%s' is also the id of %s. Ids are unique across all four kinds; rename one." % [component.id, seen[component.id]]))
		else:
			seen[component.id] = component.resource_path
	return problems


## The problems of one component on its own.
static func check_component(component: SpellComponent, manifest: Dictionary) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	var file: String = component.resource_path
	var folder: String = file.get_base_dir().get_file()
	if component.id == &"":
		problems.append(_problem("required-field", file, "id", "Set `id` to the folder name ('%s')." % folder))
	elif String(component.id) != folder:
		problems.append(_problem("id-folder", file, "id", "`id` is '%s' but the folder is '%s'. Rename one so they match." % [component.id, folder]))
	if component.display_name.strip_edges() == "":
		problems.append(_problem("required-field", file, "display_name", "Give it a name for the builder, for example \"Frost\"."))
	if component.icon == null:
		problems.append(_problem("icon", file, "icon", "Add a 16x16 icon.svg to the folder and set `icon` to it."))
	else:
		var icon_path: String = component.icon.resource_path
		if icon_path == "" or not manifest.has(icon_path.trim_prefix("res://")):
			problems.append(_problem("icon-manifest", file, "icon", "Add a line for '%s' to art/manifest.json (path, origin, author, license)." % icon_path.trim_prefix("res://")))
	for line in component.range_problems():
		var field: String = line.get_slice(":", 0)
		problems.append(_problem("range", file, field, "%s. Change it to a value inside the range (documented next to the field)." % line))
	if component is FormBase:
		problems.append_array(_check_form(component as FormBase))
	elif component is ElementBase:
		problems.append_array(_check_element(component as ElementBase))
	elif component is ModifierBase:
		problems.append_array(_check_modifier(component as ModifierBase))
	elif component is TriggerBase:
		problems.append_array(_check_trigger(component as TriggerBase))
	return problems


## The problems of the reaction table's rows. `element_ids` are the ids of the elements
## that exist.
static func check_reactions(table: ReactionTable, element_ids: Array[StringName]) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	var file: String = table.resource_path
	var pairs: Dictionary = {}
	for i in table.rows.size():
		var row: ReactionRow = table.rows[i]
		var where: String = "rows[%d]" % i
		if row == null:
			problems.append(_problem("reaction-row", file, where, "The row is empty. Remove it or fill it in."))
			continue
		if row.reaction_id == &"":
			problems.append(_problem("required-field", file, where + ".reaction_id", "Name the reaction, for example &\"shatter\"."))
		else:
			where = "%s (%s)" % [where, row.reaction_id]
		if row.display_name.strip_edges() == "":
			problems.append(_problem("required-field", file, where + ".display_name", "Give the reaction a name for the builder."))
		if not KNOWN_STATUSES.has(row.status_id):
			problems.append(_problem("unknown-status", file, where + ".status_id", "'%s' is not a status combat knows. Use one of: %s." % [row.status_id, _join(KNOWN_STATUSES)]))
		if not element_ids.has(row.element_id):
			problems.append(_problem("reaction-element", file, where + ".element_id", "No element has the id '%s'. Use an element's id or add the element." % row.element_id))
		var pair: String = "%s+%s" % [row.status_id, row.element_id]
		if pairs.has(pair):
			problems.append(_problem("reaction-pair", file, where, "Status '%s' and element '%s' already react in %s. A pair has one row." % [row.status_id, row.element_id, pairs[pair]]))
		else:
			pairs[pair] = "rows[%d]" % i
		for field: String in REACTION_RANGES:
			var bounds: Vector2 = REACTION_RANGES[field]
			var value: float = float(row.get(field))
			if value < bounds.x or value > bounds.y:
				var rule: String = "unknown-effect" if field == "effect" else "range"
				problems.append(_problem(rule, file, "%s.%s" % [where, field], "%s: %s is outside [%s, %s]. Change it." % [field, str(row.get(field)), str(bounds.x), str(bounds.y)]))
		problems.append_array(_check_row_effect(row, file, where))
	return problems


## One line for a problem: "rule: file: field: fix".
static func format(problem: Dictionary) -> String:
	return "%s: %s: %s: %s" % [problem["rule"], problem["file"], problem["field"], problem["fix"]]


static func _check_form(form: FormBase) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	var file: String = form.resource_path
	match form.motion:
		FormBase.Motion.STRAIGHT:
			if form.speed <= 0.0:
				problems.append(_problem("required-field", file, "speed", "A STRAIGHT form needs a `speed` above 0."))
		FormBase.Motion.ORBIT:
			if form.orbit_radius <= 0.0:
				problems.append(_problem("required-field", file, "orbit_radius", "An ORBIT form needs an `orbit_radius` above 0."))
		FormBase.Motion.RAY:
			if form.ray_length <= 0.0:
				problems.append(_problem("required-field", file, "ray_length", "A RAY form needs a `ray_length` above 0."))
	return problems


static func _check_element(element: ElementBase) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	var file: String = element.resource_path
	if element.status_id != &"":
		if not KNOWN_STATUSES.has(element.status_id):
			problems.append(_problem("unknown-status", file, "status_id", "'%s' is not a status combat knows. Use one of: %s, or leave it empty." % [element.status_id, _join(KNOWN_STATUSES)]))
		if element.status_duration <= 0.0:
			problems.append(_problem("required-field", file, "status_duration", "An element with a status needs a `status_duration` above 0, or it does nothing."))
	return problems


static func _check_modifier(modifier: ModifierBase) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	if modifier.behaviour != ModifierBase.Behaviour.NONE and modifier.behaviour_strength <= 0.0:
		problems.append(_problem("required-field", modifier.resource_path, "behaviour_strength", "HOMING (turn rate) and CHAIN (jumps) need a `behaviour_strength` above 0."))
	return problems


static func _check_trigger(trigger: TriggerBase) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	if trigger.event == TriggerBase.Event.TIMER and trigger.interval < SpellLimits.MIN_TIMER_INTERVAL:
		problems.append(_problem("required-field", trigger.resource_path, "interval", "A TIMER trigger needs an `interval` of at least %s seconds." % str(SpellLimits.MIN_TIMER_INTERVAL)))
	return problems


static func _check_row_effect(row: ReactionRow, file: String, where: String) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	match row.effect:
		ReactionRow.Effect.BURST, ReactionRow.Effect.SPREAD:
			if row.radius <= 0.0:
				problems.append(_problem("required-field", file, where + ".radius", "This effect works in a circle: set `radius` above 0."))
		ReactionRow.Effect.CONSUME:
			if row.damage <= 0:
				problems.append(_problem("required-field", file, where + ".damage", "CONSUME deals bonus damage: set `damage` above 0."))
		ReactionRow.Effect.EXTEND:
			if row.duration <= 0.0:
				problems.append(_problem("required-field", file, where + ".duration", "EXTEND lengthens the status: set `duration` above 0."))
	return problems


static func _problem(rule: String, file: String, field: String, fix: String) -> Dictionary:
	return {"rule": rule, "file": file, "field": field, "fix": fix}


static func _join(names: Array[StringName]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for name in names:
		parts.append(String(name))
	return ", ".join(parts)
