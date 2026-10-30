class_name CarrierTraits
extends RefCounted
## The yes/no questions a carrier answers about itself (`Carrier.traits`, a set of these flags), and
## that a card's needs are written in (`ModifierBase.NEEDS`, `TriggerBase.NEEDS`). On their own here,
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
## It uses `speed` and `lifetime` (all but a teleport, which is over at once).
const SPEED: int = 1 << 7
## It fires `shots` (a split makes more).
const SHOTS: int = 1 << 8
## Its shots leave along a fan or a line that `spread` widens.
const SPREAD: int = 1 << 9
## Its hits spend `pierce`.
const PIERCE: int = 1 << 10
## Its shots spread round a circle instead of a fan.
const RING: int = 1 << 11
## A payload its shot fires goes outward from the shot's caster, not along the shot's way.
const OUTWARD: int = 1 << 12
## Held, it is cast anew each time it is over (a rain falls again, a swing sweeps back).
const REPEATS_HELD: int = 1 << 13
## It plays its own staff animation with its wind-up and strike.
const OWN_POSE: int = 1 << 14
## It is over at once, so a homing one looks at least as far as it goes.
const INSTANT_HOMING: int = 1 << 15
## It reads a payload of its own after it, as a trigger does (a rain).
const CARRIES_PAYLOAD: int = 1 << 16
## The staff keeps working through its `lifetime` (a beam, a rain, a dash): its staff animation's
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
const MOVES_CASTER: int = 1 << 21
