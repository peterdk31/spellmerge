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
	var driver: String = " ".join(OS.get_video_adapter_driver_info()).strip_edges()
	out.append(PackedStringArray(["GPU", "%s (%s)%s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), (", driver " + driver) if not driver.is_empty() else ""]]))
	out.append(PackedStringArray(["OS and CPU", "%s %s; %s, %d cores" % [OS.get_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count()]]))
	var window: Vector2i = DisplayServer.window_get_size()
	var picture: Vector2i = tree.root.content_scale_size
	out.append(PackedStringArray(["Window", "%dx%d, picture %dx%d" % [window.x, window.y, picture.x, picture.y]]))
	out.append(PackedStringArray(["Render thread", "separate" if render_thread_separate() else "the main thread's"]))
	return out


## Whether the renderer runs on a thread of its own (Godot's separate thread model: the desktop
## builds', core/README.md, "The render thread"; `--render-thread` on the command line): asked from
## the main thread, which is the render thread on the other models. A benchmark then reads no
## viewport's render time, since each read waits for the render thread (a sync a frame) and would
## time it as if on one.
static func render_thread_separate() -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and not RenderingServer.is_on_render_thread()


## The facts as "Name: value" lines.
static func lines(tree: SceneTree) -> PackedStringArray:
	var out := PackedStringArray()
	for fact in facts(tree):
		out.append("%s: %s" % [fact[0], fact[1]])
	return out
