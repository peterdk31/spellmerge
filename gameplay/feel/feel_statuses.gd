class_name FeelStatuses
extends Object
## Feel's statuses and names: a status shown on its character until it ends (a following flash,
## its card's glow and motes), an element reaction's cue and rising name, a discharge's arc and a
## downed wizard's note. Methods working on Feel (`feel`), whose members hold all of it.

const FeelScript := preload("res://gameplay/feel/feel.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## Not Feel's own: Feel, the other jobs this one calls and Feel's containers it works on, each
## Feel's own (shared, never a copy), linked by `link`.
const LINKED: Array[StringName] = [&"feel", &"_job_cues", &"_job_flashes", &"_rng", &"_labels", &"_label_left", &"_label_total", &"_label_start", &"_status_enemies", &"_status_effect", &"_status_age", &"_status_shown", &"_status_next_poll", &"_status_cards", &"_reaction_cues", &"_reaction_names", &"_flash_kind", &"_flash_seconds", &"_flash_follow", &"_reaction_heard", &"_label_id"]

var feel: FeelScript = null
var _job_cues: FeelCues = null
var _job_flashes: FeelFlashes = null
var _rng: RandomNumberGenerator
var _labels: Array[Label]
var _label_left: PackedFloat32Array
var _label_total: PackedFloat32Array
var _label_start: PackedVector2Array
var _status_enemies: PackedInt64Array
var _status_effect: PackedInt32Array
var _status_age: PackedFloat32Array
var _status_shown: Array[StringName]
var _status_next_poll: PackedFloat32Array
var _status_cards: Dictionary
var _reaction_cues: Dictionary
var _reaction_names: Dictionary
var _flash_kind: PackedInt32Array
var _flash_seconds: PackedFloat32Array
var _flash_follow: Array[Node2D]
var _reaction_heard: Dictionary
var _label_id: Array[StringName]


## Takes Feel and its containers and jobs, by the names in LINKED (`Feel._link_jobs`).
func link(owner: FeelScript) -> void:
	feel = owner
	for name: StringName in LINKED:
		if name != &"feel":
			set(name, owner.get(name))


## A line of text rising from `position` for `seconds`, in a label slot of the reactions.
func _show_note(text: String, position: Vector2, tint: Color, seconds: float) -> void:
	var slot: int = feel._next_reaction
	feel._next_reaction = (feel._next_reaction + 1) % FeelScript.REACTION_SLOTS
	var label: Label = _labels[slot]
	label.text = text
	label.modulate = tint
	_label_start[slot] = position + Vector2(-label.get_minimum_size().x * 0.5, -22.0)
	label.global_position = _label_start[slot]
	label.visible = true
	_label_left[slot] = seconds
	_label_total[slot] = seconds
	_label_id[slot] = &"note"


## An element reaction fired at `position`: its cue (`reaction_<id>`, else `reaction`;
## content/cues: a puff, a ring and a ring of the reacting shot's motes in the reaction's own
## colour, a hold, shake and its sound, as strong as its `power`), and its name rising from the spot
## in that colour. The cue's weight (hold, shake, sound) comes at most every `CueBase.REACTION_REPEAT` seconds
## per reaction, its looks every time. The same for every player; it changes nothing in the fight.
func _on_reaction_triggered(caster: int, reaction_id: StringName, position: Vector2, shot: int) -> void:
	if not _reaction_names.has(reaction_id):
		_reaction_names[reaction_id] = String(reaction_id).capitalize()
	if not _reaction_cues.has(reaction_id) and feel.registry != null:
		_reaction_cues[reaction_id] = CueBase.reaction_cue(reaction_id, _job_cues.cue_of)
	var id: StringName = _reaction_cues.get(reaction_id, CueBase.REACTION_CUE) as StringName
	var heard: bool = feel._clock - (_reaction_heard.get(reaction_id, -CueBase.REACTION_REPEAT) as float) < CueBase.REACTION_REPEAT
	if not heard:
		_reaction_heard[reaction_id] = feel._clock
	# The reaction's own hit (kind `reaction`) holds its target by the plain rule; a hold only ever
	# lengthens, so whichever of the two comes first, the caster is held for the longer one.
	_job_cues.play_cue(id, caster, position, Vector2.ZERO, 0.0, Color.WHITE, feel.projectiles.get_look_of(shot) if feel.projectiles != null and shot >= 0 else 0, ActorsScript.NONE, shot, -1, 0, not heard)
	if _label_showing(reaction_id, position):
		return
	var cue: CueBase = _job_cues.cue_of(id)
	var slot: int = feel._next_reaction
	feel._next_reaction = (feel._next_reaction + 1) % FeelScript.REACTION_SLOTS
	var label: Label = _labels[slot]
	var shown: String = _reaction_names[reaction_id] as String
	if label.text != shown:
		label.text = shown
	label.modulate = cue.color if cue != null and cue.color.a > 0.0 else Color.WHITE
	_label_start[slot] = position + Vector2(-label.get_minimum_size().x * 0.5, -18.0)
	label.global_position = _label_start[slot]
	label.visible = true
	_label_left[slot] = FeelScript.REACTION_NAME_SECONDS
	_label_total[slot] = 0.0
	_label_id[slot] = reaction_id


## A discharge jumped from `from` to `to`: the cue `discharge_arc` from the one to the other, as
## long as the gap (a jagged line of lightning in the discharge's colour that burns out; its `arc`
## part, KIND_ARC).
func _on_discharge_arc(caster: int, from: Vector2, to: Vector2) -> void:
	_job_cues.play_cue(FeelScript.DISCHARGE_ARC, caster, from, to - from, from.distance_to(to))


## A character got a status: show it until combat says it has ended.
func _on_status_applied(_player: int, target: Node, _status_id: StringName) -> void:
	if target == null or not is_instance_valid(target) or feel.combat == null:
		return
	var id: int = target.get_instance_id()
	var known: int = _status_enemies.find(id)
	if known >= 0:
		# A new status on a shown character (a chill that froze it) changes the look at once.
		_status_shown[known] = _status_of(target)
		_pose_status(known)
		return
	if not target is Node2D or _status_enemies.size() >= FeelScript.STATUS_SLOTS:
		return
	_status_enemies.append(id)
	_status_effect.append(-1)
	_status_age.append(0.0)
	_status_shown.append(_status_of(target))
	_status_next_poll.append(FeelScript.STATUS_POLL)
	_pose_status(_status_enemies.size() - 1)


## Read the statuses now and then; end the flash of a status that ended.
func _step_statuses(real_delta: float) -> void:
	var at: int = _status_enemies.size() - 1
	while at >= 0:
		_status_age[at] += real_delta
		var enemy := instance_from_id(_status_enemies[at]) as Node
		var keep: bool = enemy != null and feel.combat != null
		if keep:
			if _status_age[at] >= _status_next_poll[at]:
				_status_next_poll[at] = _status_age[at] + FeelScript.STATUS_POLL
				var shown: StringName = _status_of(enemy)
				if shown != _status_shown[at]:
					_status_shown[at] = shown
					_end_status_effect(at)
			keep = _status_shown[at] != &""
		if keep:
			_pose_status(at)
		else:
			_end_status_effect(at)
			var last: int = _status_enemies.size() - 1
			_status_enemies[at] = _status_enemies[last]
			_status_effect[at] = _status_effect[last]
			_status_age[at] = _status_age[last]
			_status_shown[at] = _status_shown[last]
			_status_next_poll[at] = _status_next_poll[last]
			_status_enemies.resize(last)
			_status_effect.resize(last)
			_status_age.resize(last)
			_status_shown.resize(last)
			_status_next_poll.resize(last)
		at -= 1


## The status to show on `enemy` (the first of `status_order` it has), or empty for none.
func _status_of(enemy: Node) -> StringName:
	if not is_instance_valid(enemy):
		return &""
	for id in feel.preset.status_order:
		if (feel.combat.call("status_left", enemy, id) as float) > 0.0:
			return id
	return &""


## Keep status `at` shown: a flash that follows its character, a glow in its card's colour
## (`status_color`), started again if a crowd of other flashes took its slot. Hidden while the
## character's sprite is. Its motes are `_status_motes`'.
func _pose_status(at: int) -> void:
	var enemy := instance_from_id(_status_enemies[at]) as Node2D
	var card: Array = _status_card(_status_shown[at])
	var sprite: CanvasItem = null
	if enemy != null:
		sprite = enemy.get_node_or_null("Sprite") as CanvasItem
	if enemy == null or card.is_empty() or (sprite != null and not sprite.is_visible_in_tree()):
		_end_status_effect(at)
		return
	var slot: int = _status_effect[at]
	if slot >= 0 and slot < feel.effect_slots and _flash_seconds[slot] > 0.0 and _flash_follow[slot] == enemy:
		return
	var layer: int = card[ElementBase.STATUS_LOOK_LAYER] as int
	var bits: int = ProjectileManagerScript.pack_look(PackedInt32Array([layer])) if layer > 0 else 0
	_status_effect[at] = _job_flashes._show_flash(FeelScript.KIND_STATUS, enemy.global_position, Vector2.RIGHT, status_color(_status_shown[at]), 0, bits | FeelScript.EXACT, FeelScript.STATUS_ZOOM, FeelScript.FOREVER, 0.0, enemy)


## How status `id` is shown (spell spectacle 2, S6 item 11): the `status_look()` of the element
## card whose status it is, or for a status no element puts on (freeze), of the one whose status it
## deepens from (`FeelPreset.deep_statuses`): [status, tint, look layer, card id], ElementBase's
## STATUS_LOOK_*. Empty for none (an unknown status shows nothing). Found once in the registry's
## cards.
func _status_card(id: StringName) -> Array:
	var from: StringName = feel.preset.deep_statuses.get(id, id) as StringName
	if _status_cards.has(from):
		return _status_cards[from] as Array
	var found: Array = []
	if feel.registry != null and from != &"":
		for card: Resource in feel.registry.get_all(FeelScript.STATUS_CARD_FOLDER):
			if not card is ElementBase:
				continue
			var look: Array = (card as ElementBase).status_look()
			if look[ElementBase.STATUS_LOOK_STATUS] as StringName == from:
				found = look
				break
	_status_cards[from] = found
	return found


## Whether status `id` is shown at full depth (`FeelPreset.deep_statuses`: freeze).
func _status_deep(id: StringName) -> bool:
	return feel.preset.deep_statuses.has(id)


## The colour status `id` glows in and its motes cool from: its card's tint, `status_deep_white` of
## the way to white for a deep one (freeze); white for a status with no card.
func status_color(id: StringName) -> Color:
	var card: Array = _status_card(id)
	if card.is_empty():
		return Color.WHITE
	var tint: Color = card[ElementBase.STATUS_LOOK_TINT] as Color
	tint.a = 1.0
	return tint.lerp(Color.WHITE, feel.preset.status_deep_white) if _status_deep(id) else tint


## The shown statuses' motes over `real_delta` seconds (S6 item 11; the status shader's particles
## until then): each gives off its card's motes round its character, `status_mote_rate` a second
## (`status_deep_motes` times that for a deep one), in its colour.
func _status_motes(real_delta: float) -> void:
	if real_delta <= 0.0 or not feel._spectacle.motes_on():
		return
	for at in _status_enemies.size():
		if _status_effect[at] < 0:
			continue
		var enemy := instance_from_id(_status_enemies[at]) as Node2D
		var id: StringName = _status_shown[at]
		var card: Array = _status_card(id)
		if enemy == null or card.is_empty():
			continue
		var rate: float = feel.preset.status_mote_rate * (feel.preset.status_deep_motes if _status_deep(id) else 1.0)
		var count: int = floori(rate * real_delta + _rng.randf())
		if count > 0:
			feel._spectacle.status_motes(card[ElementBase.STATUS_LOOK_CARD] as StringName, card[ElementBase.STATUS_LOOK_LAYER] as int, enemy.global_position, 4.0 * FeelScript.STATUS_ZOOM, status_color(id), count, id)


## A falling body's motes (`FallLook`): `count` of them round `at`, the void's, drifting.
func _throw_fall_motes(at: Vector2, count: int) -> void:
	feel._spectacle.status_motes(&"", LookNames.layer_of(&"drift"), at, 6.0, FallLook.MOTE_COLOUR, count)


## End the flash that shows status `at`, if it still shows it.
func _end_status_effect(at: int) -> void:
	var slot: int = _status_effect[at]
	var enemy := instance_from_id(_status_enemies[at]) as Node2D
	if slot >= 0 and slot < feel.effect_slots and _flash_kind[slot] == FeelScript.KIND_STATUS and _flash_follow[slot] == enemy:
		_flash_seconds[slot] = 0.0
		_flash_follow[slot] = null
	_status_effect[at] = -1


## The status shown on `enemy` (empty for none), for tests.
func status_shown(enemy: Node) -> StringName:
	var at: int = _status_enemies.find(enemy.get_instance_id())
	if at < 0 or _status_effect[at] < 0:
		return &""
	return _status_shown[at]


## Statuses showing right now (for tests).
func live_statuses() -> int:
	return _job_flashes._count_flashes(FeelScript.KIND_STATUS)


## Is the name of `reaction_id` already rising near `position`?
func _label_showing(reaction_id: StringName, position: Vector2) -> bool:
	for i in FeelScript.REACTION_SLOTS:
		if _label_left[i] > 0.0 and _label_id[i] == reaction_id \
				and _label_start[i].distance_to(position) < FeelScript.REACTION_LABEL_NEAR:
			return true
	return false


## Raise and fade the reaction names.
func _step_labels(real_delta: float) -> void:
	for i in FeelScript.REACTION_SLOTS:
		if _label_left[i] <= 0.0:
			continue
		_label_left[i] -= real_delta
		var label: Label = _labels[i]
		if _label_left[i] <= 0.0:
			label.visible = false
			continue
		var total: float = _label_total[i] if _label_total[i] > 0.0 else FeelScript.REACTION_NAME_SECONDS
		var t: float = _label_left[i] / total
		label.global_position = _label_start[i] + Vector2(0.0, -FeelScript.REACTION_RISE * (1.0 - t))
		label.modulate.a = minf(t * 2.0, 1.0)


## Reaction names showing right now (for tests).
func live_labels() -> int:
	var count: int = 0
	for i in FeelScript.REACTION_SLOTS:
		if _label_left[i] > 0.0:
			count += 1
	return count


func _on_player_downed(player: int) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var combat: Node = feel.combat
	# The event names no position, so a downed wizard's cue draws nothing: the game-wide stop,
	# shake and sound only (its point is never used)...
	_job_cues.play_cue(CueBase.DOWNED_CUE, ActorsScript.NONE, Vector2.ZERO)
	# ...and, when their own (or a teammate's) spell did it, a note over them saying so: the
	# seat's own body (its home actor, also while the seat drives another), in its light shade.
	if combat == null or not combat.has_method("home_actor_of"):
		return
	var actor: int = combat.home_actor_of(player) as int
	var table: ActorsScript = feel._actor_table()
	if actor == ActorsScript.NONE or table == null:
		return
	var note: String = combat.downed_note_of(actor) as String
	var wizard: Node2D = table.node_of(actor) as Node2D
	if note.is_empty() or wizard == null:
		return
	_show_note(note, wizard.global_position if wizard.is_inside_tree() else wizard.position, ProjectileManagerScript.ramp_light(table.ramp_of(actor)), feel.preset.downed_note_seconds)
