extends SceneTree
## Tests for core/pools: objects are made once, reused, never over capacity.
##
## godot --headless --path . --script res://tests/core/test_pools.gd

const PoolScript := preload("res://core/pools/pool.gd")

var _failures: Array[String] = []
var _made: int = 0
var _acquired: Array[Object] = []
var _released: Array[Object] = []


func _initialize() -> void:
	_test_builds_everything_up_front()
	_test_acquire_until_empty()
	_test_reuse_makes_nothing_new()
	_test_release_rejects_bad_items()
	_test_hooks()
	_test_zero_and_negative_size()
	_test_clear_frees_the_objects()
	if _failures.is_empty():
		print("TEST OK: core/pools")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _make() -> Object:
	_made += 1
	return Node2D.new()


func _pool(size: int) -> RefCounted:
	_made = 0
	return PoolScript.new(_make, size)


func _test_builds_everything_up_front() -> void:
	var pool: RefCounted = _pool(8)
	_check(_made == 8, "the factory runs once per object, up front")
	_check(pool.created == 8 and pool.capacity == 8, "created and capacity are 8")
	_check(pool.available() == 8 and pool.in_use() == 0, "all 8 are available at first")
	pool.clear()


func _test_acquire_until_empty() -> void:
	var pool: RefCounted = _pool(4)
	var seen: Dictionary = {}
	for i in 4:
		var item: Object = pool.acquire()
		_check(item != null, "acquire %d returns an object" % i)
		_check(not seen.has(item), "acquire never hands out the same object twice")
		seen[item] = true
	_check(pool.acquire() == null, "an empty pool returns null")
	_check(pool.in_use() == 4 and pool.available() == 0, "4 in use, none available")
	_check(_made == 4, "an empty pool does not make more")
	pool.clear()


func _test_reuse_makes_nothing_new() -> void:
	var pool: RefCounted = _pool(2)
	var first: Object = pool.acquire()
	_check(pool.release(first), "release of an acquired object works")
	var again: Object = pool.acquire()
	_check(again == first, "the released object is reused first")
	for i in 1000:
		var item: Object = pool.acquire()
		pool.release(item)
	_check(_made == 2 and pool.created == 2, "1000 acquire/release cycles make nothing new")
	_check(pool.available() == 1 and pool.in_use() == 1, "the counts stay right after the cycles")
	pool.release(again)
	pool.clear()


func _test_release_rejects_bad_items() -> void:
	var pool: RefCounted = _pool(2)
	var item: Object = pool.acquire()
	_check(pool.release(item), "first release works")
	_check(not pool.release(item), "a second release does nothing")
	_check(pool.available() == 2, "a double release does not add a copy")
	var stranger := Node2D.new()
	_check(not pool.release(stranger), "an object from elsewhere is refused")
	_check(not pool.release(null), "null is refused")
	_check(pool.available() == 2, "refused releases change nothing")
	stranger.free()
	pool.clear()


func _test_hooks() -> void:
	_acquired.clear()
	_released.clear()
	_made = 0
	var pool: RefCounted = PoolScript.new(_make, 2, _on_acquire, _on_release)
	var item: Object = pool.acquire()
	_check(_acquired.size() == 1 and _acquired[0] == item, "on_acquire runs with the object")
	pool.release(item)
	pool.release(item)
	_check(_released.size() == 1 and _released[0] == item, "on_release runs once, not for a refused release")
	pool.clear()


func _on_acquire(item: Object) -> void:
	_acquired.append(item)


func _on_release(item: Object) -> void:
	_released.append(item)


func _test_zero_and_negative_size() -> void:
	var empty: RefCounted = _pool(0)
	_check(empty.acquire() == null and empty.capacity == 0, "size 0 is an empty pool")
	var negative: RefCounted = _pool(-3)
	_check(negative.acquire() == null and negative.capacity == 0, "a negative size is an empty pool")


func _test_clear_frees_the_objects() -> void:
	var pool: RefCounted = _pool(3)
	var item: Object = pool.acquire()
	var other: Object = pool.acquire()
	pool.release(other)
	pool.clear()
	_check(not is_instance_valid(item) and not is_instance_valid(other), "clear frees every object")
	_check(pool.acquire() == null and pool.capacity == 0, "a cleared pool is empty")
