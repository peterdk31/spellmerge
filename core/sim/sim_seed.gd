class_name SimSeed
extends RefCounted
## Where a simulation script gets a seed nobody chose (online-ready N1, docs/milestones/online-ready.md):
## the start of something that should not play like the last one (a horde's waves, a swarm's
## scatter). It is the one way the simulation folders reach the engine's global generator, so
## tests/core/test_state_declared.gd forbids `randomize()`, `randf()` and the like everywhere else.
## A test seeds the generator it gets after this (`director.rng.seed = 7`), as before.
##
## While a replay records or plays (N2, `Frames.record`, `Frames.play`), the seeds are dealt from
## the run's seed (`begin`), which the replay carries: the same run gives the same seeds in the same
## order. Otherwise each is random. The replay's header carries the seed beside the run's rules
## (`SessionRules`, N11), which a replay deals the same way.
##
##     rng.seed = SimSeed.fresh()

## The run's dealer while a replay records or plays (`begin`), else null.
static var _run: RandomNumberGenerator = null


## A seed: the next of the run's (`begin`), else one of the engine's global generator.
static func fresh() -> int:
	if _run != null:
		return _run.randi()
	return randi()


## A new run's seed (random), for `begin`.
static func pick() -> int:
	return randi() << 32 | randi()


## Deal every seed from `run_seed` until `end`: a run recorded or played from the same seed gets
## the same seeds.
static func begin(run_seed: int) -> void:
	_run = RandomNumberGenerator.new()
	_run.seed = run_seed


## Random seeds again.
static func end() -> void:
	_run = null


## Set the run's dealer aside (returned; null when none deals) while something that is not the game
## takes seeds (a blank, `SimFresh.blank_of`): they come from the engine's generator, and the
## run's seeds are dealt as if it had taken none. `back` puts the dealer back.
static func aside() -> RandomNumberGenerator:
	var dealer: RandomNumberGenerator = _run
	_run = null
	return dealer


static func back(dealer: RandomNumberGenerator) -> void:
	_run = dealer


## True while the seeds are dealt from a run's seed.
static func is_dealing() -> bool:
	return _run != null
