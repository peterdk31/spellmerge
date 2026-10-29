extends RefCounted
## One piece of work done behind the loading screen (`core/loading/loading.gd`), in small units,
## one a frame, so the screen keeps drawing and its bar moves. Extend it and override what you
## need; `Loading.run` calls `begin` once, then `step` once a frame until `is_done`, then `end`
## (also when the load is cancelled). Example: `core/projectiles/shader_warmup.gd`, which compiles
## one shader a unit.


## How many units the whole task is (the bar's share of it). At least 1.
func units() -> int:
	return 1


## How many are done so far.
func units_done() -> int:
	return units() if is_done() else 0


## Start: `host` is a node in the tree to add anything that must be drawn or processed to.
func begin(_host: Node) -> void:
	pass


## Do the next unit.
func step() -> void:
	pass


func is_done() -> bool:
	return true


## Finished or cancelled: free whatever `begin` made.
func end() -> void:
	pass
