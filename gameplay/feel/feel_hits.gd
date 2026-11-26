class_name FeelHits
extends Object
## Feel's hits (gameplay/feel/feel.gd, the header): a hit's flash, squash, shake and sound
## (`_on_damage_dealt`, `_juice`), a shot's impact on a body or a wall, its end, a deflect or block,
## the hit sprites' squash (`_react`, `_step_reactions`), and a death's break into motes and its
## remnant. Methods working on Feel (`feel`), whose members hold all of it.

const FeelScript := preload("res://gameplay/feel/feel.gd")
const BodyLooksScript := preload("res://gameplay/feel/body_looks.gd")
const HitRepeatsScript := preload("res://gameplay/feel/hit_repeats.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const CardSoundsScript := preload("res://gameplay/feel/card_sounds.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## Not Feel's own: Feel, the other jobs this one calls and Feel's containers it works on, each
## Feel's own (shared, never a copy), linked by `link`.
const LINKED: Array[StringName] = [&"feel", &"_job_cues", &"_job_view", &"_juiced_frame", &"_juiced_step", &"_juiced_body", &"_juiced_by", &"_juiced_kind", &"_card_sounds", &"_react_actor", &"_react_of_actor", &"_react_sprites", &"_react_scale", &"_react_written", &"_react_left", &"_react_total", &"_react_amount", &"_flash_seconds", &"_body_looks", &"_hit_repeats"]

var feel: FeelScript = null
var _job_cues: FeelCues = null
var _job_view: FeelView = null
var _juiced_frame: PackedInt64Array
var _juiced_step: PackedInt64Array
var _juiced_body: PackedInt64Array
var _juiced_by: PackedInt32Array
var _juiced_kind: Array[StringName]
var _card_sounds: CardSoundsScript
var _react_actor: PackedInt32Array
var _react_of_actor: PackedInt32Array
var _react_sprites: PackedInt64Array
var _react_scale: PackedVector2Array
var _react_written: PackedVector2Array
var _react_left: PackedFloat32Array
var _react_total: PackedFloat32Array
var _react_amount: PackedFloat32Array
var _flash_seconds: PackedFloat32Array
var _body_looks: BodyLooksScript
var _hit_repeats: HitRepeatsScript


## Takes Feel and its containers and jobs, by the names in LINKED (`Feel._link_jobs`).
func link(owner: FeelScript) -> void:
	feel = owner
	for name: StringName in LINKED:
		if name != &"feel":
			set(name, owner.get(name))


## Flash and squash the hit sprites for `real_delta` seconds, and put back those done.
func _step_reactions(real_delta: float) -> void:
	var at: int = feel._react_count - 1
	while at >= 0:
		_react_left[at] -= real_delta
		var sprite := instance_from_id(_react_sprites[at]) as Sprite2D
		var alive: bool = sprite != null
		if alive and sprite.scale != _react_written[at]:
			# The sprite's owner changed the scale (a dash look): that is the new base.
			_react_scale[at] = sprite.scale
		if _react_left[at] <= 0.0 or not alive:
			if alive:
				sprite.material = null
				sprite.scale = _react_scale[at]
			_drop_reaction(at)
		else:
			var squash: float = _react_amount[at] * _react_left[at] / maxf(_react_total[at], 0.001)
			_react_written[at] = _react_scale[at] * Vector2(1.0 + squash, 1.0 - squash)
			sprite.scale = _react_written[at]
		at -= 1


## The world transform a dead body's art is broken from (S3, `Spectacle.break_body`): its sprite's,
## at its rest scale (a body killed mid-squash would otherwise break squashed).
func _rest_transform(sprite: Sprite2D, dead: Node) -> Transform2D:
	var rest: Vector2 = sprite.global_scale
	var at: int = _find_reaction(sprite.get_instance_id(), FeelScript._actor_of(dead))
	if at >= 0 and sprite.scale.x != 0.0 and sprite.scale.y != 0.0:
		rest = rest / sprite.scale * _react_scale[at]
	return Transform2D(sprite.global_rotation, rest, 0.0, sprite.global_position)


## The Sprite2D a body shows as: its `Sprite` child; null for none.
func _body_sprite(body: Node) -> Sprite2D:
	if body == null or not is_instance_valid(body):
		return null
	return body.get_node_or_null("Sprite") as Sprite2D


## Start the white flash and the squash (wide and low) of the hit node's `Sprite` child, if it
## has one, for `hit_flash_seconds`; a hit on a sprite still reacting starts it again.
func _react(target: Node) -> void:
	var seconds: float = feel.preset.hit_flash_seconds
	var amount: float = feel.preset.hit_squash
	if seconds <= 0.0 or target == null or not is_instance_valid(target):
		return
	var sprite := target.get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var id: int = sprite.get_instance_id()
	var actor: int = FeelScript._actor_of(target)
	var at: int = _find_reaction(id, actor)
	if at < 0:
		if feel._react_count == _react_sprites.size():
			_grow_reactions(maxi(feel._react_count * 2, FeelScript.REACT_START))
		at = feel._react_count
		feel._react_count += 1
		_react_sprites[at] = id
		_react_actor[at] = actor
		if actor >= 0 and actor < _react_of_actor.size():
			_react_of_actor[actor] = at
		_react_scale[at] = sprite.scale
		_react_written[at] = sprite.scale
	_react_left[at] = seconds
	_react_total[at] = seconds
	_react_amount[at] = amount
	# One material shared by every flashing sprite (its flash is the shader's): nothing per flash.
	sprite.material = feel._hit_flash_material


## The reaction of the sprite with instance id `sprite` (of the actor `actor`, -1 for none), or -1.
func _find_reaction(sprite: int, actor: int) -> int:
	if actor >= 0 and actor < _react_of_actor.size():
		var at: int = _react_of_actor[actor]
		return at if at >= 0 and at < feel._react_count and _react_sprites[at] == sprite else -1
	var found: int = _react_sprites.find(sprite)
	return found if found < feel._react_count else -1


## Reaction `at` ends: the last one takes its place.
func _drop_reaction(at: int) -> void:
	var last: int = feel._react_count - 1
	var actor: int = _react_actor[at]
	if actor >= 0 and actor < _react_of_actor.size() and _react_of_actor[actor] == at:
		_react_of_actor[actor] = -1
	if at != last:
		_react_sprites[at] = _react_sprites[last]
		_react_actor[at] = _react_actor[last]
		_react_scale[at] = _react_scale[last]
		_react_written[at] = _react_written[last]
		_react_left[at] = _react_left[last]
		_react_total[at] = _react_total[last]
		_react_amount[at] = _react_amount[last]
		var moved: int = _react_actor[at]
		if moved >= 0 and moved < _react_of_actor.size() and _react_of_actor[moved] == last:
			_react_of_actor[moved] = at
	_react_sprites[last] = 0
	feel._react_count = last


## Room for `size` reactions (they only grow), and the index by actor id once.
func _grow_reactions(size: int) -> void:
	if _react_of_actor.is_empty():
		_react_of_actor.resize(ActorsScript.ACTORS)
		_react_of_actor.fill(-1)
	_react_sprites.resize(size)
	_react_actor.resize(size)
	_react_scale.resize(size)
	_react_written.resize(size)
	_react_left.resize(size)
	_react_total.resize(size)
	_react_amount.resize(size)


func _on_damage_dealt(caster: int, target: Node, amount: float, position: Vector2) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var preset: FeelPresetScript = feel.preset
	var spectacle: SpectacleScript = feel._spectacle
	if not _damage_look_shown(target, caster):
		# Past its body's looks this frame for its staff: no spray, squash, shake or sound.
		feel._impact_target = 0
		feel._kind_target = 0
		return
	var hit_id: int = FeelScript._actor_of(target)
	var repeat: bool = _repeat_hit(hit_id, target, caster)
	if not repeat:
		_react(target)
	var aim: Vector2 = Vector2.ZERO
	var at: Vector2 = position
	var tint: Color = Color.WHITE
	var size: float = 1.0
	var colours: int = 0
	# The spray's motes are a hit's: the shot's impact's roll when it did this hit, else one of its own.
	var held: bool = false
	if target != null and is_instance_valid(target):
		# An actor of a hat ramp is hit in its own colours: white, its ramp; the rest in their own
		# colour (`EnemyBase.hit_color`).
		var ramp: int = feel._hat_ramp_of_id(hit_id)
		if ramp >= 0:
			colours = ramp
		else:
			tint = _hit_color_of(target)
		# The shot that did this hit told us where it struck and which way it flew.
		if target.get_instance_id() == feel._impact_target and caster == feel._impact_caster and Engine.get_physics_frames() == feel._impact_frame:
			aim = feel._impact_aim
			at = feel._impact_at
			held = true
			spectacle.hold_hit(caster, feel._impact_tag, feel._impact_shown)
			size = clampf(1.0 + float(amount - FeelScript.SPRAY_REF_DAMAGE) * preset.hit_spray_per_damage, FeelScript.SPRAY_MIN_SIZE, FeelScript.SPRAY_MAX_SIZE)
	feel._impact_target = 0
	# The kind of the hit came just before (`hit_landed`): its shake and sound (its stop is the
	# game's, `HitStop`).
	# A hit of part of a point (an atom's speck) shakes as much as its share, so a stream of them
	# is not a quake.
	var shake: float = preset.hit_shake * minf(amount, 1.0)
	var sound: StringName = preset.hit_sound
	var own: bool = false
	if target != null and target.get_instance_id() == feel._kind_target and Engine.get_physics_frames() == feel._kind_frame:
		# Its kind's look, else a shot's, else none (one read of the table each).
		var looks: Dictionary = preset.kind_looks
		var found: Variant = looks.get(feel._kind)
		if found == null:
			found = looks.get(&"shot", FeelScript.NO_LOOK)
		var look: Dictionary = found as Dictionary
		shake *= look.get("shake", 1.0) as float
		sound = look.get("sound", preset.hit_sound) as StringName
		# A carrier's own hit (a shot, a ray, a sweep, a slam's wave) sounds as its card says; a
		# reaction, a status and a heal keep their kind's.
		if feel._kind_card != &"" and FeelScript.CARD_SOUND_KINDS.has(feel._kind):
			var card_sound: StringName = _card_sounds.sound_of(feel._kind_card, CardSoundsScript.Use.HIT)
			if card_sound != &"":
				sound = card_sound
		own = feel._kind_own
	feel._kind_target = 0
	var voice: int = feel._hit_voice
	if not held:
		spectacle.begin_hit(caster, 0)
	_juice(position, shake, &"" if repeat else sound, aim, tint, size, at, colours)
	spectacle.end_hit()
	if repeat:
		# The sound of the hit it repeats is still this hit's (a kill stops it, `_on_enemy_died`).
		feel._hit_voice = voice
	if own:
		# Their own spell: the cue `self_hit` (a ring in its own colour) on this frame, so it is
		# never taken for an enemy's hit.
		_job_cues.play_cue(&"self_hit", caster, position)


## True when the hit on `target` (the actor `id`) by `caster` repeats the last one this physics
## frame and Feel step that was flashed, held and heard (same body, attacker and kind: `_juiced_*`); else it
## becomes that hit. Only an actor's hits are told apart.
func _repeat_hit(id: int, target: Node, caster: int) -> bool:
	if id < 0 or id >= _juiced_frame.size() or target == null:
		return false
	var frame: int = Engine.get_physics_frames()
	var body: int = target.get_instance_id()
	var kind: StringName = feel._kind if body == feel._kind_target and frame == feel._kind_frame else &""
	if _juiced_frame[id] == frame and _juiced_step[id] == feel._steps and _juiced_body[id] == body and _juiced_by[id] == caster and _juiced_kind[id] == kind:
		return true
	_juiced_frame[id] = frame
	_juiced_step[id] = feel._steps
	_juiced_body[id] = body
	_juiced_by[id] = caster
	_juiced_kind[id] = kind
	return false


## The kind of the hit that `damage_dealt` announces next, and whether an actor hit itself.
func _on_hit_landed(caster: int, target: Node, _amount: float, _position: Vector2, kind: StringName, shot: int, card: StringName) -> void:
	if target == null:
		return
	feel._kind_target = target.get_instance_id()
	feel._kind = kind
	feel._kind_shot = shot
	feel._kind_card = card
	feel._kind_frame = Engine.get_physics_frames()
	feel._kind_own = kind != &"heal" and kind != &"status" and caster != ActorsScript.NONE and FeelScript._actor_of(target) == caster


## Whether the hit on `target` by `caster` that `damage_dealt` announces shows its look: as its shot's
## impact decided (`_impact_looked`), else counted now (`_body_looks`, by the caster's first staff). A
## hit of no body always shows.
func _damage_look_shown(target: Node, caster: int) -> bool:
	if target == null or not is_instance_valid(target):
		return true
	var body: int = target.get_instance_id()
	if body == feel._impact_target and caster == feel._impact_caster and Engine.get_physics_frames() == feel._impact_frame:
		return feel._impact_looked
	return _body_looks.take(body, SpectacleScript.hit_group(caster, 0))


## A shot struck. On a character, remember how, for the damage event that follows at once; a hit
## past its body's looks this frame for its staff (`_body_looks`) shows nothing, nor does its damage.
## On a wall or pillar (`target` is null), show the impact.
func _on_projectile_impact(caster: int, target: Node, position: Vector2, direction: Vector2) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var projectiles: ProjectileManagerScript = feel.projectiles
	var spectacle: SpectacleScript = feel._spectacle
	var tag: int = projectiles.impact_tag if projectiles != null else 0
	if target == null:
		_wall_impact(caster, tag, position, direction)
		return
	feel._impact_target = target.get_instance_id()
	feel._impact_caster = caster
	feel._impact_frame = Engine.get_physics_frames()
	feel._impact_looked = _body_looks.take(feel._impact_target, SpectacleScript.hit_group(caster, tag))
	if not feel._impact_looked:
		feel._impact_shown = false
		return
	var ramp: int = feel._ramp_of(caster)
	# One hit: its motes all spray or none do, by its staff's share of the frame's (`hit_shares.gd`).
	feel._impact_shown = spectacle.begin_hit(caster, tag)
	feel._impact_at = position
	feel._impact_aim = direction
	feel._impact_tag = tag
	# Its cards' motes back along the way it came, in its own ramp.
	if projectiles != null:
		spectacle.shed_hit(position, -direction, projectiles.impact_core, ramp, projectiles.impact_look, feel.preset.hit_mote_share, tag)
	feel._hit_flash = true
	_show_impact(caster, ramp, position, direction)
	feel._hit_flash = false
	spectacle.end_hit()


## A shot of `caster`'s (tagged `tag`) ended on a wall or pillar at `position`, flying `direction`:
## knocked back off the surface, the shot's own motes and the wall's, and its impact. As on a body,
## only a staff's first shot to end on a spot of the wall (WALL_SPOT pixels a side) shows its look
## in a frame (`_body_looks`, by the spot): a volley into one wall reads as one burst a spot, not
## dozens stacked (performance, 2026-11-17: wall impacts were Feel's costliest, uncapped).
func _wall_impact(caster: int, tag: int, position: Vector2, direction: Vector2) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var spectacle: SpectacleScript = feel._spectacle
	if not _body_looks.take(_wall_spot(position), SpectacleScript.hit_group(caster, tag)):
		return
	var ramp: int = feel._ramp_of(caster)
	spectacle.begin_hit(caster, tag)
	spectacle.shed_on_wall(ramp, position, -direction)
	_show_impact(caster, ramp, position, direction)
	spectacle.end_hit()


## The key of the wall spot `at` is on for `_body_looks`: below zero, so it is never a body's
## instance id (those are positive).
static func _wall_spot(at: Vector2) -> int:
	var x: int = floori(at.x / FeelScript.WALL_SPOT) & 0xFFFF
	var y: int = floori(at.y / FeelScript.WALL_SPOT) & 0xFFFF
	return -1 - (y * 65536 + x)


## A bolt or orbit shot whose life ran out goes off: the cue `expire` (a small pop of its own
## colours where it was and a puff of its cards' motes on along the way it flew, a share of their
## count; S6), with the shot's own look while the event is sent. One that ended on a wall already
## showed its impact, and a still one (a rune, a wall's stone) goes off its own way.
func _on_projectile_expired(caster: int, position: Vector2, tag: int, shot: int) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var projectiles: ProjectileManagerScript = feel.projectiles
	if projectiles == null or projectiles.expired_on_wall:
		return
	var body: int = projectiles.impact_body
	if body != ProjectileManagerScript.KIND_BOLT and body != ProjectileManagerScript.KIND_ORBIT:
		return
	_job_cues.play_cue(&"expire", caster, position, projectiles.impact_heading, 0.0, projectiles.impact_core, projectiles.impact_look, ActorsScript.NONE, shot, -1, tag)


## A shot was deflected (melee I5; docs/milestones/M2-staffs.md, "The look"): the cue `deflect`,
## a big white-hot cross in its new caster's (`caster`'s) colours, bigger than a hit's, aimed the
## way it leaves (`shot`, the deflected shot). Its longer tail needs
## nothing here: it flies 1.7x faster, and its tail is a pixel per pixel of travel.
func _on_shot_deflected(caster: int, position: Vector2, _tag: int, shot: int) -> void:
	if not position.is_finite() or caster < ActorsScript.NONE or caster >= ActorsScript.ACTORS:
		return
	var heading: Vector2 = Vector2.RIGHT
	if feel.projectiles != null and shot >= 0:
		heading = feel.projectiles.get_velocity_of(shot) as Vector2
	_job_cues.play_cue(&"deflect", caster, position, heading)


## A shot was blocked. A shot's own shield (`shot`, the shielded shot) blocks as a barrier does: its
## shell loses that charge's motes (`barriers.gd`) and the cue `shield_block` plays where the
## blocked shot was, turned back toward the shield. A swing's block is a parry (`shield · swing`; the
## projectile manager's `impact_carrier` says which carrier blocked): the cue `parry`, a big
## four-point star in Spark gold and a local stop on the parrying actor alone. Other carriers'
## blocks show nothing of their own.
func _on_shot_blocked(caster: int, position: Vector2, _tag: int, shot: int) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var projectiles: ProjectileManagerScript = feel.projectiles
	if projectiles == null or not position.is_finite():
		return
	if shot >= 0:
		var from: Vector2 = projectiles.get_position_of(shot)
		_job_cues.play_cue(FeelScript.SHIELD_BLOCK_CUE, caster, position, (position - from).normalized() if from.is_finite() and from != position else Vector2.ZERO)
		feel._spectacle.shot_blocked(shot, position)
		return
	if projectiles.impact_carrier != &"swing":
		return
	_job_cues.play_cue(CueBase.PARRY_CUE, caster, position)


## The payoff of a shot, on a body or a wall: the `impact_cue` of the card the shot is (the
## projectile manager's `impact_carrier_card` while the impact is sent; `impact`, a flare, for none), in the
## shot's colour and cards (its `impact_core`, `impact_look` and `impact_tag`) and its caster's `ramp`:
## an enemy's lands the same way, in the enemy ramp (staffs F7: one look for every spell). As big as
## the card's radius: a rune goes off in `rune_burst`, a wall's adds a ring (`impact_ring`).
func _show_impact(caster: int, ramp: int, position: Vector2, direction: Vector2) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var projectiles: ProjectileManagerScript = feel.projectiles
	var carrier_card: StringName = &""
	var core: Color = Color.WHITE
	var bits: int = 0
	var tag: int = 0
	if projectiles != null:
		carrier_card = projectiles.impact_carrier_card
		core = projectiles.impact_core
		bits = projectiles.impact_look
		tag = projectiles.impact_tag
	var cues: Array = _job_cues._carrier_card_cues_of(carrier_card)
	_job_cues.play_cue(cues[FeelScript.CUE_IMPACT] as StringName, caster, position, direction, cues[FeelScript.CUE_RADIUS] as float, core, bits, ActorsScript.NONE, -1, -1, tag, true, FeelScript.NO_BODY, ramp)


## A death: its body breaks into motes of its own art (S3; the white-hot copy that fell apart
## pixel by pixel before), then the cue `enemy_death` (a white-hot ring, its motes and mark, and a
## puff in the body's own colour; the killer and the shot hold for the kill, the dead body is freed
## at once) or, for a boss, `boss_death`, which also stops the whole game. The killing blow's sound
## gives way to the death's. A layered body (its `BodyPart`s, boss plan OB8) breaks each part into
## motes (a share of each, `REMNANT_MOTE_SHARE`) and leaves its parts as a remnant flying apart
## (`remnants.gd`).
func _on_enemy_died(killer: int, enemy: Node, position: Vector2, shot: int) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var preset: FeelPresetScript = feel.preset
	var projectiles: ProjectileManagerScript = feel.projectiles
	# The body breaks into motes of its own art (S3), from where it stood at its rest scale.
	var body: Sprite2D = _body_sprite(enemy)
	var art: Sprite2D = _body_art(body)
	if body != null and art != body:
		_leave_remnant(body, enemy)
	elif body != null:
		feel._spectacle.break_body(body, _rest_transform(body, enemy), preset.death_mote_kind, preset.death_mote_share, preset.death_mote_most, preset.death_mote_speed, preset.death_mote_up)
	# The hit that killed it (its flash still showing here) is silenced for the death's sound.
	if feel._hit_voice >= 0 and feel._hit_slot >= 0 and feel._hit_position == position and _flash_seconds[feel._hit_slot] > 0.0:
		if feel.audio != null:
			feel.audio.stop(feel._hit_voice)
	# Its motes: the killing shot's cards' kinds (read while the event is sent), and the surface
	# kinds in the colours of the body's own art.
	var look: int = 0
	var core: Color = Color.WHITE
	if projectiles != null and shot >= 0:
		look = projectiles.get_look_of(shot)
		core = projectiles.get_core_of(shot)
	# What broke is the body: its surface kinds and marks in the colours of its own art, its puff in
	# its own colour.
	# A body whose data names its own death sound sounds it in place of the cue's (boss plan OB15).
	feel._sound_instead = (enemy as Actor).data.death_sound if enemy is Actor and (enemy as Actor).data != null else &""
	_job_cues.play_cue(CueBase.BOSS_DEATH_CUE if _is_boss(enemy) else CueBase.ENEMY_DEATH_CUE, killer, position, Vector2.ZERO, 0.0, core, look, ActorsScript.NONE, shot, feel._spectacle.body_source(art), 0, true, _hit_color_of(enemy))


## A dead layered body: each part breaks into a share of its motes, and the parts fly apart as a
## remnant from the body's middle to the floor at its feet.
## Both from the body at its rest scale: a body killed mid-squash (the killing hit's) breaks and
## flies as it stood, as a body of one sprite does (`_rest_transform`). The motes of all its parts
## together are at most the preset's most.
func _leave_remnant(body: Sprite2D, enemy: Node) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var preset: FeelPresetScript = feel.preset
	var parts: Array[BodyPart] = []
	BodyPart.parts_of(body, parts)
	var unsquash: Transform2D = _rest_transform(body, enemy) * body.global_transform.affine_inverse()
	var most: int = maxi(preset.death_mote_most / maxi(parts.size(), 1), 1)
	for part in parts:
		if part.texture != null and part.is_visible_in_tree():
			feel._spectacle.break_body(part, unsquash * part.global_transform, preset.death_mote_kind, preset.death_mote_share * FeelScript.REMNANT_MOTE_SHARE, most, preset.death_mote_speed, preset.death_mote_up)
	var feet: Vector2 = (enemy as Node2D).global_position
	var middle: Vector2 = feet + ((enemy as Actor).body_offset if enemy is Actor else Vector2.ZERO)
	feel._remnants.leave(body, middle, feet.y, unsquash)


## The sprite a body's art is: its `Sprite`, or, for a layered body (it has `BodyPart`s, whatever
## its `Sprite` shows; boss plan OB8), its first part with art (null for none).
func _body_art(body: Sprite2D) -> Sprite2D:
	if body == null:
		return null
	var parts: Array[BodyPart] = []
	BodyPart.parts_of(body, parts)
	if parts.is_empty():
		return body
	for part in parts:
		if part.texture != null:
			return part
	return null


## A hit's shake, looks and sound (its stop is the game's, `HitStop`).
## A hit with an `aim` (the way the shot flew) sprays along it, `size` times as big, from `at`,
## in the ramp of `tint` (white: `player`'s colours); without one it is a puff at `position`.
func _juice(position: Vector2, shake: float, sound: StringName, aim: Vector2 = Vector2.ZERO, tint: Color = Color.WHITE, size: float = 1.0, at: Vector2 = Vector2.INF, player: int = 0) -> void:
	if feel.shake_enabled and _job_view._in_picture(position):
		_job_view._refresh_camera()
		_job_view._shake(shake)
	if position != Vector2.INF:
		# The cue `hit` (a spray and its sparks along the way the shot flew) or, with no way,
		# `hit_puff`, `size` steps of HIT_STEP pixels big, in the hit body's colours.
		var from: Vector2 = position if at == Vector2.INF else at
		var zoom: int = clampi(roundi(size), 1, 3)
		feel._cue_flash = -1
		feel._hit_flash = true
		_job_cues.play_cue(&"hit" if aim != Vector2.ZERO else &"hit_puff", ActorsScript.NONE, from, aim, zoom * FeelScript.HIT_STEP, tint, 0, ActorsScript.NONE, -1, -1, 0, true, FeelScript.NO_BODY, player)
		feel._hit_flash = false
		feel._hit_slot = feel._cue_flash
		feel._hit_position = position
	if sound != &"" and feel._hit_sounds >= FeelScript.HIT_SOUNDS_PER_FRAME:
		feel._hit_voice = -1
		return
	feel._hit_voice = feel._play(sound, position, _hit_repeats.volume(sound, feel._clock) if sound != &"" else 0.0)
	if feel._hit_voice >= 0:
		feel._hit_sounds += 1


## The own colour of a body that is no wizard: its enemy data's `hit_color`, or the default for a
## body with none (a stand-in).
static func _hit_color_of(body: Node) -> Color:
	if body is Actor and (body as Actor).data != null:
		return (body as Actor).data.hit_color
	return EnemyBase.DEFAULT_HIT_COLOR


## True for the death of a boss: an enemy whose data says `boss`.
static func _is_boss(enemy: Node) -> bool:
	return enemy is Actor and (enemy as Actor).data != null and (enemy as Actor).data.boss
