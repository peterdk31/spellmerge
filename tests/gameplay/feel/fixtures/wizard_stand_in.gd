extends Actor
## A stand-in actor for the Feel tests: an `Actor` body whose `id` (and `ramp`, `mover`) the test
## sets, with none of the kit started: no services, no components, no id of its own (Feel reads a
## hit body by its actor id, actors G8; the test opens the id in its own actor table).


func _enter_tree() -> void:
	pass


func _ready() -> void:
	pass


func _exit_tree() -> void:
	pass


func _physics_process(_delta: float) -> void:
	pass
