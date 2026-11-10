class_name NetLog
extends RefCounted
## A session's counters kept as a file (netcode spike S4, docs/milestones/netcode-spike.md; what S5
## reads): `user://net/host.log` or `user://net/client.log`, a line of JSON per row, written fresh
## by each session of that side. The two paths are written out here; nothing of a path comes from
## its holder or the wire.

var _file: FileAccess = null


## Start this side's log afresh. False when it cannot be written: rows are then dropped.
func open(hosting: bool) -> bool:
	close()
	if DirAccess.make_dir_recursive_absolute("user://net") != OK:
		return false
	if hosting:
		_file = FileAccess.open("user://net/host.log", FileAccess.WRITE)
	else:
		_file = FileAccess.open("user://net/client.log", FileAccess.WRITE)
	return _file != null


func row(values: Dictionary) -> void:
	if _file != null:
		_file.store_line(JSON.stringify(values))
		_file.flush()


func close() -> void:
	if _file != null:
		_file.close()
		_file = null
