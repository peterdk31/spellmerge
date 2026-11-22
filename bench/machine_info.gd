extends RefCounted
## What a benchmark ran on (D1, 2026-11-22): the renderer and its driver, the GPU, the OS, the CPU
## and its cores, the window and the picture, and the build. Read from the engine only, so it is the
## same on every platform; `lines()` is what the results screen and `user://benchmark.txt` start with.


## The facts, each a [name, value] pair, in the order they are shown.
static func facts(tree: SceneTree) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var version: Dictionary = Engine.get_version_info()
	out.append(PackedStringArray(["Build", "%s (Godot %s)" % [BuildInfo.describe(), String(version.get("string", ""))]]))
	out.append(PackedStringArray(["Renderer", "%s, %s %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_api_version()]]))
	out.append(PackedStringArray(["GPU", "%s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()]]))
	out.append(PackedStringArray(["GPU driver", " ".join(OS.get_video_adapter_driver_info())]))
	out.append(PackedStringArray(["OS", "%s %s" % [OS.get_name(), OS.get_version()]]))
	out.append(PackedStringArray(["CPU", "%s, %d cores" % [OS.get_processor_name(), OS.get_processor_count()]]))
	var window: Vector2i = DisplayServer.window_get_size()
	var picture: Vector2i = tree.root.content_scale_size
	out.append(PackedStringArray(["Window", "%dx%d, picture %dx%d" % [window.x, window.y, picture.x, picture.y]]))
	return out


## The facts as "Name: value" lines.
static func lines(tree: SceneTree) -> PackedStringArray:
	var out := PackedStringArray()
	for fact in facts(tree):
		out.append("%s: %s" % [fact[0], fact[1]])
	return out
