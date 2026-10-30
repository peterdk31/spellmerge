# Combat

## Purpose

Damage pipeline, hit and hurt boxes, knockback, status effects, and applying element reactions.

Built in M1 (see "Gameplay sub-areas" in docs/PLAN.md).

Element reactions are content data, so new ones are added without touching this code. Projectiles themselves come from `core/projectiles`; this area decides what a hit does.

## Contract

- **Public entry script:** `gameplay/combat/combat.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. It is the autoload `Combat`. Every shot's hit is described by `Spells.hit_profile(tag)` (a shot without one does nothing). `Combat.hit(caster, target, amount, direction, strength, kind)` is the pipeline for hits that do not come from a spell.
- **One body model by actor id (actors G5, [M2-actors.md](../../docs/milestones/M2-actors.md), "Combat: one rule"):** every body that can be hurt is one row of packed arrays sized `Actors.ACTORS`, indexed by its actor id; finding a row is an array read (by id) or one dictionary read (by node), freeing one is O(1). A body's id is its own (a kit Actor's `id`; a plain test body's `actor_id` or `caster`), or for a body with none one Combat opens in the actor table (the enemies' team) and closes again, so every body has an owner (the projectile manager's target owner).
  - *The actor API:* `register_actor(node, health, radius, contact_damage, offset) -> id` (the kit's Hurtbox calls it) and `unregister_actor(actor)`; `actor_of(node)`, `is_registered`, `actor_count`, `health_of`, `knockback_of`; `apply_status(caster, actor, id, duration, strength)`, `status_left`, `has_status`, `chill_stacks`; `give_shield(actor, charges, seconds, tag)`, `shield`; `pull(caster, position, radius, strength)`; `downed_note_of(actor)`; `pace(node)` / `pace_of(actor)` and `consume_knockback(node, delta)` for whoever moves a body, and `own_pace(node, id)` / `own_knockback(node, id, delta)`, the same answers asked by a kit actor's own id without a node lookup (its row is its id; the kit's Mover and the AI ask every step). **Parameters:** a parameter named `actor` takes either the actor id or the node; the calls a body makes about itself every step take its node (and its id). Attackers (`caster`) are actor ids, `NO_PLAYER` for none.
  - *Health:* a kit Actor's is its Health component (`take(amount, killer)`, `heal`; at 0 `die(killer)`, unless `downable`: something downs it instead). A player of `gameplay/player` (registered by seat, until G7) keeps its own: `damage_dealt` and `heal_dealt` reach it, and a quiet hit goes to its `take_damage`, so its HUD hears every change. Any other body's health is kept in its row (until G6).
  - *Deaths:* a body at 0 sends `kill_landed` (a spell's own hit only) and `enemy_died` (every body not on the players' team; flow counts the wave by it), and is freed.
  - `home_actor_of(seat)`: the registered actor whose home controller has that seat (the player body it plays, also while the seat drives another actor), for Feel's downed note. The seat-keyed wrappers of G5 are gone (actors G8).
- **The one rules (owner, 2026-10-28), the same on every actor:** *shock*: the next spell hit also jumps to the nearest other actor of the victim's team (`SHOCK_JUMP_RANGE`); *static*: any hit but a burn tick sets it off: the victim's actors of other teams within `STATIC_RANGE` take its share (at least 1) as `reaction` hits credited to the charged actor, with `reaction_triggered(actor, &"discharge", ...)` and `discharge_arc` for each; the charge is always spent, the discharge starts nothing more, and a hit that discharged puts no first status on; *hex*: extra damage, and a spell hit pulls the victim toward it; *pull*: every actor in the circle; *barriers*: any actor (`wizard_shield_requested` gives the caster's own actor one; a burn tick passes); *several elements*: every element acts in turn, later statuses too; *burn ticks* are quiet for everyone (no event unless the tick kills); *contact*: an actor with contact damage hurts each actor of another team whose hurt circle its own overlaps, once per `CONTACT_COOLDOWN` per victim, credited to the toucher; *mend*: a heal hit heals an actor of the caster's team and is a plain hit on the others.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `enemy_died`, `damage_dealt`, `status_applied`, `reaction_triggered`, `discharge_arc`, `hit_landed`, `heal_dealt`, `kill_landed`, `reaction_landed`, `actor_hurt` (the hurt actor's id, for every actor) and `shield_blocked` (the shielded actor's id).
  - Statuses (M2 part 7): `Combat.apply_status(caster, actor, id, duration, strength)` for burn, chill, shock, hex and static (three chills make `freeze`); `status_left`, `has_status`, `chill_stacks`, and `pace` for whoever moves a body (multiply walking and attack timers by it: 0 when frozen). A spell's hit comes with `Spells.hit_profile(tag)` (damage, knockback, status).
  - Static (#243): lightning puts `static` on (strength is the percent of a hit's damage that discharges; the rule is above). A new status is the `StringName`, the two packed arrays, and a line in each `match` of `combat.gd`; `REACTING_STATUSES` and the validator's `KNOWN_STATUSES` list it, so reaction rows can start from it.
  - Reactions (M2 part 8): when a spell's hit of element B lands on an enemy that has status A, the row for (A, B) in `content/spells/reactions.tres` runs instead of B's own status, after the hit's damage and only if the enemy lived. Four effect kinds, each implemented once: `BURST` (damage in a circle, with an optional pull), `CONSUME` (the status for bonus damage, doubled on a frozen enemy), `EXTEND` (a longer or stronger status; chill becomes a freeze) and `SPREAD` (the status to neighbours). It sends `reaction_triggered(caster, reaction_id, position)` first. Reaction damage sets off no more reactions. An enemy reacts at most once per `REACTION_WAIT` (0.5 s), and `EXTEND` is capped (`MAX_FREEZE`, `MAX_EXTENDED_TIME`, `MAX_EXTENDED_PERCENT`). A new element is new rows in the table; `combat` changes only for a new effect kind.
  - **The staffs kit (B3, [M2-staffs.md](../../docs/milestones/M2-staffs.md), "Self-harm and hits"):**
    - *Hit kinds:* every hit has a kind (`KIND_SHOT`, `KIND_RAY`, `KIND_BURST`, `KIND_REACTION`, `KIND_STATUS`, and `KIND_HEAL` for a heal). A spell's kind is `HitProfile.kind`; an area hit is `burst`; a reaction's damage is `reaction`; burn ticks are `status` (a tick on a player sends `hit_landed` and `damage_dealt` but not `actor_hurt`, and Feel gives it no self-hit ring); a player's contact hit counts as `shot`; a heal is `heal`. `hit_landed(caster, target, amount, position, kind)` comes just before `damage_dealt` (Feel reads it). `Combat.hit(..., kind)` takes it as its last argument.
    - *Self-harm is always on:* a spell's hit on any actor goes through the same pipeline: damage (`damage_dealt`, the hurt kit actor's own `Actor.damaged(by, amount)` right after it for its components, then `actor_hurt(actor, amount, position, tag, kind)` with the hurt actor's id), a push (`consume_knockback`), and the hit's status. Which shots can reach a body is `core/projectiles`' rule (every shot but the caster's own while it is still in its hitbox).
    - *Statuses on every actor:* the same rows and rules for players and enemies (actors G5); a down actor takes none and loses what it had. A burn tick is not a hit: no hex bonus, no barrier, no static, no `actor_hurt`.
    - *Barriers:* `wizard_shield_requested(caster, charges, seconds, tag)` (or `give_shield`) gives the caster's actor blocked hits, whoever it is; each blocked hit sends `shield_blocked(actor, position, tag)` and does no damage, status or push.
    - *Area hits:* a blast and the cards that land on a point are `projectile_hit`s of their carrier, one per body (core/spells strikes everything in the circle, the caster included, rules R4 F2); Combat has no area hit of its own.
    - *Several elements:* a profile's `element_ids` act in order on one hit; the first reacts with what the target had, each later one with what the ones before left, or puts its own status on (`later_status_*`). Reactions are one per hit on a target, but the elements of one hit chain: `fire · frost · bolt` melts, then the bolt reacts with what is left. On a player it is the same (staffs F6): players react from the same table to every spell, an enemy's, a teammate's or their own (`_react_wizard`: CONSUME hurts the player, BURST every player in the circle, EXTEND lengthens or freezes, SPREAD copies the status to the players near; a player waits `REACTION_WAIT` before reacting again), and `reaction_landed` names the caster's tag, so an enemy's `on reaction` fires too. A burn tick on a player is not a hit: it takes no hex bonus and spends no shock or static.
    - *Heals:* a profile with `heal > 0` heals an actor of the caster's team (`heal_dealt`; a player of `gameplay/player` adds it itself, a kit Actor's Health is healed by Combat; nothing to a down actor). An actor of another team takes the profile's `damage`.
    - *Pulls and slams:* `Combat.pull(caster, position, radius, strength, foes_only, to)` sets the push of every actor in the circle toward the point (with `to`, of every actor within `radius` of the line from `position` to `to`, toward its nearest point on it: a magnet beam, rules R4f); `pull_requested` (the Magnet card) does the same with `foes_only`, so the caster and its teammates are left alone and keep their push and slam (it replaces the push, so a pull every step does not pile speed up). A heavy profile (`slam > 0`) arms the actor it pushes: knocked at least `SLAM_MIN_SPEED` into a wall it takes `slam` once (sent as a `reaction` hit).
    - *For cards:* `kill_landed(caster, target, position, tag)` for a kill by a spell's own hit (not by burn, a slam, a shock jump, a static discharge or a reaction's damage), `reaction_landed(caster, reaction_id, target, position, tag)`, `actor_hurt`, `shield_blocked`.
    - *"Downed by your own ...":* `downed_note_of(actor)` gives the words ("downed by your own Blast", "downed by player 2's Frost Nova", or empty when no seat drives the actor who did it); Feel shows them when `player_downed` arrives (`home_actor_of(seat)`, then `downed_note_of`). `HitProfile.source_name` names the spell; empty uses the kind's word.
  - Listens to: `projectile_hit` (from `core/projectiles`), `wizard_shield_requested`, `pull_requested`, `player_downed` and `player_revived`.
  - (Earlier:) listens to `projectile_hit` (from `core/projectiles`). For every tag it asks `Spells.hit_profile(tag)` (an enemy's spell too); a tag with no profile does nothing.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/combat/combat.gd` is the example, and `tests/gameplay/combat/test_combat.gd` shows how to test it (damage, knockback, death and contact hits, with several players). Hits arrive as `projectile_hit` events on a test bus; time moves with `Combat.step(delta)`. Combat never moves a body: whoever moves it adds `Combat.consume_knockback(node, delta)` to its own velocity each physics frame. `test_combat_actors.gd` shows the actor API on kit actors.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here changes one step of the damage pipeline (a status effect, knockback, a hit or hurt box rule), reads reactions from data, and does not allocate per hit. Besides the general review:

- Is damage applied the same for any player index and any enemy? Does it stay within the frame budget with 1,000+ projectiles?
- Does it keep to the dependency direction, without calling another area directly?
