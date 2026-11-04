class_name ShotTails
extends RefCounted
## The "Tails" setting (docs/milestones/spell-spectacle-2.md, S5: "do shots need tails?"): whether
## flying shots draw their tails (the projectile manager's `tails_enabled`). A dev switch for the
## owner to play the sandbox and a horde fight with them off; the owner then picks what the game
## keeps. Its numbers live in core, so the pause menu that sets it (hud) and the projectile manager
## that uses it (core/projectiles) read the same ones.

## On until the owner picks (today's look: the long cooling tails, 2026-10-27).
const DEFAULT: bool = true
