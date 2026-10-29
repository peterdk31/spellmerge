class_name CardRules
extends RefCounted
## The one table of what a card does on a carrier (docs/milestones/M2-rules.md, rule 1 and R2):
## modifier behaviour x motion, and trigger event x motion. A cell is "runs", or a reason a player
## understands. The staff compiler asks it for every card before it keeps the card (a card that
## cannot run is listed as wasted with the reason, and the runtime never sees it), and the
## runtime's own checks (`homing_steers`, `guards`) read the same rows, so the two cannot drift.
##
## Not in the table, by design: what a card means on a fallback (cards left over with no carrier to
## ride: `TRAVEL_ONLY` in the compiler) and a shield that a deflect on the same carrier leaves with
## nothing to do (`_shield_outrun`). Both are about how cards meet each other, not about a carrier.
## The table is also only what the compiler lists: that the runtime does what a "runs" cell says is
## rules R3's job.
##
## Adding a carrier (a `FormBase.Motion`) or a card kind: add its row or column here. A motion
## with no entry runs only what is `ALL`, and every other card on it is listed as wasted.
## Making a wasted cell work (R4) means changing the runtime and the row in one PR.

const Behaviour := ModifierBase.Behaviour
const Event := TriggerBase.Event
const Motion := FormBase.Motion

## A row that holds for every motion.
const ALL: Array[int] = []

## Shots that fly out from the hand and can be steered, bent, bounced and returned.
const FLIES: Array[int] = [Motion.STRAIGHT, Motion.HOOK, Motion.SWAP]
## Carriers whose hits are made under their own tag (so they can chain, slam, siphon, possess, set
## off `on hit`, `on kill` and `on reaction`).
const HITS: Array[int] = [
	Motion.STRAIGHT, Motion.STILL, Motion.ORBIT, Motion.RAY, Motion.HOOK, Motion.SWAP,
	Motion.WALL, Motion.FISSURE, Motion.SWING, Motion.SLAM,
]
## Carriers that are a live shot in the air: the runtime tracks them each step (magnet, relay,
## arc, `timer`, `on hurt`).
const AIRBORNE: Array[int] = [Motion.STRAIGHT, Motion.STILL, Motion.ORBIT, Motion.HOOK, Motion.SWAP, Motion.WALL]
## Carriers a shield or a deflect guards with (shots that touch them are stopped or turned).
const GUARDS: Array[int] = [
	Motion.STRAIGHT, Motion.STILL, Motion.ORBIT, Motion.WALL, Motion.RAY, Motion.FISSURE,
	Motion.SWING, Motion.SLAM,
]

## behaviour -> the motions it runs on (`ALL` for every motion). A behaviour not here is `ALL`.
const BEHAVIOUR_RUNS: Dictionary = {
	Behaviour.HOMING: [Motion.STRAIGHT, Motion.HOOK, Motion.SWAP, Motion.RAY, Motion.DASH, Motion.TELEPORT],
	Behaviour.CHAIN: HITS,
	Behaviour.HEAVY: HITS,
	Behaviour.SIPHON: HITS,
	Behaviour.POSSESS: HITS,
	# Dash and teleport bar the caster; a hook guards on the pull; the rest guard by touch.
	Behaviour.SHIELD: [
		Motion.STRAIGHT, Motion.STILL, Motion.ORBIT, Motion.RAY, Motion.DASH, Motion.TELEPORT, Motion.HOOK,
		Motion.SWAP, Motion.WALL, Motion.FISSURE, Motion.SWING, Motion.SLAM,
	],
	Behaviour.DEFLECT: [
		Motion.STRAIGHT, Motion.STILL, Motion.ORBIT, Motion.WALL, Motion.RAY, Motion.FISSURE,
		Motion.SWING, Motion.SLAM, Motion.HOOK, Motion.SWAP,
	],
	Behaviour.HOLD: [
		Motion.STRAIGHT, Motion.STILL, Motion.ORBIT, Motion.RAY, Motion.HOOK, Motion.SWAP, Motion.WALL,
		Motion.DECOY, Motion.FAMILIAR, Motion.SWING, Motion.SLAM,
	],
	Behaviour.RECOIL: [
		Motion.STRAIGHT, Motion.STILL, Motion.ORBIT, Motion.RAY, Motion.HOOK, Motion.SWAP, Motion.WALL,
		Motion.RAIN, Motion.FISSURE, Motion.DECOY, Motion.FAMILIAR, Motion.SWING, Motion.SLAM,
	],
	Behaviour.BOUNCE: [Motion.STRAIGHT, Motion.HOOK, Motion.SWAP, Motion.RAY, Motion.FISSURE],
	Behaviour.LINGER: FLIES,
	Behaviour.STICKY: FLIES,
	Behaviour.GHOST: FLIES,
	Behaviour.SPIRAL: FLIES,
	Behaviour.GROWTH: FLIES,
	Behaviour.RETURN: FLIES,
	Behaviour.MAGNET: AIRBORNE,
	Behaviour.RELAY: AIRBORNE,
	Behaviour.ARC: AIRBORNE,
	Behaviour.MIRROR: [Motion.STRAIGHT, Motion.RAY, Motion.FISSURE, Motion.SWING, Motion.SLAM],
}

## trigger event -> the motions it fires on (`ALL` for every motion; an event not here is `ALL`).
## `on cast`, `when it ends` and the rest that depend on nothing the carrier lacks run everywhere.
const TRIGGER_RUNS: Dictionary = {
	Event.HIT: HITS,
	Event.KILL: HITS,
	Event.REACTION: HITS,
	# A timer and `on hurt` need a live shot to count on (R4 may give the others one).
	Event.TIMER: AIRBORNE,
	Event.HURT: AIRBORNE,
	# Only a carrier that moves through the room meets a wall; a beam or fissure ends on one.
	Event.WALL: [Motion.STRAIGHT, Motion.HOOK, Motion.SWAP, Motion.RAY, Motion.FISSURE],
	# A block needs a shield on the carrier (see SHIELD above).
	Event.BLOCK: [
		Motion.STRAIGHT, Motion.STILL, Motion.ORBIT, Motion.RAY, Motion.DASH, Motion.TELEPORT, Motion.HOOK,
		Motion.SWAP, Motion.WALL, Motion.FISSURE, Motion.SWING, Motion.SLAM,
	],
}

## What each carrier is, in a sentence fragment that starts a reason.
const NATURE: Dictionary = {
	Motion.STRAIGHT: "it flies",
	Motion.STILL: "it stays where it is",
	Motion.ORBIT: "it only circles you",
	Motion.RAY: "it is over at once",
	Motion.DASH: "it moves you and hits nothing on the way",
	Motion.TELEPORT: "you are there at once and it hits nothing on the way",
	Motion.HOOK: "it pulls you to what it hits",
	Motion.SWAP: "it trades places with what it hits",
	Motion.WALL: "its shots stand still",
	Motion.RAIN: "it only drops what it carries",
	Motion.FISSURE: "it is over at once",
	Motion.DECOY: "it only stands and draws fire",
	Motion.FAMILIAR: "it only casts what it carries",
	Motion.SWING: "it sweeps round your hand",
	Motion.SLAM: "it strikes one spot",
}

## What each behaviour needs, to finish a reason ("<nature>, and this needs <need>").
const BEHAVIOUR_NEEDS: Dictionary = {
	Behaviour.HOMING: "something it can steer",
	Behaviour.CHAIN: "a hit to jump from",
	Behaviour.HEAVY: "a hit to knock back",
	Behaviour.SIPHON: "a hit to refund mana from",
	Behaviour.POSSESS: "a hit to take over with",
	Behaviour.SHIELD: "something that blocks shots",
	Behaviour.DEFLECT: "something that touches shots",
	Behaviour.HOLD: "a carrier that stays in the room",
	Behaviour.RECOIL: "a shot or beam to push you back",
	Behaviour.BOUNCE: "a shot that reaches walls",
	Behaviour.LINGER: "a shot that flies",
	Behaviour.STICKY: "a shot that flies",
	Behaviour.GHOST: "a shot that flies",
	Behaviour.SPIRAL: "a shot that flies",
	Behaviour.GROWTH: "a shot that flies",
	Behaviour.RETURN: "a shot that flies out",
	Behaviour.MAGNET: "a shot that stays in the air",
	Behaviour.RELAY: "a shot that stays in the air",
	Behaviour.ARC: "a shot that stays in the air",
	Behaviour.MIRROR: "a carrier you aim",
}

## What each trigger needs.
const TRIGGER_NEEDS: Dictionary = {
	Event.HIT: "a carrier that hits",
	Event.KILL: "a carrier that hits",
	Event.REACTION: "a carrier that hits",
	Event.TIMER: "a shot that stays in the air",
	Event.HURT: "a shot that stays in the air",
	Event.WALL: "a carrier that meets a wall",
	Event.BLOCK: "a shield that blocks",
}


## True when `behaviour` does something on a carrier of `motion`.
static func behaviour_runs(behaviour: int, motion: Motion) -> bool:
	var runs: Variant = BEHAVIOUR_RUNS.get(behaviour, ALL)
	return runs == ALL or (runs as Array).has(motion)


## Why `behaviour` does nothing on a carrier of `motion`, for the wasted card ("" when it runs).
static func behaviour_why_not(behaviour: int, motion: Motion) -> String:
	if behaviour_runs(behaviour, motion):
		return ""
	return _reason(NATURE.get(motion, "it cannot run it"), BEHAVIOUR_NEEDS.get(behaviour, ""))


## True when a trigger of `event` fires for a carrier of `motion`.
static func trigger_runs(event: int, motion: Motion) -> bool:
	var runs: Variant = TRIGGER_RUNS.get(event, ALL)
	return runs == ALL or (runs as Array).has(motion)


## Why a trigger of `event` never fires for a carrier of `motion` ("" when it does).
static func trigger_why_not(event: int, motion: Motion) -> String:
	if trigger_runs(event, motion):
		return ""
	return _reason(NATURE.get(motion, "it cannot run it"), TRIGGER_NEEDS.get(event, ""))


## Whether homing steers a carrier of `motion` (the compiler and the projectile code ask this).
static func homing_steers(motion: Motion) -> bool:
	return behaviour_runs(Behaviour.HOMING, motion)


## Whether a shield or deflect guards by touch on a carrier of `motion`.
static func guards(motion: Motion) -> bool:
	return GUARDS.has(motion)


static func _reason(nature: String, need: String) -> String:
	if need.is_empty():
		return nature
	return "%s, and this needs %s" % [nature, need]
