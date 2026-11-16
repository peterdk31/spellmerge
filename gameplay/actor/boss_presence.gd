class_name BossPresence
extends ActorLook
## A boss in play, told to the HUD (boss plan OB16, docs/milestones/boss-old-broom.md, "HUD: the
## boss bar and the entrance"). The actor adds one itself when its data is a boss's
## (`EnemyBase.boss`, `Actor._apply_data`), as it adds a boss's `Phases`, so a boss is still data with
## no scene of its own.
##
## It draws nothing and is never stepped. As its body is in play (ready with its id open, and again
## each time it comes back into the tree) it sends `boss_shown` on the bus (its id, its name, its
## lore line, a mark at each phase's health share and whether it has an intro, `EnemyBase.boss_intro`),
## then `boss_health_changed`; each change of its
## Health follows (`Health.changed`: a hit, a heal, a player joining or leaving); and `boss_hidden`
## once when it dies or its body leaves the tree. After a snapshot (`sync`) the health is told again,
## the boss is not shown again (the HUD still shows it). The HUD keeps the bar and plays the banner;
## Feel plays the `boss_intro` cue. View only, as every look.

const ActorsScript := preload("res://core/actors/actors.gd")

## True between a `boss_shown` and its `boss_hidden`.
var _shown: bool = false
## The id it was shown under (its body's id is closed before it leaves the tree).
var _shown_id: int = ActorsScript.NONE


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	if actor.health != null and not actor.health.changed.is_connected(_on_health_changed):
		actor.health.changed.connect(_on_health_changed)
	if not actor.died.is_connected(_on_died):
		actor.died.connect(_on_died)
	if not actor.tree_exiting.is_connected(hide_boss):
		actor.tree_exiting.connect(hide_boss)
	if not actor.tree_entered.is_connected(show_boss):
		# Back in the tree (its id opened again by its `_enter_tree`).
		actor.tree_entered.connect(show_boss)
	if not actor.ready.is_connected(show_boss):
		# Set up in the actor's `_ready` (added by its `_apply_data`), which opens its id after its
		# looks, or a snapshot gave it one already: shown once it is ready either way.
		actor.ready.connect(show_boss, CONNECT_ONE_SHOT)


## Tell the boss shown (nothing while it is already, without an id, or out of the tree).
func show_boss() -> void:
	if _shown or actor == null or actor.events == null or actor.id == ActorsScript.NONE or not actor.is_inside_tree():
		return
	_shown = true
	_shown_id = actor.id
	actor.events.boss_shown.emit(actor.id, actor.data.shown_name() if actor.data != null else "", actor.data.lore if actor.data != null else "", marks_of(actor.data), actor.data != null and actor.data.boss_intro != null)
	_tell_health()


## Tell the boss gone (once for each show).
func hide_boss() -> void:
	if not _shown:
		return
	_shown = false
	if actor.events != null and is_instance_valid(actor.events):
		actor.events.boss_hidden.emit(_shown_id)
	_shown_id = ActorsScript.NONE


## True between a `boss_shown` and its `boss_hidden`.
func is_shown() -> bool:
	return _shown


func sync() -> void:
	_tell_health()


## A mark for each phase of `data` that starts by health: its share of the most health, between 0
## and 1, largest first (a phase by time only has none).
static func marks_of(data: EnemyBase) -> PackedFloat32Array:
	var marks := PackedFloat32Array()
	if data == null:
		return marks
	for phase in data.phases:
		if phase != null and phase.health_below > 0.0 and phase.health_below < 1.0:
			marks.append(phase.health_below)
	marks.sort()
	marks.reverse()
	return marks


func _tell_health() -> void:
	if _shown and actor.health != null and actor.events != null:
		actor.events.boss_health_changed.emit(_shown_id, actor.health.health, actor.health.max_health)


func _on_health_changed(health: float, max_health: float) -> void:
	if _shown and actor.events != null:
		actor.events.boss_health_changed.emit(_shown_id, health, max_health)


func _on_died(_killer: int) -> void:
	hide_boss()
