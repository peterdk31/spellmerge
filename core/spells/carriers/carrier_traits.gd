class_name CarrierTraits
extends RefCounted
## The yes/no questions a carrier answers about itself (`Carrier.traits`, a set of these flags), and
## that a card's needs are written in (`ModifierBase.RULES` "needs", `TriggerBase.NEEDS`). On their own here,
## so a card and a carrier can both name them. `Carrier` has the same names, for its subclasses.

## A shot flying out on its own: `reach` stretches its life, `return` brings it back.
const FLIES: int = 1 << 0
## A shot that stays in the world a while: arc, magnet and relay ride on it.
const STAYS: int = 1 << 1
## It hits under its own tag: hit cards, infusions and `on hit` work on it.
const HITS: int = 1 << 2
## It lasts a while: timers tick and `on hurt` listens while it lives.
const LASTS: int = 1 << 3
## It goes a distance `reach` stretches (its flight or its `ray_length`).
const REACHES: int = 1 << 4
## Its shield stops only the shots that touch it, so a deflect on it outruns a shield.
const GUARDS: int = 1 << 5
## Homing can steer it (turn it, bend it or place it on a target).
const STEERS: int = 1 << 6
## It uses `speed`: it, or the shots it is made of, travels (not a teleport, over at once, nor a
## decoy, a familiar or a portal, which stand where they are made). Its `lifetime` counts where
## it LASTS too.
const SPEED: int = 1 << 7
## It fires `shots` (a split makes more).
const SHOTS: int = 1 << 8
## Its shots leave along a fan or a line that `spread` widens.
const SPREAD: int = 1 << 9
## Its hits spend `pierce`.
const PIERCE: int = 1 << 10
## A payload its shot fires goes outward from the shot's caster, not along the shot's way.
const OUTWARD: int = 1 << 12
## Held, it is cast anew each time it is over (a swing sweeps back).
const REPEATS_HELD: int = 1 << 13
## It plays its own staff animation with its wind-up and strike.
const OWN_POSE: int = 1 << 14
## It is over at once, so a homing one looks at least as far as it goes.
const INSTANT_HOMING: int = 1 << 15
## The staff keeps working through its `lifetime` (a beam, a dash): its staff animation's
## strike lasts that long.
const HOLDS_STAFF: int = 1 << 17
## Does it travel along a path through the world (a bolt, a swap, an orbit)? Linger, sticky
## and spiral change that path.
const MOVES: int = 1 << 18
## Is it a line that is there at once (a beam)? It turns at walls, waves, grows and pulls as a line.
const LINE: int = 1 << 19
## Can it stop or turn other shots (its shot, line, sweep or body touches them, or it moves its
## caster, whom its shield then guards)? Shield, deflect and `on block` need it.
const MEETS_SHOTS: int = 1 << 20
## Does it move its caster (a dash, a teleport)? A mirror would cancel it, and nothing keeps it on.
## The wizard's own cast of it goes the way its body walks, along the aim when it stands
## (`CarrierMove.launch`, owner 2026-11-08).
const MOVES_CASTER: int = 1 << 21
## Does it strike one point near its caster's hand (a slam's impact, `Carrier.strike_point`)? A
## staff animation's `land` keys put the staff's tip there; on any other carrier they are refused.
const STRIKES_POINT: int = 1 << 22
## Does it stand in the world and stop other actors' shots on its own (a wall)? Read by the AI's
## summary of a cast (`CastSense.blocks`; docs/milestones/M2-enemy-ai.md), no card needs it.
const BLOCKS: int = 1 << 23
## Does it make a body of its own that stays and acts for its caster (a decoy, a familiar)? Read
## by `CastSense.spawns`; no card needs it.
const SPAWNS: int = 1 << 24
## Does it open a way through the world that shots and bodies take (a portal)? Read only by
## `CastSense.opens`; no card needs it.
const GATES: int = 1 << 25
## Is it shots of the projectile manager, each of which casts what it fires while it lives (a bolt,
## a rune, an orbit, a wall's stones)? A payload such a shot fires is cast by that shot while it
## lives (a Pulse in it is round the shot).
const CASTS_FROM_SHOT: int = 1 << 26
## Is it a body of its own, an actor (a decoy)? What it fires while it lives is cast from that body,
## and a Pulse in a payload it fires is round it.
const CASTS_FROM_BODY: int = 1 << 27
## Does it go out all round the point it is cast at, not along an aim (a pulse's ring)? It is not
## aimed, so scatter, mirror and nova turn nothing there (`Spells`, `ModifierBase.RULES`) and the AI
## reads it as an area round its caster (`CastSense`); and it goes out as a shot does, so return
## brings it back and ghost takes it through walls.
const AOE: int = 1 << 28
## Is it melee: held by or carried with the body that casts it, never leaving it (a swing, a slam, a
## dash's pass, a teleport's landing)? Then it never hits that body (`CarrierKit.spared`); anything
## else (ranged) spares it only until it has left it: a shot over time, a beam along its path
## (owner, 2026-11-06).
const MELEE: int = 1 << 29
