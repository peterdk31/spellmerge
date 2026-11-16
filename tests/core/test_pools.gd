extends "res://tests/support/suite.gd"
## Tests for core/pools: objects are made once, up front, reused, never over capacity; a release
## is refused for what the pool does not hand out; the hooks run once per hand-out and take-back;
## an object freed from outside is skipped and forgotten; `clear` frees them all. Each test makes
## its own pool (`_pool`, counting the factory's calls) and clears it after.

const PoolScript := preload("res://core/pools/pool.gd")

var made: int = 0
var acquired: Array[Object] = []
var released: Array[Object] = []
var pool: RefCounted


func before_each() -> void:
	made = 0
	acquired.clear()
	released.clear()
	pool = null


func after_each() -> void:
	if pool != null:
		pool.clear()
	pool = null


func _make() -> Object:
	made += 1
	return Node2D.new()


func _on_acquire(item: Object) -> void:
	acquired.append(item)


func _on_release(item: Object) -> void:
	released.append(item)


## A pool of `size` objects from `_make`, cleared after the test.
func _pool(size: int) -> RefCounted:
	pool = PoolScript.new(_make, size)
	return pool


func test_the_factory_runs_once_per_object_up_front() -> void:
	_pool(8)
	check_equal(made, 8, "the factory runs once per object, up front")
	check(pool.created == 8 and pool.capacity == 8, "created and capacity are 8")


func test_every_object_is_available_at_first() -> void:
	_pool(8)
	check(pool.available() == 8 and pool.in_use() == 0, "all 8 are available at first")


func test_acquire_never_hands_out_one_object_twice() -> void:
	_pool(4)
	var seen: Dictionary[Object, bool] = {}
	for i in 4:
		var item: Object = pool.acquire()
		check(item != null, "acquire %d returns an object" % i)
		check(not seen.has(item), "acquire never hands out the same object twice")
		seen[item] = true
	check(pool.in_use() == 4 and pool.available() == 0, "4 in use, none available")


func test_an_empty_pool_returns_null_without_making_more() -> void:
	_pool(4)
	for i in 4:
		pool.acquire()
	check(pool.acquire() == null, "an empty pool returns null")
	check_equal(made, 4, "an empty pool does not make more")


func test_a_released_object_is_reused_first() -> void:
	_pool(2)
	var first: Object = pool.acquire()
	check(pool.release(first), "release of an acquired object works")
	check(pool.acquire() == first, "the released object is reused first")


func test_acquire_release_cycles_make_nothing_new() -> void:
	_pool(2)
	var held: Object = pool.acquire()
	for i in 1000:
		var item: Object = pool.acquire()
		pool.release(item)
	check(made == 2 and pool.created == 2, "1000 acquire/release cycles make nothing new")
	check(pool.available() == 1 and pool.in_use() == 1, "the counts stay right after the cycles")
	pool.release(held)


func test_a_second_release_is_refused() -> void:
	_pool(2)
	var item: Object = pool.acquire()
	check(pool.release(item), "first release works")
	check(not pool.release(item), "a second release does nothing")
	check_equal(pool.available(), 2, "a double release does not add a copy")


func test_a_release_of_an_object_from_elsewhere_is_refused() -> void:
	_pool(2)
	var stranger: Node2D = own(Node2D.new()) as Node2D
	check(not pool.release(stranger), "an object from elsewhere is refused")
	check(not pool.release(null), "null is refused")
	check_equal(pool.available(), 2, "refused releases change nothing")


func test_on_acquire_runs_with_the_object() -> void:
	pool = PoolScript.new(_make, 2, _on_acquire, _on_release)
	var item: Object = pool.acquire()
	check(acquired.size() == 1 and acquired[0] == item, "on_acquire runs with the object")


func test_on_release_runs_once_not_for_a_refused_release() -> void:
	pool = PoolScript.new(_make, 2, _on_acquire, _on_release)
	var item: Object = pool.acquire()
	pool.release(item)
	pool.release(item)
	check(released.size() == 1 and released[0] == item, "on_release runs once, not for a refused release")


func test_a_pool_of_size_zero_is_empty() -> void:
	_pool(0)
	check(pool.acquire() == null and pool.capacity == 0, "size 0 is an empty pool")


func test_a_pool_of_negative_size_is_empty() -> void:
	_pool(-3)
	check(pool.acquire() == null and pool.capacity == 0, "a negative size is an empty pool")


## A pool of three, all released, with `third` (the one that comes up first) freed behind the
## pool's back. Returns [first, second].
func _pool_with_a_freed_object() -> Array[Object]:
	_pool(3)
	var first: Object = pool.acquire()
	var second: Object = pool.acquire()
	var third: Object = pool.acquire()
	pool.release(first)
	pool.release(second)
	pool.release(third)
	third.free()
	return [first, second]


func test_acquire_skips_an_object_freed_from_outside() -> void:
	var left: Array[Object] = _pool_with_a_freed_object()
	var got: Object = pool.acquire()
	check(got != null and is_instance_valid(got), "acquire never returns a freed object")
	check(got == left[1], "it skips to the next free one")


func test_the_pool_forgets_an_object_freed_from_outside() -> void:
	_pool_with_a_freed_object()
	pool.acquire()
	check_equal(pool.capacity, 2, "the pool forgets the dead object")


func test_acquire_returns_null_once_every_free_object_was_freed() -> void:
	var left: Array[Object] = _pool_with_a_freed_object()
	var got: Object = pool.acquire()
	left[0].free()
	check(pool.acquire() == null, "when every free object was freed, acquire returns null")
	check(pool.capacity == 1 and pool.available() == 0, "only the one handed out is still counted")
	got.free()


func test_clear_frees_every_object() -> void:
	_pool(3)
	var item: Object = pool.acquire()
	var other: Object = pool.acquire()
	pool.release(other)
	pool.clear()
	check(not is_instance_valid(item) and not is_instance_valid(other), "clear frees every object")


func test_a_cleared_pool_is_empty() -> void:
	_pool(3)
	pool.acquire()
	pool.clear()
	check(pool.acquire() == null and pool.capacity == 0, "a cleared pool is empty")
