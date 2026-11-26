# Field: a carrier that catches every shot and lets them go in one burst

**Status (2026-11-26): the owner decided to build it** (Part 2 of [foundations.md](foundations.md), "fields"; builds 5 to 8), and gave it its design the same day: "A circular field (vibrating edge) that sucks in every shot to its center, which then grows and grows based on how many shots are in. Then when it ends, it fires every shot out in one big burst in the opposite direction a shot has come in. No need to keep track of each shot's position, just the angles (rough), where shots have entered, so they can come out the opposite way." With the owner's answer to open point 4 (2026-11-25): **a field serves every shot, enemies' too: one rule.** It replaces the first design (a field that gave its cards to shots passing through), which was built and reworked before its PR.

## What the players see

**Field** (`content/spells/carriers/field/`, carrier `field`, `core/spells/carriers/field.gd`): "Catches every shot, then lets them all go at once."

- It is **a round field on the floor a step ahead** (`ray_length`, short of a wall), there for its life, its edge trembling. It hits nothing.
- **Every shot in it is caught**, wherever it came from: one that flies in, one cast from inside it, one split or spawned inside it, one it grows over (the owner, 2026-11-26: "It should capture all that hits it's area"). It is drawn in to its middle and held there, its life waiting. Anyone's shots: a teammate's, an enemy's, the caster's own (the owner's answer 4).
- **It grows with every shot it holds**, so a full field catches more.
- **When it ends it lets them all go in one burst** from its middle, each the way it was going when it came in: a shot that came in from the west going east leaves to the east, carrying on through. An enemy's bolt at you leaves at you.
- **What leaves it takes its cards**: a fire field's burst is fire, a homing field's burst homes, a bounce field's comes off the walls.
- **A card's numbers shape the field** (Bigger, Reach, Slow, Growth); **a card's behaviour or element is what the burst takes.**
- **The look:**
  - a ring of light on the floor in its infusions' colours, its edge trembling a pixel in and out in 4 stepped frames at 12 a second;
  - it opens in 4 frames and closes in 4 (docs/STYLE.md, "Smooth": whole pixels, no fades);
  - four marks inside it and a slow shimmer;
  - it grows with its shots and gives a soft light;
  - a shot caught flashes where it goes in (`field_through`) and is drawn in to the middle step by step;
  - the burst is a ring and rays going out (`field_burst`).

## The carrier: its traits

`STAYS | LASTS | REACHES | SHOTS | SPREAD | CASTS_FROM_SHOT | GIVES`

- It is a **still shot of the projectile manager** (as a rune and a pool are), placed `ray_length` ahead.
  - It hits nothing and is never spent. `set_field` gives it no hit layers, so no guard, shield or AI's threat test meets it either.
  - Its life, Slow, Hold, Split (more fields, fanned as a portal's exits), Orbit, Skyfall, its triggers and its end are the shots' own.
- **`GIVES` (new flag):** "Does it give its cards to the shots it lets go (a field)?" A behaviour a field gives names it in its need (`ModifierBase.RULES`), so `Carrier.works` and the builder answer yes on a field without a case for it: Homing, Linger, Bounce, Ghost, Spiral, Return, Sticky, Shield and Deflect.
- `takes_infusion` and `takes_element` are as a portal's: what leaves it takes its element and status. Mend, which has no status, does nothing on it (only a blast carries it).
- **Its own shot wears none of the cards it gives** (`Carrier.gives_cards`): `Spells._travel_shots` puts only its Growth on it.

## What each card does on it

| Card on the field | What it does |
| --- | --- |
| an infusion | every shot of the burst takes its element and status (`CarrierKit.infuse_shot`, as through a portal; the shot then hits alone) |
| Homing | the burst homes (a shot's own homing, if any, stays) |
| Bounce, Ghost, Spiral, Return, Sticky, Shield, Deflect | the shot gains it, at least the field's count (a shot with more of its own keeps its own) |
| Linger | the burst lingers: each shot stops half way through its life, as Linger does on any shot (holding is the field's own now) |
| Growth | **grows the field** over its life, on top of what its shots grow it (the owner, 2026-11-26) |
| Bigger, Reach, Slow, Hold | its size, how far ahead, how long it holds (the burst's moment), held open while the staff is held |
| Split, Scatter, Mirror, Nova | more fields, as for every carrier that fires `shots` (the owner, 2026-11-26) |
| Magnet, Zap | the field pulls bodies to it, or zaps near it, as on every carrier that stays |
| Timer, On Near, On Recast, On Expire | fire from its middle, as from a rune; On Expire with the burst |
| Blast | goes off where it ends, with the burst, carrying its infusion (the owner, 2026-11-26) |
| Faster and the speed curves, Pierce, Chain, Heavy, Siphon, Relay, Possess, Pull, Barrier, Plow, the damage numbers, On Hit, On Kill, On Reaction, On Block, On Wall | **nothing** (marked in the builder, `test_card_rules`): it hits nothing, does not travel, and a field does not rebuild a shot (a shot's damage and count are its build's) |

## How a shot is caught and let go

- **Caught:**
  - when: the first step its middle is inside the field's circle, wherever it came from (flown in, cast, split or spawned inside it, or the field grew over it), or went through it (a shot faster than the field is wide in a step, an atom). A wizard casts after the field's step, so a bolt cast inside a field is caught the next step, one step out of the hand (it can hit a body in that first step, as the hit pass runs before the field's);
  - how: the manager's field pass hands it back, and the carrier holds it with a local stop (`freeze_shot`) that lasts until its field lets it go (`HELD_STOP`), so its life, its motion and its hits wait, and it is never caught twice;
  - what is kept: only **the way it was going, in 32 steps round** (a byte, `WAYS`), not its position. A shot at rest (no velocity) keeps the way from it to the field's middle;
  - **in two fields at once** it is the first one's in the carrier's list, the one cast first: the pass hands back each shot once.
- **Drawn in:** each step a held shot moves a fifth of the way left to the middle (`DRAW_IN`). It is held, so it hits nothing on the way.
- **What is caught:** every live shot in it (flying, circling, spiralling, homing, returning, slowed to a stop by its speed). Not caught:
  - a field;
  - a shot already stopped (a local stop, a linger's hold, a stuck one);
  - a falling shot in the air;
  - a still shot: a rune, a pool or a wall standing in it (it is placed, it does not hit the field), but what a rune's Timer fires inside it is caught;
  - the field's own payloads (a Timer's bolts from its middle): a shot whose caster is that field's shot (`set_caster_shot`) is never that field's, though another field over it catches it. Only its direct payloads: a payload's own payload (its caster that bolt) is caught;
  - a shot another field holds, which is stopped.
- **No most** (the owner, 2026-11-26: "No limits"): a field holds every shot that comes in. Its rows grow by doubling and are walked once a step and once at the burst, so nothing is allocated a step once grown.
- **It grows** 1.5 px of radius a shot caught (`GROW_PER_SHOT`), with no most but the room's size, the most any shot is (as Growth keeps it): at that a field covers the room, catches all that moves in it, and is drawn clipped by the screen. Growth grows it further over time. A wider field catches more.
- **The burst:**
  - when: the step after its shot ends (its life out, switched off, its caster gone);
  - spread over steps when it is big (the owner, 2026-11-26: "If it helps performance, you can make the field emit its payload over multiple ticks"): at most 200 a step (`BURST_PER_STEP`), the first caught first, all from its middle as it was, so a field of 2000 bursts over 10 steps (a sixth of a second) and still reads as one burst; a bursting field catches nothing more, and goes once it holds none;
  - every shot it holds leaves from its middle (just outside its own radius) along its kept way, at the speed it had. Its field is gone, so it is not caught again by it; let go inside another live field, it is caught by that one;
  - each is let go (`release_shot`) and takes the field's cards;
- **A field's own payloads** (a Timer's bolts, from its middle) are not caught by it: the pass passes a shot by for the field that is its caster.
- **A wall in the same step:** a shot that comes into a field and meets a wall in one step ends at the wall first (the manager's step runs before the field pass).
- **Not in this build:** beams (a beam's ray is no shot), and bodies (the floor's and the Pool's).

## Numbers

| | |
| --- | --- |
| radius | 32 (64 px at 2x: a cell's width either way of its middle), growing 1.5 a shot, up to the room's size |
| `ray_length` | 72 (its middle, ahead of the hand) |
| lifetime | 3 s (the burst's moment; Slow holds longer) |
| holds | every shot that comes in (no most) |
| mana | 18; wind-down 0.5 s; complexity 3 |
| damage | 0.1 (the least a card has; it hits nothing) |

## The cost, and where it runs

**Catching runs in the projectile manager and its native kernel.** `ProjectileManager.shots_into_fields` is a pass over every shot against every field. The field carrier's step calls it once per tick, after the manager's step. It hands back pairs (a shot, the field it is in), in slot order, each shot once (the first field in the list it is in). The pass is the hot part:

- `ShotKernel.field_pass` runs it natively.
- The GDScript stays as the reference and the fallback.
- `tests/core/test_native_kernel.gd` compares the two to the bit: the pairs and their order, on straight, circling, homing, falling and stopped shots, shots born inside a field (at rest or slow), still shots and a field's own payloads, through still, growing and circling fields, with stale rows in the list.

Nothing runs while no field is open. Holding, drawing in and the burst are GDScript. Measured, held by the same test: a field holding 500 shots takes 0.5 ms a step; one holding 2000 takes 1.8 ms a step. Its burst took 10.5 ms in one step before it was spread over steps, and now takes about 1.4 ms at most a step over 10 steps.

`tests/core/test_field_budget.gd` holds the cost: 2048 shots against 16 fields a step, natively within its budget (about 150 us a step measured; the GDScript fallback's 5 ms is printed, not held). It is printed as `BUDGET:` lines.

## Simulation

The field carrier's rows are state, hashed and in snapshots with no code of their own:

- each field's slot and birth, where its middle is, its card's radius and how many shots it holds;
- each held shot's slot, birth, field and way.

It rolls no dice and reads no clock but `delta`. Its angles go through `DMath` (`DMath.angle`, `DMath.from_angle`). The manager's pass reads its arrays and writes only its hand-back (`_field_out`, `_field_out_field`), which is scratch (DERIVED). `test_determinism` and `test_content_determinism` play the card and its combos twice and through a snapshot.

## Tests

- `content/spells/carriers/field/test_field.gd`:
  - the card; a field lies ahead, short of a wall, and hits nothing;
  - a shot is caught, drawn in, and the field grows;
  - the burst at the field's end, each shot the way it came, with the field's cards;
  - a field switched off early bursts then;
  - an enemy's shot is caught and sent on at the caster with the field's frost;
  - a shot keeps more of a card than the field gives;
  - a shot through it in one step is caught;
  - a cast made inside it is caught, and leaves the way it was going;
  - a shot spawned inside it (a rune's Timer bolts) is caught, the rune is not;
  - a shot stopped (a local stop) or held by a linger is not caught;
  - a field's own payload is caught by another field over it;
  - a burst's shot let go inside another live field is caught by that one;
  - a field grown over a slow shot catches it;
  - a shot in two fields is the first one's;
  - every shot is held, with no most, and the field grows to the room's size at most;
  - a big burst is spread over steps, a share a step, the first caught first;
  - its own shot wears none of its cards but Growth;
  - its own payload is not caught;
  - an enemy shot with a shield or deflect leaves the field be.
- `tests/core/test_card_rules.gd`: every card on it. A teammate sends a shot into it, as into a portal: `GIVES` carriers get the courier, and the cast runs past the field's end, so its burst is in the trace.
- `tests/core/test_native_kernel.gd`, `tests/core/test_field_budget.gd`: the pass, its mirror, its cost.
- The combos (`content/spells/carriers/field/combos/`), the builds:
  - **5, the gun line:** a fire field; frost bolts it caught leave burning too, and set off Thaw on the imp beyond.
  - **6, the ricochet gate:** a bounce field; a bolt it caught leaves, comes off the wall beyond and hits the imp it could not reach.
  - **7, the dam:** a field holds a volley; the imp beyond is untouched while it lasts.
  - **8, the bend:** a homing field past a pillar; a straight bolt it caught leaves homing and turns to the imp behind the pillar.
- Screenshots (`tests/screenshots/shot_field.gd`, `shot_field_tree.gd`, `shot_field_inside.gd`):
  - a field catching shots, grown;
  - the burst with its cards;
  - an enemy's shots caught by a player's field and sent back;
  - the builder.

## The owner's answers (2026-11-26)

1. **The design** above (catch, grow, burst the way they came; only a rough angle kept).
2. **Growth grows the field itself**, not the shots.
3. **Blast and Split work on a field** (a blast where it ends, more fields), as on a portal.
4. **A field's own payloads are not caught** (born inside it; the pass passes them by for their own field).
5. **What leaves it takes its cards** ("as in the gives rule").
6. **A field catches every shot in its circle**, not only what crosses its edge (2026-11-26: "It should capture all that hits it's area"): a cast made inside it, a shot spawned inside it, one it grows over.
