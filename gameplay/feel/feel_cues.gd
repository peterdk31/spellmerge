class_name FeelCues
extends Object
## Feel's cues (gameplay/feel/feel.gd, "A cue"): `play_cue` and its part players' table
## (`add_cue_part`), the cues and plans read once, a cue's `every`, and the events that only play a
## cue (a cue shown, a carrier's end, a staff swap, a possession, a boss's entrance, a heal).
## Methods working on Feel (`feel`), whose members hold all of it.

const FeelScript := preload("res://gameplay/feel/feel.gd")
const CueSizeScript := preload("res://gameplay/feel/cue_size.gd")
const CueContextScript := preload("res://gameplay/feel/cue_context.gd")
const CuePlanScript := preload("res://gameplay/feel/cue_plan.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## Not Feel's own: Feel, the other jobs this one calls and Feel's containers it works on, each
## Feel's own (shared, never a copy), linked by `link`.
const LINKED: Array[StringName] = [&"feel", &"_job_flashes", &"_job_view", &"_cue_parts", &"_cue_plans", &"_cue_contexts", &"_unknown_part_warned", &"_carrier_card_cues", &"_cue_cache", &"_cue_every_at", &"_cue_next_at"]

var feel: FeelScript = null
var _job_flashes: FeelFlashes = null
var _job_view: FeelView = null
var _cue_parts: Dictionary
var _cue_plans: Dictionary
var _cue_contexts: Array[CueContextScript]
var _unknown_part_warned: Dictionary
var _carrier_card_cues: Dictionary
var _cue_cache: Dictionary
var _cue_every_at: Dictionary
var _cue_next_at: PackedFloat32Array


## Takes Feel and its containers and jobs, by the names in LINKED (`Feel._link_jobs`).
func link(owner: FeelScript) -> void:
	feel = owner
	for name: StringName in LINKED:
		if name != &"feel":
			set(name, owner.get(name))


## A heal: the cue `heal` (a soft ring in green on the wizard, with no stop and no shake). Its
## ring is in its own colour, whoever healed.
func _on_heal_dealt(_player: int, _target: Node, _amount: float, position: Vector2) -> void:
	play_cue(&"heal", ActorsScript.NONE, position)


## An enemy starts to come out of its mark (`SpawnLook`): its style's cue `cue` at its feet, as no
## actor's; unweighted (its dust only, no sound) when another spawn sounded just before.
func _play_spawn_cue(cue: StringName, at: Vector2, weighted: bool) -> void:
	play_cue(cue, ActorsScript.NONE, at, Vector2.ZERO, 0.0, Color.WHITE, 0, ActorsScript.NONE, -1, -1, 0, weighted)


## The spawn style of id `id` (content/spawn_styles), null for none: `SpawnLook`'s lookup.
func _spawn_style(id: StringName) -> SpawnStyle:
	return feel.registry.get_resource(SpawnStyle.FOLDER, id) as SpawnStyle if feel.registry != null else null


## Play the cue `id` (a `CueBase`, `content/cues/<id>.tres`; `cue_shown` calls this) at `at`, set
## off by `caster` (NONE for none: the enemy ramp; its body is where `away` punches from) along
## `dir`, `size` pixels big (what a part's `reach` is times; the seconds a `lasts_size` part
## lasts), in its ramp with `tint` (as `show_flash`'s `core`) and the cards of the packed `look`,
## on `target` (an actor, for `hold_target`), sent by `shot`, for what broke in the colours of the
## ramp-table source `surface` (a dying body's art; -1: the room's walls), of the spell of `tag` (its
## cards' motes and marks; 0: the tag of `shot`, if any), in `ramp` (a hat ramp, or the enemy ramp:
## for a moment of a seat or of a hit body rather than of the caster's spell, a seat's cast; CASTER_RAMP:
## the caster's, `Actors.ramp_of`). Plays its parts, each by
## the player of its type (`add_cue_part`), then its weight: holds, the game-wide stop, shake and
## punch (both off with the screen shake setting) and its sound; with `weight` false, its parts
## only (a reaction repeated within `CueBase.REACTION_REPEAT`). `body_color` is the own colour of the body
## the cue is of (a dying enemy's `EnemyBase.hit_color`), for its `body` flashes (alpha 0: none).
## With `follow` (a body), its flashes move with that body while they last, where they were played
## from it, and end when it is gone (S6, item 9: a staff's swap, a possession's ring).
## Its `power` is applied here and in the parts' players, by one rule (`CueBase`): times its sizes
## and counts, its holds, shake and punch. A cue with an `every` played again for the same actor
## sooner than that plays nothing (`_cue_due`). An unknown cue plays nothing. A cue is read once for
## playing (`_plan_of`, `CuePlan`). With `follow` (a body), its flashes move with that body while
## they last, where they were played from it, and end when it is gone (S6, item 9: a staff's swap,
## a possession's ring).
func play_cue(id: StringName, caster: int, at: Vector2, dir: Vector2 = Vector2.ZERO, size: float = 0.0, tint: Color = Color.WHITE, look: int = 0, target: int = ActorsScript.NONE, shot: int = -1, surface: int = -1, tag: int = 0, weight: bool = true, body_color: Color = Color(0.0, 0.0, 0.0, 0.0), ramp: int = FeelScript.CASTER_RAMP, follow: Node2D = null) -> void:
	var instead: StringName = feel._sound_instead
	feel._sound_instead = &""
	if not at.is_finite() or caster < ActorsScript.NONE or caster >= ActorsScript.ACTORS:
		return
	var plan: CuePlanScript = _cue_plans.get(id) as CuePlanScript
	if plan == null:
		plan = _plan_of(id)
		if plan == null:
			return
	if plan.every > 0.0 and not _cue_due(plan.cue, caster):
		return
	if feel._hit_flash and not (weight and plan.weighted) and _hides_hit(plan):
		# A hit's look that would show nothing is not played (hundreds of hits a frame in a crowd).
		feel._cue_flash = -1
		return
	var aim: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	if feel._cue_depth == _cue_contexts.size():
		_cue_contexts.append(CueContextScript.new())
	var context: CueContextScript = _cue_contexts[feel._cue_depth]
	context.caster = caster
	context.ramp = feel._ramp_of(caster) if ramp == FeelScript.CASTER_RAMP else ramp
	context.at = at
	context.aim = aim
	context.size = size
	context.tint = tint
	context.look = look
	context.target = target
	context.shot = shot
	context.surface = surface
	context.body = body_color
	context.follow = follow if follow != null and is_instance_valid(follow) else null
	context.tag = tag if tag != 0 or shot < 0 or feel.projectiles == null else feel.projectiles.get_tag_of(shot)
	context.color = plan.color
	context.power = plan.power
	var grow: float = CueSizeScript.factor(plan.cue.size_ref, size)
	context.grow = grow
	feel._cue_depth += 1
	# A cue with a `light` part lights by it alone: the flashes it shows light nothing (S6, item 4).
	var unlit_before: bool = feel._cue_unlit
	feel._cue_unlit = plan.lights
	var prepared: Array = plan.prepared
	var n: int = 0
	# A hit's flashes past the frame's share are skipped here, not called only to stop at once.
	var no_flashes: bool = feel._hit_flash and _job_flashes._hit_flashes_full()
	for player: Callable in plan.players:
		if no_flashes and prepared[n] is CuePlanScript.Flash:
			feel._cue_flash = -1
		else:
			player.call(prepared[n], context)
		n += 1
	if not plan.unknown.is_empty():
		for type: StringName in plan.unknown:
			_unknown_cue_part(id, type)
	feel._cue_unlit = unlit_before
	feel._cue_depth -= 1
	if not weight or not plan.weighted:
		if weight and instead != &"":
			feel._play(instead, at)
		return
	var cue: CueBase = plan.cue
	var power: float = plan.power
	# A cue played bigger than it is made shakes, kicks and sounds bigger (`CueBase.size_ref`: `grow`).
	# Its holds and game-wide stop are the game's (`HitStop`, online-ready N4), not drawn here.
	var table: ActorsScript = feel._actor_table() if cue.kick_way == &"away" else null
	if feel.shake_enabled and (cue.shake > 0.0 or cue.kick > 0.0) and _job_view._in_picture(at):
		_job_view._refresh_camera()
		_job_view._shake(cue.shake * power * CueSizeScript.shake(grow))
		var way: Vector2 = Vector2.DOWN
		var kick_way: StringName = cue.kick_way
		# Back or along its way only when it has one (a cast with no aim kicks nowhere).
		if kick_way == &"back":
			way = -aim if dir != Vector2.ZERO else Vector2.ZERO
		elif kick_way == &"aim":
			way = aim if dir != Vector2.ZERO else Vector2.ZERO
		elif kick_way == &"away":
			var body: Node2D = table.node_of(caster) as Node2D if table != null and table.is_open(caster) else null
			if body != null and body.global_position.distance_to(at) > 1.0:
				way = body.global_position.direction_to(at)
		feel._kick = (feel._kick + way * cue.kick * power * CueSizeScript.shake(grow)).limit_length(FeelScript.MAX_KICK_PIXELS)
	var sound: StringName = instead if instead != &"" else cue.sound
	var pitch: float = CueSizeScript.pitch(grow)
	if feel._play(sound, at, CueSizeScript.volume(grow), pitch) >= 0 and cue.duck < 0.0:
		# The music gives way for as long as the sound plays (Audio's duck: the deepest wins), a
		# deeper one longer.
		feel.audio.duck(cue.duck, feel.audio.length_of(sound) / pitch)


## Whether `plan`, played as the look of the hit being shown, would show nothing: each of its parts
## is a flash past the frame's share of hit flashes or a part that needs a spray of a hit whose motes
## do not spray (`CuePlan.shows_always` and the two gates).
func _hides_hit(plan: CuePlanScript) -> bool:
	if plan.shows_always:
		return false
	if plan.has_flashes and not _job_flashes._hit_flashes_full():
		return false
	return not plan.has_spray_parts or (feel._spectacle != null and feel._spectacle.hit_unsprayed())


## Whether the cue `cue` (which has an `every`) may play for `caster` now, and if so, not again for
## its `every` seconds. Allocates only the first time a cue with an `every` plays.
func _cue_due(cue: CueBase, caster: int) -> bool:
	var first: Variant = _cue_every_at.get(cue.id)
	if first == null:
		first = _cue_next_at.size()
		_cue_every_at[cue.id] = first
		_cue_next_at.resize(int(first) + ActorsScript.ACTORS + 1)
		for i in ActorsScript.ACTORS + 1:
			_cue_next_at[int(first) + i] = -INF
	var at: int = int(first) + caster + 1
	if feel._clock < _cue_next_at[at]:
		return false
	_cue_next_at[at] = feel._clock + cue.every
	return true


## Play a cue's parts of the type `type` (`CueBase.PART_TYPES`) with `player`, a Callable taking
## the part (a Dictionary) and the cue's `CueContext`; a player already there is replaced. With
## `prepare` (a Callable taking the part), each part is prepared once when its cue is first played
## and `player` takes what it made instead, so a part played often reads no key while it plays
## (a flash's keys as typed fields: `CuePlan.Flash`). With `needs_spray` (a Callable taking what
## `player` takes), the parts it says true for show nothing for a hit whose motes do not spray
## (`Spectacle.hit_unsprayed`: the spectacle's `often` motes), so a hit's cue of only such parts and
## flashes is not played at all for a hit that would show none of them (`_hides_hit`). Leave it out
## for a type whose parts play whatever the hit. Feel's own flashes are `flash`, the spectacle's
## `motes` and `mark` (`Spectacle.cue_parts`).
func add_cue_part(type: StringName, player: Callable, prepare: Callable = Callable(), needs_spray: Callable = Callable()) -> void:
	_cue_parts[type] = [player, prepare, needs_spray]
	_cue_plans.clear()


## Whether a cue part of the type `type` has a player.
func has_cue_part(type: StringName) -> bool:
	return _cue_parts.has(type)


## A part of the cue `id` of a type nothing plays: skipped and counted, and warned of once per type
## (`CueBase.problems` names it in content; this is for a part a player was taken away from).
func _unknown_cue_part(id: StringName, type: StringName) -> void:
	feel.unknown_cue_parts += 1
	if not _unknown_part_warned.has(type):
		_unknown_part_warned[type] = true
		push_warning("Feel: cue '%s' has a part of the type '%s', which nothing plays" % [id, type])


## The cue `id` read for playing (`CuePlan`: its parts' players and prepared parts), made the first
## time it is played (`play_cue` keeps it by id) and again after a part player changed
## (`add_cue_part`) or `forget_cues`; null for no cue.
func _plan_of(id: StringName) -> CuePlanScript:
	var cue: CueBase = cue_of(id)
	if cue == null:
		return null
	var plan: CuePlanScript = _cue_plans.get(id) as CuePlanScript
	if plan == null or plan.cue != cue:
		plan = CuePlanScript.make(cue, _cue_parts) as CuePlanScript
		_cue_plans[id] = plan
	return plan


## Forget the cues read so far (`cue_of`, and their plans), so the next play reads them again (a
## cue file changed, or a test's own cue).
func forget_cues() -> void:
	_cue_cache.clear()
	_cue_plans.clear()


## The cue `id` (`content/cues/<id>.tres`), or null when there is none or no registry yet. Read
## once per id, then kept: a cue allocates nothing.
func cue_of(id: StringName) -> CueBase:
	var cached: Variant = _cue_cache.get(id)
	if cached != null:
		return cached as CueBase
	if feel.registry == null or id == &"":
		return null
	var cue: CueBase = feel.registry.get_resource(&"cues", id) as CueBase
	if cue != null:
		_cue_cache[id] = cue
	return cue


func _on_cue_shown(caster: int, cue: StringName, at: Vector2, direction: Vector2, size: float, tint: Color, look: int) -> void:
	play_cue(cue, caster, at, direction, size, tint, look, ActorsScript.NONE, -1, -1, _cue_tag())


## The spell runtime's tag of the spell whose cue, carrier card or carrier's end is being sent (its cards'
## motes and marks; `SpellRuntime.cue_tag`), 0 for none.
func _cue_tag() -> int:
	var tag: Variant = feel.spells.get(&"cue_tag") if feel.spells != null else null
	return tag if tag is int else 0


## A carrier with no shot ended (a teleport or dash landing, a slam striking, a
## decoy or familiar going): the streams its cues started end (a dash's streaks), and its card's
## `end_cue` plays, `size` big.
func _on_carrier_ended(caster: int, carrier_card: StringName, at: Vector2, direction: Vector2, size: float, tint: Color, look: int) -> void:
	var tag: int = _cue_tag()
	if feel._spectacle != null:
		feel._spectacle.end_streams(caster, tag)
	if feel._held != null:
		feel._held.end_carrier(caster, tag)
	var cue: StringName = _carrier_card_cues_of(carrier_card)[FeelScript.CUE_END] as StringName
	if cue != &"":
		play_cue(cue, caster, at, direction, size, tint, look, ActorsScript.NONE, -1, -1, tag)


## The cues the carrier card `carrier_card` names and its radius (`CarrierCard.look_cues`: [cast_cue,
## shown_cue, impact_cue, end_cue, radius], CUE_CAST to CUE_RADIUS), the defaults (`cast` and `impact`, radius
## 0) for an id that is no carrier card; a modifier that shows itself (`carrier_shown` `zap`, `siphon`) brings its
## own `cue` as its shown cue. Read once per card id, then kept: a cast or a hit allocates nothing.
## With no registry yet, or no carrier card id, the defaults are answered but not kept.
func _carrier_card_cues_of(carrier_card: StringName) -> Array:
	var cached: Variant = _carrier_card_cues.get(carrier_card)
	if cached != null:
		return cached as Array
	if feel.registry == null or carrier_card == &"":
		return FeelScript.NO_CARRIER_CARD_CUES
	var card: Resource = feel.registry.get_resource(&"spells", carrier_card)
	var cues: Array = FeelScript.NO_CARRIER_CARD_CUES
	if card is CarrierCard:
		cues = (card as CarrierCard).look_cues()
	elif card is ModifierBase and (card as ModifierBase).cue != &"":
		# A modifier that shows itself (a zap: `carrier_shown` names its card) plays its own cue there.
		cues = [FeelScript.NO_CARRIER_CARD_CUES[FeelScript.CUE_CAST], (card as ModifierBase).cue, FeelScript.NO_CARRIER_CARD_CUES[FeelScript.CUE_IMPACT], &"", 0.0, FeelScript.NO_CARRIER_CARD_CUES[FeelScript.CUE_WIND]]
	_carrier_card_cues[carrier_card] = cues
	return cues


## Whether the cue `id` has a sound of its own (an unknown cue, or none, has not).
func _cue_sounds(id: StringName) -> bool:
	if id == &"":
		return false
	var plan: CuePlanScript = _cue_plans.get(id) as CuePlanScript
	if plan == null:
		plan = _plan_of(id)
	return plan != null and plan.cue.sound != &""


## A body's phase cue (`BodySounds`): played from it, following it.
func _play_body_cue(cue: StringName, actor: int, at: Vector2, body: Node2D) -> void:
	play_cue(cue, actor, at, Vector2.ZERO, 0.0, Color.WHITE, 0, ActorsScript.NONE, -1, -1, 0, true, FeelScript.NO_BODY, FeelScript.CASTER_RAMP, body)


## Another staff went on show (the personality swap, living staffs H4): the cue `staff_swap` along
## the whole new staff (the cue's line: played at the staff's lower end behind the hand,
## `Actor.butt_position`, along the aim, its size the staff's length from there to its tip,
## `Actor.muzzle_position`, so its parts can cover the whole staff), following
## the body, in the actor's ramp with the colour and cards of the new staff's first spell (S6, item
## 9). StaffLook swaps the body and face at 35% of its POOF_TIME: the cue's look is timed to that.
func _on_staff_shown(caster: int, actor: Node, staff: int) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var spells: Node = feel.spells
	var body: Actor = actor as Actor
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return
	var tag: int = 0
	var tint: Color = Color.WHITE
	var look: int = 0
	if spells != null and spells.has_method(&"current_tag"):
		tag = int(spells.call(&"current_tag", body.id, staff))
		var spell: Object = spells.call(&"profile", tag) as Object if tag != 0 else null
		if spell != null:
			tint = spell.get(&"tint") as Color
			look = int(spell.get(&"look"))
	var butt: Vector2 = body.butt_position()
	play_cue(FeelScript.STAFF_SWAP, caster, butt, body.aim, butt.distance_to(body.muzzle_position()), tint, look, body.id, -1, -1, tag, true, FeelScript.NO_BODY, FeelScript.CASTER_RAMP, body)


## A possession started: the cue `possess_start` on the possessed actor's body (a ring closing in
## the driver's ramp, the sound `possess`).
func _on_possess_started(caster: int, actor: int) -> void:
	_cue_on_body(FeelScript.POSSESS_START, caster, actor)


## A possession ended: the cue `possess_end` on the body let go, if it is still there (a ring going
## out in the driver's ramp).
func _on_possess_ended(caster: int, actor: int) -> void:
	_cue_on_body(FeelScript.POSSESS_END, caster, actor)


## A boss entered play (boss plan OB16): its entrance cue on its body, under the HUD's banner; one
## with an intro waits (`_intro_wait`).
func _on_boss_shown(actor: int, _boss_name: String, _lore: String, _marks: PackedFloat32Array, has_intro: bool) -> void:
	if not has_intro:
		_cue_on_body(FeelScript.BOSS_INTRO, actor, actor)


## A boss with an intro waits no more: its entrance cue plays only when no intro `played`.
func _on_boss_released(actor: int, played: bool) -> void:
	if not played:
		_cue_on_body(FeelScript.BOSS_INTRO, actor, actor)


## Play the cue `id` of `caster` at the drawn body of `actor` (its `body_offset`), following the
## body; nothing when the body is gone.
func _cue_on_body(id: StringName, caster: int, actor: int) -> void:
	var table: ActorsScript = feel._actor_table()
	var body: Node2D = table.node_of(actor) as Node2D if table != null and actor != ActorsScript.NONE else null
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return
	play_cue(id, caster, body.global_position + ((body as Actor).body_offset if body is Actor else Vector2.ZERO), Vector2.ZERO, 0.0, Color.WHITE, 0, actor, -1, -1, 0, true, FeelScript.NO_BODY, FeelScript.CASTER_RAMP, body)
