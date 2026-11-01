class_name AIBehaviour
extends RefCounted
## One thing an AI may want to do (docs/milestones/M2-enemy-ai.md, "Behaviours"): fight, dodge,
## keep its range... Each is one file in `gameplay/ai/behaviours/`, listed once in
## `behaviours.gd`. It holds no state: one copy serves every AI, and what it must remember per AI
## goes in the brain's `memo` and `picks` at its `index`, so nothing is allocated per step.
##
## The brain asks every behaviour `want` on its decision timer, keeps the highest (the running one
## gets a bonus, `AIProfile.commitment`) and calls its `act`, which writes the brain's plan:
## `plan_staff` (which staff to wind up and cast, -1 for none), `plan_move` and `plan_way` (how to
## walk), `plan_urgent` (dash that way if a staff's next cast moves the caster). It reads only
## what the brain perceived and what each staff casts next (`CastSense`), never a card.

## Its place in the brain's list (set once by `AIBehaviours`), for `memo` and `picks`.
var index: int = -1


## A short name for the arena's AI view and the tests.
func name() -> String:
	return "behaviour"


## How much it wants to act now: 0 for not at all; about 0.1 for a fallback, 1 for a clear chance.
## It may note a staff in `brain.picks[index]` for `act`.
func want(_brain: AIBrain) -> float:
	return 0.0


## Write the brain's plan (it starts empty: no staff, standing, not urgent).
func act(_brain: AIBrain) -> void:
	pass
