class_name FeelBeams
extends Object
## Feel's beams: the live beams drawn from Spells every frame along their paths (`_draw_live_beams`,
## thinned past LIVE_BEAM_POINTS), a beam shown whole and fading (`_on_carrier_shown`), their sounds
## and motes, the beam and swing meshes, and the carrier cards' own looks and shaders. Methods
## working on Feel (`feel`), whose members hold all of it.

const FeelScript := preload("res://gameplay/feel/feel.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const BEAM_SHADER: Shader = preload("res://core/projectiles/shot_beam.gdshader")
const BirthsScript := preload("res://gameplay/feel/births.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SwingTrailsScript := preload("res://gameplay/feel/swing_trails.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## Not Feel's own: Feel, the other jobs this one calls and Feel's containers it works on, each
## Feel's own (shared, never a copy), linked by `link`.
const LINKED: Array[StringName] = [&"feel", &"_job_casts", &"_job_cues", &"_live_beams", &"_carrier_card_looks", &"_live_paths", &"_thin_points", &"_thin_keep", &"_thin_turn", &"_thin_sorted", &"_shown_beams", &"_shown_beam_paths", &"_shown_beam_left", &"_shown_beam_total", &"_shown_beam_body", &"_shown_beam_ramp", &"_shown_beam_look", &"_shown_beam_tint", &"_shown_beam_tag", &"_next_shown_beam"]

static var _beam_mesh: ArrayMesh = null
static var _swing_mesh: ArrayMesh = null
var feel: FeelScript = null
var _job_casts: FeelCasts = null
var _job_cues: FeelCues = null
var _live_beams: Array[MeshInstance2D]
var _carrier_card_looks: Dictionary
var _live_paths: Array[PackedVector3Array]
var _thin_points: PackedVector2Array
var _thin_keep: PackedByteArray
var _thin_turn: PackedFloat32Array
var _thin_sorted: PackedFloat32Array
var _shown_beams: Array[MeshInstance2D]
var _shown_beam_paths: Array[PackedVector3Array]
var _shown_beam_left: PackedFloat32Array
var _shown_beam_total: PackedFloat32Array
var _shown_beam_body: PackedColorArray
var _shown_beam_ramp: PackedInt32Array
var _shown_beam_look: PackedInt32Array
var _shown_beam_tint: PackedColorArray
var _shown_beam_tag: PackedInt64Array
var _next_shown_beam: PackedInt32Array
## What each live beam's node (`_live_beams`, by index) was last given of the uniforms that seldom
## change, in LIVE_SET's order: `_draw_live_beams` sets one only when its value changes (a fan of
## split beams is dozens of nodes, #972), and every one again when the node's shader changes. Feel's
## own; an entry is made with its node.
var _live_set: Array[Array] = []
## The order of `_live_set`'s entries.
enum LiveSet { SHADER, CORE, BODY, LEAD, WIDTH, PLAYER, LOOK, INFUSIONS, INFUSION_COUNT, FADE, SWELL, GLOW, SIZE }


## Takes Feel and its containers and jobs, by the names in LINKED (`Feel._link_jobs`).
func link(owner: FeelScript) -> void:
	feel = owner
	for name: StringName in LINKED:
		if name != &"feel":
			set(name, owner.get(name))


## The carrier card `carrier_card`'s look as the area `drawer` (Carrier.LOOK_BEAM, LOOK_SWING) draws it
## (`Spells.look_of`; `CardLook.PLAIN` with no Spells, no card, or a card another area draws), asked
## once per id and kept: a cast allocates nothing.
func _carrier_card_look_of(carrier_card: StringName, drawer: int) -> CardLook:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var spells: Node = feel.spells
	var cache: Dictionary = _carrier_card_looks.get(drawer, {})
	var known: CardLook = cache.get(carrier_card) as CardLook
	if known != null:
		return known
	if spells == null or carrier_card == &"" or not spells.has_method(&"look_of"):
		return CardLook.PLAIN
	var look: CardLook = spells.call(&"look_of", carrier_card, drawer) as CardLook
	cache[carrier_card] = look
	_carrier_card_looks[drawer] = cache
	return look


## The shader that draws the carrier card `carrier_card`'s look in the area `drawer`, or `plain` when its
## card names none (or is drawn by another area).
func _carrier_card_shader_of(carrier_card: StringName, drawer: int, plain: Shader) -> Shader:
	var shader: Shader = _carrier_card_look_of(carrier_card, drawer).shader
	return shader if shader != null else plain


## Warms the carrier cards' own shaders Feel draws (beams' and swing trails', one mesh each:
## `Spells.look_shaders`) before the first room, as it warms its own; Spells knows nothing of how.
func _warm_card_looks() -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var spells: Node = feel.spells
	if spells == null or not spells.has_method(&"look_shaders"):
		return
	for drawer: int in [Carrier.LOOK_BEAM, Carrier.LOOK_SWING]:
		for shader: Shader in spells.call(&"look_shaders", drawer):
			ShaderWarmupScript.want(shader, ShaderWarmupScript.MESH)
	# The portals' lenses are a batch of quads (`portal_look.gd`).
	for shader: Shader in spells.call(&"look_shaders", Carrier.LOOK_PORTAL):
		ShaderWarmupScript.want(shader, ShaderWarmupScript.BATCH)


## Gives `node`'s own material `shader` (a beam's or a trail's: each node keeps its own material,
## since each sets its own uniforms), only when it has another, so nothing is recompiled per cast.
static func _use_shader(node: CanvasItem, shader: Shader) -> void:
	var material: ShaderMaterial = node.material as ShaderMaterial
	if material.shader != shader:
		material.shader = shader


## A beam's node: a beam mesh in world space drawn by the beam shader, hidden until shown.
func _make_beam() -> MeshInstance2D:
	var node := MeshInstance2D.new()
	node.mesh = beam_mesh()
	var material := ShaderMaterial.new()
	material.shader = BEAM_SHADER
	node.material = material
	node.top_level = true
	node.visible = false
	node.z_index = FeelScript.SHOWN_BEAM_Z
	feel.add_child(node)
	return node


func _make_beam_path() -> PackedVector3Array:
	var path := PackedVector3Array()
	path.resize(FeelScript.LIVE_BEAM_POINTS)
	return path


## The mesh a beam is drawn as (`shot_beam.gdshader`, PARTICLES ARE GEOMETRY there): small quads
## told in their UV which quad kind (BEAM_Q_*) and slot they are, in BEAM_QUADS' order, as
## `flash_mesh`. The shader places them along the beam's path in the world, so the mesh says
## nothing of where: it is never culled (its box is the whole world). Made once.
static func beam_mesh() -> ArrayMesh:
	if _beam_mesh == null:
		_beam_mesh = FeelFlashes._quads_mesh(FeelScript.BEAM_QUADS)
		_beam_mesh.custom_aabb = BatchesScript.WORLD
	return _beam_mesh


## The mesh a swing's trail is drawn as (`SwingTrailsScript.SWING_QUADS`; Q_* in
## `shot_swing.gdshader`), as `beam_mesh`. Made once.
static func swing_mesh() -> ArrayMesh:
	if _swing_mesh == null:
		_swing_mesh = FeelFlashes._quads_mesh(SwingTrailsScript.SWING_QUADS)
		_swing_mesh.custom_aabb = BatchesScript.WORLD
	return _swing_mesh


## The shader a swing of the carrier card `carrier_card` trails with (its `look_shader`, or the plain trail's).
func _swing_shader_of(carrier_card: StringName) -> Shader:
	return _carrier_card_shader_of(carrier_card, Carrier.LOOK_SWING, SwingTrailsScript.SHADER)


## The shader's player for a swing of `actor` (`_beam_ramp` of its ramp).
func _swing_ramp(actor: int) -> int:
	return _beam_ramp(feel._ramp_of(actor))


## A carrier showed itself: its card's `shown_cue` (where a teleport leaves, each end of a swap, a decoy or familiar
## appearing, a dash's dust and lightning arc, S5), then a beam (drawn by `shot_beam.gdshader` in
## the element's ramp) with the cast's cards, in the caster's ramp: an enemy's look the same, in the
## enemy ramp (staffs F7). The beam keeps state of its own (its slot while it fades), so it stays
## in code. A slam's strike is its end (`carrier_ended`); its
## wind-up shows only on the staff (the rising, glowing staff: a ring there distracted from it).
func _on_carrier_shown(caster: int, carrier_card: StringName, origin: Vector2, direction: Vector2, length: float, tint: Color, look: int) -> void:
	if caster < ActorsScript.NONE or caster >= ActorsScript.ACTORS or not origin.is_finite():
		return
	var cue: StringName = _job_cues._carrier_card_cues_of(carrier_card)[FeelScript.CUE_SHOWN] as StringName
	if cue != &"":
		_job_cues.play_cue(cue, caster, origin, direction, length, tint, look, ActorsScript.NONE, -1, -1, _job_cues._cue_tag())
	# A move's staff's own moment besides (boss plan OB15: a Sweep's swish, held until it lands);
	# never another carrier of its cast (its `on wall` pulse), which sends no end.
	var tag: int = _job_cues._cue_tag()
	var own: StaffBase = _job_casts._staff_of_tag(tag)
	if own != null and own.move_cue != &"" and _job_casts._moves_along(tag):
		feel._cue_move = tag
		_job_cues.play_cue(own.move_cue, caster, origin, direction, length, tint, look, ActorsScript.NONE, -1, -1, tag)
		feel._cue_move = 0
	var ramp: int = feel._ramp_of(caster)
	if carrier_card != &"beam" or length <= 0.0 or direction == Vector2.ZERO:
		return
	var seconds: float = feel.preset.beam_seconds
	if seconds <= 0.0:
		return
	# Each seat's caster reuses only its own oldest slots, so nobody's beams push out another's;
	# the actors no seat drives share one seat's worth (by budget), so a crowd never takes a seat's.
	var who: int = feel._budget_of(caster)
	var slot: int = who * FeelScript.SHOWN_BEAMS_PER_PLAYER + _next_shown_beam[who]
	_next_shown_beam[who] = (_next_shown_beam[who] + 1) % FeelScript.SHOWN_BEAMS_PER_PLAYER
	var node: MeshInstance2D = _shown_beams[slot]
	var end: Vector2 = origin + direction.normalized() * length
	var path: PackedVector3Array = _shown_beam_paths[slot]
	path[0] = Vector3(origin.x, origin.y, 0.0)
	path[1] = Vector3(end.x, end.y, length)
	# Drawn by its card's own shader (`CarrierCard.look_shader`), or the plain beam's.
	_use_shader(node, _carrier_card_shader_of(carrier_card, Carrier.LOOK_BEAM, BEAM_SHADER))
	var material: ShaderMaterial = node.material as ShaderMaterial
	material.set_shader_parameter(&"core_override", Color(tint.r, tint.g, tint.b, 1.0))
	# A path of two points, BEAM_LEAD past each end, so the flares are whole.
	material.set_shader_parameter(&"beam_path", path)
	material.set_shader_parameter(&"beam_points", 2)
	material.set_shader_parameter(&"beam_width", FeelScript.BEAM_TEXTURE_HEIGHT)
	material.set_shader_parameter(&"beam_length", length)
	material.set_shader_parameter(&"beam_lead", FeelScript.BEAM_LEAD)
	material.set_shader_parameter(&"beam_start", origin)
	material.set_shader_parameter(&"beam_end", end)
	material.set_shader_parameter(&"beam_player", _beam_ramp(ramp))
	material.set_shader_parameter(&"beam_look", look)
	# A shown beam carries its tint and look only: its look works its infusion out from them.
	material.set_shader_parameter(&"beam_infusion_count", 0)
	material.set_shader_parameter(&"beam_glow", feel.preset.beam_alpha)
	var body: Color = Color.WHITE
	if feel.projectiles != null:
		body = feel.projectiles.tint_of(caster)
	_shown_beam_body[slot] = body
	_shown_beam_ramp[slot] = _beam_ramp(ramp)
	_shown_beam_look[slot] = look
	_shown_beam_tint[slot] = tint
	_shown_beam_tag[slot] = _job_cues._cue_tag()
	_shown_beam_left[slot] = seconds
	_shown_beam_total[slot] = seconds
	node.visible = true
	_pose_shown_beam(slot, 1.0)


## Fade the beams, and give off their motes.
func _step_shown_beams(real_delta: float) -> void:
	for i in FeelScript.SHOWN_BEAM_SLOTS:
		if _shown_beam_left[i] <= 0.0:
			continue
		_shown_beam_left[i] -= real_delta
		if _shown_beam_left[i] <= 0.0:
			_shown_beams[i].visible = false
			continue
		var t: float = _shown_beam_left[i] / _shown_beam_total[i]
		_pose_shown_beam(i, t)
		var path: PackedVector3Array = _shown_beam_paths[i]
		var from: Vector2 = Vector2(path[0].x, path[0].y)
		var end: Vector2 = Vector2(path[1].x, path[1].y)
		_beam_motes(path, 2, path[1].z, end, from.direction_to(end), t, _shown_beam_ramp[i], _shown_beam_look[i], _shown_beam_tint[i], _shown_beam_tag[i], real_delta)


## Draw every live beam where it is this frame: along its curve, as far as it got, in its owner's
## tint with its element's colour in the core. It flares on each hit, flickers a little and fades
## over the last quarter of its life. Nothing is allocated.
## Marks in `_thin_keep` which of the `all` points of live beam `i` to draw when it has more than
## LIVE_BEAM_POINTS: its two ends and the LIVE_BEAM_POINTS - 2 points where it turns most (a wall
## it bounces off turns it sharply, a target it bends at less, a point of a gentle curve hardly),
## the first of equal ones; the points of its gentlest curves are dropped. Only a path that long
## (many pierce cards on a homing beam, many bounces) comes here; its scratch grows to the
## longest path seen.
func _thin_beam(beams: Object, i: int, all: int) -> void:
	if _thin_keep.size() < all:
		_thin_keep.resize(all)
		_thin_turn.resize(all)
		_thin_points.resize(all)
	_thin_sorted.resize(all - 2)
	for n in all:
		_thin_points[n] = beams.call(&"beam_point", i, n)
	var prev: Vector2 = _thin_points[0]
	var here: Vector2 = _thin_points[1]
	for n in range(1, all - 1):
		var next: Vector2 = _thin_points[n + 1]
		var into: Vector2 = here - prev
		var out: Vector2 = next - here
		var turn: float = 0.0 if into.is_zero_approx() or out.is_zero_approx() else absf(into.angle_to(out))
		_thin_turn[n] = turn
		_thin_sorted[n - 1] = turn
		prev = here
		here = next
	_thin_sorted.sort()
	var room: int = FeelScript.LIVE_BEAM_POINTS - 2
	var least: float = _thin_sorted[all - 2 - room]
	var above: int = 0
	for n in range(1, all - 1):
		if _thin_turn[n] > least:
			above += 1
	var equal_room: int = room - above
	_thin_keep[0] = 1
	_thin_keep[all - 1] = 1
	for n in range(1, all - 1):
		var keep: bool = _thin_turn[n] > least
		if not keep and _thin_turn[n] == least and equal_room > 0:
			keep = true
			equal_room -= 1
		_thin_keep[n] = 1 if keep else 0


func _draw_live_beams(real_delta: float) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var preset: FeelPresetScript = feel.preset
	var spells: Node = feel.spells
	var spectacle: SpectacleScript = feel._spectacle
	if spectacle != null:
		spectacle.light_beams_begin()
	if feel._beam_sounds != null:
		feel._beam_sounds.new_frame()
	var count: int = 0
	# The beams' rows (`Spells.carrier(&"beam")`, a `CarrierBeam`).
	var beams: Object = spells.call(&"carrier", &"beam") if spells != null and spells.has_method(&"carrier") else null
	if beams != null:
		count = int(beams.call(&"beam_slots"))
	while _live_beams.size() < count:
		_live_beams.append(_make_beam())
		_live_paths.append(_make_beam_path())
	while _live_set.size() < _live_beams.size():
		var last: Array = []
		last.resize(LiveSet.SIZE)
		_live_set.append(last)
	# What the beams' rows can tell, asked once a frame (a stand-in may lack some).
	var has_look: bool = beams != null and beams.has_method(&"beam_look")
	var has_card: bool = beams != null and beams.has_method(&"beam_carrier_card")
	var has_growth: bool = beams != null and beams.has_method(&"beam_growth")
	var has_infusions: bool = beams != null and beams.has_method(&"beam_infusions")
	var has_tag: bool = beams != null and beams.has_method(&"beam_tag")
	for i in _live_beams.size():
		var node: MeshInstance2D = _live_beams[i]
		if i >= count or not bool(beams.call(&"beam_on", i)):
			if node.visible:
				node.visible = false
			continue
		var all: int = int(beams.call(&"beam_point_count", i))
		var points: int = mini(all, FeelScript.LIVE_BEAM_POINTS)
		# A longer path keeps the points that shape it most (`_thin_beam`).
		var thin: bool = all > FeelScript.LIVE_BEAM_POINTS
		if thin:
			_thin_beam(beams, i, all)
		var reach: float = beams.call(&"beam_reach", i)
		var origin: Vector2 = beams.call(&"beam_point", i, 0) if points > 0 else Vector2.INF
		if reach <= 0.0 or points < 2 or not origin.is_finite():
			node.visible = false
			continue
		# Its path up to where it got: whole pieces, then the last one cut short, each point with
		# how far along the beam it is. The shader draws it BEAM_LEAD past each end, so the flares
		# there are whole.
		var path: PackedVector3Array = _live_paths[i]
		var walked: float = 0.0
		var prev: Vector2 = origin
		var used: int = 1
		var end_at: Vector2 = origin
		path[0] = Vector3(origin.x, origin.y, 0.0)
		for n in range(1, all):
			if used == FeelScript.LIVE_BEAM_POINTS:
				break
			if thin and _thin_keep[n] == 0:
				continue
			var point: Vector2 = _thin_points[n] if thin else beams.call(&"beam_point", i, n)
			var piece: float = prev.distance_to(point)
			if walked + piece >= reach:
				end_at = prev.move_toward(point, reach - walked)
				walked = reach
				path[used] = Vector3(end_at.x, end_at.y, walked)
				used += 1
				break
			walked += piece
			path[used] = Vector3(point.x, point.y, walked)
			end_at = point
			used += 1
			prev = point
		var before: Vector3 = path[used - 2]
		var end_dir: Vector2 = Vector2(before.x, before.y).direction_to(end_at)
		var since: float = beams.call(&"beam_since_hit", i)
		# It dissolves at its end as its carrier says (`Carrier.fade_left`), when it acts no more.
		var fade: float = beams.call(&"beam_fade", i)
		var flare: float = 1.0 + preset.beam_flare * maxf(1.0 - since / maxf(preset.beam_seconds * preset.beam_flare_share, 0.001), 0.0)
		var flicker: float = 1.0 - preset.beam_flicker_depth * float(int(since * preset.beam_flicker_rate) % 2)
		# Drawn across a fixed width; flare, flicker and fade swell and dissolve its pixels instead
		# of stretching them.
		var caster: int = beams.call(&"beam_caster", i)
		var body: Color = Color.WHITE
		if feel.projectiles != null:
			body = feel.projectiles.tint_of(caster)
		var tint: Color = beams.call(&"beam_tint", i)
		var ramp: int = _beam_ramp(feel._ramp_of(caster))
		var look_id: int = int(beams.call(&"beam_look", i)) if has_look else 0
		# Drawn by its card's own shader (`CarrierCard.look_shader`), or the plain beam's, and lit as
		# its card says (`look_light_intensity`, `look_light_reach`).
		var look: CardLook = _carrier_card_look_of(beams.call(&"beam_carrier_card", i) as StringName if has_card else &"", Carrier.LOOK_BEAM)
		var shader: Shader = look.shader if look.shader != null else BEAM_SHADER
		var last: Array = _live_set[i]
		if last[LiveSet.SHADER] != shader:
			# Another shader: every uniform is given again.
			_use_shader(node, shader)
			last.fill(null)
			last[LiveSet.SHADER] = shader
		var material: ShaderMaterial = node.material as ShaderMaterial
		var core: Color = Color(tint.r, tint.g, tint.b, 1.0)
		if last[LiveSet.CORE] != core:
			material.set_shader_parameter(&"core_override", core)
			last[LiveSet.CORE] = core
		var body_tint: Color = Color(body.r, body.g, body.b, fade * preset.beam_alpha)
		if last[LiveSet.BODY] != body_tint:
			material.set_shader_parameter(&"body_tint", body_tint)
			last[LiveSet.BODY] = body_tint
		material.set_shader_parameter(&"beam_path", path)
		material.set_shader_parameter(&"beam_points", used)
		material.set_shader_parameter(&"beam_length", walked)
		if last[LiveSet.LEAD] != FeelScript.BEAM_LEAD:
			material.set_shader_parameter(&"beam_lead", FeelScript.BEAM_LEAD)
			last[LiveSet.LEAD] = FeelScript.BEAM_LEAD
		material.set_shader_parameter(&"beam_start", origin)
		material.set_shader_parameter(&"beam_end", end_at)
		material.set_shader_parameter(&"sim_time", feel._clock)
		# A growing beam is drawn wider as it hits wider (growth, rules R4f).
		var grown: float = float(beams.call(&"beam_growth", i)) if has_growth else 1.0
		var width: float = FeelScript.BEAM_WIDTH * grown
		if last[LiveSet.WIDTH] != width:
			material.set_shader_parameter(&"beam_width", width)
			last[LiveSet.WIDTH] = width
		if last[LiveSet.PLAYER] != ramp:
			material.set_shader_parameter(&"beam_player", ramp)
			last[LiveSet.PLAYER] = ramp
		if last[LiveSet.LOOK] != look_id:
			material.set_shader_parameter(&"beam_look", look_id)
			last[LiveSet.LOOK] = look_id
		# Every infusion on it, in slot order, for a look that shows each (the beam card's strands).
		var infusions: PackedColorArray = beams.call(&"beam_infusions", i) if has_infusions else PackedColorArray()
		if last[LiveSet.INFUSIONS] != infusions:
			material.set_shader_parameter(&"beam_infusions", infusions)
			last[LiveSet.INFUSIONS] = infusions
		var infusion_count: int = mini(infusions.size(), FeelScript.BEAM_INFUSIONS_MOST)
		if last[LiveSet.INFUSION_COUNT] != infusion_count:
			material.set_shader_parameter(&"beam_infusion_count", infusion_count)
			last[LiveSet.INFUSION_COUNT] = infusion_count
		if last[LiveSet.FADE] != fade:
			material.set_shader_parameter(&"beam_fade", fade)
			last[LiveSet.FADE] = fade
		var swell: float = maxf(fade, 0.35) * flare * flicker * grown
		if last[LiveSet.SWELL] != swell:
			material.set_shader_parameter(&"beam_swell", swell)
			last[LiveSet.SWELL] = swell
		if last[LiveSet.GLOW] != preset.beam_alpha:
			material.set_shader_parameter(&"beam_glow", preset.beam_alpha)
			last[LiveSet.GLOW] = preset.beam_alpha
		node.visible = true
		_sound_beam(beams, i, caster, origin, fade)
		_beam_motes(path, used, walked, end_at, end_dir, fade, ramp, look_id, tint, int(beams.call(&"beam_tag", i)) if has_tag else 0, real_delta)
		# Spell light along the same path (P3b; through the spectacle, `SpellLight.light_beam`).
		if spectacle != null:
			spectacle.light_beam(i, path, used, ramp, look_id, tint, fade, look.light_intensity, look.light_reach)


## The sound of live beam `i` of `beams` (its card's hum and its infusions' loops, `beam_sounds.gd`)
## for this frame, from its caster's body (else its `origin`): an enemy's ENEMY_CAST_VOLUME quieter,
## as its cast is; a prop's none (the world's); as it dissolves (`fade`, 1 to 0) it fades with it,
## down to BEAM_FADE_FLOOR.
func _sound_beam(beams: Object, i: int, caster: int, origin: Vector2, fade: float) -> void:
	if feel._beam_sounds == null or not beams.has_method(&"beam_elements"):
		return
	# This frame's beams hold all the sounds they may: the hold would refuse this one.
	if feel._beam_sounds.full():
		return
	var table: ActorsScript = feel._actor_table()
	var team: int = table.team_of(caster) if table != null else ActorsScript.TEAM_WIZARDS
	if team == ActorsScript.TEAM_WORLD:
		return
	var body: Node2D = table.node_of(caster) as Node2D if table != null and table.is_open(caster) else null
	var card: StringName = beams.call(&"beam_carrier_card", i) as StringName
	var elements: Array[StringName] = beams.call(&"beam_elements", i)
	var volume: float = FeelScript.ENEMY_CAST_VOLUME if team == ActorsScript.TEAM_ENEMIES else 0.0
	volume += maxf(linear_to_db(maxf(fade, 0.0001)), FeelScript.BEAM_FADE_FLOOR)
	feel._beam_sounds.hold(card, elements, caster, body, origin, volume)


## The motes a beam gives off over `seconds` (see BEAM_SPLASH_RATE), into the spectacle's births
## while motes are on: its path is the first `points` of `path` (x, y and how far along), `length`
## pixels long, landing at `end_at` going `end_dir`, `fade` whole (1 to 0), of the shader ramp
## `ramp` (0-3 a hat ramp, -1 the enemies'), the look `look`, the tint `tint`, the spell of `tag`.
func _beam_motes(path: PackedVector3Array, points: int, length: float, end_at: Vector2, end_dir: Vector2, fade: float, ramp: int, look: int, tint: Color, tag: int, seconds: float) -> void:
	if seconds <= 0.0 or points < 2 or not feel._spectacle.motes_on():
		return
	var births: BirthsScript = feel._spectacle.births
	var core: Color = Color(tint.r, tint.g, tint.b, 1.0)
	if fade > FeelScript.BEAM_SPLASH_FADE:
		for n in births.roll(FeelScript.BEAM_SPLASH_RATE * seconds):
			if not births.add(end_at, -end_dir, 0, ramp, look, core, tag):
				return
	var kinds: int = BirthsScript.emitting_count(look)
	if kinds == 0 or length <= 0.0:
		return
	for n in births.roll(float(mini(4 + 2 * kinds, FeelScript.BEAM_PARTICLES_MOST)) * FeelScript.BEAM_PARTICLE_RATE * seconds):
		var along: float = length * births.dice()
		var k: int = 1
		while k < points - 1 and path[k].z < along:
			k += 1
		var a: Vector2 = Vector2(path[k - 1].x, path[k - 1].y)
		var b: Vector2 = Vector2(path[k].x, path[k].y)
		var span: float = path[k].z - path[k - 1].z
		var at: Vector2 = a.lerp(b, clampf((along - path[k - 1].z) / span, 0.0, 1.0)) if span > 0.0 else a
		var way: Vector2 = a.direction_to(b)
		var out: Vector2 = Vector2(-way.y, way.x) * (1.0 if births.dice() < 0.5 else -1.0)
		if not births.add(at, out, births.emitting_layer(look), ramp, look, core, tag):
			return


## Show beam `slot` at `t` (1 just shown, 0 gone): its rim and glow swell for its first moments
## (the payoff), then thin and flicker, and it dissolves into pixels (`beam_swell`, `beam_fade`).
func _pose_shown_beam(slot: int, t: float) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var preset: FeelPresetScript = feel.preset
	var body: Color = _shown_beam_body[slot]
	var age: float = 1.0 - t
	var material: ShaderMaterial = _shown_beams[slot].material as ShaderMaterial
	material.set_shader_parameter(&"sim_time", feel._clock)
	material.set_shader_parameter(&"body_tint", Color(body.r, body.g, body.b, t * preset.beam_alpha))
	var flare: float = 1.0 + preset.beam_flare * maxf(1.0 - age / preset.beam_flare_share, 0.0)
	var step: int = int(age * _shown_beam_total[slot] * preset.beam_flicker_rate)
	var flicker: float = 1.0 - preset.beam_flicker_depth * float(step % 2)
	material.set_shader_parameter(&"beam_swell", t * flare * flicker)
	material.set_shader_parameter(&"beam_fade", t)


## The shader's `beam_player` for `ramp`: the hat ramp 0-3, or -1 for the enemy ramp.
static func _beam_ramp(ramp: int) -> int:
	return ramp if ProjectileManagerScript.is_hat_ramp(ramp) else -1
