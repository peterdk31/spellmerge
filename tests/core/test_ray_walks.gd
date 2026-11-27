extends "res://tests/support/suite.gd"
## Many beams' rays walked together (`Projectiles.ray_walks`, #972): in C++ (`ShotKernel.ray_walks`)
## they give the bits of the GDScript, which walks each with `ray_points` as the beam carrier does
## between a beam's hits. Seeded rooms of walls and targets (round and boxed, on both layers, one
## freed while still listed), each walked in rounds with the targets' grid fresh and stale, rays
## straight and bent, cut by walls, spent on targets, cast from a target's body, through walls
## (ghost), and the rays the kernel hands back to GDScript (one not cast, a caster that is no actor,
## more pierce than it keeps, a path longer than the manager's scratch): what each ray hands back and
## every member of the two managers after, byte for byte, and the room grid's. Without the module
## the GDScript is checked against `ray_points` alone (SPELLMERGE_NATIVE=required fails then).
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const NativeScript := preload("res://core/native/native.gd")

const BOUNDS: Rect2 = Rect2(-320.0, -240.0, 960.0, 640.0)
const ROOMS: int = 24
const ROUNDS: int = 4
const RAYS: int = 48
## Members the managers own apart: the kernel, the switch, the scratch the kernel is handed.
const NOT_COMPARED: Array[StringName] = [&"_kernel", &"native", &"_kernel_nearest", &"_kernel_rays", &"_walk_skips"]

var _rays_walked_natively: int = 0


func _manager(native: bool) -> ManagerScript:
	var m: ManagerScript = own(ManagerScript.new()) as ManagerScript
	m.native = native
	m.set_bounds(BOUNDS)
	root.add_child(m)
	return m


## The same seeded room in each manager of `managers`: walls, and targets on both layers (returned,
## a node a target each, the same for every manager).
func _room(managers: Array, rng: RandomNumberGenerator) -> Array[Node2D]:
	var walls: Array[Rect2] = []
	for n in rng.randi_range(0, 8):
		walls.append(Rect2(BOUNDS.position + Vector2(rng.randf_range(0.0, BOUNDS.size.x), rng.randf_range(0.0, BOUNDS.size.y)), Vector2(rng.randf_range(8.0, 90.0), rng.randf_range(8.0, 90.0))))
	var nodes: Array[Node2D] = []
	var shapes: Array = []
	for n in rng.randi_range(0, 30):
		var node: Node2D = own(Node2D.new()) as Node2D
		root.add_child(node)
		node.global_position = Vector2(rng.randf_range(-100.0, 500.0), rng.randf_range(-150.0, 300.0))
		var half: Vector2 = Vector2.ZERO if rng.randf() < 0.5 else Vector2(rng.randf_range(2.0, 24.0), rng.randf_range(2.0, 24.0))
		shapes.append([rng.randf_range(2.0, 16.0), ManagerScript.LAYER_ENEMY if rng.randf() < 0.7 else ManagerScript.LAYER_PLAYER, half])
		nodes.append(node)
	for m: ManagerScript in managers:
		m.set_walls(walls)
		for n in nodes.size():
			m.add_target(nodes[n], shapes[n][0], shapes[n][1], -1, Vector2.ZERO, 0, shapes[n][2])
	return nodes


## RAYS rays, each a row of `points` (`stride` a row): straight, bent (a homing beam's curve and its
## legs), or waving, some of them cut short by their length, and now and then one the kernel hands back.
func _rays(rng: RandomNumberGenerator, nodes: Array[Node2D], stride: int) -> Dictionary:
	var rays: Dictionary = {
		"actors": PackedInt32Array(), "points": PackedVector2Array(), "offsets": PackedInt32Array(), "counts": PackedInt32Array(),
		"lengths": PackedFloat64Array(), "pierces": PackedInt32Array(), "widths": PackedFloat64Array(), "ghosts": PackedByteArray(), "sources": [] as Array[Node]}
	rays["points"].resize(RAYS * stride)
	for n in RAYS:
		var from: Vector2 = Vector2(rng.randf_range(-60.0, 420.0), rng.randf_range(-120.0, 260.0))
		var source: Node = null
		if not nodes.is_empty() and rng.randf() < 0.2:
			# Cast from a target's body: it is spared until the path leaves it.
			var body: Node2D = nodes[rng.randi_range(0, nodes.size() - 1)]
			source = body
			from = body.global_position
		var way: Vector2 = Vector2.from_angle(rng.randf() * TAU)
		var count: int = 2
		var kind: float = rng.randf()
		if kind < 0.3:
			count = rng.randi_range(3, mini(stride, 26))
		elif kind < 0.33:
			count = stride
		var point: Vector2 = from
		for k in count:
			rays["points"][n * stride + k] = point
			way = way.rotated(rng.randf_range(-0.6, 0.6)) if count > 2 else way
			point += way * rng.randf_range(4.0, 300.0 / float(count - 1) * 2.0)
		var length: float = rng.randf_range(10.0, 400.0)
		var actor: int = rng.randi_range(-1, 3)
		var pierce: int = rng.randi_range(0, 3)
		var odd: float = rng.randf()
		# The kernel's hand-backs, a few of each.
		if odd < 0.03:
			count = 1
		elif odd < 0.06:
			actor = ManagerScript.ACTORS + 5
		elif odd < 0.09:
			pierce = 100
		elif odd < 0.11:
			length = 0.0
		elif odd < 0.13:
			rays["points"][n * stride] = Vector2.INF
		elif odd < 0.15:
			rays["points"][n * stride + 1] = Vector2(NAN, 0.0)
		rays["actors"].append(actor)
		rays["offsets"].append(n * stride)
		rays["counts"].append(count)
		rays["lengths"].append(length)
		rays["pierces"].append(pierce)
		rays["widths"].append(0.0 if rng.randf() < 0.2 else rng.randf_range(0.5, 14.0))
		rays["ghosts"].append(1 if rng.randf() < 0.1 else 0)
		rays["sources"].append(source)
	return rays


func _walk(m: ManagerScript, rays: Dictionary) -> Array:
	var got := PackedFloat64Array()
	var ends := PackedVector2Array()
	var headings := PackedVector2Array()
	got.resize(RAYS)
	ends.resize(RAYS)
	headings.resize(RAYS)
	m.ray_walks(RAYS, rays["actors"], rays["points"], rays["offsets"], rays["counts"], rays["lengths"], rays["pierces"], rays["widths"], rays["ghosts"], rays["sources"], ManagerScript.ACTOR_LAYERS, got, ends, headings)
	return [got, ends, headings]


## What the beam carrier did before rays were walked together: each ray alone, `ray_points` after
## `ray_gates`.
func _walk_alone(m: ManagerScript, rays: Dictionary) -> Array:
	var got := PackedFloat64Array()
	var ends := PackedVector2Array()
	var headings := PackedVector2Array()
	for n in RAYS:
		m.ray_gates = true
		m.ray_air = 0.0
		got.append(m.ray_points(rays["actors"][n], rays["points"], rays["offsets"][n], rays["counts"][n], rays["lengths"][n], rays["pierces"][n], ManagerScript.ACTOR_LAYERS, 0, rays["widths"][n], rays["sources"][n], false, 0, Callable(), rays["ghosts"][n] != 0))
		ends.append(m.ray_end)
		headings.append(m.ray_end_heading)
	return [got, ends, headings]


## Every state member of the two managers (not DERIVED or VIEW, nor NOT_COMPARED, nor the objects
## they hold) byte for byte, and the room grid's; the first that differs, or "".
func _difference(a: ManagerScript, b: ManagerScript) -> String:
	for prop: Dictionary in a.get_property_list():
		var member: StringName = prop["name"]
		if (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or member in NOT_COMPARED or member in ManagerScript.DERIVED or member in ManagerScript.VIEW or prop["type"] == TYPE_OBJECT or prop["type"] == TYPE_CALLABLE or prop["type"] == TYPE_SIGNAL:
			continue
		var x: Variant = a.get(member)
		var y: Variant = b.get(member)
		if prop["type"] == TYPE_ARRAY:
			# Arrays of nodes and scratch: compared as what they hold, by instance.
			if str(x) != str(y):
				return String(member)
			continue
		if var_to_bytes(x) != var_to_bytes(y):
			return String(member)
	for prop: Dictionary in a.grid().get_property_list():
		var member: StringName = prop["name"]
		if (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and var_to_bytes(a.grid().get(member)) != var_to_bytes(b.grid().get(member)):
			return "room grid " + String(member)
	return ""


func test_the_kernel_walks_the_rays_as_ray_points_does() -> void:
	var native: bool = NativeScript.loaded()
	if not native:
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261127
	var walked: int = 0
	var spent: int = 0
	var walled: int = 0
	for room in ROOMS:
		# The GDScript, the native kernel, and each ray alone (the carrier's old way).
		var managers: Array = [_manager(false), _manager(true), _manager(false)]
		var nodes: Array[Node2D] = _room(managers, rng)
		if room == 3 and not nodes.is_empty():
			# A target freed while it is still listed (its grid row is skipped, never hit).
			nodes[0].free()
			nodes.remove_at(0)
		for turn in ROUNDS:
			if turn == 2 and not nodes.is_empty():
				# The targets move and one leaves: the grid is stale again, filled by the first ray
				# that needs it (the kernel hands that one back).
				for node in nodes:
					node.global_position += Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0))
				for m: ManagerScript in managers:
					m.remove_target(nodes[nodes.size() - 1])
			var stride: int = ManagerScript.RAY_PATH_START + 12 if turn == 3 else 32
			var rays: Dictionary = _rays(rng, nodes, stride)
			var outs: Array = [_walk(managers[0], rays), _walk(managers[1], rays), _walk_alone(managers[2], rays)]
			for side in [1, 2]:
				for k in 3:
					var first: int = -1
					for n in RAYS:
						if var_to_bytes(outs[side][k][n]) != var_to_bytes(outs[0][k][n]):
							first = n
							break
					check(first < 0, "room %d round %d: the %s %s of ray %d (%s, the GDScript's %s)" % [room, turn, ["native", "alone"][side - 1], ["got", "ends", "headings"][k], first, outs[side][k][maxi(first, 0)], outs[0][k][maxi(first, 0)]])
				var differs: String = _difference(managers[0], managers[side])
				check_equal(differs, "", "room %d round %d: the %s manager is left as the GDScript leaves it" % [room, turn, ["native", "alone"][side - 1]])
			for n in RAYS:
				if outs[0][0][n] > 0.0:
					walked += 1
					if outs[0][0][n] < rays["lengths"][n] - 0.01:
						if (outs[0][1][n] as Vector2).is_finite():
							spent += 1
		walled += 1 if managers[0].grid().has_walls() else 0
		for m: ManagerScript in managers:
			m.queue_free()
	# The rooms meet every case.
	check(walked > ROOMS * ROUNDS * RAYS / 2, "most rays walked (%d)" % walked)
	check(spent > 100, "rays cut short by a wall or a target (%d)" % spent)
	check(walled > ROOMS / 2, "rooms with walls (%d)" % walled)


func test_the_kernel_walks_plain_rays_itself() -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		return
	var m: ManagerScript = _manager(true)
	check(m.is_native() and m._kernel_rays, "the kernel has ray_walks")
	var target: Node2D = own(Node2D.new()) as Node2D
	root.add_child(target)
	target.global_position = Vector2(100.0, 4.0)
	m.add_target(target, 8.0)
	m.set_walls([Rect2(200.0, -50.0, 20.0, 100.0)] as Array[Rect2])
	# A fresh grid (asked once), then a fan of straight rays the kernel walks with no hand-back.
	m.nearest_target(Vector2.ZERO, 1.0, ManagerScript.ACTOR_LAYERS)
	var points := PackedVector2Array()
	var offsets := PackedInt32Array()
	var counts := PackedInt32Array()
	var lengths := PackedFloat64Array()
	var zeros := PackedInt32Array()
	var widths := PackedFloat64Array()
	var ghosts := PackedByteArray()
	var skips := PackedInt32Array()
	var fan: int = 9
	for n in fan:
		points.append(Vector2.ZERO)
		points.append(Vector2.from_angle(deg_to_rad(-15.0 + 30.0 * n / (fan - 1))) * 300.0)
		offsets.append(n * 2)
		counts.append(2)
		lengths.append(300.0)
		zeros.append(0)
		widths.append(3.0)
		ghosts.append(0)
		skips.append(-1)
	var got := PackedFloat64Array()
	var ends := PackedVector2Array()
	var headings := PackedVector2Array()
	got.resize(fan)
	ends.resize(fan)
	headings.resize(fan)
	var stop: int = m._kernel.call(&"ray_walks", m, 0, fan, zeros, points, offsets, counts, lengths, zeros, widths, ghosts, skips, ManagerScript.ACTOR_LAYERS, m._targets.size(), false, got, ends, headings)
	check_equal(stop, fan, "every ray walked in C++")
	check(got[fan / 2] <= 100.01, "the middle ray is spent on the target (%f)" % got[fan / 2])
	check(absf(got[0] - 300.0) > 1.0 and got[0] < 300.0, "the first ray stops at the wall (%f)" % got[0])
	check_equal(m.ray_path_count, 2, "the last walk kept")
	# A stale grid: the first ray that needs the targets is handed back.
	m.remove_target(target)
	stop = m._kernel.call(&"ray_walks", m, 0, fan, zeros, points, offsets, counts, lengths, zeros, widths, ghosts, skips, ManagerScript.ACTOR_LAYERS, m._targets.size(), true, got, ends, headings)
	check_equal(stop, fan, "with no target listed no ray needs the grid")
	m.add_target(target, 8.0)
	stop = m._kernel.call(&"ray_walks", m, 0, fan, zeros, points, offsets, counts, lengths, zeros, widths, ghosts, skips, ManagerScript.ACTOR_LAYERS, m._targets.size(), true, got, ends, headings)
	check_equal(stop, 0, "a stale grid hands back the first ray that needs it")
