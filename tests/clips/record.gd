extends SceneTree
## The clip recorder (#245): casts each scenario on a stage with the real spell runtime and
## Feel, and saves a frame sequence per clip to user://clips/<id>/ in the format of the
## docstring of ci/smbot/clips.py: `meta.json` ({"id", "kind", "title", "fps"}) and
## `frame_0000.png` and up, at most 240 frames of at most 640x360. The scenarios come from the
## content (scenarios.gd), so a new combo row, component or reaction is a new clip with no
## change here.
##
## Needs a display (a dummy renderer gives no pixels), so it runs only through
## `ci/build/build.sh --quick --clips`, which copies the clips to build/clips/:
##
##   godot --path . --script res://tests/clips/record.gd -- [--list] [id ...]
##
## The ids to record are the user arguments; none means all of them. `--list` prints the ids
## and records nothing. Recording a clip twice gives the same frames (docs/DECISIONS.md).
## The simulation steps by hand, 1/60 s at a time, and a frame is drawn every third step
## (20 frames a second), so the frames do not depend on how fast the machine renders.

const ScenariosScript := preload("res://tests/clips/scenarios.gd")
const StageScript := preload("res://tests/clips/stage.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

const CLIPS_DIR := "user://clips"
const FPS: int = 20
const STEPS_PER_FRAME: int = 3
## The most frames a clip has, and the biggest a frame is (the limits in ci/smbot/clips.py).
const MAX_FRAMES: int = 240
const MAX_FRAME_SIZE: Vector2i = Vector2i(640, 360)
## The part of the world a frame shows, in game pixels, around the middle of the action.
const CROP: Vector2i = Vector2i(320, 180)
## A clip stops growing past this many bytes of PNG (the pipeline's limit is 4 MB).
const MAX_CLIP_BYTES: int = 3_500_000
const SETTLE_FRAMES: int = 3


func _initialize() -> void:
	await process_frame
	var registry: Node = root.get_node_or_null("Registry")
	var table := load(ScenariosScript.REACTIONS) as ReactionTable
	if registry == null or table == null:
		printerr("CLIPS FAILED: the Registry autoload and the reaction table must exist")
		quit(1)
		return
	var namer: Node = SpellsScript.new()
	namer.set("registry", registry)
	var all: Array[Dictionary] = ScenariosScript.build(registry, namer, ScenariosScript.read_combos(), table)
	namer.free()
	var wanted: PackedStringArray = PackedStringArray()
	var list: bool = false
	for argument in OS.get_cmdline_user_args():
		if argument == "--list":
			list = true
		else:
			wanted.append(argument)
	if list:
		for scenario in all:
			print("CLIP: %s (%s) %s" % [scenario["id"], scenario["kind"], scenario["title"]])
		quit(0)
		return
	var chosen: Array[Dictionary] = _choose(all, wanted)
	var failed: PackedStringArray = PackedStringArray()
	var stage := StageScript.new(root, registry)
	for scenario in chosen:
		if not ScenariosScript.valid_id(scenario["id"]):
			printerr("CLIP SKIPPED: %s is not a valid clip id" % scenario["id"])
			failed.append(scenario["id"])
			continue
		var frames: Array[PackedByteArray] = await _play(stage, scenario)
		if frames.is_empty():
			failed.append(scenario["id"])
			continue
		if not _save(scenario, frames):
			failed.append(scenario["id"])
	stage.free_all()
	for id in wanted:
		if not _has(all, id):
			printerr("CLIP UNKNOWN: there is no clip %s (--list shows them)" % id)
			failed.append(id)
	if failed.is_empty():
		print("CLIPS OK: %d" % chosen.size())
	else:
		printerr("CLIPS FAILED: %s" % ", ".join(failed))
	quit(0 if failed.is_empty() else 1)


## The scenarios to record: the ones named, all of them for no names.
func _choose(all: Array[Dictionary], wanted: PackedStringArray) -> Array[Dictionary]:
	var chosen: Array[Dictionary] = []
	for scenario in all:
		if wanted.is_empty() or wanted.has(scenario["id"]):
			chosen.append(scenario)
	return chosen


func _has(all: Array[Dictionary], id: String) -> bool:
	for scenario in all:
		if scenario["id"] == id:
			return true
	return false


## Plays `scenario` and returns its frames (empty when it can't be played).
func _play(stage: RefCounted, scenario: Dictionary) -> Array[PackedByteArray]:
	var frames: Array[PackedByteArray] = []
	if not stage.call("start", scenario):
		return frames
	for i in SETTLE_FRAMES:
		await process_frame
	var count: int = mini(int(float(scenario["seconds"]) * FPS), MAX_FRAMES)
	var bytes: int = 0
	for frame in count:
		for step in STEPS_PER_FRAME:
			stage.call("tick")
		stage.call("update_draw")
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = _crop()
		if image == null:
			printerr("CLIP FAILED: %s: the viewport gave no image" % scenario["id"])
			frames.clear()
			break
		var png: PackedByteArray = image.save_png_to_buffer()
		bytes += png.size()
		if bytes > MAX_CLIP_BYTES:
			print("CLIP CUT: %s stops at frame %d (size limit)" % [scenario["id"], frame])
			break
		frames.append(png)
	if scenario["kind"] == "reaction" and not (stage.call("reaction_ids") as Array).has(StringName(String(scenario["id"]).trim_prefix("reaction_").trim_suffix("_coop"))):
		printerr("CLIP FAILED: %s did not set off its reaction" % scenario["id"])
		frames.clear()
	stage.call("free_all")
	return frames


## The middle of the picture, CROP game pixels wide, at most MAX_FRAME_SIZE.
func _crop() -> Image:
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		return null
	var factor: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var size: Vector2i = Vector2i(Vector2(CROP) * factor)
	var corner: Vector2i = ((image.get_size() - size) / 2).clamp(Vector2i.ZERO, image.get_size())
	var crop: Image = image.get_region(Rect2i(corner, size.min(image.get_size())))
	if crop.get_size() != CROP:
		crop.resize(CROP.x, CROP.y, Image.INTERPOLATE_NEAREST)
	crop.convert(Image.FORMAT_RGB8)
	return crop


## Writes the frames and meta.json of one clip, replacing a folder of the same id.
func _save(scenario: Dictionary, frames: Array[PackedByteArray]) -> bool:
	var folder: String = "%s/%s" % [CLIPS_DIR, scenario["id"]]
	DirAccess.make_dir_recursive_absolute(folder)
	var directory := DirAccess.open(folder)
	if directory == null:
		printerr("CLIP FAILED: could not open " + folder)
		return false
	for file in directory.get_files():
		directory.remove(file)
	for i in frames.size():
		var file := FileAccess.open("%s/frame_%04d.png" % [folder, i], FileAccess.WRITE)
		if file == null:
			printerr("CLIP FAILED: could not save frame %d of %s" % [i, scenario["id"]])
			return false
		file.store_buffer(frames[i])
		file.close()
	var meta := FileAccess.open(folder + "/meta.json", FileAccess.WRITE)
	if meta == null:
		printerr("CLIP FAILED: could not write the meta.json of " + scenario["id"])
		return false
	meta.store_string(JSON.stringify({"id": scenario["id"], "kind": scenario["kind"], "title": scenario["title"], "fps": FPS}))
	meta.close()
	print("CLIP: %s (%d frames)" % [scenario["id"], frames.size()])
	return true
