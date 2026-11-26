# Oil and Spill: the floor that burns

**Status (2026-11-26): built (this PR).** Part 1's second slice of [foundations.md](foundations.md) ("a floor that answers", the order's step 2), on the floor of [floor.md](floor.md) and its look of [floor-look.md](floor-look.md). Builds 2 and 3. With the owner's directions of 2026-11-25/26: everything touches the floor as it passes; a cell remembers who lit it; **Spill makes a shot touch a wide area where it lands** (a bigger splash); Oil "coats the floor where it lands. Burns long once lit."

## What the players see

- **Oil on bare floor is a slick.** An oil bolt, spray, Nova or dash leaves the floor oiled where it lands and along the way it goes (everything touches the floor as it passes). Oil does nothing by itself, to bodies or to the AI: the enemies walk over it. It lies long (30 s) and soaks in.
- **Oil and a match (build 2).** One fire atom into the oil and it catches; the fire runs through every oiled cell joined to it (about a cell every 0.12 s: a corridor of oil burns end to end in a couple of seconds), burns long (6 s), burns down and leaves the floor scorched. Whoever stands in it burns and is struck by fire; the enemies will not walk into it.
- **The fire road (build 3).** A dash with Oil lays a lane of oil behind its caster; a second staff (or a teammate) lights it: a wall of fire drawn by moving.
- **It is the lighter's.** A burning cell's harm is the caster whose fire lit it (or whose fire the spread came from), not the one who poured the oil: its kills count for `on kill`, Siphon on the lighting spell pays, the run's numbers name the lighter.
- **Spill: a bigger splash.** A carrier with Spill touches a wide circle of floor where it lands: a Spill water bolt makes a puddle 4 cells across where it hits; a Spill oil bolt a slick. It changes the floor only, never what it hits.
- **Water and frost put an oil fire out** (the owner, 2026-11-26): the flames go out and the oil is left, to be lit again.

## The new states of `floor`

`content/cover/floor/floor.tres`, beside the first slice's (floor.md). Each change of look is a state of its own that plays its frames (docs/STYLE.md, "Smooth"; 4 frames, whole pixels).

| State | Look | Gives who stands in it | Moves on |
| --- | --- | --- | --- |
| `dry` (rest) | nothing | nothing | water: `wetting` (as before); **oil: `oiling`** |
| `oiling` | oil spreads out from the slick's middle, 4 frames, 0.25 s | nothing | after 0.25 s: `oiled` |
| `oiled` | oil, its sheen drifting (6 frames at 4 fps) | nothing | oil: `oiled` again (its time from 0); fire: `catching`; after 30 s: `soaking` |
| `soaking` | the oil shrinks to its middle, 4 frames, 0.5 s; a faint stain left (Oil's shadow, 3 s) | nothing | after 0.5 s: `dry` |
| `catching` | flames creep in over the oil from the shore, 4 frames in 0.25 s; Fire light | burn | spreads fire to its neighbours, 8 a second; water or frost: `doused`; after 0.3 s: `burning` |
| `burning` | flames on the oil, a 6-frame loop at 12 fps; embers and smoke given off; Fire light | burn 3 for 2 s, every 0.5 s, and struck: fire, 2 damage, every 0.5 s | spreads fire to its neighbours, 8 a second; water or frost: `doused`; after 6 s: `burning_down` |
| `burning_down` | the flames sink into the soot, 4 frames, 0.5 s | burn | after 0.5 s: `scorched` |
| `scorched` | soot and cracks, its last embers winking out | nothing | oil: `oiling`; after 10 s: `scorch_fading` |
| `scorch_fading` | the soot shrinks to its middle, 4 frames, 0.5 s; a faint scorch left (Stone's shadow, 3 s) | nothing | after 0.5 s: `dry` |
| `doused` | the flames go out over the oil, 4 frames, 0.35 s; smoke | nothing | after 0.35 s: `oiled` |

- **The fire touches its neighbours** (`spreads = fire`), so it does what fire does to each: oil catches, grass catches, a puddle's edge boils away (steam), ice thaws. One rule, the cover's own; no row names a neighbour's kind.
- **Who lit it:** a fire's touch on oil makes the cell the fire's caster's (the touch that moves a cell sets its lighter, floor.md "Who lit it"); a spread hands it on; `doused` and `scorched` keep it, rest drops it.
- **Danger:** `catching`, `burning` and `burning_down` harm (not `harmless`): the AI's look marks them and the enemies walk out and around. `oiled` gives nothing, so the AI does not see it.
- **Lightning does not light oil** (the owner, 2026-11-26): fire is the one match, and lightning stays the lake's.
- **Oil on water, on ice:** nothing (a cell holds one state; the oil is lost on the water). Oil on `scorched` lays new oil.

## The cards

### Oil (infusion), `content/spells/elements/oil/`

"Coats the floor where it lands. Burns long once lit." (`description`: "Coats the floor where it lands. Burns long once lit.", 52 characters.)

| Field | Value | Why |
| --- | --- | --- |
| `status_id` | none | its point is the floor (as Mend has none: it heals; Oil coats) |
| `damage_scale` | 0.6 | a coating, not a blow: an oil bolt is a weak bolt |
| `tint` | Oil's base | a new palette material, below |
| `look_id` | `slick` | drips that hang and fall, the sheen catching the light; its own look, once the look slots were widened (the owner's answer 4 below) |
| `complexity` | 2 | a card for a second staff or a teammate |

- **A new palette material, Oil** (docs/STYLE.md: new element colours are added when their spells are built): a dark umber with an amber sheen, `#211a1e`, `#4a3729`, `#b88a3e`. Far from Wood's reds and Blight's ochre in its base, the darkest base of the palette (a slick reads as a hole in the floor's light).
- `test_elements.gd` asked every element of no status to heal; it now asks that it heals or that some cover kind answers it (an element row in a `CoverKind`), so Oil passes by its floor rows.

### Spill (modifier), `content/spells/modifiers/spill/`

"The next carrier splashes wide where it lands." (`description`, 46 characters.)

- **A behaviour, `spill`** (`ModifierBase.Behaviour.SPILL`, `behaviour_strength` 32 px; stacks by adding: two Spills are 64 px). Every touch of the floor the carrier makes where it lands (`floor_touched`: a shot's end, a ray's end, a blast, a pulse's ring, a pool) is `behaviour_strength` px wider; a carrier that only passes over the floor (a dash, a swing, a beam, a slam) touches that wide where it lands (`CarrierKit.land`). Its passing touches along the way are unchanged, one cell each.
- `mana_mult` 1.25, `complexity` 2, `look_id` `ripple`.
- **It needs an infusion on its carrier**: with no element nothing touches the floor, so Spill alone is wasted. A new key of a needs row, `"infused": true` (`ModifierBase.RULES`, `Carrier.works`), read by the compiler as `on reaction`'s `or_infused` is.

**What Spill does on each carrier** (docs/CARRIERS.md, "needs": `{"not": SPAWNS | GATES, "infused": true}`):

| Carrier | Where it lands, with Spill |
| --- | --- |
| atom, bolt, rune, orbit's shots, wall's stones | each shot's end: wider (`_touch_end`) |
| spray | where it pours, over its cone's end: wider |
| pool | where it lies and on its ticks: wider |
| pulse | its ring where it goes off: wider |
| any carrier with Blast | the blast's touch: wider |
| a ray (a beam's first strike) | its end: wider |
| beam | its end, where it ends |
| dash | where it ends |
| teleport | where its caster arrives |
| swap | its shot's end, where it hits |
| swing | its tip, where the sweep ends |
| slam | its impact point |
| decoy, familiar, portal | nothing: they make a body or a gate, whose own cards are their payloads' (wasted, the builder shows it) |
| field (Part 3, in parallel) | nothing: a still shot that touches no floor of its own; its trait `GIVES` joins Spill's "not" with whichever lands second |

## The engine work

- **`ModifierBase.Behaviour.SPILL`** and its RULES row, with the new `"infused"` key; `Carrier.works(behaviour, blasts, infused)`; the compiler hands whether the carrier has an infusion that counts (`_elements_on`) to `_modifiers_on`; `card_works` answers a card alone (Spill alone: wasted). `test_behaviour_table.gd` knows the key.
- **Spells' `_touch_floor`** adds the spell's Spill to every landing touch; **`CarrierKit.land(spell, tag, actor, at)`**, where a carrier that touched no floor of its own ends (a beam's end, a dash's or a teleport's, a swing's tip, a slam's impact), goes off as its blast, or with none touches Spill's width round it (nothing without either). No new state: Spill is a compiled number.
- **A spray pours on the floor** (the first slice's order named it, but a spray touched nothing: it strikes its cone at once, with no shot): along its middle (a passing touch, `floor_passed`) and over its cone's end (`floor_touched`, within a quarter of the cone's width there: about a cell at a spray's reach). So `oil · spray` lays oil down a corridor (build 2).
- **No change to the trail pass or its native kernel**: what passes still touches one cell; Spill changes where a carrier lands. No new member of the simulation; the floor's states are data.
- **The combo arena gets a floor** (`"floor": true` in a combo: the real cover area with the `floor` kind under the combo, its imps in the actor table so the floor's statuses and strikes reach them), so a card whose point is the floor has combos that show it.

## The look (gameplay/feel)

Three new surfaces (`CoverState.FlatSurface`: OIL, FIRE, SCORCH; a branch each in `cover_flat.gdshader`'s `surface`), drawn at 64 px a 32-unit cell in single art pixels (floor-look.md's standard):

- **Oil:** a dark slick lying in the floor (its shadow under the upper left bank as water's), a rim of its light inside the lower right one, and its sheen: thin diagonal streaks of its light that drift a pixel a frame (6 frames at 4 fps), each from its own phase, broken by a hash so they never line up across cells.
- **Fire:** flame tongues over the oil: columns of Fire rising from the cell's lower edge, each a hashed height that flickers frame to frame (6 frames at 12 fps), Spark's light at their roots and Bone's white heat at the hottest; its light Fire, 0.45. `catching` grows the flames in from the shore (`GROW_IN` over oil); `burning_down` shrinks them off the soot (`SHRINK`, under: Stone).
- **Scorch:** Stone's shadow soot speckled with its base, cracks a pixel wide, and embers (Fire's light pixels) that wink out over its first 2 s.
- **Motes, a few:** burning's embers (2 a cell a second) and smoke (1), doused's smoke, through the cover's motes (at most 48 a frame for all the cover; Low none).
- **Marks:** `soaking` leaves Oil's stain, `scorched`'s end Stone's scorch (`flat_trace`).

## Numbers

| What | Number | Why |
| --- | --- | --- |
| Oil lies | 30 s, then 0.5 s soaking in | "a long while": laid in one room's fight, lit in the next wave |
| Catching | 0.3 s | as grass |
| Burning | 6 s | "burns long": three grass fires' time |
| Its harm | burn 3 for 2 s every 0.5 s, and fire 2 every 0.5 s | grass is burn 2; a strike so on kill and Siphon count |
| Its spread | 8 a second a neighbour | a corridor of 20 cells burns through in about 2.5 s |
| Scorched | 10 s | a mark of where the fire was |
| Spill | +32 px a card | a bolt's 6 px end touches 1 cell; with Spill about 13 (4 across) |

## Tests

- `content/spells/elements/oil/test_oil.gd`: the card's data; an oil bolt oils its way and its end; a fire bolt lights it and the fire runs through joined oil and not past its edge; burning harms who stands in it as the lighter's (status and strike, the tag of the fire's spell); it burns down to scorched and dry; water and frost douse it to oil; oil renews; lightning does not light it.
- `content/spells/modifiers/spill/test_spill.gd`: the card's data; Spill alone is wasted, with an infusion it is kept; on every carrier card the registry finds where it is kept, a cast with Spill touches the floor at least 32 px wider than without (`floor_touched`), and where it is wasted (decoy, familiar, portal) nothing changes; two Spills add.
- `content/cover/floor/test_floor.gd`: the oil rows of the table through the real area.
- **Build 2** and **build 3** (`tests/gameplay/cover/test_floor_builds.gd`): `oil · spray` held down a corridor, then one `fire · atom`: the corridor burns end to end, the dummies in it are struck as the atom's caster's, and a kill is that caster's (`kill_landed`); a dash with Oil lays a lane, a second staff's `fire · bolt` lights it: a burning line along the dash's way.
- The combos: Oil's two (`oil_and_a_match`, `oil_pool_spark`) and Spill's two (`spill_puddle`, `spill_oil_match`) in the combo arena's floor.
- `tests/core/test_card_rules.gd`: a probe for Spill (it plays every card on every carrier; Spill alone is wasted everywhere, and forced on it changes nothing with no element).
- `tests/gameplay/feel/test_floor_look.gd`: the new states' looks as data (a surface, a glow, a mark each); burning lights a patch in Fire; scorched leaves its mark.
- The determinism, snapshot and content-determinism tests play the new cards and states as they are (state by default; no new member).

## Measures

- **A burning field:** 400 oiled cells lit at once, the cover's step while all burn and spread (`test_floor_budget.gd`, printed; budget: under 4 ms a tick on a loaded CI machine).
- **Spill's touch:** a 38 px touch is about 20 cells; 8 bolts of a Nova with Spill landing in one tick, the cover's step printed beside the first slice's.

## The owner's answers (2026-11-26)

1. **Water and frost on burning oil:** they put it out (the flames go out, the oil is left to be lit again), as they put out burning grass; a fire still catching too (built).
2. **Lightning and oil:** lightning does not light oil; fire is the one match (built).
3. **Oil on a body:** nothing (built). A later card could make an oiled body burn longer.
4. **Oil's particle look** (on #948): widen the look slots so Oil's shots get a look of their own (sheen and drips). **Built (the PR after #948):** a look channel of the shots' instance colour carries 10 bits instead of 8 (`ProjectileManager.LOOK_CHANNEL_BITS`, n / 1023: a MultiMesh colour channel keeps ten bits whole, measured on the web's renderer, 1024 of 1024 values; the desktop's stores floats), so the look holds 30: kinds 1 to 28 and the two flags at the top (the enemy ramp, kind 29; Feel's EXACT, kind 30). Oil's look is kind 23, `slick`: a heavy drip that hangs under the shot, stretches to a string and falls, its top catching the light (`shot_particle.gdshaderinc`), and its motes, `content/motes/oil_drip.tres`. Oil is the eighth palette material the shots' and the light's nearest-material match know. Mirrored to the bit in the native kernels (`shot_kernel.cpp`'s look colour, `light_grid.cpp`) and the light grid's compute shader; `test_projectile_looks`, `test_light_grid` and `test_native_kernel` hold them.
5. **The flames' look** (on #948): ART2 redraws them later; they stay as built here.

**Field (Part 3, in parallel):** a field is a still shot that touches no floor of its own, so Spill is wasted on it; whichever of the two lands second adds the field's new trait (`GIVES`) to Spill's "not" (`test_card_rules` names it).
