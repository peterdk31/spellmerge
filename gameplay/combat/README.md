# Combat

## Purpose

Damage pipeline, hit and hurt boxes, knockback, status effects, and applying element reactions.

**Built in M1. Opens for PRs in M4** (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Element reactions are content data (`content/spells/reactions.tres`); this area applies them but holds no reaction list. Projectiles come from `core/projectiles`.

## Contract

- **Public entry script:** `gameplay/combat/combat.gd`. Other code uses only this script and the events below; nothing else in the folder is public. The script arrives when the area is built (M1).
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and reads content data through the registry. `core/` never depends on it, and content never reaches into it.
- **Areas never call each other directly.** They talk through `core/events`; direct calls only in the documented directions. Events sent: `damage_dealt`, `enemy_died`, `status_applied`. Names are provisional until the event bus is built in M1.
- **Depends on:** projectile hits from `core/projectiles`; reaction data from the registry.
- Every system takes a player index 0–3. Nothing assumes a single player.
- Performance: no per-frame allocations; use the pools and the projectile manager from `core/`; respect the particle limits.

## Allowed files

`.gd`, `.tres`, `.tscn`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only (types on every variable, parameter and return); no banned APIs. Tests mirror the tree in `tests/gameplay/combat/`.

## Steps

1. Pick an issue labelled `now` in this area (only once the area is open) and comment `/claim`.
2. Read this contract and the events above; make one focused change.
3. Add or update tests in `tests/gameplay/combat/`.
4. Run the checks below, then open a PR using the template. For gameplay changes, add a short GIF or video.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

Besides the standard criteria:

- Is damage deterministic and easy to follow? Does it stay within the projectile and per-frame allocation budgets at 1,000+ projectiles?
- Does it keep to the dependency direction, without calling another area directly?
