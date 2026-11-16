class_name Phases
extends ActorComponent
## A boss's phases (enemy AI AI7, docs/milestones/M2-enemy-ai.md, "The enemy's data"): the actor
## adds this component itself when its data has `phases` (`EnemyBase.phases`), so a boss is data,
## no scene of its own. It follows the body whoever drives it (a wizard possessing a boss still
## sees it change).
##
## Each step it checks the next phase's condition (`EnemyPhase.health_below`, a fraction of the
## most health, or `after_seconds` since the body appeared); the first that holds starts, once,
## in order. **Not during a possession** (boss plan OB7): a phase whose condition is met while the
## body is possessed starts when the possession ends, so the possessor never loses its staffs
## mid-cast. Starting one: its stats, when it names some, become the body's (`Stats.apply`; null
## keeps the last), the body is protected for its `transition` (`Health.protect`), its
## staffs are replaced (`Inventory.replace_hands`, items I8: the Caster's follow; each pool full), its look changes (the Face's
## style and glow, the body's size; the sprite by whoever draws it, from `started`), and the
## controller hears it (`ActorController.phase_started`: an AI stands through the transition and
## takes the phase's profile).
##
## **Its adds** (boss plan OB13, `EnemyPhase.adds`, `EnemyAdds`): as a phase starts, each of its adds
## entries is asked for on the bus (`adds_requested`: the body's actor id, the entry, its `key` and
## not a wave), and an entry with waves is asked again every `every` seconds while the phase lasts
## (`wave` true), counted by the body's own steps and not while it is possessed (whoever drives it
## calls nobody). Flow stands them (how many by the players in play, under the entry's cap) and lets
## them crumble when the body dies; the next phase's adds replace the last's waves.

## A phase began: its index in the data's `phases`, and the phase.
signal started(index: int, phase: EnemyPhase)

## The phases, in order (from the data).
var list: Array[EnemyPhase] = []
## The index of the phase in play (-1: the data's own staffs, before the first).
var current: int = -1
## Seconds since the body appeared.
var elapsed: float = 0.0
## Seconds to the next wave of each adds entry of the phase in play (one a entry; 0 for none).
var wave_left: PackedFloat64Array = PackedFloat64Array()

## How many adds entries a phase may have: an entry's `key` is its phase's index times this, plus
## its own index.
const ADDS_MOST: int = 16


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	list = owner_actor.data.phases if owner_actor.data != null else ([] as Array[EnemyPhase])


## Move time on and start the next phase when its condition holds.
func step(delta: float) -> void:
	elapsed += delta
	if actor.possessed_by == null:
		_count_waves(delta)
	var next: int = current + 1
	if next >= list.size():
		return
	var phase: EnemyPhase = list[next]
	if phase == null or actor.possessed_by != null or not _holds(phase):
		return
	begin(next)


## Start phase `index` now, whatever its condition.
func begin(index: int) -> void:
	if index < 0 or index >= list.size() or list[index] == null:
		return
	current = index
	var phase: EnemyPhase = list[index]
	# The stats first: the staffs below are built at their spell scale.
	var rescaled: bool = phase.stats != null and actor.stats != null and actor.stats.apply(phase.stats)
	if phase.transition > 0.0 and actor.health != null:
		actor.health.protect(phase.transition)
	if rescaled and phase.staffs.is_empty() and actor.caster != null:
		# The staffs it keeps are built again at the new size.
		actor.caster.rebuild()
	if not phase.staffs.is_empty() and actor.caster != null:
		var staffs: Array[StaffBase] = []
		var cards: Array = []
		for entry: StaffCards in phase.staffs.slice(0, EnemyBase.MAX_STAFFS):
			staffs.append(entry.staff if entry != null else null)
			cards.append(entry.cards.duplicate() if entry != null else [])
		# Through its inventory (every actor has one), so the staffs it holds stay its Caster's (items I8).
		actor.inventory.replace_hands(staffs, cards)
	if phase.look != null:
		_restyle(phase.look)
	if actor.controller != null:
		actor.controller.phase_started(actor, phase)
	_call_adds(index, phase)
	started.emit(index, phase)


## Which adds entry `entry` of phase `phase` is, for Flow's count of those alive (`adds_requested`).
static func adds_key(phase: int, entry: int) -> int:
	return phase * ADDS_MOST + entry


## The phase's burst of adds, and its waves' count started.
func _call_adds(index: int, phase: EnemyPhase) -> void:
	var entries: int = mini(phase.adds.size(), ADDS_MOST)
	wave_left.resize(entries)
	for k in entries:
		var adds: EnemyAdds = phase.adds[k]
		wave_left[k] = adds.every if adds != null and adds.has_waves() else 0.0
		if adds != null and adds.count + adds.per_player > 0:
			_ask(adds, adds_key(index, k), false)


## Each wave due of the phase in play.
func _count_waves(delta: float) -> void:
	if current < 0 or wave_left.is_empty():
		return
	var phase: EnemyPhase = list[current]
	for k in wave_left.size():
		if wave_left[k] <= 0.0:
			continue
		wave_left[k] -= delta
		if wave_left[k] <= 0.0:
			var adds: EnemyAdds = phase.adds[k]
			wave_left[k] += adds.every
			_ask(adds, adds_key(current, k), true)


func _ask(adds: EnemyAdds, key: int, wave: bool) -> void:
	if actor.events != null:
		actor.events.adds_requested.emit(actor.id, adds, key, wave)


func _holds(phase: EnemyPhase) -> bool:
	if phase.health_below > 0.0 and actor.health != null and actor.health.max_health > 0.0:
		if actor.health.health <= actor.health.max_health * phase.health_below:
			return true
	return phase.after_seconds > 0.0 and elapsed >= phase.after_seconds


## The Face's style, glow and own art's row and the body's size; the sprite is its look's (`started`).
func _restyle(look: PhaseLook) -> void:
	if look.size > 0.0:
		actor.set_size(look.size)
	for child in actor.get_children():
		var face := child as Face
		if face != null:
			face.restyle(look.face_style, look.glow, look.face_row)
