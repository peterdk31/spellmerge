class_name GpuCompute
extends RefCounted
## Whether an effect may be worked out by compute shaders on the GPU (the owner's decision of
## 2026-11-22: the heaviest per-frame effects on the GPU, the desktop builds only): the one place
## that says so, and the one place a compute shader is compiled (core/README.md, "Compute effects").
##
## - **Where:** the desktop builds' Mobile renderer (Vulkan, or Direct3D 12 on Windows) has a
##   RenderingDevice and compute; the web's Compatibility renderer (OpenGL ES), the OpenGL fallback
##   of a GPU with neither and a headless run have none. There `available()` is false and every
##   effect keeps its CPU path, which stays the reference (an effect's GPU path is tested against
##   it) and the fallback.
## - **Not on a software device:** a RenderingDevice whose device is the CPU (llvmpipe) keeps the CPU
##   paths unless `on_software` (the PR's measure: the compute work took the same cores, the splits'
##   frames a few per cent slower).
## - **Switched for tests and benchmarks:** `allowed` (true by default) turns every GPU effect off at
##   once; an effect asks `available()` when it is made or switched (`LightGrid.use_gpu`).
## - **The render thread:** a RenderingDevice call is made on the render thread only, through
##   `on_render_thread` (Godot's `RenderingServer.call_on_render_thread`: at once on the web's and
##   CI's one thread, queued in order with the frame's other calls on the desktop's separate one), so
##   what an effect dispatches at a frame's `frame_pre_draw` reads the buffers handed before it and is
##   drawn by that frame.
## - **The shaders** are `.glsl` files (imported by Godot as `RDShaderFile`; AGENTS.md, hard rule 2,
##   the owner's decision of 2026-11-22: in `core/` or `gameplay/feel/`, drawing only), each loaded
##   with a literal `load()` only behind `available()` (so never on the web or the OpenGL fallback;
##   never preloaded) and made by `compile`.
##
## View only: nothing here touches the simulation.

## Whether GPU effects may be used at all (tests and `--cpu-effects` turn it off).
static var allowed: bool = true
## Whether they may run on a device that is the CPU itself (a software Vulkan such as llvmpipe: the
## "GPU" work then takes the same cores the CPU path would, and measured slower in the splits; off by
## default, on for tests and `--gpu-on-software`).
static var on_software: bool = false


## Whether a compute effect can run here now: allowed, not the web, and a renderer with a
## RenderingDevice (the Mobile or Forward+ renderer; never Compatibility or headless).
static func available() -> bool:
	if not allowed or OS.has_feature("web"):
		return false
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return false
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		return false
	return on_software or RenderingServer.get_video_adapter_type() != RenderingDevice.DEVICE_TYPE_CPU


## `job` run on the render thread (at once when this is it), where RenderingDevice calls belong.
static func on_render_thread(job: Callable) -> void:
	RenderingServer.call_on_render_thread(job)


## The render thread's device (call from `on_render_thread`'s job only).
static func device() -> RenderingDevice:
	return RenderingServer.get_rendering_device()


## A compute shader made on `rd` (on the render thread) from `file`, a `.glsl` file Godot imported:
## its RID, or an invalid RID with the compiler's error pushed.
static func compile(rd: RenderingDevice, file: RDShaderFile, name: String) -> RID:
	if file == null:
		push_error("GpuCompute: %s did not load" % name)
		return RID()
	if file.base_error != "":
		push_error("GpuCompute: %s does not import: %s" % [name, file.base_error])
		return RID()
	var spirv: RDShaderSPIRV = file.get_spirv()
	if spirv == null or spirv.compile_error_compute != "":
		push_error("GpuCompute: %s does not compile: %s" % [name, spirv.compile_error_compute if spirv != null else "no SPIR-V"])
		return RID()
	return rd.shader_create_from_spirv(spirv, name)


## `rids` freed on the render thread, in order (what an effect made there, once it is done with it).
static func free_later(rids: Array[RID]) -> void:
	on_render_thread(_free_now.bind(rids))


static func _free_now(rids: Array[RID]) -> void:
	var rd: RenderingDevice = device()
	if rd == null:
		return
	for rid in rids:
		if rid.is_valid():
			rd.free_rid(rid)
