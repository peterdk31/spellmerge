class_name Phases
extends ActorComponent
## A boss's phases (enemy AI AI7, docs/milestones/M2-enemy-ai.md, "The enemy's data"): the actor
## adds this component itself when its data has `phases` (`EnemyBase.phases`), so a boss is data,
## no scene of its own. It follows the body whoever drives it (a wizard possessing a boss still
## sees it change).
##
## Each step it checks the next phase's condition (`EnemyPhase.health_below`, a fraction of the
## most health, or `after_seconds` since the body appeared); the first that holds starts, once,
## in order. Starting one: the body is protected for its `transition` (`Health.protect`), its
## staffs are replaced (`Caster.replace_staffs`, each pool full), its look changes (the Face's
## style and glow, the body's size; the sprite by whoever draws it, from `started`), and the
## controller hears it (`ActorController.phase_started`: an AI stands through the transition and
## takes the phase's profile).

## A phase began: its index in the data's `phases`, and the phase.
signal started(index: int, phase: EnemyPhase)

## The phases, in order (from the data).
var list: Array[EnemyPhase] = []
## The index of the phase in play (-1: the data's own staffs, before the first).
var current: int = -1
## Seconds since the body appeared.
var elapsed: float = 0.0


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	list = owner_actor.data.phases if owner_actor.data != null else ([] as Array[EnemyPhase])


## Move time on and start the next phase when its condition holds.
func step(delta: float) -> void:
	elapsed += delta
	var next: int = current + 1
	if next >= list.size():
		return
	var phase: EnemyPhase = list[next]
	if phase == null or not _holds(phase):
		return
	begin(next)


## Start phase `index` now, whatever its condition.
func begin(index: int) -> void:
	if index < 0 or index >= list.size() or list[index] == null:
		return
	current = index
	var phase: EnemyPhase = list[index]
	if phase.transition > 0.0 and actor.health != null:
		actor.health.protect(phase.transition)
	if not phase.staffs.is_empty() and actor.caster != null:
		var staffs: Array[StaffBase] = []
		var cards: Array = []
		for entry: StaffCards in phase.staffs.slice(0, EnemyBase.MAX_STAFFS):
			staffs.append(entry.staff if entry != null else null)
			cards.append(entry.cards.duplicate() if entry != null else [])
		actor.caster.replace_staffs(staffs, cards)
	if phase.look != null:
		_restyle(phase.look)
	if actor.controller != null:
		actor.controller.phase_started(actor, phase)
	started.emit(index, phase)


func _holds(phase: EnemyPhase) -> bool:
	if phase.health_below > 0.0 and actor.health != null and actor.health.max_health > 0.0:
		if actor.health.health <= actor.health.max_health * phase.health_below:
			return true
	return phase.after_seconds > 0.0 and elapsed >= phase.after_seconds


## The Face's style and glow and the body's size; the sprite is its look's (`started`).
func _restyle(look: PhaseLook) -> void:
	if look.size > 0.0:
		actor.set_size(look.size)
	for child in actor.get_children():
		var face := child as Face
		if face != null:
			face.restyle(look.face_style, look.glow)
