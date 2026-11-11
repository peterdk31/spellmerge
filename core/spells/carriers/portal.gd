class_name CarrierPortal
extends Carrier
## A portal (`&"portal"`; docs/milestones/portal.md): one cast opens a mouth a step ahead along the
## aim and `shots` exits `ray_length` ahead, fanned as a split fans shots, each facing out along its
## own way. Its cards act on what comes out of it (owner, 2026-11-05: no rules of its own): its
## infusion, and its homing, which steers what leaves it onto a target.
## What goes into the mouth comes out of every exit, and what goes into an exit comes out of the
## mouth: it works both ways (owner, 2026-11-05), so a foe can fire back through it. It belongs to
## no team: anybody's shots, beams and bodies go through.
##
## Its gates (the mouth and the exits) are rows of the projectile manager (`open_gate`), which
## rays read as they walk (a beam goes on from the other side: `CarrierBeam`); this carrier moves
## the flying shots that went in (`Projectiles.shots_into_gates`: the first way out keeps the shot,
## every other is a full copy of it) and the bodies (`target_move_requested`, the exits taken in
## turn), as often as they come to it (no cap: owner, 2026-11-09; a shot passes once a step and
## its life runs on, a body rests `PORTAL_REST` after each pass). It hurts nothing itself; its
## infusion goes to everything that comes out of it (owner, 2026-11-05). Its end points are every
## gate: its blast, its `on expire` payload and its end look happen at each when it closes.

## Not state: scratch, refilled before every use (core/sim/README.md).
const DERIVED: Array[StringName] = [&"_outs", &"_near", &"_near_centres", &"_near_radii"]
## State as who they point at: the bodies resting after a pass (core/sim/README.md).
const REFS: Array[StringName] = [&"_rest_body"]

## The live portals, rows that double when every one is on: on, its birth (its gates' group), its
## spell and tag, its caster, its life left and whole span, its gates (the mouth first, then the
## exits; `_pt_stride` a row, `_pt_gates_used` used), the exit the next body takes, how big its
## gates were made, and when its gates next zap and how many rolls its zaps have used.
var _pt_on: PackedByteArray = PackedByteArray()
var _pt_born: PackedInt64Array = PackedInt64Array()
var _pt_next_born: int = 1
var _pt_spell: Array[CompiledSpell] = []
var _pt_tag: PackedInt64Array = PackedInt64Array()
var _pt_actor: PackedInt32Array = PackedInt32Array()
var _pt_life: PackedFloat32Array = PackedFloat32Array()
var _pt_span: PackedFloat32Array = PackedFloat32Array()
var _pt_gates: PackedInt32Array = PackedInt32Array()
var _pt_gates_used: PackedInt32Array = PackedInt32Array()
var _pt_turn: PackedInt32Array = PackedInt32Array()
var _pt_radius: PackedFloat32Array = PackedFloat32Array()
var _pt_zap_at: PackedFloat32Array = PackedFloat32Array()
var _pt_zap_rolls: PackedInt32Array = PackedInt32Array()
var _pt_stride: int = SpellLimits.PORTAL_EXITS_START + 1
## The bodies that came through a portal, and the clock time each may go through again.
var _rest_body: Array[Node2D] = []
var _rest_until: PackedFloat64Array = PackedFloat64Array()

var _outs: PackedInt32Array = PackedInt32Array()
var _near: Array[Node2D] = []
var _near_centres: PackedVector2Array = PackedVector2Array()
var _near_radii: PackedFloat32Array = PackedFloat32Array()


func id() -> StringName:
	return &"portal"


## What draws its look: Feel's portal gates (a card's `look_shader` draws each gate's lens; the
## lips and drift round it are motes), read through `read_view`.
func look_drawer() -> int:
	return LOOK_PORTAL


## The portals of the runtime `spells` (its bound `portal` carrier), for what reads its own
## getters (the looks, the tests).
static func of(spells: SpellRuntime) -> CarrierPortal:
	return spells.carrier(&"portal") as CarrierPortal


## It stays a while where it was opened (its `lifetime`: slow keeps it open longer), homing steers
## what comes out of it, `reach` moves its exits further, `shots` is how many exits and `spread`
## fans them. It hits
## nothing itself and meets no shot (a shot that touches it goes through), so shield, deflect and
## the hit cards do nothing on it.
func traits() -> int:
	return STAYS | LASTS | STEERS | REACHES | SHOTS | SPREAD | GATES


func step_order() -> int:
	# Before beams: a beam that walks into a gate finds it open the step it opens.
	return 1


func required_fields() -> Dictionary:
	return {
		"ray_length": "A portal needs a `ray_length` above 0 (how far ahead its exit opens).",
		"radius": "A portal needs a `radius` above 0 (how big its gates are).",
	}


## Everything that comes out of it takes its infusion (owner, 2026-11-05), so an infusion counts
## on it although it hits nothing.
func takes_infusion(_blasts: bool) -> bool:
	return true


## What comes out of it takes an infusion's element and status, not its heal: an infusion with no
## status (mend) counts only when a blast carries it.
func takes_element(element: ElementBase, blasts: bool) -> bool:
	return blasts or element.status_id != &""


func reach_of(spell: CompiledSpell) -> float:
	return spell.ray_length


func bind(runtime_kit: CarrierKit, staff_poses: StaffPoses) -> void:
	super(runtime_kit, staff_poses)
	_fit_rows(SpellLimits.PORTAL_ROWS_START)


# --- Opening ---------------------------------------------------------------------------------

## One portal: its mouth a step ahead of `origin` along `direction`, facing it, and `spell.shots`
## exits (P1, P2). Returns 1 when it opened.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _source: Node, lifetime: float, _chain: int, _prev: int) -> int:
	if kit.projectiles == null or not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx():
		return 0
	var way: Vector2 = direction.normalized()
	var at: int = _pt_on.find(0)
	if at < 0:
		at = _pt_on.size()
		_fit_rows(at * 2)
	# Room for its mouth and every exit before any gate is written.
	var exits: int = maxi(spell.shots, 1)
	_fit_stride(exits + 1)
	var born: int = _pt_next_born
	_pt_next_born += 1
	_pt_on[at] = 1
	_pt_born[at] = born
	_pt_spell[at] = spell
	_pt_tag[at] = tag
	_pt_actor[at] = actor
	_pt_life[at] = lifetime
	_pt_span[at] = lifetime
	_pt_turn[at] = 0
	_pt_radius[at] = spell.radius
	_pt_zap_at[at] = kit.clock() + (SpellLimits.ZAP_AGAIN if spell.zap_chance > 0.0 else 0.0)
	_pt_zap_rolls[at] = 0
	var used: int = 0
	var mouth_at: Vector2 = kit.placed_at(spell, actor, origin, way)
	var mouth: int = kit.projectiles.open_gate(born, tag, mouth_at, way, spell.radius, true)
	if mouth >= 0:
		_pt_gates[at * _pt_stride] = mouth
		used = 1
	for n in exits:
		# Fanned as a split fans shots, each facing out along its own way (P1).
		var angle: float = DMath.angle(way) + kit.fan_angle(n, exits, spell) + kit.staff_spread(tag, spell)
		var face: Vector2 = DMath.from_angle(angle)
		var exit_at: Vector2 = _clear_of_walls(actor, origin, origin + face * spell.ray_length, spell.radius)
		var exit: int = kit.projectiles.open_gate(born, tag, exit_at, face, spell.radius, false)
		if exit >= 0:
			_pt_gates[at * _pt_stride + used] = exit
			used += 1
			if spell.fires_live():
				kit.live_join(spell, tag, SpellRuntime.LC_POINT, -1, born, false, lifetime, exit_at, face)
	_pt_gates_used[at] = used
	kit.shot_started(tag)
	if kit.events != null:
		for k in used:
			var gate: int = _pt_gates[at * _pt_stride + k]
			kit.set_cue_tag(tag)
			kit.events.form_shown.emit(actor, spell.form_id, kit.projectiles.gate_position(gate), kit.projectiles.gate_face(gate), spell.radius, spell.tint, spell.look)
			kit.set_cue_tag(0)
	return 1


## Where a gate meant for `to` opens: there, or short of the first wall from `from` (its caster
## `actor`'s cast, so its own footprint does not count), by `radius`.
func _clear_of_walls(actor: int, from: Vector2, to: Vector2, radius: float) -> Vector2:
	var clipped: Vector2 = kit.projectiles.clip_to_walls(from, to, actor)
	if clipped.is_equal_approx(to):
		return to
	var back: float = minf(radius, from.distance_to(clipped))
	return clipped - from.direction_to(clipped) * back if not clipped.is_equal_approx(from) else from


# --- Each step ---------------------------------------------------------------------------------

func step(delta: float) -> void:
	for at in _pt_on.size():
		if _pt_on[at] == 0:
			continue
		_pt_life[at] -= delta
		if _pt_life[at] <= 0.0:
			_close(at, true)
			continue
		_grow(at)
		_pull(at)
		_zap(at)
	if kit.projectiles != null and kit.projectiles.has_gates():
		_pass_shots()
		_pass_bodies()


## Growth widens its gates, as a growing shot widens, up to the room's size.
func _grow(at: int) -> void:
	var spell: CompiledSpell = _pt_spell[at]
	var growth: float = spell.behaviour(ModifierBase.Behaviour.GROWTH)
	if growth <= 1.0:
		return
	var radius: float = minf(_pt_radius[at] * DMath.pow(growth, _pt_span[at] - _pt_life[at]), maxf(kit.projectiles.room_size(), _pt_radius[at]))
	for k in _pt_gates_used[at]:
		kit.projectiles.set_gate_radius(_pt_gates[at * _pt_stride + k], radius)


## Magnet pulls the bodies within its card's reach toward every gate (each is a way in).
func _pull(at: int) -> void:
	var spell: CompiledSpell = _pt_spell[at]
	var reach: float = spell.behaviour(ModifierBase.Behaviour.MAGNET)
	if reach <= 0.0 or kit.events == null:
		return
	for k in _pt_gates_used[at]:
		var gate: int = _pt_gates[at * _pt_stride + k]
		var where: Vector2 = kit.projectiles.gate_position(gate)
		kit.events.pull_requested.emit(_pt_actor[at], where, reach, SpellLimits.MAGNET_PULL, _pt_tag[at], where)


## Zap: every SpellLimits.ZAP_AGAIN seconds each gate rolls its card's chance for every other
## body in reach and zaps the ones that win (a zap is a hit of the portal's own: its infusion).
func _zap(at: int) -> void:
	var spell: CompiledSpell = _pt_spell[at]
	if spell.zap_chance <= 0.0 or spell.zap_reach <= 0.0 or spell.zap_hit == null or kit.clock() < _pt_zap_at[at]:
		return
	_pt_zap_at[at] = kit.clock() + SpellLimits.ZAP_AGAIN
	var tag: int = _pt_tag[at]
	for k in _pt_gates_used[at]:
		var where: Vector2 = kit.projectiles.gate_position(_pt_gates[at * _pt_stride + k])
		var found: int = kit.projectiles.targets_near(where, spell.zap_reach, SpellRuntime.ProjectilesScript.ACTOR_LAYERS, kit.team(_pt_actor[at]), _near, _near_centres, _near_radii)
		for n in found:
			if not kit.zap_room():
				return
			var roll: float = SpellRuntime.zap_hash(_pt_born[at], _pt_zap_rolls[at])
			_pt_zap_rolls[at] += 1
			if roll < spell.zap_chance:
				kit.zap(spell, tag, where, _near_centres[n], 0, 0, spell.zap_hit)


## The flying shots that went into a gate this step come out of where it leads (P5): the first way
## out keeps the shot, each other gets a full copy of it, turned as the gates are, just outside.
func _pass_shots() -> void:
	var found: int = kit.projectiles.shots_into_gates()
	if found == 0:
		return
	# The list is the manager's, and a copy's spawn does not touch it, but a nested call might.
	var slots: PackedInt32Array = kit.projectiles.gate_shots.slice(0, found)
	var gates: PackedInt32Array = kit.projectiles.gate_shot_gates.slice(0, found)
	for i in found:
		var slot: int = slots[i]
		var gate: int = gates[i]
		if not kit.projectiles.is_alive(slot):
			continue
		var outs: int = kit.projectiles.gate_outs(gate, _outs)
		if outs == 0:
			continue
		var velocity: Vector2 = kit.projectiles.get_velocity_of(slot)
		var radius: float = kit.projectiles.get_radius_of(slot)
		var tag: int = kit.projectiles.get_tag_of(slot)
		var actor: int = kit.projectiles.get_actor_of(slot)
		var life: float = kit.projectiles.get_life_of(slot)
		var spell: CompiledSpell = kit.spell_of(tag)
		var portal: CompiledSpell = kit.spell_of(kit.projectiles.gate_tag(gate))
		var into: Vector2 = kit.projectiles.get_position_of(slot)
		_shown(gate, into, velocity)
		var first: int = _outs[0]
		var ways: PackedInt32Array = _outs.slice(0, outs)
		for k in outs:
			var to: int = ways[k]
			var way: Vector2 = kit.projectiles.gate_turn(gate, to, velocity)
			var out_at: Vector2 = _out_point(to, way, radius)
			var moved: int = -1
			if to == first:
				if kit.projectiles.pass_shot(slot, out_at, way):
					moved = slot
			elif spell != null and life > 0.0:
				moved = kit.projectiles.spawn(actor, out_at, way, life, radius, SpellRuntime.HITS, spell.pierce, tag)
				if moved >= 0 and kit.land_shot(moved, spell, tag, null, 0, 0) == 0:
					moved = -1
			if moved < 0:
				continue
			if portal != null:
				kit.infuse_shot(moved, portal.hit, portal.tint)
				# Its homing steers what comes out of it (the shot's own homing, if any, stays).
				if portal.homing_range > 0.0 and (spell == null or spell.homing_range <= 0.0):
					kit.projectiles.set_homing_curve(moved, portal.homing_curve, portal.homing_range)
			_shown(to, out_at, way)


## Where something going `way` comes out of gate `to`, `radius` pixels round: just outside it.
func _out_point(to: int, way: Vector2, radius: float) -> Vector2:
	var centre: Vector2 = kit.projectiles.gate_position(to)
	var out_way: Vector2 = way.normalized() if not way.is_zero_approx() else kit.projectiles.gate_face(to)
	var out: Vector2 = centre + out_way * (kit.projectiles.gate_radius(to) + radius + 1.0)
	return kit.projectiles.clip_to_walls(centre, out, SpellRuntime.ActorsScript.NONE)


## The bodies whose middle went into a gate come out of where it leads (P6): from a mouth, its
## exits in turn; small enough bodies only (the gate's size or less), and not again within
## SpellLimits.PORTAL_REST. A body is moved, not hit; the portal's infusion gives it its status.
func _pass_bodies() -> void:
	var now: float = kit.clock()
	for at in _pt_on.size():
		if _pt_on[at] == 0:
			continue
		for k in _pt_gates_used[at]:
			var gate: int = _pt_gates[at * _pt_stride + k]
			if not kit.projectiles.gate_open(gate):
				continue
			var centre: Vector2 = kit.projectiles.gate_position(gate)
			var radius: float = kit.projectiles.gate_radius(gate)
			var found: int = kit.projectiles.targets_near(centre, radius, SpellRuntime.ProjectilesScript.ACTOR_LAYERS, SpellRuntime.ActorsScript.NONE, _near, _near_centres, _near_radii)
			if found == 0:
				continue
			# Copied: a move below may change what the next query finds.
			var bodies: Array[Node2D] = _near.duplicate()
			var centres: PackedVector2Array = _near_centres.slice(0, found)
			var radii: PackedFloat32Array = _near_radii.slice(0, found)
			for n in found:
				var body: Node2D = bodies[n]
				if not is_instance_valid(body) or radii[n] > radius or centres[n].distance_to(centre) > radius or _resting(body, now):
					continue
				var outs: int = kit.projectiles.gate_outs(gate, _outs)
				if outs == 0:
					continue
				var to: int = _outs[_pt_turn[at] % outs] if kit.projectiles.gate_is_mouth(gate) else _outs[0]
				if kit.projectiles.gate_is_mouth(gate):
					_pt_turn[at] += 1
				var going: Vector2 = centres[n].direction_to(centre) if not centres[n].is_equal_approx(centre) else kit.projectiles.gate_face(gate)
				var way: Vector2 = kit.projectiles.gate_turn(gate, to, going)
				var out_at: Vector2 = _out_point(to, way, radii[n] + 1.0)
				var moved_by: Vector2 = out_at - centres[n]
				_rest(body, now + SpellLimits.PORTAL_REST)
				_shown(gate, centres[n], going)
				if kit.events != null:
					kit.events.target_move_requested.emit(_pt_actor[at], body, body.global_position + moved_by)
				_shown(to, out_at, way)
				_infuse_body(_pt_spell[at], _pt_actor[at], body)


## The portal's infusions put their statuses on `body`, which came through it.
func _infuse_body(spell: CompiledSpell, actor: int, body: Node2D) -> void:
	if kit.events == null or spell == null or spell.hit == null or spell.hit.element_ids.is_empty():
		return
	var hit: HitProfile = spell.hit
	if hit.status_id != &"":
		kit.events.status_requested.emit(actor, body, hit.status_id, hit.status_duration, hit.status_strength)
	for n in hit.later_status_ids.size():
		if hit.later_status_ids[n] != &"":
			kit.events.status_requested.emit(actor, body, hit.later_status_ids[n], hit.later_status_durations[n], hit.later_status_strengths[n])


## Something went through `gate` at `at` going `way`: its look (`portal_through`, a cue).
func _shown(gate: int, at: Vector2, way: Vector2) -> void:
	if kit.events == null:
		return
	var tag: int = kit.projectiles.gate_tag(gate)
	var spell: CompiledSpell = kit.spell_of(tag)
	var tint: Color = spell.tint if spell != null else Color.WHITE
	kit.events.cue_shown.emit(SpellTag.caster_of(tag), &"portal_through", at, way.normalized() if not way.is_zero_approx() else Vector2.RIGHT, kit.projectiles.gate_radius(gate), tint, 0)


# --- The bodies' rests -----------------------------------------------------------------------

func _resting(body: Node2D, now: float) -> bool:
	for i in _rest_body.size():
		if _rest_body[i] == body:
			return now < _rest_until[i]
	return false


func _rest(body: Node2D, until: float) -> void:
	var free: int = -1
	var now: float = kit.clock()
	for i in _rest_body.size():
		if _rest_body[i] == body:
			_rest_until[i] = until
			return
		if free < 0 and (not is_instance_valid(_rest_body[i]) or _rest_until[i] <= now):
			free = i
	if free < 0:
		free = _rest_body.size()
		_rest_body.append(null)
		_rest_until.append(0.0)
	_rest_body[free] = body
	_rest_until[free] = until


# --- Its end ---------------------------------------------------------------------------------

## Portal `at` closes. With `finished` (its life ran out) its blast, its `on expire` payload and its
## end look happen at every gate (P7); one switched off, rebuilt or dropped closes quietly.
func _close(at: int, finished: bool) -> void:
	if _pt_on[at] == 0:
		return
	_pt_on[at] = 0
	var spell: CompiledSpell = _pt_spell[at]
	var tag: int = _pt_tag[at]
	var actor: int = _pt_actor[at]
	_pt_spell[at] = null
	for k in _pt_gates_used[at]:
		var gate: int = _pt_gates[at * _pt_stride + k]
		var where: Vector2 = kit.projectiles.gate_position(gate)
		var face: Vector2 = kit.projectiles.gate_face(gate)
		var size: float = kit.projectiles.gate_radius(gate)
		kit.projectiles.close_gate(gate)
		if not finished or spell == null or not where.is_finite():
			continue
		if kit.events != null:
			kit.set_cue_tag(tag)
			kit.events.carrier_ended.emit(actor, spell.form_id, where, face, size, spell.tint, spell.look)
			kit.set_cue_tag(0)
		kit.blast(spell, tag, actor, where)
		if spell.fires_on(TriggerBase.Event.EXPIRE):
			kit.fire_payloads(spell, TriggerBase.Event.EXPIRE, tag, actor, where, face, null)
	_pt_gates_used[at] = 0
	kit.live_leave(tag, true)
	kit.shot_ended(tag)


func end_of(tag: int) -> void:
	for at in _pt_on.size():
		if _pt_on[at] != 0 and _pt_tag[at] == tag:
			_close(at, false)


func end_actor(actor: int) -> void:
	for at in _pt_on.size():
		if _pt_on[at] != 0 and _pt_actor[at] == actor:
			_close(at, false)


## A held portal is switched off: it closes quietly.
func switch_off(tag: int) -> void:
	end_of(tag)


func clear() -> void:
	_pt_on.fill(0)
	_pt_spell.fill(null)
	_pt_gates_used.fill(0)
	_rest_body.clear()
	_rest_until.clear()


## Widens every row's gates to room for `need` (the mouth and its exits), keeping each row's gates.
func _fit_stride(need: int) -> void:
	if need <= _pt_stride:
		return
	var wider: int = maxi(need, _pt_stride * 2)
	var gates := PackedInt32Array()
	gates.resize(_pt_on.size() * wider)
	for row in _pt_on.size():
		for k in _pt_gates_used[row]:
			gates[row * wider + k] = _pt_gates[row * _pt_stride + k]
	_pt_gates = gates
	_pt_stride = wider


func _fit_rows(size: int) -> void:
	var from: int = _pt_on.size()
	if size <= from:
		return
	for column: Variant in [_pt_on, _pt_born, _pt_spell, _pt_tag, _pt_actor, _pt_life, _pt_span, _pt_gates_used, _pt_turn, _pt_radius, _pt_zap_at, _pt_zap_rolls]:
		column.resize(size)
	_pt_gates.resize(size * _pt_stride)
	for n in range(from, size):
		_pt_on[n] = 0
		_pt_gates_used[n] = 0


# --- For the looks and the tests --------------------------------------------------------------

## The portal rows (`portal_on` says which are open).
func portal_slots() -> int:
	return _pt_on.size()


func portal_on(at: int) -> bool:
	return at >= 0 and at < _pt_on.size() and _pt_on[at] != 0


## The actor whose portal row `at` is (its look is drawn in that actor's colours).
func portal_caster(at: int) -> int:
	return _pt_actor[at]


func portal_tint(at: int) -> Color:
	return _pt_spell[at].tint if _pt_spell[at] != null else Color.WHITE


## How many gates portal `at` has (its mouth first), and the projectile manager's row of each.
func portal_gate_count(at: int) -> int:
	return _pt_gates_used[at] if portal_on(at) else 0


func portal_gate(at: int, n: int) -> int:
	return _pt_gates[at * _pt_stride + n]


## How whole portal `at` looks: its life left over its span (1 for a held one), 0 to 1.
func portal_left(at: int) -> float:
	if not portal_on(at) or _pt_span[at] <= 0.0 or _pt_span[at] >= SpellLimits.HOLD_LIFETIME:
		return 1.0
	return clampf(_pt_life[at] / _pt_span[at], 0.0, 1.0)


## Seconds portal `at` has been open, and seconds it has left (INF for a held one): how its look
## opens and closes.
func portal_seconds(at: int) -> Vector2:
	if not portal_on(at):
		return Vector2.ZERO
	var held: bool = _pt_span[at] <= 0.0 or _pt_span[at] >= SpellLimits.HOLD_LIFETIME
	return Vector2(maxf(_pt_span[at] - _pt_life[at], 0.0), INF if held else maxf(_pt_life[at], 0.0))


## How each different infusion on portal `at` looks, in slot order (`CompiledSpell.infusion_looks`:
## rgb its tint); empty for none. Read only.
func portal_infusions(at: int) -> PackedColorArray:
	return _pt_spell[at].infusion_looks if portal_on(at) and _pt_spell[at] != null else PackedColorArray()


## Open portals now (tests).
func portal_count() -> int:
	return _pt_on.count(1)


## What a viewer may know of the open portals and their gates now, into `view` (Feel's portal look:
## one typed read a frame, no getter called by name): each open portal's caster, look, core,
## infusions, seconds open and left, and its gates (the mouth first) where the projectile manager
## has them. Allocates nothing once `view` has held as many.
func read_view(view: PortalView) -> void:
	view.portals = 0
	view.gates = 0
	if kit == null or kit.projectiles == null:
		return
	var manager := kit.projectiles
	for at in _pt_on.size():
		if _pt_on[at] == 0 or _pt_gates_used[at] == 0:
			continue
		var p: int = view.portals
		var spell: CompiledSpell = _pt_spell[at]
		view.hold_portals(p + 1)
		view.key[p] = _pt_born[at]
		view.caster[p] = _pt_actor[at]
		view.look[p] = spell.look if spell != null else 0
		view.core[p] = spell.tint if spell != null else Color.WHITE
		view.infusions[p] = spell.infusion_looks if spell != null else PackedColorArray()
		var seconds: Vector2 = portal_seconds(at)
		view.since[p] = seconds.x
		view.left[p] = seconds.y
		view.first_gate[p] = view.gates
		var count: int = 0
		for n in _pt_gates_used[at]:
			var gate: int = _pt_gates[at * _pt_stride + n]
			var centre: Vector2 = manager.gate_position(gate)
			if not centre.is_finite():
				continue
			var g: int = view.gates
			view.hold_gates(g + 1)
			view.centre[g] = centre
			view.face[g] = manager.gate_face(gate)
			view.radius[g] = manager.gate_radius(gate)
			view.mouth[g] = 1 if manager.gate_is_mouth(gate) else 0
			view.gates += 1
			count += 1
		view.gate_count[p] = count
		view.portals += 1
