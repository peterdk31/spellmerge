# Carriers

A carrier is what a carrier card fires: an atom (the Atom and Bolt cards), a rune, a beam, a dash, a decoy and so on. The carrier
is the important part of a cast. **Each carrier decides for itself what it does with every other
card on it, both in what the card does and in how it looks**, and it has to decide every one:
there is no default.

The code is in `core/spells/carriers/`: one script per carrier (`atom.gd`, `beam.gd`,
`decoy.gd`...) on the base `Carrier` (`carrier.gd`). A carrier is known by its name: a carrier card
says `carrier = &"beam"`, and `Carriers.of(&"beam")` (`carriers.gd`) finds it. Carriers are never
numbered, so adding or removing one never touches another card's file.

## Which cards do nothing on a carrier: worked out, not written

A carrier answers yes/no questions about itself, in `traits()`, and nothing about other cards:

| Flag | The question |
| --- | --- |
| `FLIES` | Does it fly out on its own, as a shot (a bolt, a hook, a swap)? |
| `MOVES` | Does it travel along a path through the world (a bolt, a swap; circling with Orbit too)? |
| `LINE` | Is it a line that is there at once (a beam)? |
| `STAYS` | Is it a shot that stays in the world a while (a bolt, a rune, a pool, a wall...)? |
| `HITS` | Does it hit things itself (not a decoy or a familiar)? |
| `LASTS` | Does it last a while (not a slam or a teleport, which are over at once)? |
| `STEERS` | Can homing steer it (turn it, bend it, place it on a target, or creep it toward one: a rune, a wall, a decoy)? |
| `MEETS_SHOTS` | Can it stop or turn other shots (not a familiar)? |
| `MOVES_CASTER` | Does it move its caster (a dash, a teleport)? |
| `STRIKES_POINT` | Does it strike one point near its caster's hand (a slam)? Its staff animation can `land` there (`strike_point`). |
| `BLOCKS` | Does it stand in the world and stop other actors' shots (a wall)? Read only by the AI's summary (`CastSense`). |
| `SPAWNS` | Does it make a body of its own that stays (a decoy, a familiar)? Read only by `CastSense`. |
| `GATES` | Does it open a way through that shots and bodies take (a portal)? Read only by `CastSense` (`opens`: the AI casts it to open a fight). |
| `CASTS_FROM_SHOT` | Is it shots of the projectile manager, each casting what it fires while it lives (a bolt, a rune, a pool, a wall)? |
| `CASTS_FROM_BODY` | Is it a body of its own, an actor, that casts what it fires (a decoy)? |
| `AOE` | Does it go out all round the point it is cast at, not along an aim (a pulse's ring)? Not aimed: scatter, mirror and nova turn nothing there and the AI reads it as an area round its caster; it goes out as a shot does: Return and Ghost work on it. |
| `MELEE` | Is it held by or carried with the body that casts it, never leaving it (swing, slam, dash, teleport)? Then it never hits that body (`CarrierKit.spared`); a ranged carrier spares it only until it has left it: a shot over time, a beam along its path (it hits its caster when it bounces or bends back into them). |

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

**Required fields**, in `required_fields()`: what a carrier card of this carrier must set above 0 (a
beam's `ray_length`); the spell validator checks them.

## Pulse: a ring from the cast point

The **Pulse** card (`content/spells/carriers/pulse/`, a carrier card like Bolt) is a ring that
grows from the point it is cast at (props W9a, owner 2026-11-12). It replaced the compiler's
fallback carriers, a rule of the compiler no card played ("the 'ugly' fallback in the
SpellCompiler ... since that one is a custom rule"): **cards with no carrier after them are now
wasted**, as a trigger with no carrier is, and a staff of only an infusion does not cast
(`fire · blast` alone does nothing; `fire · blast · pulse` sends a fire ring out round you and
explodes where it ends).

It is **one carrier**, `pulse` (`pulse.gd`, `CarrierPulse`; owner: "One carrier!"), with fixed
yes/no answers like every other: it `HITS`, `LASTS`, has a `SPEED` and `PIERCE`, `GUARDS` and `MEETS_SHOTS` (as
a slam's ring), `REPEATS_HELD`, and goes out `AOE`: all round the point it is cast at, not along an
aim (a scatter turns nothing there; the AI reads it as an area round its caster; Return and Ghost
work on it as on a shot). Its rows are its own (as the slam's): `launch` starts a ring, `step`
runs it, and the looks read the `pulse_*` getters.

- **Where:** the point it is cast at: where what casts it stands then (the caster's body; in a
  payload the body or shot that fired it, else the payload's point). It stays there (owner: "from
  the cast point").
- **Its ring:** its radius grows as a shot flies, `speed` on the shots' speed curve over its
  `lifetime` (owner: "using easing as bolt/atom"; `ProjectileManager.speed_factor`,
  SpellLimits.SHOT_SPEED_* times its cards' `speed_start`, `speed_end`, `speed_ease`), so a plain
  Pulse reaches 48 px (120 px/s for 0.4 s; the curve keeps its mean). Its edge, `radius` wide,
  strikes each body it crosses once (owner: "It should not hit instantly"): only what the edge
  sweeps in a step counts, never a body that comes in behind it ("only the swept band should
  count"). It strikes where its edge meets the body, outward from its centre
  (`CarrierKit.strike_bodies`), so what the hit sets off (`on hit`) leaves from there ("It should
  fire from the edge"), and it spares the body it starts on, as every carrier does (`Spells._launch`:
  the caster, "Yes it spares its caster"; for a payload, the body it starts touching). A body is
  judged by its own shape, a box's sides or a circle (`HitShape.sides`). A bare Pulse strikes for
  its card's small damage.
- **Segments:** the ring is SpellLimits.PULSE_SEGMENTS segments, each a line out from its centre
  stopped on its own (owner: "the ring should be 'individual' motes, that can be blocked
  individually"): at the first wall on its line (set when it is cast; Ghost takes it through) and
  at the first body it strikes ("if an enemy is hit, that segment should stop propagating out
  (unless pierce is on, obviously)": with Pierce it passes that many bodies, `PIERCE`). Bodies are
  judged nearest first, so a wall or a body shadows what is behind it and the rest of the ring
  goes on. Feel draws it as motes along its edge where it is now and a trail of tail motes over
  the band its edge swept since the last frame, laid by area as a shot's tail is by distance
  (owner, 2026-11-13), only where its segment still reaches (`gameplay/feel/pulse_rings.gd`, from one typed read a frame: `CarrierPulse.read_view`,
  a `PulseView`, as the portals' look reads a `PortalView`). Its guard of shots (below)
  follows them too ("They should follow the segments too"): a shot behind a wall or a struck body
  is not turned or stopped.
- **Shots:** while it is out, a deflect on it turns the shots of other teams its edge sweeps that
  its segments reach outward, a shield stops them while its charges last (as a slam's ring;
  `CarrierKit.guard_shots`). A shot that comes in faster than
  the ring grows reaches its caster first: a guarding Pulse is cast ahead.
- **Return** grows it for half its life, then shrinks it back to its centre at the speed it had
  then, striking again what its edge crosses on the way in, its segments as when it was cast (a
  body it struck may have moved), as a returning shot flies home.
- **Not aimed:** Scatter, Mirror and Nova turn nothing on it (`AOE`; `CompiledSpell.nova_ways`,
  `mirrors`): one ring already goes every way.
- **Its end:** when its life is out (or it is home), its `blast` goes off at its centre, hitting
  whoever is there, its caster too, as every blast does (owner: "Why did you add an exception for
  blast to spare its caster?"), and its `on expire` fires from there.
- **Its triggers that fire while it lasts** (Timer, On Hurt, On Recast, On Near) fire from its centre
  (`LC_ROW`, `tip_of`). What its end and those triggers fire is cast by that point, as a slam's end
  or a beam's tip: a bolt they send hits a wizard still standing there (owner: "the bolt should hit
  the wizard if he is still standing at the cast point"). Its own strikes are cast by what cast it,
  as a slam's (a pull on its hit moves that).
- **Hold** casts it again every wind-up and life (`REPEATS_HELD`): `hold · fire · pulse` rings out
  round its wizard again and again.

**What fires a payload** is decided by the runtime each time it fires:

| Trigger | The payload is cast by |
| --- | --- |
| `on cast` | whoever cast the carrier |
| `timer`, `on hurt`, `on recast`, `on near` (toward the foe that set it off) | its own shot, its own body (a decoy), or what it moves (the shot that cast it, else the wizard's body); a beam's or swing's tip, a familiar, a portal: a point; a Pulse: what it is round |
| `on expire` | a move's end: what it moved (the wizard's body, or the shot); a shot with `pull`: what it pulled there; a Pulse: what it is round; anything else: a point |
| `on hit`, `on kill`, `on reaction` | a shot that flies on after its hit (it pierces, sticks, or its hits never spend it: a wall), what a move moves (a dash's pass and a teleport's landing are that body's or shot's strikes: `Carrier.hit_caster`), else a point |
| `on wall` | a shot that bounces on, else a point |
| `on block` | the shot whose shield stopped one, or the body its barrier is on (a decoy, a dashing or teleporting wizard); a deflect's block is a point's |

**What fires a payload casts all of it**, every carrier in it (owner, 2026-11-06): a
payload fired from an actor's body (a decoy's own, or the wizard's for a dash's timer, `on hurt`
or end, a barrier's block) is cast by that body, the way a staff's own cast is cast by the
wizard's: a dash, teleport, pull or swap in it moves that body, a circling carrier (Orbit) or a
familiar circles and follows it, a returning shot comes back to it, a beam, swing or slam is held by it, recoil pushes
it. A shot casts its payload the same way, as before. Only a point moves nothing (a move cast by
one moves the wizard, rules R4c). The payload's actor stays the wizard: kill credit, budgets,
colours and tag.

**The caster is one value**, the kit's `caster()`, for every carrier: the actor's own body
(`SpellRuntime.CASTER_BODY`), another actor's body (`SpellRuntime.body_caster(id)`), a live shot's
slot, or `CASTER_POINT`, carried through delayed fires and kept by the rows a caster holds. A
carrier reads it with `SpellRuntime.body_of(caster, actor)` (the body, or -1), `caster_shot()`,
`caster_body(actor)` and `caster_place(actor, origin)` (where it is now); `CasterMoves.moved_by` is
the one rule for what a move moves; `shot_caster(slot)` is who cast a shot that hits (its pull or
swap). **Everything a launch makes remembers who cast it:** a shot by the projectile manager's
caster, and a row a carrier keeps (a held beam, a swing, a slam, a dash's pass) by the caster and
seq it was launched with; each later step of the row, its zaps and a move's landing run between
`kit.cast_as(caster, seq)` and `kit.cast_done()`, so a pull, swap or payload on those hits reads
that caster, not whoever is casting when the step comes (owner, 2026-11-06). A shot's hit is
handled as that shot's caster too, so a chain jump belongs to the shot it jumped from (a ray's
waiting jump keeps the caster of the hit it came from).

`tests/core/test_card_rules.gd` plays every modifier and infusion on it with the Pulse card after
them (the columns `pulse`, round you; `on it`, a piercing shot's hit, and `on its body`, an
`on cast` the wizard's body casts), and the card's own test
(`content/spells/carriers/pulse/test_pulse.gd`) checks the rest.

## What a carrier runs

At runtime `Spells` makes its own carriers (`Carriers.make_all`), binds them and hands every launch
to its carrier. Nothing in `spells.gd` asks which carrier a spell has or names one
(`tests/core/test_carriers.gd` checks it). A carrier overrides what is its own:

| Hook | Default | Overridden by |
| --- | --- | --- |
| `launch` | a fan (or ring) of `spell.shots`, each made by `shoot` | portal (a mouth and its exits, gates of the projectile manager), dash and teleport (a move, `CarrierMove`), wall (one solid line) |
| `shoot` | a shot flying along its heading | rune (still, placed ahead), pool (still, spread `ray_length` ahead, never spent), beam, swing, slam (a row of their own), decoy and familiar (a body, `CarrierEntity`) |
| `on_hit` | nothing | hook (pulls its caster), swap (trades places) |
| `on_move_end` | nothing | teleport (strikes where it lands) |
| `step` | nothing | dash (strikes what it passes), beam, swing, slam (their rows), pool (forgets what it touches every `POOL_TICK`, so it strikes it again), portal (moves what went into its gates) |
| `end_of`, `end_actor`, `clear`, `reset_actor` | nothing | dash, teleport, beam, swing, slam, decoy, familiar (what they keep) |
| `hit_caster` | the point | dash and teleport (`CarrierMove`): what they move casts their hits' payloads |
| `switch_off` | nothing | beam, swing (end), decoy, familiar (asked to end): a held carrier switched off |
| `reach_of` | 0 | atom, beam, swing, slam (for an enemy's telegraph) |
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
| The cast under way | `spell_of(tag)`, `carrier_of(spell)`, `caster()` (the one caster value), `caster_seq()`, `caster_shot()`, `caster_body(actor)`, `caster_place(actor, origin)`, `shot_caster(slot)`, `pick_target(actor, at, within)` (a one-off homing pick: any enemy in reach, at random, afresh each time), `cast_as(caster, seq)`/`cast_done()` (a row steps as its caster), `is_echo(spell)`, `shot_started`, `shot_ended` |
| The aim | `aim_origin`, `aim_dir`, `aim_pivot`, `aim_seen`, `walk_turn` (by actor) |
| Shots | `fan_angle`, `staff_spread`, `placed_at`, `land_shot` (every carrier that spawns a shot: a wall makes its row solid first) |
| Hits with no shot slot | `ray_begin`/`ray_end`, `cast_jumps`, `strike`, `strike_round`, `guard` (with the carrier's `id()` as the blocking carrier, `Projectiles.impact_carrier`), `guard_path`, `turn_shots_round` (a deflect round one point, once), `bounces`, `ghost` |
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
3. Add its carrier card under `content/spells/carriers/` with `carrier = &"<name>"`, and its looks, all
   data on the card (`CarrierCard`): a `staff_pose` (`tests/core/test_staff_poses.gd` fails without
   one), its cues (`cast_cue`, the flash on the staff, `cast` by default; `shown_cue`, where it
   shows itself; `impact_cue`, where its shots strike, `impact` by default; `end_cue`, where a
   carrier with no shot ends; `tests/content/spells/test_carrier_looks.gd` fails for a cue that is
   not in `content/cues/`: one file per moment, flashes from `content/flashes/`), and a `look_shader`
   (a shader in its folder, `CarrierCard.look_shader`) if its shots are not drawn plain (a carrier says what draws its
   look, `Carrier.look_drawer`). A carrier with no shot to draw tells its moments for them:
   `carrier_shown` with its card's id (`spell.carrier_card_id`) where it shows itself, which plays its
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
(`StaffLook.tip_position`) or the strike's look (`carrier_shown`) is more than a pixel off the point
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

Removing a carrier is deleting its script. A carrier card that still names
it is refused by the validator.

## Adding a modifier behaviour or a trigger

Add the value at the end of `ModifierBase.Behaviour` (or `TriggerBase.Event`), implement it, and,
if it does not work on every carrier, say what it needs in `ModifierBase.RULES` "needs" (or `TriggerBase.NEEDS`), traits and cards alike. If it
needs something no flag asks yet, add the flag and answer it on each carrier.

A modifier that changes **how any carrier is cast or moves** (Nova, Skyfall, Orbit) is a module of
its own beside the runtime, not code in each carrier: `core/spells/skyfall.gd` and
`core/spells/orbit.gd` hold all of theirs, and the runtime calls them at a few marked lines (Orbit:
`Spells._land_shots`, which sees every row a carrier makes, turns each into a circler with
`Projectiles.set_orbit` before its other cards are set, and the beam's step asks
`CarrierKit.orbit_sweep`). No carrier knows about them, so taking one out is its file, its card
folder and those lines. What the card sets that any card could set is a general field, not the
module's (Orbit's 3 s is `ModifierBase.lifetime_base`).
