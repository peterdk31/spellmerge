# Combat

## Purpose

Damage pipeline, hit and hurt boxes, knockback, status effects, and applying element reactions.

Built in M1 (see "Gameplay sub-areas" in docs/PLAN.md).

Element reactions are content data, so new ones are added without touching this code. Projectiles themselves come from `core/projectiles`; this area decides what a hit does.

## Contract

- **Public entry script:** `gameplay/combat/combat.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. It is the autoload `Combat`. A spell's hits are described by `Spells.hit_profile(tag)`; other spawners (the enemy AI) tell it what a shot does with `Combat.set_hit_profile(tag, damage, knockback)`; enemies register with `Combat.register_enemy(node, health, hurt_radius, contact_damage)` and wizards with `Combat.register_player(index, node, radius)` (which also makes the wizard a projectile target on `LAYER_PLAYER`, so enemy shots can hit it). `Combat.hit(player, target, amount, direction, strength)` is the pipeline for hits that do not come from a projectile.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `enemy_died`, `damage_dealt`, `status_applied`, and from M2 part 8 `reaction_triggered`; from staffs B3 also `hit_landed`, `heal_dealt`, `kill_landed`, `reaction_landed`, `wizard_hurt` and `shield_blocked`.
  - Statuses (M2 part 7): `Combat.apply_status(player, enemy, id, duration, strength)` for burn, chill, shock, hex and static (three chills make `freeze`); `status_left`, `has_status`, `chill_stacks`, and `speed_factor(enemy)` for whoever moves an enemy (multiply walking and attack timers by it: 0 when frozen). A spell's hit comes with `Spells.hit_profile(tag)` (damage, knockback, status); other shots use `set_hit_profile`.
  - Static (#243): lightning puts `static` on an enemy (strength is the percent of a hit's damage that discharges). When a player's spell hits an enemy that is static, the hit discharges: every other static enemy within `STATIC_RANGE` takes that share of the damage (at least 1) as plain `hit`s for the same player, and `reaction_triggered(player, &"discharge", position)` and `discharge_arc(player, from, to)` (the struck enemy's place and the zapped one's) are sent for each. It is one step, not a second jump: the discharge starts no reaction, no status and no further discharge (`_discharging` also refuses one started from inside another). The struck enemy is spent when it discharged; the ones zapped stay charged. A hit that names no player, or a shot that is not a spell, discharges nothing. A new status is the `StringName`, the two packed arrays, and a line in each `match` of `combat.gd`; `REACTING_STATUSES` and the validator's `KNOWN_STATUSES` list it, so reaction rows can start from it.
  - Reactions (M2 part 8): when a spell's hit of element B lands on an enemy that has status A, the row for (A, B) in `content/spells/reactions.tres` runs instead of B's own status, after the hit's damage and only if the enemy lived. Four effect kinds, each implemented once: `BURST` (damage in a circle, with an optional pull), `CONSUME` (the status for bonus damage, doubled on a frozen enemy), `EXTEND` (a longer or stronger status; chill becomes a freeze) and `SPREAD` (the status to neighbours). It sends `reaction_triggered(player, reaction_id, position)` first. Reaction damage sets off no more reactions. An enemy reacts at most once per `REACTION_WAIT` (0.5 s), and `EXTEND` is capped (`MAX_FREEZE`, `MAX_EXTENDED_TIME`, `MAX_EXTENDED_PERCENT`). A new element is new rows in the table; `combat` changes only for a new effect kind.
  - **The staffs kit (B3, [M2-staffs.md](../../docs/milestones/M2-staffs.md), "Self-harm and hits"):**
    - *Hit kinds:* every hit has a kind (`KIND_SHOT`, `KIND_RAY`, `KIND_BURST`, `KIND_REACTION`, `KIND_STATUS`, and `KIND_HEAL` for a heal). A spell's kind is `HitProfile.kind`; an area hit is `burst`; a reaction's damage is `reaction`; burn ticks are `status`. `hit_landed(player, target, amount, position, kind)` comes just before `damage_dealt` (Feel reads it). `Combat.hit(..., kind)` takes it as its last argument.
    - *Self-harm is always on:* a spell's hit on any wizard goes through the same pipeline as on an enemy: damage (`damage_dealt`, then `wizard_hurt(index, amount, position, tag, kind)`), a push (`consume_wizard_knockback(index, delta)`, for whoever moves the wizard), and the hit's status. Which shots can reach a wizard is `core/projectiles`' rule (the caster once out of their hitbox, a teammate only with friendly fire). A wizard's hurt box rules stay the wizard's own (`is_invulnerable`, `is_downed`).
    - *Statuses on wizards:* `apply_wizard_status`, `wizard_status_left`, `wizard_speed_factor(index)` (0 when frozen; `gameplay/player` multiplies its pace by it, B4). Burn hurts over time (kind `status`, not stopped by a barrier), chill and freeze slow, hex adds damage, a shock adds its share to the next hit and is spent, and a static wizard discharges that share of the next hit to the enemies near. A downed wizard takes none and loses what it had.
    - *Barriers:* `wizard_shield_requested(player, charges, seconds, tag)` (or `give_wizard_shield`) gives the wizard blocked hits; each blocked hit sends `shield_blocked(index, position, tag)` and does no damage, status or push. A burn tick is not a hit and passes.
    - *Area hits:* `area_hit_requested(player, position, radius, tag)` hits every enemy and every wizard in the circle with the profile of `tag`, kind `burst`. The caster is always inside; a teammate only with friendly fire (a heal reaches everyone). Area hits that start area hits stop at `AREA_DEPTH`.
    - *Several elements:* a profile's `element_ids` act in order on one hit; the first reacts with what the target had, each later one with what the ones before left, or puts its own status on (`later_status_*`). Reactions are one per hit on a target, but the elements of one hit chain: `fire · frost · bolt` melts, then the bolt reacts with what is left. On a wizard every element's status goes on in order and nothing reacts. A burn tick on a wizard is not a hit: it takes no hex bonus and spends no shock or static.
    - *Heals:* a profile with `heal > 0` gives a wizard that health instead of damage (`heal_dealt`; `gameplay/player` adds it, up to its maximum, nothing to a downed wizard). An enemy takes the profile's `damage`.
    - *Pulls and slams:* `pull_requested` / `Combat.pull(player, position, radius, strength)` sets the knockback velocity of every enemy in the circle toward the point (it replaces the push, so a pull every step does not pile speed up). A heavy profile (`slam > 0`) arms the enemy it pushes: knocked at least `SLAM_MIN_SPEED` into a wall it takes `slam` once (sent as a `reaction` hit, so it gets the reaction look in Feel).
    - *For cards:* `kill_landed(player, target, position, tag)` for a kill by a spell's own hit (not by burn, a slam, a shock jump, a static discharge or a reaction's damage), `reaction_landed(player, reaction_id, target, position, tag)`, `wizard_hurt`, `shield_blocked`.
    - *"Downed by your own ...":* `downed_note(index)` gives the words ("downed by your own Blast", "downed by player 2's Frost Nova", or empty for an enemy); Feel shows them when `player_downed` arrives. `HitProfile.source_name` names the spell; empty uses the kind's word.
  - Listens to: `projectile_hit` (from `core/projectiles`), `area_hit_requested`, `wizard_shield_requested`, `pull_requested`, `player_downed` and `player_revived`.
  - (Earlier:) listens to `projectile_hit` (from `core/projectiles`). For a tag that is a player's spell it asks `Spells.hit_profile(tag)`; for any other tag (an enemy's shot) it uses the table of `set_hit_profile`.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/combat/combat.gd` is the example, and `tests/gameplay/combat/test_combat.gd` shows how to test it (damage, knockback, death and contact hits, with several players). Hits arrive as `projectile_hit` events on a test bus; time moves with `Combat.step(delta)`. Combat never moves enemies: whoever moves an enemy adds `Combat.consume_knockback_step(enemy, delta)` to its own velocity each physics frame.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here changes one step of the damage pipeline (a status effect, knockback, a hit or hurt box rule), reads reactions from data, and does not allocate per hit. Besides the general review:

- Is damage applied the same for any player index and any enemy? Does it stay within the frame budget with 1,000+ projectiles?
- Does it keep to the dependency direction, without calling another area directly?
