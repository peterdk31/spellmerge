class_name FeelCasts
extends Object
## Feel's casts: a seat's cast cue, a wind-up's telegraph on the staff tip, a cast's sounds as it
## leaves, a cue's `lane` and `held` parts, a move's wall cue and a barrier's shell. Methods working
## on Feel (`feel`), whose members hold all of it.

const FeelScript := preload("res://gameplay/feel/feel.gd")
const LanesScript := preload("res://gameplay/feel/lanes.gd")
const HeldSoundsScript := preload("res://gameplay/feel/held_sounds.gd")
const CueContextScript := preload("res://gameplay/feel/cue_context.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## Not Feel's own: Feel, the other jobs this one calls and Feel's containers it works on, each
## Feel's own (shared, never a copy), linked by `link`.
const LINKED: Array[StringName] = [&"feel", &"_job_cues"]

var feel: FeelScript = null
var _job_cues: FeelCues = null


## Takes Feel and its containers and jobs, by the names in LINKED (`Feel._link_jobs`).
func link(owner: FeelScript) -> void:
	feel = owner
	for name: StringName in LINKED:
		if name != &"feel":
			set(name, owner.get(name))


## A seat cast a spell (`spell_cast`, a seat's own staffs only): its carrier card's `cast_cue` at the
## staff tip, in the seat's hat ramp, along its aim (the cast flash, a ring for a ring carrier, the
## camera kicked back), from the actor the seat drives.
func _on_spell_cast(player: int, spell_id: StringName, origin: Vector2, direction: Vector2) -> void:
	if player < 0 or player >= ActorsScript.SEATS:
		return
	var table: ActorsScript = feel._actor_table()
	var actor: int = table.actor_of_seat(player) if table != null else ActorsScript.NONE
	_job_cues.play_cue(_job_cues._carrier_card_cues_of(spell_id)[FeelScript.CUE_CAST] as StringName, actor, origin, direction, 0.0, Color.WHITE, 0, ActorsScript.NONE, -1, -1, 0, true, FeelScript.NO_BODY, player)


## A cast started winding up (`cast_winding`; docs/milestones/cast-timing.md, T6b): the staff's own
## wind-up cue when it names one (`staff_cue`, `StaffBase.wind_cue`: a barrel's fuse, props W6), else
## its carrier card's `wind_cue` (an enemy's telegraph: a lane along the aim, a ring for a cast that
## is not aimed), from the staff tip, its size the wind-up's seconds, on the staff tip as it turns.
## Only for a caster not on the players' team: a telegraph warns the players (owner, 2026-11-01).
func _on_cast_winding(caster: int, staff: int, carrier_card: StringName, origin: Vector2, direction: Vector2, seconds: float, tint: Color, look: int, tag: int, staff_cue: StringName) -> void:
	if caster < 0 or caster >= ActorsScript.ACTORS or not origin.is_finite():
		return
	var table: ActorsScript = feel._actor_table()
	if table == null or table.team_of(caster) == ActorsScript.TEAM_WIZARDS:
		return
	var cue: StringName = staff_cue if staff_cue != &"" else _job_cues._carrier_card_cues_of(carrier_card)[FeelScript.CUE_WIND] as StringName
	if cue == &"":
		return
	# Its flashes sit on the staff tip as it turns (the aim follows the caster through the wind-up).
	feel._cue_tip = caster
	feel._cue_wind = staff
	_job_cues.play_cue(cue, caster, origin, direction, seconds, tint, look, ActorsScript.NONE, -1, -1, tag, true, FeelScript.NO_BODY, feel._ramp_of(caster), table.node_of(caster) as Node2D)
	feel._cue_tip = ActorsScript.NONE
	feel._cue_wind = -1


## An enemy's AI locked its aim on the cast it winds up (`aim_locked`, boss plan OB14): its lane
## flashes, a beat that says "it no longer follows you".
func _on_aim_locked(caster: int, staff: int) -> void:
	if feel._lanes != null:
		feel._lanes.beat(caster, staff)


## A cue's `lane` part (`CueBase`; T6b): a telegraph lane for the cast of the cue's tag, as long as
## the cue's size in seconds (`lanes.gd`).
func _play_lane(part: Variant, cue: CueContextScript) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var lanes: LanesScript = feel._lanes
	if lanes == null:
		return
	var reach: float = float((part as Dictionary).get("reach", 1.0)) if part is Dictionary else 1.0
	lanes.spells = feel.spells
	lanes.play(cue.caster, cue.tag, cue.size, cue.tint, reach)


## A cue's `held` part (`CueBase`, boss plan OB15): its sound held while its moment lasts, from its
## caster's body: a wind-up cue's until the cast leaves (`HeldSounds.Until.WIND`), a move's (a staff's
## `move_cue`) until that move ends (`CARRIER`), any other cue's for its seconds where it was played.
func _play_held(part: Variant, cue: CueContextScript) -> void:
	if feel._held == null or not part is Dictionary:
		return
	var held: Dictionary = part as Dictionary
	var until: int = HeldSoundsScript.Until.SECONDS
	var key: int = 0
	if feel._cue_wind >= 0:
		until = HeldSoundsScript.Until.WIND
		key = feel._cue_wind
	elif feel._cue_move != 0:
		until = HeldSoundsScript.Until.CARRIER
		key = feel._cue_move
	var follow: Node2D = cue.follow
	if follow == null and until != HeldSoundsScript.Until.SECONDS:
		var table: ActorsScript = feel._actor_table()
		follow = table.node_of(cue.caster) as Node2D if table != null and table.is_open(cue.caster) else null
	feel._held.spells = feel.spells
	feel._held.hold(StringName(held.get("sound", "")), until, cue.caster, key, follow, cue.at, float(held.get("seconds", 4.0)), float(held.get("volume", 0.0)))


## Whether the carrier of the spell tagged `tag` runs its caster along (a dash: `MOVES_ALONG`), so it
## ends with `carrier_ended`.
func _moves_along(tag: int) -> bool:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var spells: Node = feel.spells
	if spells == null or not spells.has_method(&"profile"):
		return false
	var spell: CompiledSpell = spells.call(&"profile", tag) as CompiledSpell
	return spell != null and spell.traits & CarrierTraits.MOVES_ALONG != 0


## The staff (`StaffBase`) the spell tagged `tag` was cast from, as its caster holds it now (null:
## none, or no spell runtime).
func _staff_of_tag(tag: int) -> StaffBase:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var spells: Node = feel.spells
	if tag == 0 or spells == null or not spells.has_method(&"staff_of"):
		return null
	return spells.call(&"staff_of", SpellTag.caster_of(tag), SpellTag.staff_of(tag)) as StaffBase


## A cast left its staff (`cast_left`): the staff's own `cast_cue` when it names one (boss plan OB15:
## a swat), else the cast's own sounds (`_sound_cast`), from where its caster holds it, along its aim.
func _on_cast_left(caster: int, staff: int) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var spells: Node = feel.spells
	if spells == null or not spells.has_method(&"staff_of"):
		return
	var own: StaffBase = spells.call(&"staff_of", caster, staff) as StaffBase
	if own == null or not _job_cues._cue_sounds(own.cast_cue):
		# A staff's cue with no sound of its own (a spitter's acid jet) is a look on the cast's sound.
		_sound_cast(caster, staff)
	if own == null or own.cast_cue == &"":
		return
	var origin: Vector2 = spells.call(&"aim_origin_of", caster)
	var way: Vector2 = spells.call(&"aim_of", caster)
	if not origin.is_finite():
		var table: ActorsScript = feel._actor_table()
		var body: Node2D = table.node_of(caster) as Node2D if table != null and table.is_open(caster) else null
		if body == null:
			return
		origin = body.global_position
	_job_cues.play_cue(own.cast_cue, caster, origin, way if way.is_finite() else Vector2.ZERO)


## The sounds of the cast leaving now (`Spells.leaving_cast`) of `caster`, from its staff tip: its
## carriers' own and its infusions' hints (`cast_sounds.gd`), an enemy's ENEMY_CAST_VOLUME quieter;
## nothing for a prop's (the world's: its moments are its states' cues).
func _sound_cast(caster: int, staff: int) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var spells: Node = feel.spells
	if feel._cast_sounds == null or not spells.has_method(&"leaving_cast"):
		return
	var cast: CompiledCast = spells.call(&"leaving_cast") as CompiledCast
	if cast == null:
		return
	var table: ActorsScript = feel._actor_table()
	var team: int = table.team_of(caster) if table != null else ActorsScript.TEAM_WIZARDS
	if team == ActorsScript.TEAM_WORLD:
		return
	var origin: Vector2 = spells.call(&"aim_origin_of", caster) if spells.has_method(&"aim_origin_of") else Vector2.INF
	if not origin.is_finite() and table != null and table.is_open(caster):
		var body: Node2D = table.node_of(caster) as Node2D
		origin = body.global_position if body != null else Vector2.INF
	feel._cast_sounds.play(cast, origin, FeelScript.ENEMY_CAST_VOLUME if team == ActorsScript.TEAM_ENEMIES else 0.0, caster * SpellLimits.STAFFS + staff, feel._clock)


## A move ended (`caster_move_finished`): one a wall stopped (`walled`, boss plan OB12) plays its
## staff's `wall_cue` where it stopped (OB15: the broom's crunch).
func _on_caster_move_finished(_caster: int, _mode: StringName, position: Vector2, tag: int, walled: bool) -> void:
	if not walled or not position.is_finite():
		return
	var own: StaffBase = _staff_of_tag(tag)
	if own != null and own.wall_cue != &"":
		_job_cues.play_cue(own.wall_cue, SpellTag.caster_of(tag), position, Vector2.ZERO, 0.0, Color.WHITE, 0, ActorsScript.NONE, -1, -1, tag)


## A barrier on an actor changed (combat's `barrier_changed`): the spectacle draws its shell, a
## bubble of motes round the actor in its spell's colours (`barriers.gd`).
func _on_barrier_changed(actor: int, charges: int, seconds: float, tag: int, way: Vector2, radius: float) -> void:
	feel._spectacle.barrier_changed(actor, charges, seconds, tag, way, radius, feel._ramp_of(actor))
