class_name TaillessMotes
extends RefCounted
## The "Tailless motes" dev setting (docs/milestones/spell-spectacle-2.md, S5, step 4: the owner
## plays "no tails, more motes"): the spark pool the shots' births share while the tails are off
## (the projectile manager's `tailless_particle_cap`), and the rows the motes may write a frame to
## draw them (`Motes.frame_rows`), so a bigger pool shows more motes instead of being cut by the
## frame's rows. A dev setting to judge the look: above the default it costs CPU (DECISIONS,
## 2026-11-04, "Do shots need tails?": a pool of 4,096 cost as much CPU as tails on). Its numbers
## live in core, so the pause menu that sets it (hud), the projectile manager (core/projectiles)
## and feel (gameplay) read the same ones and none reads another.

## The pools the slider steps through, smallest first.
const STOPS: Array[int] = [2048, 4096, 8192]
## The default pool (the projectile manager's TAILLESS_PARTICLE_CAP, S5's measured pick).
const DEFAULT: int = 2048
## The rows a frame the motes write at the default pool (`Motes.FRAME_ROWS`), and how many shot
## births a row more of the frame carries per pool step: at 3,000 shots the default pool gives
## about 145 births a frame (S5's figures), so a pool of n asks about n / 14 rows of births.
const BASE_ROWS: int = 256
const POOL_PER_ROW: int = 16


## The index in STOPS of the stop nearest `pool` (the lower one on a tie).
static func index_of(pool: int) -> int:
	return SettingStops.nearest(STOPS, float(pool))


## `pool` snapped to the nearest stop.
static func snap(pool: int) -> int:
	return STOPS[index_of(pool)]


## The menu's word for `pool`.
static func word_of(pool: int) -> String:
	return str(snap(pool))


## The rows a frame the motes may write for `pool`: BASE_ROWS at the default, one more for every
## POOL_PER_ROW of pool above it, so the births the bigger pool gives are written.
static func frame_rows_of(pool: int) -> int:
	return BASE_ROWS + maxi(pool - DEFAULT, 0) / POOL_PER_ROW
