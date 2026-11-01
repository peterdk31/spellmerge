class_name EnemyPhase
extends Resource
## One phase of a boss (docs/milestones/M2-enemy-ai.md, "The enemy's data"): when it starts, and
## what it changes. The `Phases` component (gameplay/actor) runs them in order: the first whose
## condition holds starts, once.

## Starts when health falls to this fraction of the most (0: not by health).
@export_range(0.0, 1.0) var health_below: float = 0.0
## Starts this many seconds after the body appeared (0: not by time).
@export var after_seconds: float = 0.0
## Its staffs (1-4; empty: keep the ones it has).
@export var staffs: Array[StaffCards] = []
## How it plays (null: keep).
@export var profile: AIProfile = null
## How it looks (null: keep).
@export var look: PhaseLook = null
## Seconds it stands, protected, while it changes (0: at once).
@export var transition: float = 1.0


## True when the phase has a condition to start by.
func has_condition() -> bool:
	return health_below > 0.0 or after_seconds > 0.0
