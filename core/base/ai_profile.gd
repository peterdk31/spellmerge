class_name AIProfile
extends Resource
## How an AI plays its staffs (docs/milestones/M2-enemy-ai.md, "The profile"): numbers only, the
## same for an enemy, a boss phase or a bot. Shared presets are files in
## `content/enemies/profiles/`; an enemy names one or has its own. It has no `id`, so the registry
## does not list it as an enemy.

## A short name for the arena's AI view and the tests.
@export var name: String = "default"
## 0-1: how far inside its reach it fights, and how readily it closes in.
@export_range(0.0, 1.0) var aggression: float = 0.5
## 0-1: when it evades or guards (its health, being crowded, shots coming).
@export_range(0.0, 1.0) var caution: float = 0.5
## 0-1: how exactly it aims (1: no error).
@export_range(0.0, 1.0) var accuracy: float = 0.85
## 0-1: how far it aims ahead of a moving target (1: where a shot meets it).
@export_range(0.0, 1.0) var lead: float = 0.5
## Seconds between its decisions; also how late it notices a shot.
@export_range(0.05, 2.0) var reaction: float = 0.3
## 0-1: how well it dodges shots (0: never, and it never looks).
@export_range(0.0, 1.0) var dodge: float = 0.5
## Times every telegraph (a windup lasts longer for a more dangerous cast in any case).
@export_range(0.25, 4.0) var windup_scale: float = 1.0
## Times the rest after each cast (0: none, it goes on at once).
@export_range(0.0, 4.0) var rest_scale: float = 1.0
## 0-1: how it presses on in a fight, as a person does: where an enemy stands (planning a cast,
## winding up, channelling, resting) it walks toward its target at this share of its speed, and it
## steps back only from a target nearer than its band's near edge × (1 - press_on), so at 1 it
## never does. An aimed cast is wanted beyond its band too, more the higher it is. 0: an enemy,
## which stands to cast and keeps its range.
@export_range(0.0, 1.0) var press_on: float = 0.0
## Degrees a second a held cast turns after its target (0: the aim stays locked).
@export_range(0.0, 720.0) var track_speed: float = 0.0
## The longest it holds a cast (seconds).
@export_range(0.0, 10.0) var channel_max: float = 2.0
## 0-1: the bonus for the behaviour it is running now (no flicker; high is decisive).
@export_range(0.0, 1.0) var commitment: float = 0.3
## 0-1: how often it takes the second-best choice or dodges late (seeded per enemy).
@export_range(0.0, 1.0) var randomness: float = 0.15
## 0-1: how much it staggers fire with its team, spreads round a target and calls attacks.
@export_range(0.0, 1.0) var teamwork: float = 0.5

## The profile an actor with no profile of its own plays by.
static var _fallback: AIProfile = null


## The shared default (every number as declared above).
static func fallback() -> AIProfile:
	if _fallback == null:
		_fallback = AIProfile.new()
	return _fallback
