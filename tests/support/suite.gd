extends SceneTree
## Base class for small, isolated unit tests.
##
## A test script extends this file and holds one method per behaviour, named `test_*`. Each
## method is a test of its own: it builds what it needs (`before_each` is for the shared
## part), checks it, and the suite frees everything it was handed with `own()` afterwards. A
## failing test never stops or changes the next one, and the report names it:
## `TEST FAILED: test_name: what was wrong`.
##
## Keep a test short and about one thing. Assert on behaviour (what happens), not on
## incidental detail (a pixel size, a tuning number, the order of children), unless that
## detail is the contract. Share setup through a fixture file in `tests/support/` or next to
## the test, never through leftover state of an earlier test.
##
## Example (see tests/core/test_svg_art.gd):
##   extends "res://tests/support/suite.gd"
##   func test_something_holds() -> void:
##       check(1 + 1 == 2, "arithmetic works")
##
## godot --headless --path . --script res://tests/<area>/test_<name>.gd

var _failures: Array[String] = []
var _current: String = ""
var _owned: Array[Object] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var names: Array[String] = []
	for method: Dictionary in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			names.append(method_name)
	names.sort()
	for method_name in names:
		_current = method_name
		await before_each()
		await call(method_name)
		await after_each()
		_free_owned()
	var label: String = String(get_script().resource_path).get_file().get_basename()
	if names.is_empty():
		_failures.append("%s: the script has no test_* method" % label)
	if _failures.is_empty():
		print("TEST OK: %s (%d tests)" % [label, names.size()])
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


## Runs before every test. Override it for setup the tests share.
func before_each() -> void:
	pass


## Runs after every test, before the objects handed to `own()` are freed.
func after_each() -> void:
	pass


## Records a failure, named after the running test, when `condition` is false.
func check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [_current, message])


## `check` for two values that must be equal; the message shows both.
func check_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s: %s (got %s, expected %s)" % [_current, message, str(actual), str(expected)])


## Hands an object to the suite: it is freed after the test. Returns it for chaining.
func own(object: Object) -> Object:
	_owned.append(object)
	return object


func _free_owned() -> void:
	for object in _owned:
		if is_instance_valid(object):
			if object is Node and (object as Node).is_inside_tree():
				(object as Node).get_parent().remove_child(object as Node)
			object.free()
	_owned.clear()
