class_name HoleRules
extends RefCounted
## The numbers of a fall (hub rework HR-H2, docs/milestones/hub-rework.md, "Holes" 4 and 5, and
## question 10): read by the actor (its fall), Combat (what it costs) and Feel (its look). Constants
## only; nothing here is state.
##
## A body that walks (a Mover) and ends a move over a hole with nothing crossing falls for
## FALL_SECONDS, down to everything that asks (`Actor.is_down`). Then a wizard comes back on its last
## ground (a place it stood with no hole within GROUND_MARGIN of its circle), protected for
## RETURN_PROTECTION seconds, having lost FALL_COST of its most health (nothing where the room says
## falls are free, `RoomBase.falls_free`: the hub); anything else dies of it, through Combat. A boss
## never falls: it is put on the nearest ground instead.

## How long a fall lasts, in seconds.
const FALL_SECONDS: float = 0.6
## The share of a wizard's most health a fall costs it (owner, 2026-11-16, question 10).
const FALL_COST: float = 0.2
## A wizard back from a fall cannot be hurt for this long (as long as a joiner, `Downed.JOIN_PROTECTION`).
const RETURN_PROTECTION: float = 2.0
## A body's last ground has no hole within this many pixels of its circle (one wall cell).
const GROUND_MARGIN: float = 8.0
