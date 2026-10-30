# Carriers

A carrier is what a form card fires: a bolt, a rune, a beam, a dash, a decoy and so on, one per
`FormBase.Motion`. The carrier is the important part of a cast. **Each carrier decides for itself
what it does with every other card on it, both in its logic and in how it looks**, and it has to
decide every one: there is no default.

The code is in `core/spells/carriers/`: one script per carrier (`bolt.gd`, `beam.gd`,
`decoy.gd`...) on the base `Carrier` (`carrier.gd`), found by `Carriers.of(motion)` (`carriers.gd`).
`tests/core/test_carriers.gd` enforces everything below.

## What a carrier decides

**Every modifier behaviour** (`ModifierBase.Behaviour`), in `BEHAVIOURS`, one row each:

| Row | Meaning |
| --- | --- |
| `[Use.RUNS, Look.X]` | The shared path runs it: the shot kit (`Spells._apply_travel`, the projectile manager's setters), the hit path (chain, siphon, possess, relay, heavy), the cast path (echo, mirror, recoil, hold) or the end point (blast). |
| `[Use.OWN, Look.X]` | The carrier runs it its own way, and the shared path leaves it alone: a beam bends, bounces, waves, grows and guards along its line; a teleport takes recoil off its distance. |
| `[Use.WITH_BLAST, Look.X, "why"]` | It runs only when the carrier also has a blast, whose area hit carries it (heavy on a decoy). The reason is shown when there is no blast. |
| `[Use.WASTED, "why"]` | It does nothing here. The card is listed as wasted in the builder with this reason, read after "Bounce does nothing on a Decoy: ". |

The look, for every row that runs:

| Look | Meaning |
| --- | --- |
| `Look.SHOWN` | The carrier draws the card's `look_layer` (and an infusion's tint) on what it shows. |
| `Look.CUE` | The card's cue plays (a blast's explosion); on a `WITH_BLAST` row, the blast's cue that carries it. |
| `Look.NONE` | Nothing of the card shows on this carrier, with the reason after it or in the carrier's `look_note()`. |

**Every trigger** (`TriggerBase.Event`), in `EVENTS`: `""` when it can fire on the carrier, else
why it never does. The compiler adds the checks that depend on the other cards (a block needs a
shield or deflect, a reaction an infusion).

**Infusions**, in `INFUSIONS`, as one row like a behaviour's. An infusion is a hit's element, so it
runs where the carrier hits, or with a blast.

**Traits**, in `traits()`: the numbers and shared rules it takes (`FLIES`, `STAYS`, `HITS`,
`LASTS`, `REACHES`, `GUARDS`, `STEERS`, `SPEED`, `SHOTS`, `SPREAD`, `PIERCE`, `RING`, `OUTWARD`,
`REPEATS_HELD`, `OWN_POSE`, `INSTANT_HOMING`; each is documented in `carrier.gd`). The compiler's
rules for numbers (does a split count here? does pierce?) read these.

## What a carrier runs

At runtime `Spells` makes its own carriers (`Carriers.make_all`), binds them and hands every launch
to its carrier. Nothing in `spells.gd` asks which motion a spell has. A carrier overrides what is
its own:

| Hook | Default | Overridden by |
| --- | --- | --- |
| `launch` | a fan (or ring) of `spell.shots`, each made by `shoot` | dash and teleport (a move), rain (a telegraph), wall (one solid line), bolt (adds the nova's ring) |
| `shoot` | a shot flying along its heading | rune (still, placed ahead), orbit (on its circle), beam, swing, slam (a row of their own), decoy and familiar (an entity) |
| `on_hit` | nothing | hook (pulls its caster), swap (trades places) |
| `on_move_end` | nothing | teleport (strikes where it lands) |
| `step`, `end_of`, `end_actor`, `clear` | nothing | beam, swing, slam (their rows) |
| `reach_of` | 0 | bolt, beam, swing, slam, rain (for an enemy's telegraph) |

A carrier asks the runtime for the shared path through `rt`: the shot kit (`_land_shot`), moves
(`_move_caster`), entities (`_spawn_entity`), and the hit path. A hit with no shot slot (a beam's,
a sweep's, a strike's, a zap, a jump) goes back through `Spells` as one `RayHit`
(`_ray_begin`/`_ray_end`), so cards, payloads and chains work the same on every carrier.

## Adding a carrier

1. Add its value at the end of `FormBase.Motion`. Values are stored as numbers in every form card's
   `.tres`, so never reorder or remove one: a retired one stays as a placeholder (`_UNUSED_10`).
2. Add `core/spells/carriers/<name>.gd`, `extends Carrier`, and list it in `Carriers.make_all`.
3. Fill `BEHAVIOURS`, `EVENTS` and `INFUSIONS` with every row, and `traits()`.
   `tests/core/test_carriers.gd` fails until every row is there and agrees with the traits.
4. Override the hooks it needs (at least `launch` or `shoot`).
5. Add its form card under `content/spells/forms/`, and add the card to `FORMS` in
   `tests/core/test_carriers.gd`. The test then casts it and checks that every look it says is
   `SHOWN` really reaches a renderer, and that a look it says is `NONE` doesn't.
6. `tests/core/test_card_rules.gd` plays every card on it and fails on a row that says a card runs
   where the runtime does nothing.

## Adding a modifier behaviour

Add the value at the end of `ModifierBase.Behaviour`, implement it on the shared path (or not at
all), and then decide it on **every** carrier: `test_carriers.gd` fails for each carrier that has
no row for it. That is on purpose: the question "what does this card do on a beam? On a decoy?"
gets answered when the card is made, not found later as a card that silently does nothing.

A new trigger event works the same way through `EVENTS`.

## What the tables show today

The look column made three gaps visible, which the tests confirm: a **teleport**, a **decoy** and a
**familiar** draw none of their cards' looks (a teleport draws nothing of its own, a decoy wears
its caster's look, a familiar is drawn as a plain orbit shot). Their blasts still show by the
blast's cue. Giving them looks is a feel task: change their rows to `Look.SHOWN` and the test will
check that the renderer really gets the looks.
