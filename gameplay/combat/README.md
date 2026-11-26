# Combat

## Purpose

Damage pipeline, hit and hurt boxes, knockback, status effects, and applying element reactions. Projectiles come from `core/projectiles`; this area decides what a hit does. Reactions are content data (`content/spells/reactions.tres`).

## Contract

- **Public entry script:** `gameplay/combat/combat.gd`, the autoload `Combat`. Nothing else in the folder is public. Every shot's hit is described by `Spells.hit_profile(tag)` (no profile: no effect). `Combat.hit(caster, target, amount, direction, strength, kind)` is the pipeline for hits not from a spell.
- **One body model by actor id:** every hurtable body is one row of packed arrays sized `Actors.ACTORS`, indexed by its actor id; a body with no id gets one Combat opens in the actor table (enemies' team) and closes again.
  - *The actor API:* `register_actor(node, health, radius, contact_damage, offset, half) -> id`, `unregister_actor(actor)`; `actor_of(node)`, `is_registered`, `actor_count`, `health_of`, `knockback_of`; `apply_status(caster, actor, id, duration, strength)`, `status_left`, `has_status`, `chill_stacks`; `give_shield(actor, charges, seconds, tag)`, `give_barrier(actor, charges, seconds, tag)`, `shield`; `pull(caster, position, radius, strength, foes_only, to)`; `downed_note_of(actor)`; `home_actor_of(seat)`; `pace(node)`/`pace_of(actor)`, `consume_knockback(node, delta)`, `own_pace(node, id)`, `own_knockback(node, id, delta)`; `step(delta)`.
  - A parameter named `actor` takes the id or the node; attackers (`caster`) are actor ids, `NO_PLAYER` for none. Never assume an actor id is a seat.
  - *Health:* a kit Actor's is its Health component; a `gameplay/player` player keeps its own; other bodies' is in their row.
  - *Deaths:* a body at 0 sends `kill_landed` (a spell's own hit only) and `enemy_died` (every foe of the players, `Actors.is_foe`), and is freed.
- **Combat never moves a body:** whoever moves it adds `consume_knockback` to its own velocity.
- **The one rules, the same on every actor:** gust (harder shove, an armed slam), static (any hit but a burn tick discharges to other teams within `STATIC_RANGE`; always spent; starts nothing more), hex (extra damage and a pull), pull (every actor in the circle; replaces the push), barriers (any actor; a Barrier card's never stops the spell that gave it and sets off no `on block`; burn ticks pass), several elements act in turn, burn ticks are quiet (no event unless it kills; not a hit: no hex bonus, barrier, static or `actor_hurt`), contact (once per `CONTACT_COOLDOWN` per victim), soak (no burn, puts burn out, boosts heals), mend/heals (heal whatever is hit, any team, and do nothing else). Self-harm is always on. A down actor takes no status and loses what it had.
- **Actor stats** (the body's `Stats`, gameplay/actor): a spell hit's damage, slam and burn are × the caster's `power` only while `Spells.cast_by_open` holds (`_power_of`); contact, plain hits, reactions and heals are not scaled. Shoves ÷ `mass`; statuses last × (1 − resist) (`_resist`).
- **Plow's carries:** a hit on a carried body arms a pin (`HitProfile.pin`) and keeps its push until `carry_ended`; a barrier that takes a carried hit whole lets go (`Plow.drop`).
- **Hit-stop is a rule of the game** (`hit_stop.gd`, `HitStop`): hits, kills, reactions, downs, parries, impacts, ends and `cue_shown` hold bodies (`Actors.hold`) and shots (`Projectiles.freeze_shot`) as their cue says; `stop_game` uses `Sim.hold`. The same with or without Feel. Cast, shown and wind cues hold nothing.
- **A slowed actor winds up slower:** after statuses count down, `Spells.hold_winds(actor id, delta × (1 − pace))`, here, not in the body's step.
- **Hit kinds:** `KIND_SHOT`, `KIND_RAY`, `KIND_BURST`, `KIND_REACTION`, `KIND_STATUS`, `KIND_HEAL`, `KIND_FLOOR`; `HitProfile.kind`. `hit_landed` comes just before `damage_dealt`. Area hits are `projectile_hit`s of their carrier, one per body; Combat has no area hit of its own. Which shots can reach a body is `core/projectiles`' rule.
- **The shot:** combat names the `shot` of the hit it deals (-1 for none) in `hit_landed`, `kill_landed`, `reaction_landed`, `reaction_triggered`, `enemy_died`.
- **No per-hit allocation:** reaction lookup is allocation-free (`ReactionTable.in_order`, `_status_bits`).
- **Dependency direction:** `core` ← `gameplay` ← `content`. Uses `core/`, the registry and the actor kit's public components (Health, Stats). Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

### Statuses

burn, chill, gust, hex, static, soak (three chills make `freeze`); `pace` is 0 when frozen. **Every status is a row of one table:** two packed arrays, `_status_left` and `_status_power`, `STATUS_COUNT` entries a body at `row * STATUS_COUNT + ST_*`; apply, extend, spread, remove, count down, carry and clear are written once. A new plain status: its `StringName`, `ST_*`, entries in `STATUSES` and `STATUS_AT`, its row in each table (`STATUS_APPLIED`, `STATUS_STRENGTH_PER_POWER`), what it does in `_hit`/`_apply_spell`, and its name in `REACTING_STATUSES` and the validator's `KNOWN_STATUSES`.

### Reactions

A spell hit of element B on a body with status A runs the row (A, B) of `content/spells/reactions.tres` instead of B's status, after the damage and only if the body lived. Effects, each implemented once: `BURST`, `CONSUME`, `EXTEND` (no cap), `SPREAD`, `REMOVE`, `FREEZE`, `CONDUCT`. `reaction_triggered` is sent first. Reaction damage sets off no more reactions; a body reacts at most once per `REACTION_WAIT`; players react from the same table (`_react_wizard`). A new element is new rows; `combat.gd` changes only for a new effect kind.

### Events

`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md).

- Sends: `enemy_died`, `damage_dealt`, `status_applied`, `reaction_triggered`, `discharge_arc`, `hit_landed`, `heal_dealt`, `kill_landed`, `reaction_landed`, `reaction_struck`, `actor_hurt`, `shield_blocked`, `barrier_changed(actor, charges, seconds, tag, way, radius)`, `cue_shown` (`SHIELD_BLOCK_CUE`, `PULL_CUE`).
- Listens to: `projectile_hit`, `wizard_shield_requested`, `pull_requested`, `carry_ended`, `health_gift_requested`, `crumble_requested`, `floor_strike_requested`, `player_downed`, `player_revived`.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/combat/combat.gd`; `tests/gameplay/combat/test_combat.gd` shows how to test it (hits as `projectile_hit` on a test bus, time with `Combat.step(delta)`), `test_combat_actors.gd` the actor API on kit actors.

Tests (`tests/gameplay/combat/`): `test_combat.gd`, `test_combat_actors.gd`, `test_combat_kit.gd`, `test_combat_statuses.gd` (every table has a row for every status), `test_combat_reactions.gd` (every mix of statuses), `test_combat_crowd.gd`, `test_combat_crumble.gd`, `test_combat_enemy_spells.gd`, `test_hit_stop.gd` (every card), `test_hit_room_oracle.gd`; `tests/gameplay/actor/test_actor_stats.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

One step of the damage pipeline per PR, reactions read from data, no allocation per hit. Same for any player index and any enemy? Within the frame budget with 1,000+ projectiles? Keeps the dependency direction?

History and reasons: [docs/history/gameplay-combat-README.md](../../docs/history/gameplay-combat-README.md).
