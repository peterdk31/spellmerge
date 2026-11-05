class_name TailMotes
extends RefCounted
## The "Tail motes" dev setting (docs/milestones/spell-spectacle-2.md, S5 step 4: tails as motes;
## the owner, 2026-11-05: "if only the motes could look more like a tail"): with the tails off,
## whether the shots lay their tails as motes, and in which of the tail kinds (`MoteKind.tail`,
## content/motes: A the first by id, B the second, C the third), so the owner can play each and
## pick. Off is the tailless look before (only the cards' motes). Its numbers live in core, so the
## pause menu that sets it (hud), the projectile manager (core/projectiles) and feel (gameplay)
## read the same ones and none reads another. It changes nothing while the tails are on.

## The picks the switch steps through: 0 Off, then the tail kinds in id order.
const WORDS: Array[String] = ["Off", "A", "B", "C"]
## The default: B, the second tail kind by id (`tail_streak`: short streaks along the way the
## shot flew, which read as one line; the pick of the sheet, tests/screenshots/shot_tail_motes.gd).
const DEFAULT: int = 2


## `pick` as one of the switch's (0 to WORDS' last).
static func snap(pick: int) -> int:
	return clampi(pick, 0, WORDS.size() - 1)


## The menu's word for `pick` ("Off", "A", ...).
static func word_of(pick: int) -> String:
	return WORDS[snap(pick)]


## Whether `pick` lays tails at all.
static func lays(pick: int) -> bool:
	return snap(pick) > 0
