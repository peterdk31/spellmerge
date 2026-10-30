class_name FormBase
extends SpellComponent
## A carrier (bolt, beam, nova, rune, orbit, dash, teleport, ...): what leaves the caster
## and ends a group when a staff is read (docs/milestones/M2-staffs.md). It sets the base
## numbers the infusions and modifiers before it then change. The class keeps its old name,
## `FormBase`, and its kind `&"form"`.

## Staff animations (`staff_pose`): the phases a key can be in, the eases into a key, the moods
## a key can show on the staff's face (its brows), the channels a key moves and the numbers each
## key is packed into for playing (`packed_pose`: phase, at, the CHANNELS, ease, mood).
const POSE_PHASES: Dictionary = {"wind": 0, "strike": 1, "hold": 2, "after": 3}
const POSE_EASES: Dictionary = {"inout": 0, "out": 1, "in": 2}
const POSE_MOODS: Array[StringName] = [&"raised", &"angry", &"furious", &"worried"]
const POSE_CHANNELS: Array[String] = ["turn", "lift", "push", "glow", "stretch", "shake"]
## Where each number is in a packed key, and how many a key has.
const PK_PHASE: int = 0
const PK_AT: int = 1
const PK_CHANNELS: int = 2
const PK_EASE: int = 8
const PK_MOOD: int = 9
const POSE_STRIDE: int = 10
## The ranges of the channels a key may set (`turn` in degrees, `lift`, `push` and `shake` in
## pixels, `glow` 0 to 1, `stretch` as a share: 0.3 is 30% longer along the aim and thinner across).
const POSE_RANGES: Dictionary = {
	"turn": Vector2(-720.0, 720.0), "lift": Vector2(-6.0, 16.0), "push": Vector2(-12.0, 12.0),
	"glow": Vector2(0.0, 1.0), "stretch": Vector2(-0.5, 1.0), "shake": Vector2(0.0, 4.0),
}

## How the shots move once spawned.
enum Motion {
	## A shot flies in a line (bolt, nova).
	STRAIGHT,
	## A shot stays where it was placed and waits for a target to enter (rune).
	STILL,
	## A shot circles its caster at `orbit_radius` (orbit).
	ORBIT,
	## No shot: one ray of `ray_length` hits along a line at once (beam).
	RAY,
	# Staffs (A3). Each is run by the kit named, until then the carrier does nothing.
	## The wizard dashes along the move direction for `lifetime` seconds at `speed` (A6a).
	DASH,
	## The wizard blinks `speed` x `lifetime` pixels along the aim, stopping before walls (B2, B4).
	TELEPORT,
	## A straight shot that pulls the caster to where it hits (B2, B4).
	HOOK,
	## A straight shot that trades places with the target it hits (B2, B4, B5).
	SWAP,
	## `shots` still shots in a line across the aim, `spread` pixels apart (B2).
	WALL,
	## Reads a payload and drops it on the aim point after `lifetime` seconds (B2).
	RAIN,
	## A crack along the ground that hits every target on its line, `ray_length` long (B2).
	FISSURE,
	## A still copy of the wizard that enemies target, for `lifetime` seconds (B2, B5).
	DECOY,
	## A helper that orbits the caster and casts its payload every `cooldown` seconds (B2, B5).
	FAMILIAR,
	## Melee (I2): the staff leans back for `wind_up` seconds, then sweeps `arc` degrees round the
	## hand, centred on the aim locked at the cast, out to `ray_length`, in `lifetime` seconds,
	## hitting each body in the swept wedge once. Forehand and backhand by turns.
	SWING,
	## Melee (I8): the staff rises for `wind_up` seconds, then strikes the floor `ray_length` ahead
	## of the hand, aimed as at the cast; a ring grows from the impact to `radius` and holds for
	## `lifetime` seconds, striking each body in it once and throwing it outward.
	SLAM,
}

## Damage of one hit before the element and modifiers.
@export var base_damage: int = 1
## Mana taken per cast.
@export var mana_cost: float = 0.0
## Seconds before the same player can cast this spell again. There is no separate cast
## time: the cooldown is the cast time.
@export var cooldown: float = 0.5
## Pixels per second. Ignored by STILL and RAY.
@export var speed: float = 0.0
## Seconds a shot lives. For RAY, how long the beam stays on (it hits every `SpellLimits.BEAM_TICK`).
@export var lifetime: float = 1.0
## Hit circle of one shot in pixels. For RAY, the half-width of the beam.
@export var radius: float = 4.0
## Shots per cast before modifiers (a nova has many, a bolt one).
@export var shots: int = 1
## Angle in degrees the shots are spread over (360 for a full ring).
@export_range(0.0, 360.0) var spread: float = 0.0
@export var motion: Motion = Motion.STRAIGHT
## Extra targets each shot passes through before it ends.
@export var pierce: int = 0
## ORBIT only: distance from the caster in pixels.
@export var orbit_radius: float = 0.0
## RAY, FISSURE and RAIN: how far it reaches in pixels. DASH and TELEPORT: how far the caster
## moves (fixed: speed only changes how long a dash takes).
@export var ray_length: float = 0.0
## SWING: degrees the sweep hits over, centred on the aim.
@export var arc: float = 0.0
## SWING: seconds the staff leans back before it sweeps (none when it chains straight on from
## the last swing, `SpellLimits.SWING_CHAIN`). SLAM: seconds it rises before it strikes.
@export var wind_up: float = 0.0
## How the staff moves when this carrier is cast (its look only; a wizard's own cast, not a payload's):
## keys, each a dictionary, played in order from the staff's pose at the cast (rest, or where the
## last animation had it) and back on the aim after the last. A key says when, as `phase` and `at`:
##   "wind"    `at` 0 to 1 of the carrier's `wind_up`
##   "strike"  `at` 0 to 1 of its strike, the carrier's own working time: a swing's sweep, a slam's
##             ring, a beam's, orbit's, rain's or dash's life (a held one's until its last shot ends);
##             the others have none, so their strike keys pass at once
##   "hold"    `at` in seconds; these keys repeat for as long as the strike lasts (a held beam
##             straining), each round from the last of them
##   "after"   `at` in seconds after the strike
## and where the staff is then, every channel it leaves out at rest (0): `turn` (degrees off the aim
## locked at the cast: for a swing the way it swings, a backhand the other way; for the others
## negative lifts the head toward the top of the screen whichever way it faces), `lift` (pixels up
## off its hover; its shadow stays on the floor), `push` (pixels along the aim; negative draws it
## back), `glow` (0 to 1: light round the staff in its infusion's colour, else its player's),
## `stretch` (longer along the aim and thinner across, negative squashed) and `shake` (pixels of
## jitter); the `ease` into it ("inout", "out" slowing into it, "in" speeding up into it) and a
## `mood` the face shows from then on (POSE_MOODS). Ranges in POSE_RANGES; the validator checks it.
## Example: [{"phase": "after", "at": 0.04, "push": -3, "ease": "out"}, {"phase": "after", "at": 0.2}].
@export var staff_pose: Array[Dictionary] = []

## `staff_pose` packed into numbers for playing (POSE_STRIDE a key), made once.
var _packed_pose: PackedFloat32Array = PackedFloat32Array()
var _pose_packed: bool = false
## Knockback of one hit in pixels per second; 0 for the usual `SpellLimits.KNOCKBACK`.
@export var knockback: float = 0.0
## How the wizard's cast flash looks for this carrier (staffs B6b; `gameplay/feel` reads it, and
## an empty one gets the plain muzzle flash). Keys, all optional: `seconds`, `size`, `stretch`
## (length along the aim), `tall`, `aim` (turned along the aim, else upright), `grow` (0.5 bursts
## outwards; negative gathers inwards) and `ring` (the nova ring art instead of the spark).
@export var cast_look: Dictionary = {}
## The same keys for the flare where this carrier's shot ends or hits (an empty one gets the wall
## spark), and `cue`: the id of a cue (`content/cues`, e.g. `quake`, the ground struck) Feel plays
## where the carrier ends on no body, as big as its `radius`, and at a slam's impact, as big as its
## ring. A new carrier brings its looks in its own `.tres`; Feel's preset has none of them.
@export var impact_look: Dictionary = {}


func kind() -> StringName:
	return &"form"


## `staff_pose` as numbers, POSE_STRIDE a key (phase, at, the POSE_CHANNELS, ease, mood: 0 for
## none, else 1 + its place in POSE_MOODS), made the first time it is asked for. A key with a
## name it does not know packs as rest (the validator reports it).
func packed_pose() -> PackedFloat32Array:
	if _pose_packed:
		return _packed_pose
	_pose_packed = true
	_packed_pose = pack_pose(staff_pose)
	return _packed_pose


static func pack_pose(keys: Array[Dictionary]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(keys.size() * POSE_STRIDE)
	for n in keys.size():
		var key: Dictionary = keys[n]
		var at: int = n * POSE_STRIDE
		out[at + PK_PHASE] = float(POSE_PHASES.get(key.get("phase", "after"), POSE_PHASES["after"]))
		out[at + PK_AT] = float(key.get("at", 0.0))
		for c in POSE_CHANNELS.size():
			out[at + PK_CHANNELS + c] = float(key.get(POSE_CHANNELS[c], 0.0))
		out[at + PK_EASE] = float(POSE_EASES.get(key.get("ease", "inout"), 0))
		out[at + PK_MOOD] = float(POSE_MOODS.find(StringName(str(key.get("mood", "")))) + 1)
	return out


## True for the carriers that read a payload of their own, as a trigger does (a rain; a familiar
## casts only what its triggers give it, rules R4 F3).
func carries_payload() -> bool:
	return motion == Motion.RAIN


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"base_damage": Vector2(1, 200),
		"mana_cost": Vector2(0.0, 100.0),
		"cooldown": Vector2(0.05, 10.0),
		"speed": Vector2(0.0, 2000.0),
		"lifetime": Vector2(0.05, 20.0),
		"radius": Vector2(1.0, 64.0),
		"shots": Vector2(1, 24),
		"spread": Vector2(0.0, 360.0),
		"motion": Vector2(0, Motion.size() - 1),
		"pierce": Vector2(0, 16),
		"orbit_radius": Vector2(0.0, 256.0),
		"ray_length": Vector2(0.0, 1024.0),
		"arc": Vector2(0.0, 360.0),
		"wind_up": Vector2(0.0, 2.0),
		"knockback": Vector2(0.0, 2000.0),
	})
	return limits
