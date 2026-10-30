# Carriers

A carrier is what a form card fires: a bolt, a rune, a beam, a dash, a decoy and so on. The carrier
is the important part of a cast. **Each carrier decides for itself what it does with every other
card on it, both in what the card does and in how it looks**, and it has to decide every one:
there is no default.

The code is in `core/spells/carriers/`: one script per carrier (`bolt.gd`, `beam.gd`,
`decoy.gd`...) on the base `Carrier` (`carrier.gd`). A carrier is known by its name: a form card
says `carrier = &"beam"`, and `Carriers.of(&"beam")` (`carriers.gd`) finds it. Carriers are never
numbered, so adding or removing one never touches another card's file.
`tests/core/test_carriers.gd` enforces everything below.

## What a carrier decides

Each carrier has three tables. Every row is a small dictionary, and its keys say which question
each value answers.

**`BEHAVIOURS`: every modifier behaviour** (`ModifierBase.Behaviour`, what a modifier card does),
one row each:

```gdscript
const BEHAVIOURS: Dictionary = {
	B.HOMING: {"works": Works.OWN_WAY, "shows": Shows.DRAWN},
	B.BLAST:  {"works": Works.YES, "shows": Shows.AS_EFFECT},
	B.RETURN: {"works": Works.NO, "why_not": "it does not fly out"},
	B.SHIELD: {"works": Works.OWN_WAY, "shows": Shows.NOTHING, "why_nothing_shows": "a decoy wears its caster's look, not its cards'"},
	...
}
```

| Key | The question it answers | Values |
| --- | --- | --- |
| `"works"` | Does the card work on this carrier? | `Works.YES`: yes, done by the code every carrier shares (the shot kit, the hit path, echo/mirror/recoil/hold, the blast at the end point). `Works.OWN_WAY`: yes, done by this carrier's own code (a beam bends, bounces and waves along its line). `Works.ONLY_WITH_BLAST`: only when the carrier also has a blast, which carries it (heavy on a decoy). `Works.NO`: no, it does nothing here. |
| `"shows"` | If it works, how does it look? | `Shows.DRAWN`: the card's look is drawn on what the carrier shows. `Shows.AS_EFFECT`: it shows as its own effect, as a blast's explosion. `Shows.NOTHING`: nothing of it shows. |
| `"why_not"` | If it does not work (or only with a blast), why? | The words a player reads in the builder: "Return does nothing on a Decoy: it does not fly out." |
| `"why_nothing_shows"` | If it shows nothing, why? | "a decoy wears its caster's look, not its cards'". |

**`EVENTS`: every trigger** (`TriggerBase.Event`, what a trigger card waits for):

```gdscript
const EVENTS: Dictionary = {
	E.HIT: {"fires": false, "why_not": "a decoy hits nothing"},
	E.EXPIRE: {"fires": true},
	...
}
```

`"fires"` answers "does this trigger ever go off on this carrier?", and `"why_not"` says why when
it never does. The compiler adds the checks that depend on the other cards (a block needs a
shield or deflect, a reaction an infusion).

**`INFUSIONS`: an element card** on this carrier, as one row with a behaviour's keys:
`{"works": Works.ONLY_WITH_BLAST, "shows": Shows.AS_EFFECT, "why_not": "a decoy hits nothing"}`.
An infusion is a hit's element, so it works where the carrier hits, or with a blast.

**Traits**, in `traits()`: the numbers and shared rules it takes (`FLIES`, `STAYS`, `HITS`,
`LASTS`, `REACHES`, `GUARDS`, `STEERS`, `SPEED`, `SHOTS`, `SPREAD`, `PIERCE`, `RING`, `OUTWARD`,
`REPEATS_HELD`, `OWN_POSE`, `INSTANT_HOMING`, `CARRIES_PAYLOAD`, `HOLDS_STAFF`; each is documented
in `carrier.gd`). The compiler's rules for numbers (does a split count here? does pierce?) read
these. **Required fields**, in `required_fields()`: what a form card of this carrier must set
above 0 (a beam's `ray_length`); the spell validator checks them.

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
   list it in `Carriers.make_all`.
2. Fill `BEHAVIOURS`, `EVENTS` and `INFUSIONS` with every row, and `traits()` and
   `required_fields()`. `tests/core/test_carriers.gd` fails until every row is there and agrees
   with the traits.
3. Override the hooks it needs (at least `launch` or `shoot`).
4. Add its form card under `content/spells/forms/` with `carrier = &"<name>"`. The test then casts
   it and checks that every card its rows say `Shows.DRAWN` really reaches a renderer, and that one they
   say `Shows.NOTHING` doesn't.
5. `tests/core/test_card_rules.gd` plays every card on it and fails on a row that says a card works
   where the runtime does nothing.

Removing a carrier is deleting its script and its line in `make_all`. A form card that still names
it is refused by the validator.

## Adding a modifier behaviour

Add the value at the end of `ModifierBase.Behaviour`, implement it on the shared path (or not at
all), and then decide it on **every** carrier: `test_carriers.gd` fails for each carrier that has
no row for it. That is on purpose: the question "what does this card do on a beam? On a decoy?"
gets answered when the card is made, not found later as a card that silently does nothing.

A new trigger event works the same way through `EVENTS`.

## What the tables show today

The look column made three gaps visible, which the tests confirm: a **teleport**, a **decoy** and a
**familiar** draw none of their cards' looks (a teleport draws nothing of its own, a decoy wears
its caster's look, a familiar is drawn as a plain orbit shot). Their blasts still show as the
blast's effect. Giving them looks is a feel task: change their rows' `"shows"` to `Shows.DRAWN` and the test
will check that the renderer really gets the looks.
