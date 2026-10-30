# Carriers

A carrier is what a form card fires: a bolt, a rune, a beam, a dash, a decoy and so on. The carrier
is the important part of a cast. **Each carrier decides for itself what it does with every other
card on it, both in what the card does and in how it looks**, and it has to decide every one:
there is no default.

The code is in `core/spells/carriers/`: one script per carrier (`bolt.gd`, `beam.gd`,
`decoy.gd`...) on the base `Carrier` (`carrier.gd`). A carrier is known by its name: a form card
says `carrier = &"beam"`, and `Carriers.of(&"beam")` (`carriers.gd`) finds it. Carriers are never
numbered, so adding or removing one never touches another card's file.

## What a carrier writes about the other cards

Only the cards that do nothing on it, each with the sentence the builder shows the player. Every
card not listed does something there.

```gdscript
## Modifier cards that do nothing on a decoy, with the sentence the builder shows after
## "<Card> does nothing on a Decoy: ".
const DOES_NOTHING: Dictionary = {
	B.RETURN: "it does not fly out",
	B.BOUNCE: "it turns a shot or a beam at walls, and a decoy is a body that hits nothing",
	...
}
## Trigger cards that never go off on a decoy, with the sentence the builder shows.
const NEVER_FIRES: Dictionary = {
	E.HIT: "a decoy hits nothing",
}
```

In the game these sentences do two things: the compiler leaves a card that does nothing out of
the spell, and the builder greys it out and shows why.

**You don't have to work the list out.** `tests/core/test_card_rules.gd` plays every card on every
carrier in a small world and compares what happens with and without the card. A card that
changes nothing and is not listed fails it:

    `return` on `decoy` does nothing and is not listed as wasted

so you add that line with a sentence (or make the card work there). A card that is listed but
does change something fails it the other way.

Two rules hold for every carrier and are not listed: on a carrier that hits nothing itself (a
decoy, a familiar), an infusion and heavy count only when a blast on it carries them
(`Carrier.takes_infusion`, `Carrier.BLAST_CARRIES`).

**Traits**, in `traits()`: the numbers and shared rules it takes (`FLIES`, `STAYS`, `HITS`,
`LASTS`, `REACHES`, `GUARDS`, `STEERS`, `SPEED`, `SHOTS`, `SPREAD`, `PIERCE`, `RING`, `OUTWARD`,
`REPEATS_HELD`, `OWN_POSE`, `INSTANT_HOMING`, `CARRIES_PAYLOAD`, `HOLDS_STAFF`; each is documented
in `carrier.gd`). The compiler's rules for numbers (does a split count here? does pierce?) read
these. **Required fields**, in `required_fields()`: what a form card of this carrier must set
above 0 (a beam's `ray_length`); the spell validator checks them. `tests/core/test_carriers.gd`
checks the lists against the traits (a carrier that hits nothing must list `on hit`).

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

1. Add `core/spells/carriers/<name>.gd`, `extends Carrier`, with `id()` returning `&"<name>"`, its
   `traits()` and `required_fields()`, and empty `DOES_NOTHING` and `NEVER_FIRES`; list it in
   `Carriers.make_all`.
2. Override the hooks it needs (at least `launch` or `shoot`).
3. Add its form card under `content/spells/forms/` with `carrier = &"<name>"`.
4. Run `tests/core/test_card_rules.gd`. For every card it says does nothing on your carrier, add a
   line with a sentence, or make the card work there. Run `tests/core/test_carriers.gd` too.

Removing a carrier is deleting its script and its line in `make_all`. A form card that still names
it is refused by the validator.

## Adding a modifier behaviour or a trigger

Add the value at the end of `ModifierBase.Behaviour` (or `TriggerBase.Event`) and implement it.
`test_card_rules.gd` then plays it on every carrier and names each carrier where it does nothing,
for a line in that carrier's list.
