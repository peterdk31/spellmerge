class_name SpellStrikes
extends Object
## A hit with no shot of its own (core/spells/spells.gd): the hit path as a ray (`_ray_begin`,
## `_ray_end`), what strikes an area or a list of bodies (`_strike`, `_strike_round`, `_blast`), a
## beam's or a swing's ray (`_shoot_ray`) and its guard against shots, and what a carrier leaves on
## the floor and on the way (`_touch_floor`, `_spill`, the passed elements). Methods working on the
## runtime (`rt`), whose members hold all of it (core/README.md, "The spell runtime").

const Runtime := preload("res://core/spells/spells.gd")

## Not state (core/sim/README.md): the runtime, the other jobs this one calls and the runtime's
## arrays it works on, each the runtime's own (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"rt", &"_job_fires", &"_pass_casters", &"_pass_tags", &"_pass_elements", &"_pass_at", &"_rec_chain", &"_rec_prev", &"_rays", &"_strike_bodies", &"_strike_marks", &"_ray_guard_points"]

var rt: Runtime = null
var _job_fires: SpellFires = null
var _pass_casters: PackedInt32Array
var _pass_tags: PackedInt64Array
var _pass_elements: Array[StringName]
var _pass_at: PackedVector2Array
var _rec_chain: PackedInt32Array
var _rec_prev: PackedInt64Array
var _rays: Array[RayHit]
var _strike_bodies: Array[Node]
var _strike_marks: PackedVector2Array
var _ray_guard_points: PackedVector2Array


## Takes the runtime's arrays and jobs, by the names in DERIVED: again whenever the runtime's
## arrays may have been replaced (`SpellRuntime._link_jobs`).
func link(runtime: Runtime) -> void:
	rt = runtime
	for name: StringName in DERIVED:
		if name != &"rt":
			set(name, runtime.get(name))


## Sends a ray: until `_ray_end`, every hit with no shot slot is this one (`_on_hit`, `hit_profile`,
## `_relay`), with `tag`'s cards, going along `dir`, with `chain` jumps left after `prev`, hitting
## with `hit` when not its spell's own (null), as a zap of shot `zap_slot` (-1 for none). Returns the
## record, so a sweep can turn `dir` from body to body and read what `relay` left in `hit`.
func _ray_begin(tag: int, dir: Vector2, chain: int, prev: int, hit: HitProfile, zap_slot: int) -> RayHit:
	rt._ray_depth += 1
	if rt._ray_depth == _rays.size():
		_rays.append(RayHit.new())
	rt._ray = _rays[rt._ray_depth]
	rt._ray.set_to(tag, dir, chain, prev, hit, zap_slot)
	return rt._ray


## Ends the ray `_ray_begin` sent: the one it was sent from (or none) is the ray again.
func _ray_end() -> void:
	rt._ray.hit = null
	rt._ray_depth -= 1
	rt._ray = _rays[rt._ray_depth]


## The one strike (rules R4 F2): the carrier `spell` with `tag` hits each of the first `found`
## bodies of the last `Projectiles.sweep` round `centre` that is not in `struck` yet (and adds it),
## where the sweep met it, as a ray (`_ray_begin`) that `_on_hit` reads: its infusions, heavy,
## chain (`chain` jumps left, `prev` the body before), siphon, possess, relay and `on hit` go with
## it, and the hit's push throws the body outward from `centre` (a whole circle strikes from
## `centre`, `Projectiles.sweep`). `hit` is what it hits with when not its spell's own (an echo's),
## else null. A swing, a slam, a dash, a teleport and a blast all strike through here. The
## bodies are copied out first (onto `_strike_bodies`): what a hit sets off can sweep. Returns what
## it hit with at the end (relay may have taken an element on), for a carrier that strikes again
## to keep, as a live beam does.
func _strike(spell: CompiledSpell, tag: int, actor: int, found: int, struck: Array, centre: Vector2, chain: int, prev: int, hit: HitProfile) -> HitProfile:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var first: int = _strike_bodies.size()
	for i in found:
		var node: Node = projectiles.sweep_nodes[i]
		if not struck.has(node):
			struck.append(node)
			_strike_bodies.append(node)
			_strike_marks.append(projectiles.sweep_points[i])
			_strike_marks.append(projectiles.sweep_heads[i])
	return _strike_listed(spell, tag, actor, first, centre, chain, prev, hit)


## `_strike` of bodies a carrier picked itself (a Pulse's ring: those its segments reach): the
## first `count` of `nodes`, each struck at its `points` entry going along its `heads` entry, those
## not in `struck` yet (and adds them).
func _strike_bodies_at(spell: CompiledSpell, tag: int, actor: int, nodes: Array[Node], points: PackedVector2Array, heads: PackedVector2Array, count: int, struck: Array, centre: Vector2, chain: int, prev: int, hit: HitProfile) -> HitProfile:
	var first: int = _strike_bodies.size()
	for i in count:
		var node: Node = nodes[i]
		if not struck.has(node):
			struck.append(node)
			_strike_bodies.append(node)
			_strike_marks.append(points[i])
			_strike_marks.append(heads[i])
	return _strike_listed(spell, tag, actor, first, centre, chain, prev, hit)


## Strikes the bodies `_strike_bodies[first..]` (and their marks), then drops them: the ray every
## strike hits through.
func _strike_listed(spell: CompiledSpell, tag: int, actor: int, first: int, centre: Vector2, chain: int, prev: int, hit: HitProfile) -> HitProfile:
	var last: int = _strike_bodies.size()
	if last == first:
		return hit
	var ray: RayHit = _ray_begin(tag, Vector2.RIGHT, chain, prev, hit, -1)
	for n in range(first, last):
		var point: Vector2 = _strike_marks[n * 2]
		var head: Vector2 = _strike_marks[n * 2 + 1]
		ray.dir = centre.direction_to(point) if not centre.is_equal_approx(point) else head
		rt.projectiles.strike(actor, _strike_bodies[n], point, head, tag, spell.carrier_card_id)
	var took: HitProfile = ray.hit
	_ray_end()
	_strike_bodies.resize(first)
	_strike_marks.resize(first * 2)
	_job_fires._cast_jumps()
	return took


## The carrier `spell` with `tag` strikes every body within `reach` of `at` at once (`_strike`),
## with `hit` (null: its own): a teleport where it lands, a blast. It strikes
## every body there, its caster's own too, but `spare` (a melee carrier's body, `CarrierKit.spared`:
## a teleport's, which lands with it), and a wall hides none (owner, 2026-11-06).
func _strike_round(spell: CompiledSpell, tag: int, actor: int, at: Vector2, way: Vector2, reach: float, hit: HitProfile, chain: int = -1, prev: int = 0, spare: Node = null) -> void:
	var found: int = rt.projectiles.sweep(actor, at, way, 1, -PI, PI, reach, Runtime.HITS, spare, false)
	if found > 0:
		_strike(spell, tag, actor, found, [], at, spell.chain_jumps if chain < 0 else chain, prev, hit)


## A `blast` at the end point `at` of the carrier with `tag`: its explosion (`cue_shown`, the cue
## its blast card names) and a strike of everything within its strength (`_strike_round`,
## `everyone`): each body it catches is a hit of the carrier (rules R4 F2), with what the carrier
## hits with now as `burst` (`CompiledSpell.blast_hit`) and the chain jumps it has left (the ray's
## being sent, else the shot `shot`'s), so a jump's blast jumps no further than the jump. Its hits
## blast no more. Nothing without a blast.
func _blast(spell: CompiledSpell, tag: int, actor: int, at: Vector2, shot: int = -1) -> void:
	var radius: float = spell.behaviour(ModifierBase.Behaviour.BLAST)
	if radius <= 0.0 or rt.events == null or not at.is_finite():
		return
	rt.cue_tag = tag
	rt.events.cue_shown.emit(actor, spell.cue_of(ModifierBase.Behaviour.BLAST), at, Vector2.ZERO, radius, spell.tint, spell.look)
	rt.cue_tag = 0
	_touch_floor(spell, actor, at, radius, tag)
	var chain: int = spell.chain_jumps
	var prev: int = 0
	if tag == rt._ray.tag:
		chain = rt._ray.chain
		prev = rt._ray.prev
	elif shot >= 0 and rt._same(shot) and rt.projectiles.get_tag_of(shot) == tag:
		chain = _rec_chain[shot]
		prev = _rec_prev[shot]
	var was: bool = rt._blasting
	rt._blasting = true
	_strike_round(spell, tag, actor, at, Vector2.RIGHT, radius, _blast_hit(spell, rt.hit_profile(tag, shot)), chain, prev)
	rt._blasting = was


## Each element of `spell` touched the floor within `radius` of `at` (`floor_touched`, ground cover
## GC5, rule 5: one event an element, in its infusions' order), for whatever lies on the floor (the
## cover area); a spell with Spill touches its strength wider (docs/milestones/oil-spill.md). Nothing
## for a spell of no element.
func _touch_floor(spell: CompiledSpell, actor: int, at: Vector2, radius: float, tag: int) -> void:
	if rt.events == null or spell == null or not at.is_finite():
		return
	var wide: float = maxf(radius, 0.0) + spell.behaviour(ModifierBase.Behaviour.SPILL)
	for element: StringName in spell.element_ids:
		rt.events.floor_touched.emit(actor, element, at, wide, tag)


## A carrier of `spell` that only passes over the floor (a dash, a swing, a beam) landed at `at`:
## with Spill its elements touch the floor Spill's strength round it (`_touch_floor`); nothing
## without (its passing touches are its own, `_pass_floor`).
func _spill(spell: CompiledSpell, actor: int, at: Vector2, tag: int) -> void:
	if spell != null and spell.behaviour(ModifierBase.Behaviour.SPILL) > 0.0:
		_touch_floor(spell, actor, at, 0.0, tag)


## The shots the projectile manager's last step handed back as entering a new floor cell
## (`Projectiles.trail_slot`, in slot order): each element of what each hits with (a relay's, an
## infusion's) passes over the floor along its step's way, every 16 px (a fast shot crosses more than a
## cell a step: no gap is left along its line).
func _trail_shots() -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if projectiles == null:
		return
	for n in projectiles.trail_count():
		var slot: int = projectiles.trail_slot(n)
		if not projectiles.is_alive(slot):
			continue
		var tag: int = projectiles.get_tag_of(slot)
		var hit: HitProfile = rt.hit_profile(tag, slot)
		if hit == null:
			continue
		var actor: int = projectiles.get_actor_of(slot)
		_add_way(actor, tag, hit.element_ids, projectiles.get_prev_of(slot), projectiles.get_position_of(slot))


## Each element of `spell` passes over the floor along `from` to `to` (a dash's way, a swing's tip,
## a beam's end: `CarrierKit.pass_floor`), once every floor cell's side and at `to` (not at `from`,
## the last step's `to`; a way of no length passes at `to`).
func _pass_floor(spell: CompiledSpell, tag: int, actor: int, from: Vector2, to: Vector2) -> void:
	if spell != null:
		_add_way(actor, tag, spell.element_ids, from, to)


## Each of `elements` passes over the floor along `from` to `to`: once every PASS_SPACING px (at
## most PASS_MOST) and at `to`, never at `from` (the last step's `to`).
func _add_way(actor: int, tag: int, elements: Array[StringName], from: Vector2, to: Vector2) -> void:
	if elements.is_empty() or not to.is_finite():
		return
	if from.is_finite():
		var way: Vector2 = to - from
		var steps: int = mini(ceili(way.length() / Runtime.PASS_SPACING), Runtime.PASS_MOST)
		for n in range(1, steps):
			var at: Vector2 = from + way * (float(n) / float(steps))
			for element: StringName in elements:
				_add_pass(actor, tag, element, at)
	for element: StringName in elements:
		_add_pass(actor, tag, element, to)


func _add_pass(actor: int, tag: int, element: StringName, at: Vector2) -> void:
	_pass_casters.append(actor)
	_pass_tags.append(tag)
	_pass_elements.append(element)
	_pass_at.append(at)


## The tick's passing touches, sent once (`floor_passed`) and emptied.
func _send_passed() -> void:
	if _pass_elements.is_empty():
		return
	if rt.events != null:
		rt.events.floor_passed.emit(_pass_casters, _pass_tags, _pass_elements, _pass_at)
	_pass_casters.resize(0)
	_pass_tags.resize(0)
	_pass_elements.clear()
	_pass_at.resize(0)


## A shot (or a ray) of `spell` ended at `at`: its elements touch the floor there, within its radius
## (rule 5); a shot with a blast touches as its blast does (`_blast`), so not twice.
func _touch_end(spell: CompiledSpell, actor: int, at: Vector2, tag: int) -> void:
	if spell == null or spell.behaviour(ModifierBase.Behaviour.BLAST) > 0.0:
		return
	_touch_floor(spell, actor, at, spell.radius, tag)


## One beam (a chain jump of any ray): counted while it is cast, with its context set
## for the hit handler. It pierces as its carrier does and passes walls with ghost.
func _shoot_ray(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, chain: int, prev: int, source: Node, length: float = -1.0, hit: HitProfile = null) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	rt.shot_started(tag)
	var ray: RayHit = _ray_begin(tag, heading, chain, prev, hit, -1)
	var reach: float = spell.ray_length if length < 0.0 else length
	var got: float = projectiles.ray(actor, origin, heading, reach, spell.pierce, Runtime.HITS, tag, spell.radius * 0.5, source, _bounces(spell), Runtime._ghost(spell))
	var end: Vector2 = origin + heading * got
	var end_heading: Vector2 = heading
	if got > 0.0 and (spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0 or spell.behaviour(ModifierBase.Behaviour.SHIELD) > 0.0):
		_ray_guard_points[0] = origin
		_ray_guard_points[1] = end
		var count: int = 2
		if projectiles.ray_path_count > 2:
			count = mini(projectiles.ray_path_count, _ray_guard_points.size())
			for n in count:
				_ray_guard_points[n] = projectiles.ray_path[n]
		# A chain jump of any ray (a swing's or a slam's too) blocks as a ray, never as its carrier: a
		# swing's jump is no parry.
		_guard_path(spell, tag, actor, _ray_guard_points, 0, count, got, spell.radius * 0.5, roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD)), Runtime.RAY_CARD)
	if got > 0.0 and projectiles.ray_path_count > 2:
		# It turned at walls: a cue for every straight leg, and it ends where the last one does.
		end = projectiles.ray_end
		end_heading = projectiles.ray_end_heading
		if rt.events != null:
			for n in projectiles.ray_path_count - 1:
				var from: Vector2 = projectiles.ray_path[n]
				var to: Vector2 = projectiles.ray_path[n + 1]
				if not from.is_equal_approx(to):
					rt.events.carrier_shown.emit(actor, Runtime.RAY_CARD, from, from.direction_to(to), from.distance_to(to), spell.tint, spell.look)
	elif got > 0.0 and rt.events != null:
		rt.events.carrier_shown.emit(actor, Runtime.RAY_CARD, origin, heading, got, spell.tint, spell.look)
	# A `ray()` that did nothing (too deep, or a bad aim) has no end to fire the payload from.
	if got > 0.0:
		_touch_end(spell, actor, end, tag)
		_blast(spell, tag, actor, end)
	if got > 0.0:
		_job_fires._fire_payloads(spell, TriggerBase.Event.EXPIRE, tag, actor, end, end_heading, null)
	_ray_end()
	rt.shot_ended(tag)
	_job_fires._cast_jumps()


## The shots of other teams touching the path `points[first]` to `points[first + count - 1]`
## (cut `reach` pixels along) of a beam with `tag`, `width` pixels either side as its
## hits: each is deflected off the line (`deflect`), else stopped while `charges` last (melee
## I3); a block is sent as the carrier `carrier`'s (`_guard`). Returns the charges left.
func _guard_path(spell: CompiledSpell, tag: int, actor: int, points: PackedVector2Array, first: int, count: int, reach: float, width: float, charges: int, carrier: StringName) -> int:
	var deflects: bool = spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	if (not deflects and charges <= 0) or count < 2 or reach <= 0.0:
		return charges
	var walked: float = 0.0
	for n in range(first, first + count - 1):
		var a: Vector2 = points[n]
		var b: Vector2 = points[n + 1]
		var piece: float = a.distance_to(b)
		if walked + piece > reach:
			b = a.move_toward(b, reach - walked)
		var found: int = rt.projectiles.shots_on_segment(actor, a, b, width)
		charges = _guard(found, actor, tag, deflects, charges, a, b, carrier)
		walked += piece
		if walked >= reach or (not deflects and charges <= 0):
			break
	return charges


## Deflects (with `deflects`) or stops (while `charges` last) the `found` shots of
## `Projectiles.guard_slots` that touched a carrier of `actor` with `tag`: outward from `a` when
## `b` is INF (a swing's hand), else off the segment from `a` to `b` (a beam's line);
## a block is sent as `carrier`'s, the carrier's id (`block_shot`: Feel tells a swing's parry by it).
## Returns the charges left. The list is copied first: what a deflect sets off can run another guard.
func _guard(found: int, actor: int, tag: int, deflects: bool, charges: int, a: Vector2, b: Vector2, carrier: StringName) -> int:
	if found == 0:
		return charges
	return _guard_shots(rt.projectiles.guard_slots.slice(0, found), actor, tag, deflects, charges, a, b, carrier)


## `_guard` of the shots a carrier picked itself (`slots`, a list it keeps: a Pulse's ring, those its
## segments reach).
func _guard_shots(slots: PackedInt32Array, actor: int, tag: int, deflects: bool, charges: int, a: Vector2, b: Vector2, carrier: StringName) -> int:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	for slot in slots:
		if not projectiles.is_alive(slot):
			continue
		var at: Vector2 = projectiles.get_position_of(slot)
		if deflects:
			var from: Vector2 = a if not b.is_finite() else Geometry2D.get_closest_point_to_segment(at, a, b)
			var normal: Vector2 = at - from
			if normal.is_zero_approx():
				normal = -projectiles.get_velocity_of(slot)
			projectiles.deflect_shot(slot, actor, normal, tag)
		elif charges > 0:
			charges -= 1
			projectiles.block_shot(slot, actor, tag, carrier)
	return charges


## How many times `spell`'s beam turns at a wall: its bounce cards' count.
func _bounces(spell: CompiledSpell) -> int:
	return roundi(spell.behaviour(ModifierBase.Behaviour.BOUNCE))


## What a blast of `spell` strikes with when its carrier hits with `hit`: the compiled `burst` copy
## of its own hit or its echo's, else (relay took an element on, a jump's parent hit) a new one.
func _blast_hit(spell: CompiledSpell, hit: HitProfile) -> HitProfile:
	if hit == spell.hit and spell.blast_hit != null:
		return spell.blast_hit
	if hit == spell.echo_hit and spell.echo_blast_hit != null:
		return spell.echo_blast_hit
	return StaffCompiler.blast_hit(hit if hit != null else spell.hit)
