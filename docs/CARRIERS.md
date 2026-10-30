# Carriers

A carrier is what a form card fires: a bolt, a rune, a beam, a dash, a decoy and so on. The carrier
is the important part of a cast. **Each carrier decides for itself what it does with every other
card on it, both in what the card does and in how it looks**, and it has to decide every one:
there is no default.

The code is in `core/spells/carriers/`: one script per carrier (`bolt.gd`, `beam.gd`,
`decoy.gd`...) on the base `Carrier` (`carrier.gd`). A carrier is known by its name: a form card
says `carrier = &"beam"`, and `Carriers.of(&"beam")` (`carriers.gd`) finds it. Carriers are never
numbered, so adding or removing one never touches another card's file.

## Which cards do nothing on a carrier: worked out, not written

A carrier answers yes/no questions about itself, in `traits()`, and nothing about other cards:

| Flag | The question |
| --- | --- |
| `FLIES` | Does it fly out on its own, as a shot (a bolt, a hook, a swap)? |
| `MOVES` | Does it travel along a path through the world (also an orbit)? |
| `LINE` | Is it a line that is there at once (a beam)? |
| `STAYS` | Is it a shot that stays in the world a while (a bolt, a rune, an orbit, a wall...)? |
| `HITS` | Does it hit things itself (not a decoy or a familiar)? |
| `LASTS` | Does it last a while (not a slam or a teleport, which are over at once)? |
| `STEERS` | Can homing steer it (turn it, bend it, or place it on a target)? |
| `MEETS_SHOTS` | Can it stop or turn other shots (not a rain or a familiar)? |
| `MOVES_CASTER` | Does it move its caster (a dash, a teleport)? |

(and the number questions: `SPEED`, `SHOTS`, `SPREAD`, `PIERCE`, `REACHES`, ... all in
`carrier.gd`.)

Each card says, once for every carrier, what it needs from a carrier (`Carrier.NEEDS`, and
`EVENT_NEEDS` for triggers):

```gdscript
B.RETURN: {"any": FLIES, "why_not": "it does not fly out"},
B.CHAIN:  {"any": HITS, "why_not": "it acts on what the carrier hits"},
B.HOLD:   {"any": LASTS, "not": MOVES_CASTER, "why_not": "nothing keeps it on"},
```

From those two the compiler works out, every time a staff is built, whether a card does anything
on a carrier, and if not, the sentence the builder shows: "Return does nothing on a Decoy: it does
not fly out, and a decoy is a body that hits nothing." A card not in `NEEDS` works on every carrier
(numbers, blast, echo, recoil). On a carrier that hits nothing, a blast carries an infusion and
heavy (`takes_infusion`, `BLAST_CARRIES`).

`tests/core/test_card_rules.gd` plays every card on every carrier in a small world and fails where
the answer is wrong (a card that does nothing but is not said to, or the other way round), so a
wrong yes/no answer is caught by CI; you don't need to run it to know what to write.

**Required fields**, in `required_fields()`: what a form card of this carrier must set above 0 (a
beam's `ray_length`); the spell validator checks them.

## What a carrier runs

At runtime `Spells` makes its own carriers (`Carriers.make_all`), binds them and hands every launch
to its carrier. Nothing in `spells.gd` asks which carrier a spell has. A carrier overrides what is
its own:

| Hook | Default | Overridden by |
| --- | --- | --- |
| `launch` | a fan (or ring) of `spell.shots`, each made by `shoot` | dash and teleport (a move, `CarrierMove`), rain (marks its aim point and lands later, `land`), wall (one solid line), bolt (adds the nova's ring) |
| `shoot` | a shot flying along its heading | rune (still, placed ahead), orbit (on its circle), beam, swing, slam (a row of their own), decoy and familiar (a body, `CarrierEntity`) |
| `on_hit` | nothing | hook (pulls its caster), swap (trades places) |
| `on_move_end` | nothing | teleport (strikes where it lands) |
| `step` | nothing | dash (strikes what it passes), beam, swing, slam (their rows) |
| `end_of`, `end_actor`, `clear`, `reset_actor` | nothing | dash, teleport, beam, swing, slam, decoy, familiar (what they keep) |
| `switch_off` | nothing | beam, swing (end), decoy, familiar (asked to end): a held carrier switched off |
| `reach_of` | 0 | bolt, beam, swing, slam, rain (for an enemy's telegraph) |

Carriers that share a mechanism share a base or a kit: dash and teleport extend `CarrierMove` (the
launch both make, with `_aim_move`, `_move_body` and `_moved_shot` for their own part), decoy and
familiar extend `CarrierEntity` (a body `ai` makes, ended by `entity_ended`), and every move of a
caster or of the shot that cast it (dash, teleport, hook, swap, recoil) goes through `CasterMoves`
(`core/spells/caster_moves.gd`), whose end point runs the carrier's `on_move_end`. A carrier asks the
runtime for the rest of the shared path through `rt`: the shot kit (`_land_shot`) and the hit path. A hit with no shot slot (a beam's,
a sweep's, a strike's, a zap, a jump) goes back through `Spells` as one `RayHit`
(`_ray_begin`/`_ray_end`), so cards, payloads and chains work the same on every carrier.

## Adding a carrier

1. Add `core/spells/carriers/<name>.gd`, `extends Carrier`, with `id()` returning `&"<name>"`, and
   answer the questions in `traits()` and `required_fields()`; list it in `Carriers.make_all`.
2. Override the hooks it needs (at least `launch` or `shoot`).
3. Add its form card under `content/spells/forms/` with `carrier = &"<name>"`.

Removing a carrier is deleting its script and its line in `make_all`. A form card that still names
it is refused by the validator.

## Adding a modifier behaviour or a trigger

Add the value at the end of `ModifierBase.Behaviour` (or `TriggerBase.Event`), implement it, and,
if it does not work on every carrier, say what it needs in `Carrier.NEEDS` (or `EVENT_NEEDS`). If it
needs something no flag asks yet, add the flag and answer it on each carrier.
