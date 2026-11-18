extends RefCounted
## Audio's buses (core/audio, docs/milestones/sound.md, section 5): the four volume settings and the
## duck, each a level eased on its bus of `default_bus_layout.tres` (Master > Music > MusicDuck,
## SFX, Ambience, UI), never a jump. Audio owns one and steps it every frame, paused or not.
##
## **Volumes:** a setting's share of a bus's own loudness (0 to 1, `AudioVolumes.share_of`), eased
## to at most VOLUME_RATE a second; silent, the bus is muted (nothing on it is mixed). A bus's
## volume is written only while it moves, so another Audio (a test's) is never fought.
##
## **The duck** (`duck`): `MusicDuck` lowered by the most any duck under way asks for, coming down
## over DUCK_IN seconds and back up over DUCK_OUT once the seconds of every deeper one are out: a
## ramp both ways. At most DUCKS at once; one more takes the place of the one with the least left.

## How fast a volume follows its setting (a share of the whole, a second).
const VOLUME_RATE: float = 4.0
## Seconds a duck comes in over, and lets up over.
const DUCK_IN: float = 0.05
const DUCK_OUT: float = 0.3
## Ducks under way at once.
const DUCKS: int = 8
## The deepest duck asked for (decibels).
const DUCK_MOST: float = -24.0

## The buses with a volume setting, in the order of the lists below, and the duck's.
var volume_buses: Array[StringName] = []
var duck_bus: StringName = &""

var _want: PackedFloat32Array = PackedFloat32Array()
var _heard: PackedFloat32Array = PackedFloat32Array()
var _duck_db: PackedFloat32Array = PackedFloat32Array()
var _duck_left: PackedFloat32Array = PackedFloat32Array()
## The duck heard now (decibels), and how fast it moves toward where it goes (decibels a second).
var _ducked: float = 0.0
var _duck_to: float = 0.0
var _duck_rate: float = 0.0


func _init(buses: Array[StringName], duck_on: StringName) -> void:
	volume_buses = buses
	duck_bus = duck_on
	_want.resize(buses.size())
	_want.fill(1.0)
	_heard.resize(buses.size())
	_heard.fill(1.0)
	_duck_db.resize(DUCKS)
	_duck_left.resize(DUCKS)


## The setting of `bus`: `share` of its loudness (0 to 1), eased to. False for a bus with none.
func set_volume(bus: StringName, share: float) -> bool:
	var at: int = volume_buses.find(bus)
	if at < 0:
		return false
	_want[at] = clampf(share, 0.0, 1.0)
	return true


## The share `bus`'s setting asks for, and the share heard now (1 for a bus with no setting).
func volume(bus: StringName) -> float:
	var at: int = volume_buses.find(bus)
	return _want[at] if at >= 0 else 1.0


func heard(bus: StringName) -> float:
	var at: int = volume_buses.find(bus)
	return _heard[at] if at >= 0 else 1.0


## Lowers the music by `decibels` (below 0) for `seconds`; the most asked for wins.
func duck(decibels: float, seconds: float) -> void:
	if decibels >= 0.0 or seconds <= 0.0:
		return
	var slot: int = 0
	for i in DUCKS:
		if _duck_left[i] <= 0.0:
			slot = i
			break
		if _duck_left[i] < _duck_left[slot]:
			slot = i
	_duck_db[slot] = maxf(decibels, DUCK_MOST)
	_duck_left[slot] = seconds


## The duck heard now (decibels; 0 none).
func ducked() -> float:
	return _ducked


## `delta` real seconds on: each volume eases to its setting, the ducks count down and the duck
## heard ramps to the deepest under way.
func step(delta: float) -> void:
	for i in volume_buses.size():
		if _heard[i] == _want[i]:
			continue
		_heard[i] = move_toward(_heard[i], _want[i], VOLUME_RATE * delta)
		_write(volume_buses[i], _heard[i])
	var deepest: float = 0.0
	for i in DUCKS:
		if _duck_left[i] > 0.0:
			deepest = minf(deepest, _duck_db[i])
			_duck_left[i] -= delta
	if deepest != _duck_to:
		# A new place to go: down over DUCK_IN, up over DUCK_OUT, from where it is now.
		_duck_rate = absf(deepest - _ducked) / (DUCK_IN if deepest < _ducked else DUCK_OUT)
		_duck_to = deepest
	if _ducked != _duck_to:
		_ducked = move_toward(_ducked, _duck_to, _duck_rate * delta)
		var at: int = AudioServer.get_bus_index(duck_bus)
		if at >= 0:
			AudioServer.set_bus_volume_db(at, _ducked)


## Every bus back to its full loudness and no duck at once (tests).
func reset() -> void:
	_want.fill(1.0)
	_heard.fill(1.0)
	for bus in volume_buses:
		_write(bus, 1.0)
	_duck_left.fill(0.0)
	_ducked = 0.0
	_duck_to = 0.0
	var at: int = AudioServer.get_bus_index(duck_bus)
	if at >= 0:
		AudioServer.set_bus_volume_db(at, 0.0)


static func _write(bus: StringName, share: float) -> void:
	var at: int = AudioServer.get_bus_index(bus)
	if at < 0:
		return
	AudioServer.set_bus_mute(at, share <= 0.0)
	AudioServer.set_bus_volume_db(at, linear_to_db(share) if share > 0.0 else -80.0)
