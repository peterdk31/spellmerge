class_name EnemyFire
extends RefCounted
## The "Enemy fire" setting (owner decision 3, 2026-10-27; staffs F10): whether an enemy's spells
## also hit other enemies. Off by default: a crowd of casters never thins itself, so every hit a
## wizard takes, and every enemy that falls, is the wizards' doing. Its default lives in core, so
## the pause menu that sets it (hud) and the AI that applies it (gameplay) read the same one and
## neither reads the other. Never on an enemy's own body or its own shots (core/projectiles).

const DEFAULT: bool = false
