extends RefCounted
## Wall-clock budgets that hold on a loaded machine (the owner's decision of 2026-11-20; tests/README.md,
## "Tests that time the machine"). A test that checks how long the game's own code takes (a load stall,
## a gross slowdown) times it through here, never with one reading of `Time.get_ticks_usec` against a
## fixed number of milliseconds: one reading is the code's cost plus whatever else the machine was
## doing, and the parallel suite (tools/ptest.sh) runs a process a core.
##
## - `fastest_usec(work, repeats)`: the fastest of several runs. Load only ever adds time, so the
##   fastest run is the nearest to the code's own cost.
## - `against(work, reference, repeats)`: the fastest run of `work` as a multiple of a reference
##   workload's time, the reference run in turn with it, for as long as it, in the same process. A
##   slow machine, or one busy with other tests, slows both alike, so the multiple is the code's cost
##   in units of this machine's speed now. A test's budget is its usual multiple, measured on a quiet
##   machine and written beside it, times a slack (1.5): the code's own 2x slowdown fails on a machine
##   like the one the usual was measured on, loaded or not. On another kind of machine the multiple
##   can be some tens of percent off (the interpreter and the engine's C++ are not quicker by the same
##   share everywhere, and a load that fights for memory slows memory-bound work more than the small
##   reference): a usual measured on another machine is moved in the PR, with its numbers.
## - The references are single-threaded: compare them with single-threaded work (a load takes a
##   threaded run's other cores away, and a threaded run's speed depends on the core count), so a
##   test runs the native kernels on one thread for its budget.
## - The references: `gdscript_reference` (interpreted GDScript: compare GDScript), and
##   `native_reference` (the engine's own C++ on one thread, sorting and hashing: compare native work).
##
## Each takes a few milliseconds; the tests that use these print their multiples, so a budget is set
## from numbers seen (the test's comment says which).

## What `against` measured: the multiple, the work's fastest run and a reference's fastest, in µs.
class Timed:
	extends RefCounted
	var multiple: float = 0.0
	var work_usec: int = 0
	var reference_usec: int = 0

	func _init(work: int, reference: float) -> void:
		work_usec = work
		reference_usec = int(reference)
		multiple = float(work) / maxf(reference, 1.0)


## The reference workloads' sizes: each a few milliseconds on a fast machine, long enough that the
## clock's resolution and a context switch are small beside it.
const GDSCRIPT_ROUNDS: int = 60000
const NATIVE_FLOATS: int = 50000
const NATIVE_BYTES: int = 1 << 20

## The native reference's input, made once before anything is timed (`against`).
static var _floats: PackedFloat32Array = PackedFloat32Array()
static var _bytes: PackedByteArray = PackedByteArray()


## The fastest of `repeats` runs of `work` (a Callable taking nothing), in µs.
static func fastest_usec(work: Callable, repeats: int) -> int:
	var best: int = -1
	for i in maxi(repeats, 1):
		var began: int = Time.get_ticks_usec()
		work.call()
		var took: int = Time.get_ticks_usec() - began
		best = took if best < 0 else mini(best, took)
	return best


## `work`'s cost in references: `repeats` rounds, each a run of `work` and then `reference` run
## again and again for as long as that run took (at least once), so the two share the machine alike
## (a reference timed alone, a few milliseconds, often runs in one undisturbed slice of a busy core
## while a longer run is cut off by the others). The fastest run of `work` over the fastest round's
## time a reference (each Callable taking nothing).
static func against(work: Callable, reference: Callable, repeats: int) -> Timed:
	_make_inputs()
	var work_best: int = -1
	var reference_best: float = -1.0
	for i in maxi(repeats, 1):
		var took: int = fastest_usec(work, 1)
		work_best = took if work_best < 0 else mini(work_best, took)
		var runs: int = 0
		var began: int = Time.get_ticks_usec()
		var spent: int = 0
		while runs == 0 or spent < took:
			reference.call()
			runs += 1
			spent = Time.get_ticks_usec() - began
		var one: float = float(spent) / float(runs)
		reference_best = one if reference_best < 0.0 else minf(reference_best, one)
	return Timed.new(work_best, reference_best)


## Interpreted GDScript of a fixed size: integer and float arithmetic, a packed array written and
## read, a branch (as the projectile manager's and the state walk's loops are made of).
static func gdscript_reference() -> void:
	var cells := PackedInt32Array()
	cells.resize(256)
	var acc: int = 0
	var x: float = 0.5
	for i in GDSCRIPT_ROUNDS:
		var at: int = (i * 37) & 255
		cells[at] = cells[at] + i
		if cells[at] & 1 == 0:
			acc += at
		x = x * 0.999 + float(at) * 0.001
	_sink(acc + int(x))


## The engine's own C++ on one thread, of a fixed size: a sort of floats and a SHA-256 of bytes (a
## compute- and a memory-bound part, as a native kernel is).
static func native_reference() -> void:
	_make_inputs()
	var sorted: PackedFloat32Array = _floats.duplicate()
	sorted.sort()
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(_bytes)
	_sink(int(sorted[0]) + hashing.finish().size())


## The native reference's input, made the first time only.
static func _make_inputs() -> void:
	if _floats.size() == NATIVE_FLOATS:
		return
	_floats.resize(NATIVE_FLOATS)
	var seed: int = 12345
	for i in NATIVE_FLOATS:
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		_floats[i] = float(seed)
	_bytes.resize(NATIVE_BYTES)
	_bytes.fill(7)


## Keeps a result alive, so no part of a reference is ever left out.
static var _kept: int = 0


static func _sink(value: int) -> void:
	_kept ^= value
