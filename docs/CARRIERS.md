# Carriers

A carrier is what a form card fires: an atom (the Atom, Bolt and Nova cards), a rune, a beam, a dash, a decoy and so on. The carrier
is the important part of a cast. **Each carrier decides for itself what it does with every other
card on it, both in what the card does and in how it looks**, and it has to decide every one:
there is no default.

The code is in `core/spells/carriers/`: one script per carrier (`atom.gd`, `beam.gd`,
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
| `STEERS` | Can homing steer it (turn it, bend it, place it on a target, or creep it toward one: a rune, a wall, a decoy)? |
| `MEETS_SHOTS` | Can it stop or turn other shots (not a rain or a familiar)? |
| `MOVES_CASTER` | Does it move its caster (a dash, a teleport)? |
| `STRIKES_POINT` | Does it strike one point near its caster's hand (a slam)? Its staff animation can `land` there (`strike_point`). |
| `BLOCKS` | Does it stand in the world and stop other actors' shots (a wall)? Read only by the AI's summary (`CastSense`). |
| `SPAWNS` | Does it make a body of its own that stays (a decoy, a familiar)? Read only by `CastSense`. |
| `GATES` | Does it open a way through that shots and bodies take (a portal)? Read only by `CastSense` (`opens`: the AI casts it to open a fight). |

(and the number questions: `SPEED`, `SHOTS`, `SPREAD`, `PIERCE`, `REACHES`, ... all in
`carrier.gd`.)

Each kind of card says, next to its own definition and once for every carrier, what it needs from a
carrier (`ModifierBase.RULES` "needs" for modifier behaviours, `TriggerBase.NEEDS` for triggers; the flags
are `CarrierTraits`):

```gdscript
B.RETURN: {"any": FLIES},
B.CHAIN:  {"any": HITS},
B.HOLD:   {"any": LASTS, "not": MOVES_CASTER},
B.HEAVY:  {"any": HITS, "or_cards": [B.BLAST]},
E.BLOCK:  {"any": MEETS_SHOTS, "cards": [B.SHIELD, B.DEFLECT]},
E.WALL:   {"any": FLIES | LINE, "not_cards": [B.GHOST]},
```

A need may also name cards: `"or_cards"` stand in for the traits (what a blast strikes is the
carrier's hit, rules R4 F2), `"cards"` must be on the carrier (or an infusion, where `"or_infused"`), and
`"not_cards"` stop it where they work. The compiler has no case per behaviour or trigger.

From those two the compiler works out, every time a staff is built, whether a card does anything
on a carrier: yes or no (Return needs `FLIES`; a decoy does not fly, so Return does nothing on a
decoy). A card that does nothing is marked in the builder; no text explains it (owner, 2026-10-30:
the visuals are enough). A card not in `NEEDS` works on every carrier
(numbers, blast, echo, recoil). On a carrier that hits nothing, a blast carries an infusion and
heavy (`takes_infusion`, and heavy's `"or_cards"` in `ModifierBase.RULES` "needs"). A carrier that
hits nothing but passes an infusion on (a portal: what comes out of it takes its element and
status) says so in `takes_infusion`, and which infusions count in `takes_element` (mend, which has
no status, does nothing on a portal).

`tests/core/test_card_rules.gd` plays every card on every carrier in a small world and fails where
the answer is wrong (a card that does nothing but is not said to, or the other way round), so a
wrong yes/no answer is caught by CI; you don't need to run it to know what to write.

**Asking about one card.** `Spells.card_works(card_id, carrier)` (`StaffCompiler.card_works`)
answers yes or no to "does this card do anything on this carrier on its own?" before the card is
placed, with the same rules as a compile; for the builder, a reward screen or a bot.
`tests/core/test_carriers.gd` checks it against a real compile for every card on every carrier.

**Required fields**, in `required_fields()`: what a form card of this carrier must set above 0 (a
beam's `ray_length`); the spell validator checks them.

## The fallback carriers: where cards with no carrier land

A group that ends with modifiers or infusions and no carrier after them (reading rule 5,
docs/milestones/M2-staffs.md) does not drop them: they land on a **fallback carrier**, `caster`
for the cast's own group and `point` for a payload (the point it began at: where its shot hit,
ended or ticked). A lone `blast` explodes on you; `on hit · bolt · blast` explodes where the bolt
hits, with no second carrier. Both are carriers like any other (`caster.gd`, `point.gd`, on the
shared base `fallback.gd`, `CarrierFallback`), with two differences: no form card fires them, so
`Carriers.ids()` leaves them out and a form card may not name them (`Carriers.is_fallback`); and the
compiler picks one itself (`Carriers.fallback(payload)`) for the cards left over.

Everything else is the one rule. Their yes/no answers decide which cards do something there, through
the same needs as on every carrier: both `HITS` (one strike of everything within
`SpellLimits.FALLBACK_RADIUS`, or the blast's strength, the caster too), and only `caster`
`MEETS_SHOTS` (its shield is the caster's barrier, its deflect turns the shots round the caster as
it is cast; a point guards no one). Neither flies, moves, stays, lasts or steers, and neither has a
cooldown of its own (`has_cooldown`), so homing, bounce, hold, split or a shorter cooldown are wasted
there, and chain, pull, possess, relay, penta and mirror work. The runtime launches them like any
other carrier, so echo strikes again, recoil pushes, mirror strikes twice and penta strikes from a
ring. When none of the cards does anything there, nothing lands and every one is wasted.

`tests/core/test_card_rules.gd` plays every modifier and infusion on both (the columns `on you` and
`right there`), and `tests/core/test_fallback_carriers.gd` checks the rest.

## What a carrier runs

At runtime `Spells` makes its own carriers (`Carriers.make_all`), binds them and hands every launch
to its carrier. Nothing in `spells.gd` asks which carrier a spell has or names one
(`tests/core/test_carriers.gd` checks it). A carrier overrides what is its own:

| Hook | Default | Overridden by |
| --- | --- | --- |
| `launch` | a fan (or ring) of `spell.shots`, each made by `shoot` | portal (a mouth and its exits, gates of the projectile manager), dash and teleport (a move, `CarrierMove`), rain (marks its aim point and lands later, `land`), wall (one solid line), atom (adds the nova's ring) |
| `shoot` | a shot flying along its heading | rune (still, placed ahead), orbit (on its circle), beam, swing, slam (a row of their own), decoy and familiar (a body, `CarrierEntity`) |
| `on_hit` | nothing | hook (pulls its caster), swap (trades places) |
| `on_move_end` | nothing | teleport (strikes where it lands) |
| `step` | nothing | dash (strikes what it passes), beam, swing, slam (their rows), portal (moves what went into its gates) |
| `end_of`, `end_actor`, `clear`, `reset_actor` | nothing | dash, teleport, beam, swing, slam, decoy, familiar (what they keep) |
| `switch_off` | nothing | beam, swing (end), decoy, familiar (asked to end): a held carrier switched off |
| `reach_of` | 0 | atom, beam, swing, slam, rain (for an enemy's telegraph) |
| `tip_of` | INF | beam, swing: where a row is, for a `timer` or `on hurt` on it (`LC_ROW`) |

Carriers that share a mechanism share a base or a kit: dash and teleport extend `CarrierMove` (the
launch both make, with `_aim_move`, `_move_body` and `_moved_shot` for their own part), decoy and
familiar extend `CarrierEntity` (a body `ai` makes, ended by `entity_ended`), and every move of a
caster or of the shot that cast it (dash, teleport, hook, swap, recoil) goes through `CasterMoves`
(`core/spells/caster_moves.gd`), whose end point runs the carrier's `on_move_end`.

### What a carrier may ask of the runtime: `CarrierKit`

A carrier sees the runtime only as `kit` (`core/spells/carrier_kit.gd`, `CarrierKit`), never as
`Spells`: that one short file is all a new carrier needs to learn of the runtime. Each call is the
runtime's one rule for it, shared by every carrier:

| Group | Calls |
| --- | --- |
| The world | `projectiles`, `events`, `clock()` |
| The cast under way | `spell_of(tag)`, `carrier_of(spell)`, `caster()`, `caster_seq()`, `caster_shot()`, `is_echo(spell)`, `shot_started`, `shot_ended` |
| The aim | `aim_origin`, `aim_dir`, `aim_pivot`, `aim_seen`, `walk_turn` (by actor) |
| Shots | `fan_angle`, `staff_spread`, `placed_at`, `land_shot` (or `apply_travel` then `register`) |
| Hits with no shot slot | `ray_begin`/`ray_end`, `cast_jumps`, `strike`, `strike_round`, `guard` (with the carrier's `id()` as its block form), `guard_path`, `bounces`, `ghost` |
| What it leaves behind | `blast`, `fire_payloads`, `fire`, `delay` |
| Live carriers | `live_join` (`SpellRuntime.LC_SLOT`, `LC_ROW`, `LC_ACTOR`, `LC_POINT`), `live_leave` |
| Moves and entities | `moves()` (`CasterMoves`), `request_entity` |

A hit with no shot slot (a beam's, a sweep's, a strike's, a zap, a jump) goes back through the
runtime as one `RayHit` (`ray_begin`/`ray_end`), so cards, payloads and chains work the same on
every carrier. If a carrier needs something the kit does not give, add it to the kit (one rule for
every carrier), never a back door into `Spells`.

### Reading a carrier's own rows

The looks, `ai` and the tests read a carrier's own getters from that carrier's class:
`CarrierBeam.of(spells)`, `CarrierSwing.of(spells)`, `CarrierSlam.of(spells)`,
`CarrierDash.of(spells)`, `CarrierDecoy.of(spells)` (each is `Spells.carrier(id)`, typed). A new
carrier with rows others read adds the same `static func of`.

### Its end: when a carrier is going

A carrier that dissolves at its end says so once, in `fade()`: the share of its life, at its end,
over which it fades out (0, the default, ends at once; a beam's is `SpellLimits.BEAM_FADE`, its last
quarter; a held one never fades, it ends when switched off). Two shared helpers on `Carrier` read
it, so the logic and the looks agree on the moment:

- `active_left(life_left, span)`: the seconds it may still act. Anything a carrier times waits
  within it, and a wait still running when it reaches 0 is dropped: a carrier that is going does
  nothing more of its own accord (owner, 2026-10-31). A won zap does this, a beam's in its rows and
  a shot's in `Spells._active_left`.
- `fade_left(life_left, span)`: how whole it looks, 1 to 0 over its fade. Feel draws a beam's fade
  from it (`CarrierBeam.beam_fade`).

To time something new on a carrier, wait at most `active_left` and check it again before acting.
To give a carrier a fade, override `fade()`, and draw its look from `fade_left`.

## Adding a carrier

1. Add `core/spells/carriers/<name>.gd`, `extends Carrier`, with `id()` returning `&"<name>"`, and
   answer the questions in `traits()` and `required_fields()`. `Carriers.make_all` finds it in the
   folder by its `class_name`; give it a `step_order()` only if its rows must step before or after
   another carrier's.
2. Override the hooks it needs (at least `launch` or `shoot`), asking the runtime only through
   `kit` (`CarrierKit`, above). Nothing in `spells.gd` changes.
3. Add its form card under `content/spells/forms/` with `carrier = &"<name>"`, and its looks, all
   data on the card (`FormBase`): a `staff_pose` (`tests/core/test_staff_poses.gd` fails without
   one), its cues (`cast_cue`, the flash on the staff, `cast` by default; `shown_cue`, where it
   shows itself; `impact_cue`, where its shots strike, `impact` by default; `end_cue`, where a
   carrier with no shot ends; `tests/content/spells/test_carrier_looks.gd` fails for a cue that is
   not in `content/cues/`: one file per moment, flashes from `content/flashes/`), and a `shot_body` if
   its still shots are not runes. A carrier with no shot to draw tells its moments for them:
   `form_shown` with its card's id (`spell.form_id`) where it shows itself, which plays its
   `shown_cue`, and `carrier_ended` where it ends, which plays its `end_cue` (a carrier that moves its caster gets this from
   `CasterMoves.end`). Feel names no carrier: nothing there changes.
4. If its look strikes one point near the caster (a slam's impact), give it `STRIKES_POINT` and
   draw that look at `strike_point` (override it for a point off the aim; the runtime stops it at a
   wall; tell `StaffPoses.land_at` if the point moves before the strike). Its card's staff
   animation can then `land` the staff's tip there, with no pixels to tune.

### Lining a staff animation up with its look

A key's `land` (0 to 1) moves the drawn staff so its tip lies on the point the carrier strikes,
whichever of the 16 head columns shows and whichever way it aims; `turn`, `lift` and `push` then
only shape the way there. Two checks keep it lined up: `tests/gameplay/player/test_staff_alignment.gd`
casts every card that lands, in 32 aims and by a wall, and fails when the drawn tip
(`StaffLook.tip_position`) or the strike's look (`form_shown`) is more than a pixel off the point
struck; the screenshot `shot_staff_alignment` (`ci/build/build.sh --quick --screenshots`) draws
them, a white cross on each tip and a red ring on each point struck. A card asks for nothing: it is
found because it lands. While a hit holds the caster (a local stop), the body shows the moment of
the hit, not the step before (`Actor.step`).

### Portals: gates in the world

A portal (`portal.gd`, docs/milestones/portal.md) opens gates, rows of the projectile manager
(`open_gate`) that the other carriers meet without knowing the portal: a beam's ray stops where it
goes into one when the beam asks (`ray_gates`) and goes on from every gate it leads to as a leg of
its own (`CarrierBeam._start_leg`); a flying shot that went in is moved by the portal after the
step (`shots_into_gates`, `pass_shot`); a body by `target_move_requested`. A new carrier whose
rays should go through portals sets `ray_gates` before its ray and reads `ray_gate` after it.

Removing a carrier is deleting its script. A form card that still names
it is refused by the validator.

## Adding a modifier behaviour or a trigger

Add the value at the end of `ModifierBase.Behaviour` (or `TriggerBase.Event`), implement it, and,
if it does not work on every carrier, say what it needs in `ModifierBase.RULES` "needs" (or `TriggerBase.NEEDS`), traits and cards alike. If it
needs something no flag asks yet, add the flag and answer it on each carrier.
