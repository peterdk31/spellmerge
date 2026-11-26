# Field: a carrier whose cards are its meaning

**Status (2026-11-26): the owner decided to build it** (Part 2 of [foundations.md](foundations.md), "fields", which the order there calls step 3; builds 5 to 8), with the owner's answer to open point 4 (2026-11-25): **a field serves every shot, enemies' too: one rule.** It is `linger · field` that now stands for the pane the owner passed on ("shots through it take its cards"), with no code of its own.

## What the players see

**Field** (`content/spells/carriers/field/`, carrier `field`, `core/spells/carriers/field.gd`): "A circle ahead. Shots through it take its cards."

- It is **a circle on the floor a step ahead** (`ray_length`, short of a wall), there for its life. It hits nothing and stops nothing.
- **Every shot that comes into it takes its cards**: a fire field sets every bolt through it burning, a bounce field makes them come off the walls beyond, a homing field turns them toward the nearest foe, a linger field holds them until it ends. **Anyone's shots**: a teammate's, an enemy's, the caster's own (the owner's answer 4).
- **A card's numbers shape the field; a card's behaviour or element is what it gives.** Bigger widens it, Reach puts it further, Slow keeps it longer; Faster does nothing on it (it does not travel, and it changes no shot's speed).
- **The look:** a ring of light on the floor, 64 px across at 2x detail, drawn in its infusions' colours, with a slow inner shimmer; it opens over 4 frames and closes over 4 (docs/STYLE.md, "Smooth": whole pixels, no fades). A shot that takes it flashes where it goes in (`field_through`). It gives a soft light (it is a light, as a shot is).

## The carrier: its traits

`STAYS | LASTS | REACHES | SHOTS | SPREAD | CASTS_FROM_SHOT | GIVES`

- It is a **still shot of the projectile manager** (as a rune and a pool are), placed `ray_length` ahead, that hits nothing (no hit layers) and is never spent. So its life, Slow, Hold, Split (more fields, fanned as a portal's exits), Orbit, Skyfall, its triggers and its end are the shots' own, with no new code.
- **`GIVES` (new flag):** "Does it give its cards to the shots that come into it (a field)?" A behaviour a field gives names it in its need (`ModifierBase.RULES`), so `Carrier.works` and the builder answer yes on a field without a case for it: Homing, Linger, Bounce, Ghost, Spiral, Return, Sticky, Shield and Deflect.
- `takes_infusion` and `takes_element` as a portal's: what comes into it takes its element and status; Mend, which has no status, does nothing on it (only a blast carries it).
- **Its own shot wears none of the cards it gives** (`Carrier.gives_cards`): `Spells._travel_shots` puts only its Growth on it, so a homing field does not creep and a shield field is no ward itself.

## What each card does on it

| Card on the field | What it does |
| --- | --- |
| an infusion | every shot that comes in takes its element and status (as through a portal: `CarrierKit.infuse_shot`; the shot then hits alone) |
| Homing | a shot that comes in homes (its own homing, if any, stays) |
| Linger | **the dam:** a shot that comes in stops where it is (a local stop, its life waiting) until the field ends; a field that ends early (switched off, its caster gone) lets its shots go then |
| Bounce, Ghost, Spiral, Return, Sticky | the shot gains it (at least the field's count: a bounce field of 2 leaves a shot with 3 of its own at 3) |
| Shield, Deflect | the shot becomes a ward (at least the field's charges), or turns others' shots |
| Growth | **widens the field** (as it widens a portal's gates), not the shots |
| Bigger, Reach, Slow, Hold | its size, how far ahead, how long, held open while the staff is held |
| Split, Scatter, Mirror, Nova | more fields, as for every carrier that fires `shots` |
| Magnet, Zap | the field pulls bodies to it, or zaps near it (as on every carrier that stays) |
| Timer, On Near, On Recast, On Expire | fire from its middle, as from a rune |
| Blast | goes off where it ends (as a portal's at its gates) and carries its infusion |
| Faster and every speed curve, Pierce, Chain, Heavy, Siphon, Relay, Possess, Pull, Barrier, Plow, the damage numbers, On Hit, On Kill, On Reaction, On Block | **nothing** (marked in the builder, `test_card_rules`): it hits nothing, does not travel, and a field does not rebuild a shot (a shot's damage and count are its build's) |

## How a shot takes a field

- **Once each time it comes in:** the step its middle goes from outside the field's circle to inside it, or through it (a shot faster than the field is wide in a step, an atom). A shot that stays inside takes nothing more; one that leaves and comes back takes it again (an orbit through it, a bounce back into it).
- **What it takes is "at least the field's"**, so taking the same field again changes nothing (an element it has is not added twice, a count is the larger of the two, a flag is on). Two fields of different cards stack: a fire field then a homing field gives a burning shot that homes.
- **What is seen:** every live shot that moved this step (straight, circling, spiralling, homing, returning), but a field's own, a stopped one (a local stop, a lingering shot's hold, a stuck one) and a falling one in the air. A rune, a pool and a wall stand still, so they never come in.
- **A wall in the same step:** a shot that comes into a field and meets a wall in one step ends at the wall first (the manager's step runs before the field pass), so a ghost or bounce field right against a wall does not save it.
- **A field's own payloads** (a Timer's bolts, from its middle) are born inside it, so they do not take it.
- **Not in this build:** a beam's stretch past a field (as through a portal: later), and bodies (the floor's and the Pool's).

## Numbers

| | |
| --- | --- |
| radius | 32 (64 px at 2x: a cell's width either way of its middle) |
| `ray_length` | 72 (its middle, ahead of the hand) |
| lifetime | 5 s |
| mana | 18; wind-down 0.5 s; complexity 3 |
| damage | 0 (it hits nothing) |

## The cost, and where it runs

A field is a pass of the projectile manager over every shot against every field (`ProjectileManager.shots_into_fields`), run by the field carrier's step once per tick, after the manager's step; it hands back the pairs (a shot, the field it came into) in slot order, then field order, and the carrier gives the cards (a few setters, only on the step a shot comes in). The pass is the hot part: **the native kernel runs it** (`ShotKernel.field_pass`), the GDScript stays the reference and the fallback, and `tests/core/test_native_kernel.gd` compares the two to the bit (pairs and order) on straight, circling, homing and falling shots through moving and growing fields. Nothing runs, and nothing is asked of the kernel, while no field is open.

`tests/core/test_field_budget.gd` holds the cost: 2048 shots through 16 fields a step, natively within its budget (printed as `BUDGET:` lines; the GDScript fallback's is printed, not held).

## Simulation

The field carrier's rows (each field's slot and birth, each held shot's slot, birth and field) are state, hashed and in snapshots with no code of their own; it rolls no dice, reads no clock but `delta`, and does no trigonometry (a circle test is squares). The manager's pass reads its arrays and writes only its hand-back (`field_shots`, `field_shot_fields`, scratch, DERIVED). `test_determinism` and `test_content_determinism` play the card and its combos twice and through a snapshot.

## Tests

- `content/spells/carriers/field/test_field.gd`: the card; a shot takes its infusion once and not again inside; a shot that leaves and comes back takes it again; an enemy's shot through a player's field; the dam holds and lets go at the field's end, and early when it is switched off; a field's own payload does not take it; Growth widens the field; a shield field is no ward itself.
- `tests/core/test_card_rules.gd`: every card on it (a teammate sends a shot through it, as through a portal: `GIVES` carriers get the courier).
- `tests/core/test_native_kernel.gd`, `tests/core/test_field_budget.gd`: the pass, its mirror, its cost.
- The combos (`content/spells/carriers/field/combos/`), the builds:
  - **5, the gun line:** a fire field, a teammate's frost bolts through it: the imp beyond burns (and Thaw where frost meets fire).
  - **6, the ricochet gate:** a bounce field at a corridor's mouth; plain bolts through it come off the wall beyond into an imp behind cover.
  - **7, the dam:** a linger field; a volley piles up in it and leaves when it ends.
  - **8, the bend:** a homing field between the caster and a pillar; straight bolts past the pillar turn to the imp behind it.
  - **the enemy's shot:** an enemy bolt through the caster's frost field chills the caster.
- Screenshots (`tests/screenshots/`): a field changing shots, an enemy's shot through a player's field.

## The owner's answers (2026-11-26)

1. **Growth grows the field itself** (as a portal's gates), not the shots.
2. **Blast and Split work on a field** (a blast where it ends, more fields), as on a portal.
3. **A field's own payloads do not take it** (born inside, they never come in).
