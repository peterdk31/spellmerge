extends "res://core/spells/spells.gd"
## Test stand-in for the spell runtime (not content): every staff with a card in it builds,
## `cast_staff` records who fired which staff from where and keeps a delay per caster and staff,
## and nothing is spawned. It lets the player tests run the wizard on its own, with `cost` and
## `cooldown_time` set per test. The carrier it reports for a cast (`last_form`) is the first
## card of the staff.

## Mana a cast takes, and seconds before the same player and staff may cast again.
var cost: float = 1.0
var cooldown_time: float = 0.0
## One entry per cast that fired.
var fired_players: Array[int] = []
var fired_slots: Array[int] = []
var origins: Array[Vector2] = []
var directions: Array[Vector2] = []
## [player, staff] for every install, in order.
var installed: Array[Vector2i] = []
## actor -> [aim locked at the cast, pose (turn, lift, push)] of its staff's animation, as a test
## sets it (`poses()`: `staff_pose`, `staff_pose_dir`).
var staff_poses: Dictionary = {}

var _left: PackedFloat32Array = PackedFloat32Array()
var _has: PackedByteArray = PackedByteArray()
var _first: Array[StringName] = []
var _poses_set: SetPoses = null


## Room for every actor id's four staffs.
const ROWS: int = 512 * 4


func _init() -> void:
	super()
	_left.resize(ROWS)
	_has.resize(ROWS)
	for at in ROWS:
		_first.append(&"")


func compile_staff(cards: Array[StringName], staff: StaffBase) -> CompiledStaff:
	var out := CompiledStaff.new()
	out.staff = staff
	out.cards = cards.duplicate()
	for id in cards:
		if id != &"":
			out.casts.append(CompiledCast.new())
			break
	return out


func staff_view(cards: Array[StringName], _staff: StaffBase) -> Dictionary:
	return {"empty": cards.is_empty(), "cards": cards.duplicate(), "casts": [], "wasted": {}}


func install_staff(player: int, staff: int, compiled: CompiledStaff) -> int:
	installed.append(Vector2i(player, staff))
	var at: int = player * 4 + staff
	_has[at] = 0 if compiled.is_empty() else 1
	_first[at] = &""
	for id in compiled.cards:
		if id != &"":
			_first[at] = id
			break
	return 0 if compiled.is_empty() else 1


func cast_staff(player: int, staff: int, origin: Vector2, direction: Vector2, mana: float, _walk: Vector2 = Vector2.ZERO) -> float:
	var at: int = player * 4 + staff
	if _has[at] == 0 or _left[at] > 0.0 or mana < cost:
		return REFUSED
	_left[at] = cooldown_time
	fired_players.append(player)
	fired_slots.append(staff)
	origins.append(origin)
	directions.append(direction)
	return cost


func last_form(player: int, staff: int) -> StringName:
	return _first[player * 4 + staff]


## The staff animations a test set (`staff_poses`), handed out as the runtime hands out its own.
func poses() -> StaffPoses:
	if _poses_set == null:
		_poses_set = SetPoses.new(CarrierKit.new(self))
		_poses_set.fake = self
	return _poses_set


## Reads the poses a test set on the fake that owns it (`staff_poses`).
class SetPoses:
	extends StaffPoses
	var fake: Object = null

	func staff_pose(actor: int) -> Vector3:
		return _part(actor, 1, Vector3.ZERO)

	func staff_glow(actor: int) -> float:
		return _part(actor, 2, 0.0)

	func staff_glow_tint(actor: int) -> Color:
		return _part(actor, 5, Color.WHITE)

	func staff_stretch(actor: int) -> float:
		return _part(actor, 3, 0.0)

	func staff_shake(_actor: int) -> float:
		return 0.0

	func staff_mood(actor: int) -> StringName:
		return _part(actor, 4, &"")

	func staff_pose_dir(actor: int) -> Vector2:
		return _part(actor, 0, Vector2.ZERO)

	## Part `n` of the pose a test set for `actor` ([dir, pose, glow, stretch, mood, glow tint]), or `none`.
	func _part(actor: int, n: int, none: Variant) -> Variant:
		var set_poses: Dictionary = fake.get("staff_poses")
		return set_poses[actor][n] if set_poses.has(actor) and set_poses[actor].size() > n else none


func is_holding(_player: int, _staff: int) -> bool:
	return false


func step(delta: float) -> void:
	for at in _left.size():
		_left[at] = maxf(_left[at] - delta, 0.0)
