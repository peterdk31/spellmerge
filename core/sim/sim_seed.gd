class_name SimSeed
extends RefCounted
## Where a simulation script gets a seed nobody chose (online-ready N1, docs/milestones/online-ready.md):
## the start of something that should not play like the last one (a horde's waves, a swarm's
## scatter). It is the one way the simulation folders reach the engine's global generator, so
## tests/core/test_state_declared.gd forbids `randomize()`, `randf()` and the like everywhere else,
## and N11 can make it the session's seed, which a replay carries. A test seeds the generator it
## gets after this (`director.rng.seed = 7`), as before.
##
##     rng.seed = SimSeed.fresh()


## A seed of the engine's global generator (random each run until N11).
static func fresh() -> int:
	return randi()
