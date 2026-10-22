extends "res://tests/support/suite.gd"
## The placeholder SVGs follow docs/STYLE.md ("Placeholder SVGs"): rects only, palette colours
## only, whole numbers inside the canvas, no overlapping rects, a size on the 8 px grid, and an
## entry in art/manifest.json. Every file is checked on its own and the message names it, so
## one bad sprite never hides another.

const ROOTS: Array[String] = ["res://art/tilesets", "res://art/vfx", "res://art/ui", "res://content"]
## Files that must be found, so a broken scan cannot pass by finding nothing.
const KNOWN: Array[String] = [
	"res://art/tilesets/crypt/floor.svg",
	"res://content/enemies/ember_imp/idle.svg",
]
const PALETTE: Array[String] = [
	"#14121f",
	"#2b2840", "#4a4663", "#7a7694",
	"#a39fb8", "#d4d0e0", "#f4f1ea",
	"#8f2d2a", "#e0592f", "#ffa23c",
	"#b8801f", "#f2c230", "#fff3a6",
	"#3d2a2e", "#7a4a35", "#b27a4a",
	"#8a5a44", "#d99a74", "#f5cfa8",
	"#1f7080", "#4fd6dc", "#c4f6f2",
	"#4a1450", "#a0309a", "#e08ad8",
	"#1d3a6b", "#3b73c9", "#7fc0f0",
	"#7a2347", "#d9477a", "#f59ab8",
	"#1f4a3a", "#3f8f4f", "#8fd46a",
	"#4a2a6b", "#8a4fc4", "#c99af0",
]
const RECT_ATTRIBUTES: Array[String] = ["x", "y", "width", "height", "fill"]

var _files: Array[String] = []


func before_each() -> void:
	if _files.is_empty():
		for root_path in ROOTS:
			_find(root_path)


func test_the_scan_finds_the_art() -> void:
	for known in KNOWN:
		check(_files.has(known), "the scan did not find %s: it is broken" % known)


func test_the_checker_catches_a_bad_file() -> void:
	var bad: String = '<svg width="8" height="8"><circle r="3"/><rect x="0" y="0" width="9" height="1" fill="#123456"/></svg>'
	check(not _problems(bad).is_empty(), "a circle, a stray colour and a rect outside the canvas passed")
	var good: String = '<svg width="8" height="8" shape-rendering="crispEdges"><rect x="0" y="0" width="2" height="1" fill="#14121f"/></svg>'
	check_equal(_problems(good), [] as Array[String], "a valid file was rejected")
	var overlap: String = '<svg width="8" height="8" shape-rendering="crispEdges"><rect x="0" y="0" width="2" height="1" fill="#14121f"/><rect x="1" y="0" width="2" height="1" fill="#14121f"/></svg>'
	check(not _problems(overlap).is_empty(), "overlapping rects passed")


func test_every_svg_follows_the_style_rules() -> void:
	for path in _files:
		for problem in _problems(FileAccess.get_file_as_string(path)):
			check(false, "%s: %s" % [path, problem])


func test_every_svg_is_in_the_manifest() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://art/manifest.json"))
	check(manifest is Dictionary, "art/manifest.json is a JSON object")
	if not manifest is Dictionary:
		return
	var listed: Dictionary = {}
	for entry: Variant in (manifest as Dictionary).get("assets", []):
		if entry is Dictionary:
			listed["res://" + String((entry as Dictionary).get("path", ""))] = true
	for path in _files:
		check(listed.has(path), "%s has no entry in art/manifest.json" % path)


## Every problem in one SVG text; empty when it is valid.
func _problems(text: String) -> Array[String]:
	var problems: Array[String] = []
	var header: RegExMatch = RegEx.create_from_string('<svg[^>]*width="(\\d+)"[^>]*height="(\\d+)"').search(text)
	if header == null:
		problems.append("no <svg> with a width and a height")
		return problems
	var width: int = header.get_string(1).to_int()
	var height: int = header.get_string(2).to_int()
	if width % 8 != 0 or height % 8 != 0:
		problems.append("size %dx%d is not on the 8 px grid" % [width, height])
	if not text.contains('shape-rendering="crispEdges"'):
		problems.append('the root has no shape-rendering="crispEdges"')
	for tag in RegEx.create_from_string("<([A-Za-z]+)").search_all(text):
		var name: String = tag.get_string(1)
		if name != "svg" and name != "rect":
			problems.append("<%s> is not allowed, only <rect>" % name)
	var taken: PackedByteArray = PackedByteArray()
	taken.resize(width * height)
	var attribute_pattern: RegEx = RegEx.create_from_string('([A-Za-z-]+)="([^"]*)"')
	for rect in RegEx.create_from_string("<rect ([^>]*)/>").search_all(text):
		var values: Dictionary = {}
		for pair in attribute_pattern.search_all(rect.get_string(1)):
			values[pair.get_string(1)] = pair.get_string(2)
		var shift: Vector2i = Vector2i.ZERO
		for key: String in values:
			if key == "transform":
				# Only a whole-number translate is allowed (docs/STYLE.md).
				var move: RegExMatch = RegEx.create_from_string("^translate\\((-?\\d+)[ ,]+(-?\\d+)\\)$").search(String(values[key]))
				if move == null:
					problems.append('transform "%s" is not a whole-number translate' % values[key])
				else:
					shift = Vector2i(move.get_string(1).to_int(), move.get_string(2).to_int())
			elif not RECT_ATTRIBUTES.has(key):
				problems.append("a rect has the attribute %s" % key)
		var fill: String = String(values.get("fill", ""))
		if not PALETTE.has(fill):
			problems.append("fill %s is not a palette colour (lower-case #rrggbb)" % fill)
		var box: Array[int] = []
		for key in ["x", "y", "width", "height"]:
			var raw: String = String(values.get(key, ""))
			if not raw.is_valid_int():
				problems.append("%s=\"%s\" is not a whole number" % [key, raw])
				break
			box.append(raw.to_int())
		if box.size() != 4:
			continue
		box[0] += shift.x
		box[1] += shift.y
		if box[2] <= 0 or box[3] <= 0 or box[0] < 0 or box[1] < 0 or box[0] + box[2] > width or box[1] + box[3] > height:
			problems.append("rect %s is empty or outside the %dx%d canvas" % [str(box), width, height])
			continue
		var overlapped: bool = false
		for y in range(box[1], box[1] + box[3]):
			for x in range(box[0], box[0] + box[2]):
				overlapped = overlapped or taken[y * width + x] != 0
				taken[y * width + x] = 1
		if overlapped:
			problems.append("rect %s overlaps another rect" % str(box))
	return problems


func _find(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_find(dir_path.path_join(sub))
	for file_name in dir.get_files():
		if file_name.ends_with(".svg"):
			_files.append(dir_path.path_join(file_name))
