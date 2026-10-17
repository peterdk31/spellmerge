extends RefCounted
## A fixed-size object pool: every object is made once, up front, and then
## handed out and taken back, so nothing is allocated while the game runs.
##
## GDScript has no generics, so the pool is typed by its factory: a Callable
## that returns a new object of one type. Cast what acquire() returns:
##
##     var pool := PoolScript.new(func() -> Object: return Spark.new(), 64)
##     var spark := pool.acquire() as Spark
##     if spark != null:
##         ...
##         pool.release(spark)
##
## The pool never grows. When every object is out, acquire() returns null and
## the caller degrades (skips the effect, or reuses its oldest one) instead of
## allocating in the middle of a frame.
##
## Optional hooks: `on_acquire(item)` runs as an object leaves the pool and
## `on_release(item)` as it comes back (reset state, hide a node). Releasing an
## object twice, or one the pool did not make, does nothing and returns false.
## An object freed from outside while in the pool is dropped when it comes up,
## and `capacity` shrinks by one.

## Total objects the pool owns.
var capacity: int = 0
## How many times the factory ran. Equals `capacity` after construction and
## never changes later, which is how tests show nothing is allocated.
var created: int = 0

var _on_acquire: Callable
var _on_release: Callable
## The objects ready to hand out (a stack: the last released is reused first).
var _free: Array[Object] = []
## Every object the pool owns -> true while it sits in the pool.
var _is_free: Dictionary = {}


func _init(factory: Callable, size: int, on_acquire: Callable = Callable(), on_release: Callable = Callable()) -> void:
	_on_acquire = on_acquire
	_on_release = on_release
	for i in maxi(size, 0):
		var item: Object = factory.call() as Object
		if item == null:
			push_error("Pool: the factory returned no object")
			break
		created += 1
		_free.append(item)
		_is_free[item] = true
	capacity = created


## Take an object out, or null if every one is in use.
func acquire() -> Object:
	var item: Object = null
	while not _free.is_empty():
		var candidate: Object = _free.pop_back()
		if is_instance_valid(candidate):
			item = candidate
			break
		# Freed from outside (say its parent room was freed): forget it.
		_is_free.erase(candidate)
		capacity -= 1
	if item == null:
		return null
	_is_free[item] = false
	if _on_acquire.is_valid():
		_on_acquire.call(item)
	return item


## Give an object back. False if it is not from this pool or is already back.
func release(item: Object) -> bool:
	if item == null or not _is_free.has(item) or _is_free[item]:
		return false
	_is_free[item] = true
	_free.append(item)
	if _on_release.is_valid():
		_on_release.call(item)
	return true


## Objects ready to acquire.
func available() -> int:
	return _free.size()


## Objects currently handed out.
func in_use() -> int:
	return capacity - _free.size()


## Free every object the pool made (nodes in the tree with queue_free) and
## empty the pool. Anything still handed out is freed too, so call it only
## when the pool is done.
func clear() -> void:
	for key: Variant in _is_free.keys():
		if not is_instance_valid(key) or key is RefCounted:
			continue
		var item: Object = key
		var node := item as Node
		if node != null and node.is_inside_tree():
			node.queue_free()
		else:
			item.free()
	_is_free.clear()
	_free.clear()
	capacity = 0
