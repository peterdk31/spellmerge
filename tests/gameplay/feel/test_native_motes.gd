extends "res://tests/support/suite.gd"
## The motes' native kernel against its GDScript (native/README.md): two pools of the same kinds,
## one writing the trails' births with `MoteKernel` and one without (`Motes.native`), each settling
## into a mark layer of its own, are given the same seeded births frame after frame: every look
## kind, the dash's streak, a kind with two motes to pick from, spells' kinds through a cards
## lookup, the enemy ramp and the exact colour, a birth at no point, a frame that runs out of rows,
## and every "Particle amount". After every frame each array of the two pools (every chunk's rows,
## the chunks' flags and lives), their counters and their random state, and the settles each mark
## layer was handed must be equal byte for byte.
##
## Without the native module the test only says so (SPELLMERGE_NATIVE=required fails it).
##
## godot --headless --path . --script res://tests/gameplay/feel/test_native_motes.gd

const MotesScript := preload("res://gameplay/feel/mote.gd")
const MarksScript := preload("res://gameplay/feel/marks.gd")
const NativeScript := preload("res://core/native/native.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

const FRAMES: int = 24
const BIRTHS: int = 400
## The counters and state compared after every frame (each ring's next row and rows written: S4,
## a burst a row; the births are one-mote rows of SINGLES).
const SCALARS: Array[StringName] = [&"_ring_next", &"_ring_written", &"_rows_left", &"_settles_left", &"written", &"cut", &"births", &"settles", &"settles_skipped"]


## A spell lookup (as card_kinds.gd's `layer_motes`): odd tags get kinds of their own.
class Cards:
	extends RefCounted
	var motes: Object = null

	func layer_motes(tag: int, layer: int) -> PackedInt32Array:
		if tag % 2 == 1:
			return PackedInt32Array([3, 4]) if layer % 2 == 0 else PackedInt32Array([1])
		return motes.call(&"kinds_of_layer", layer)


func _kind(id: StringName, layers: PackedInt32Array, gravity: float, settles: StringName = &"") -> MoteKind:
	var kind := MoteKind.new()
	kind.id = id
	kind.gravity = gravity
	kind.bounce = 0.35
	kind.drag = 2.0
	kind.look_layers = layers
	kind.settles = settles
	kind.speed = Vector2(30.0, 110.0)
	kind.up = Vector2(15.0, 70.0)
	kind.life = Vector2(0.6, 2.2)
	kind.spread = 120.0
	kind.height = 5.0
	return kind


func _kinds() -> Array[MoteKind]:
	var spark := _kind(&"spark", PackedInt32Array([0]), 300.0)
	var ember := _kind(&"ember", PackedInt32Array([1]), -14.0)
	var fleck := _kind(&"fleck", PackedInt32Array([2]), 260.0, &"speck")
	fleck.wobble = 3.0
	fleck.wobble_rate = 7.5
	var ash := _kind(&"ash", PackedInt32Array([3]), 90.0, &"speck")
	ash.drag = 0.0
	var grit := _kind(&"grit", PackedInt32Array([3]), 420.0)
	grit.spread = 360.0
	var streak := _kind(&"streak", PackedInt32Array(), 0.0)
	streak.dash_path = true
	var chip := _kind(&"chip", PackedInt32Array(), 320.0, &"speck")
	chip.surface = true
	return [spark, ember, fleck, ash, grit, streak, chip]


func _side(native: bool, cards: bool) -> Array:
	var motes: MotesScript = own(MotesScript.new(3000, 0, _kinds())) as MotesScript
	motes.native = native
	root.add_child(motes)
	var speck := MarkKind.new()
	speck.id = &"speck"
	speck.form = "speck"
	var marks: MarksScript = own(MarksScript.new(-1, [speck] as Array[MarkKind])) as MarksScript
	root.add_child(marks)
	marks.enter(Rect2(-200.0, -200.0, 1000.0, 800.0), null, 8.0)
	marks.step(0.0)
	motes.settle_into(marks)
	if cards:
		var lookup := Cards.new()
		lookup.motes = motes
		motes.use_cards(lookup)
	motes.step(0.0)
	return [motes, marks]


## A frame's births, seeded: every look kind (and one with no kinds), the streak, tags odd and
## even, ramps in and out of the hats', the flags, now and then no point or no way back.
func _births(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var stride: int = ProjectilesScript.SPARK_BIRTH_STRIDE
	var given := PackedFloat32Array()
	given.resize(BIRTHS * stride)
	var kinds: PackedInt32Array = PackedInt32Array([ProjectilesScript.SPARK_STREAK, 0, 1, 2, 3, 9])
	var flags: PackedInt32Array = PackedInt32Array([0, MotesScript.LOOK_ENEMY_RAMP, MotesScript.LOOK_EXACT, MotesScript.LOOK_ENEMY_RAMP | MotesScript.LOOK_EXACT])
	for n in BIRTHS:
		var b: int = n * stride
		given[b + ProjectilesScript.SPARK_X] = rng.randf_range(-100.0, 700.0) if n % 97 != 5 else NAN
		given[b + ProjectilesScript.SPARK_Y] = rng.randf_range(-100.0, 500.0)
		var back: Vector2 = Vector2.from_angle(rng.randf() * TAU) if n % 13 != 0 else Vector2.ZERO
		given[b + ProjectilesScript.SPARK_BACK_X] = back.x
		given[b + ProjectilesScript.SPARK_BACK_Y] = back.y
		given[b + ProjectilesScript.SPARK_KIND] = kinds[rng.randi_range(0, kinds.size() - 1)]
		given[b + ProjectilesScript.SPARK_RAMP] = rng.randi_range(-1, 5)
		given[b + ProjectilesScript.SPARK_LOOK] = (1 << rng.randi_range(0, 4)) | flags[rng.randi_range(0, flags.size() - 1)]
		for c in 3:
			given[b + ProjectilesScript.SPARK_CORE + c] = rng.randf()
		given[b + ProjectilesScript.SPARK_TAG] = rng.randi_range(0, 7)
		given[b + ProjectilesScript.SPARK_TAG + 1] = rng.randi_range(0, 2)
	return given


func _compare(a: MotesScript, b: MotesScript, ma: MarksScript, mb: MarksScript, when: String) -> bool:
	var same: bool = true
	for name in SCALARS:
		if a.get(name) != b.get(name):
			check(false, "%s: %s native %s, GDScript %s" % [when, name, a.get(name), b.get(name)])
			same = false
	if a.get(&"_rng").state != b.get(&"_rng").state:
		check(false, "%s: the random state differs" % when)
		same = false
	for name: StringName in [&"_dirty", &"_until"]:
		if a.get(name) != b.get(name):
			check(false, "%s: %s differs" % [when, name])
			same = false
	var buffers_a: Array = a.get(&"_buffers")
	var buffers_b: Array = b.get(&"_buffers")
	for c in buffers_a.size():
		var one: PackedFloat32Array = buffers_a[c]
		var other: PackedFloat32Array = buffers_b[c]
		if one.to_byte_array() != other.to_byte_array():
			check(false, "%s: chunk %d's rows differ" % [when, c])
			same = false
	for name: StringName in [&"_settle", &"_settle_count", &"_settle_serial"]:
		var one: Variant = ma.get(name)
		var other: Variant = mb.get(name)
		if one != other:
			check(false, "%s: the mark layer's %s differs" % [when, name])
			same = false
	return same


func _run(cards: bool) -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		return
	var native: Array = _side(true, cards)
	var plain: Array = _side(false, cards)
	var a: MotesScript = native[0]
	var b: MotesScript = plain[0]
	check(a.get(&"_kernel") != null, "the native side runs the kernel")
	check(b.get(&"_kernel") == null, "the other runs the GDScript")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var densities: PackedFloat32Array = PackedFloat32Array([1.0, 2.0, 0.5, 1.0, 0.0, 1.0])
	var settled: int = 0
	for frame in FRAMES:
		var now: float = 0.1 + frame * (1.0 / 60.0)
		# Some frames have few rows (the births run out of them), most the default.
		var rows: int = 40 if frame % 5 == 3 else MotesScript.FRAME_ROWS * 2
		for side in [a, b]:
			side.frame_rows = rows
			side.density = densities[frame % densities.size()]
			side.step(now)
		(native[1] as MarksScript).step(now)
		(plain[1] as MarksScript).step(now)
		var given: PackedFloat32Array = _births(rng)
		var count: int = BIRTHS if frame % 4 != 1 else 37
		a.give_off(given, count)
		b.give_off(given, count)
		if not _compare(a, b, native[1], plain[1], "frame %d" % frame):
			return
		settled = a.settles
	check(settled > 0, "motes settled: %d" % settled)
	check(a.cut > 0, "a frame ran out of rows: %d cut" % a.cut)
	check(a.births > 0 and a.written > a.births / 2, "births written: %d of %d" % [a.written, a.births])


func test_the_kernel_writes_the_births_as_the_gdscript_does() -> void:
	_run(false)


func test_and_with_spells_kinds_through_a_cards_lookup() -> void:
	_run(true)
