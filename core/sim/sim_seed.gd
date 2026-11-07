class_name SimSeed
extends RefCounted
## Where a seed nobody chose comes from (online-ready N1, docs/milestones/online-ready.md): a new
## run's, when no replay deals one (`Frames.next_run_seed`; a replay deals its runs' seeds from its
## own, core/sim/replay_tape.gd), and a new replay's. It is the one way the simulation reaches the
## engine's global generator, so tests/core/test_state_declared.gd forbids `randomize()`, `randf()`
## and the like in the simulation folders. Everything else the game rolls is a hash of the run's
## seed (`Sim.chance`).
##
## It holds nothing: what a run's seed is is the frames service's to say, never a global switch.


## A random seed (32 bits).
static func fresh() -> int:
	return randi()


## A random seed for a new replay (64 bits).
static func pick() -> int:
	return randi() << 32 | randi()
