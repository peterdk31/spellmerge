# Spell spectacle, part 2: one particle system, spectacle by card

**Status: the owner's direction of 2026-11-04** (after the P1c, P1d and P2b integration and its two reviews). The owner asked whether the motes are a good addition, whether they could be better, and whether older effects should move to them, and answered:

- **Q1:** "Particles off" may become a minimal ring of motes instead of the old effects, so the older particle effects fold into the motes and every particle has one code path: "Yes!"
- **Q2:** how a card gets motes and marks of its own when the shots' look bits are full: "Figure this out in the best possible way!" (the design is S2 below).
- **Q3:** plan the follow-ups: "Yes".

The owner's goal for this part: "It should be easy to add new effects, and when adding new content, there should be minimal coupling to this code, so it is easy to add 'unrelated, but related' code in the future."

Like part 1, this changes no damage, hit, rule or card behaviour. Everything here is drawn.

## What is wrong today

The integration's design review (2026-11-04) found:

- **Feel is one 2,600-line node,** and the motes, the marks and the light added about 300 lines of settings setters, pool creation, registry reads, cue-part readers and colour lookups to it. A new cue part type means editing `play_cue`'s if-chain and `CueBase.problems()`. A dying body's colours reach the cue parts through a side channel (`_cue_surface`).
- **The motes are keyed on the shots' look layers,** the 21 bits of `Projectiles` look (`LOOK_EMBERS` to `LOOK_DRIFT`) plus three flags, all 24 used. A card can only have motes of its own by owning a look layer, and there are none left. Every card on one layer sheds the same motes.
- **There are 16 mote kinds at most** (`MAX_KINDS`: the kind numbers are uniform arrays in `mote.gdshader`), 7 used. A kind must name a look layer or be a surface kind, so a kind for one cue (ash) cannot exist, and every room's walls throw the same chips.
- **Two particle systems run side by side.** Feel's effect batch draws particles of its own (`KIND_SPRAY`, `KIND_PUFF`, `KIND_CHIPS`, `KIND_DEBRIS`, `KIND_SCORCH`, `shot_effect.gdshader`), and the trail shader still draws its 22 particle kinds when motes are off (`shot_trail.gdshader`, the spark pool `PARTICLE_CAP`). With Particles off the game falls back to the old ones, so every particle is drawn two ways, each with its own tests. A hit draws both a spray effect and motes.
- **A mote costs the CPU a GDScript row write** (about 2.5 us in a fight, `FRAME_ROWS` 288 a frame), so a cue's burst of 40 motes is 40 writes.

## S1: The spectacle node (refactor, first)

A home for motes, marks and light, and for whatever drawn-only effect comes next, out of Feel.

- `gameplay/feel/spectacle.gd`, a child of Feel like `swing_trails.gd`: it owns the ramp table, the mote pool, the mark layer and the spell light, their settings (MoteCap, MoteDensity, FloorMarks, SpellLight) and their events. Feel keeps `motes()`, `marks()` and `light()` for the tests, as forwards.
- **Cue parts by table.** `play_cue` hands each part to a handler from a `{part: Callable}` table that each system adds itself to (`Spectacle.add_part(&"motes", _cue_motes)`); a part with no handler is an error. `CueBase` checks a part's keys from a table of part types (`CueBase.PART_KEYS`), so a new part type is one handler and one table row, and P3b's light parts edit neither `play_cue` nor `problems()`.
- **The cue's context as a value.** A `CueContext` (caster, shot, at, dir, size, tint, look, the colour source of what broke) is handed to each part handler, in place of the `_cue_surface` side channel. One `CueContext` is kept and reused (no allocation per cue).
- **Stepped settings share one helper** (`index_of`, `snap`, `word_of` over `STOPS` and `WORDS`) for MoteCap, MoteDensity and ShotCap.
- Tests: the existing ones run unchanged through the forwards; a test plays a cue with a part type added at run time; a test that `play_cue` errors on an unknown part.

No look changes: the screenshot sheets (`shot_motes`, `shot_mote_sources`, `shot_marks`) are pixel for pixel the same before and after. **Built** (DECISIONS, 2026-11-04, "The spectacle node and cue parts by type"): the sheets are not the same from run to run on any branch (real-time clocks), so the check is a trace of every mote and mark row over a fixed list of events, the same on main and after S1. The spectacle does not listen to the hit events itself; Feel's handlers still call it, in their order. An unknown part type is warned of, not an error.

## S2: Spectacle by card (the owner's Q2)

**The idea:** a shot's motes and marks come from **its spell's cards**, looked up through the tag every shot already carries, not from bits packed into its look. The look bits stay what they are, how a shot is drawn in flight; the motes and marks stop depending on them.

- **Kinds name cards.** `MoteKind` and `MarkKind` gain `cards: Array[StringName]`, the ids of the cards (forms, elements, modifiers) they belong to, beside today's `look_layers`.
- **A card's kinds:** the kinds that name its id; if none, the kinds that name its `look_layer` (today's rule, so every existing card keeps its motes with no edit); if none, layer 0's. A spell's kinds are the union of its cards'.
- **Worked out once per spell.** At an event the shot's tag gives its spell (`Spells.profile(tag)`, already in core), and the spectacle node keeps each spell's kinds by tag together with the spell they were worked out for. A tag's build generation is a ring of 8, so after 8 rebuilds of one staff a tag can name another spell: an entry is used only while `profile(tag)` is still the same spell, and worked out again otherwise. The cache is cleared when it grows past a bound. At a hit, an end or a wall the cost is two lookups, which replace P1c's per-look cache.
- **Shots with no spell** (enemy attacks with gameplay/ai tags, the sandbox's and the benchmarks' shots) keep the look-layer rule.
- **Trail motes** (P1d): a birth also carries its shot's tag (`SPARK_B_TAG`), so a trail's motes are its cards' kinds too. The birth's look kind picks among them as today: the spell's kinds for that layer.
- **Marks by card** the same way: a `cards: true` mark part stamps the marks of the cue's spell's cards.
- **No kind limit.** The kinds' numbers move from uniform arrays to a data texture (one row a kind, like the ramp table), so `MAX_KINDS` goes from 16 to 256 and the shader's arrays stop growing with content.
- **A kind may be named only** (no cards, no layers, not a surface kind) and be thrown by a cue that names it: ash for a fireball's cue, splinters for a staff breaking.
- **Surface kinds by room.** `RoomBase.surface_kinds` (mote kind ids, empty for the default surface kinds), so a wooden room's walls shed splinters and the crypt's chips.

**Adding content after S2** (the owner's goal):

| To add | Files | Code |
|---|---|---|
| A mote kind | one `content/motes/*.tres` | none |
| A card's own motes | one `content/motes/*.tres` naming the card | none; the card's file is not touched |
| A mark | one `content/marks/*.tres` | none (a new mark *shape* is a shader form) |
| A cue with motes and marks | one `content/cues/*.tres` | none, if something plays it |
| A new part type (light, sound, ...) | a handler and a `CueBase.PART_KEYS` row | in its own system's file only |

Why this way and not a per-shot effect id in core/projectiles: a per-shot id costs an array in the manager, a write at every spawn and a field in the native kernel's layout, and the spell table already answers "which cards fired this shot" through the tag. Looking it up at the event costs two lookups where a hit already costs tens of microseconds.

Tests: a kind naming a card is shed by a shot of that card's spell and by no other; a card with no kind of its own sheds its look layer's; an enemy shot sheds its look layer's; a trail birth of a spell's shot gives off that spell's kinds; a rebuilt staff's spell gets its new cards' kinds, also after its generation ring wraps (8 rebuilds); every card id a kind names exists (the registry); 32 kinds load and draw (the texture).

Measured: the storm with S2 against without, the CPU of Feel's hit handlers in `sandbox_storm.gd -- --motes`.

**Built** (DECISIONS, 2026-11-04, "Spectacle by card"): as above, in `gameplay/feel/card_kinds.gd` (the spectacle's `cards`), with these changes. A spell is checked against `profile(tag)` once a frame, not at every hit, and each answer is kept for the frame by its tag and look, so a hit costs about what the look's lookup did (a rebuild is seen the next frame). The tags reach Feel as `Projectiles.impact_tag` (while a shot's impact or end is sent), `Spells.cue_tag` (while a blast's `cue_shown` is sent), the events' own tag or shot, and the births' `SPARK_TAG` (two floats: a spell's tag is above what a float holds whole). A `motes` cue part gains `colours` (`spell` or `surface`), so the fireball's `ash`, a kind that names nothing, cools through the colours of what burned. Two kinds came with it: `ash` and `grit` (heavy's own, a demo of a card's motes). Marks keep their 16-kind arrays: they are few and none is drawn per mote.

## S3: One particle system (the owner's Q1)

Every particle is a mote; the old particle paths are removed.

- **Particles off becomes a minimal ring:** `MoteCap`'s stops become Minimal 2,048, Low 8,192, Medium 16,384 and High 32,768 (0 is gone). The motes always exist, so nothing has a "motes off" path.
- **Trail particles:** the trail shader's particle kinds are removed and the trails are the tail line and the dashes' streaks only. The spark pool (`PARTICLE_CAP`) stays only as the births' share, renamed for what it does. `spark_motes_below` and the trail mesh's particle slots go.
- **The hit spray and puff** (`KIND_SPRAY`, `KIND_PUFF`): a hit's motes are its spray (one look, not two); the puff of a hit with no way is a ring of motes.
- **Chips, debris and scorch** (`KIND_CHIPS`, `KIND_DEBRIS`, `KIND_SCORCH`): chips and debris are surface motes, scorch is a mark.
- **Death disintegration:** measured and tried as motes in the body's own art colours (`colours_of_art`), kept as it is if the motes cannot keep its pixel-by-pixel look.
- **Kept in the effect batch:** the flashes, rings, blasts, casts, arcs and status marks, which are shapes, not particles.
- Each removal is its own commit with a screenshot sheet before and after for the owner's eyes, and the tests of the removed path go with it.

Measured: `trail_gpu.gd` at 60, 400 and 3,000 shots and the storm, before and after. The trail shader without its particle code should be cheaper still.

**Built** (DECISIONS, 2026-11-04, "One particle system"): Particles' least stop is Minimal (2,048), and nothing has a "motes off" path; the trail shader keeps the tail, lightning's line and a dash's speed streaks (a dash's cards are births like a shot's, the owner's ask); a spray's and a puff's sparks are motes thrown with their flash; an explosion's fragments are its surface motes and its scorch a mark; a dead body breaks into motes of its own art (kept: the owner said it need not look the same, only good). The flashes' and bursts' own sparks, runes' and beams' card particles are still the shaders' (a follow-up). Trail shader 760 to 583 lines, blast shader 368 to 259, Feel 2,423 to 2,328.

## S4: A burst a row (an experiment, measured)

Today a mote is a row and every row is a GDScript write. Instead, one row could hold a whole burst: where, which way, the kind, the count, the seed, the source and the time. A burst's batch draws a mesh of `BURST_QUADS` quads (16) a row, and the vertex shader works out each mote from the row, its quad's index and the seed, as the trails already work out their particles. A burst of 40 is three rows instead of 40, and the quads past the count are folded away.

- The CPU cost becomes a write per burst, not per mote, so `FRAME_ROWS` could go up or away and a blast could throw hundreds.
- Settled motes still need each mote's resting point. Either the CPU works it out for the settling kinds only (as now, from the same seed), or the mark layer draws the frame's resting motes from the burst rows itself (one draw into its viewport on frames when motes come to rest).
- The cost moves to the GPU's vertices: 16 quads a row drawn or folded. That is measured against the CPU it saves.

Merged only if the storm's CPU drops and the GPU time on llvmpipe and the Intel UHD does not grow more than that; the result goes in DECISIONS either way. After S3, so fewer callers write rows.

## S5: Do shots need tails? (the owner, 2026-11-04)

The owner asked whether the shots need tails at all now that they shed motes. After S3 the trail shader draws only the tail line and the dashes' streaks; the tails have been the shots' largest GPU cost (DECISIONS, 2026-11-02: their vertex count, drawn or folded), and the manager uploads every shot's recent positions for them each frame (`trail_data`). Without tails, that budget could go to motes instead: more births a shot in busy fights, so a fight of thousands of shots keeps the look of a fight of tens (the owner: "This might also allow us to increase motes in busier fights, so the visual look will stay the same for more projectiles").

**What a tail does that motes don't:** it shows at a glance which way a shot flies and how fast, which matters most for dodging enemy shots with small (3-5 px) cores and four players; and it carries the caster's colour (staffs B6a). Motes drift and scatter. At high shot counts the spark pool's share thins each shot's births, so in the busiest fights most shots would show nothing behind them unless the motes get the budget the tails leave. The owner chose "long cooling tails" for the carriers' look on 2026-10-27; this asks that again.

**Steps:**
1. **The ceiling:** a "no tails" switch on the projectile manager (`tails_enabled`), in `trail_gpu.gd` and the storm runner: the GPU and the CPU a frame with no tails at 60, 400 and 3,000 shots, against today's. With no tails the manager writes no trail rows and draws no trail batches (the dashes' streaks are part of the question too: measured on and off).
2. **Motes with the tails' budget:** with tails off, the births' share no longer thins with the shot count as the spark pool's share does now, up to what the measured GPU and the motes' CPU allow (a frame's rows, `FRAME_ROWS`; the native module writing births if GDScript is the limit). Measured the same way.
3. **A dev switch to play with:** "Tails: on / off" in the pause menu's dev rows (as the other dev switches), saved, so the owner can play the sandbox and a horde fight with tails off, enemy shots included. A screenshot sheet is not enough: whether shots read is about motion.
4. **The owner decides:** no tails; short tails; tails only where they matter most (enemy shots, fast shots); or tails below a shot count and none above it. The pick is built in its own PR; DECISIONS records the figures either way.

5. **The dash** (the owner, 2026-11-04: "Can the dash also just be motes? Since a dash can also carry elemental effects", and "could the dash streaks become a cue?"). Its moments become cues and its path becomes motes:
   - **Moments as cues:** the dust where a dash starts and the ring, Spark's arc and the element's flare where it lands are hardcoded in Feel today (`_on_caster_move_finished`, the `form == &"dash"` branch of `_on_form_shown`). They become two cues, `dash_start` and `dash_land`, named by the dash card's `cast_look` and `impact_look`; their `kind: spell` motes and `cards: true` marks come from the dash's cards (S2), so a fire dash throws embers and may leave a scorch. Feel loses its dash code.
   - **The path as motes:** a dash bends (the wizard steers it), so its streaks cannot be a cue at one point. S3 makes the dash's particles births like any shot's; the streak look becomes a stretched mote kind (short life, drawn along the way it flies) in those births, so with tails off a dash needs no trail shader at all.

**Built** (DECISIONS, 2026-11-04, "Do shots need tails?"): steps 1-3 and 5. The switch (`set_tails_enabled`, the pause menu's "Tails" row, on by default) and its ceiling: with the tails off the trail batches' GPU time is about a third at 60 shots and less than half at 400 and 3,000 (llvmpipe), the storm's frame 8.3-8.5 -> 7.1 ms. With them off the births' pool is `TAILLESS_PARTICLE_CAP` (2,048): twice today's births in a busy fight for still about half the GPU. The dash's moments are its card's cues `dash_start` and `dash_land`, its streaks are the `streak` mote kind given off along its path, and its trail is not drawn. **Step 4 is the owner's:** play with "Tails: Off", then pick.

## S6: Every moment a cue (the owner, 2026-11-04)

The owner asked for every other system that can be replaced to be added. A survey of main (2026-11-04) found the drawn moments that are still special-case code in Feel or particles inside shaders. Each one below becomes data: a cue (`content/cues/`), a cue part, a mote kind or a light source, so its look is a file. Ranked by value (the most special-case code removed, the most content made data). Each item is its own commit with a screenshot sheet before and after; the hit path's items are measured in the storm (`play_cue` costs a lookup and a call per part).

| # | Today (main) | Becomes |
|---|---|---|
| 1 | Reactions: a puff, a ring and motes in the reaction's colour, shake, hold and sound, from preset dictionaries (`_on_reaction_triggered`, `_show_ring`, `Spectacle.reaction_motes`, six `FeelPreset` fields) | One cue per reaction (`reaction_<id>`, or `ReactionRow.cue`), with a `color` on its parts. A reaction's `power` scales the cue's size; a rule for what `power` scales (counts, hold, shake) is written once in `play_cue`. The repeat throttle and the reaction's name stay code |
| 2 | Cast and impact looks: the cast flash, ring and camera kick (`_on_spell_cast`) and the impact burst, ring and rune burst (`_show_impact`), from a second mini-format beside `cue` in the forms' `cast_look` and `impact_look` (`size`, `seconds`, `ring`, `grow`) | A form's `cast_look` and `impact_look` become one cue id each, with default cues `cast` and `impact`; the kick becomes cue data. The `form == &"rune"` branch and `wall_spark_size` go. **The hottest path:** measured in the storm before it merges |
| 3 | Particles inside the flash shader: `effect_spark` (burst, cast, rune burst, poof, quake rubble, rise and fall) and its card particles (`shot_effect.gdshader`) | Motes parts in the cues of 1, 2 and 5; the shader keeps the flash's shape and its light. After S4 (the rows' cost) |
| 4 | Which effects light the room, by Feel's effect kinds (`SpellLight.EFFECT_LIGHT`, `BLAST_LIGHT`) | A `light` cue part (strength, reach, seconds, colour) through the part table, so content can light a rune or a heal. Today's free mirroring of the effect rows stays the default; the part overrides it |
| 5 | A bolt or orbit running out of life: a pop and its motes (`_on_projectile_expired`, `POP_*`) | A cue `expire` (a burst part and a motes part with a `share` key) |
| 6 | The extra puff in `enemy_hit_color` after an enemy's death cue (`_on_enemy_died`, `_upgrade_hit`) | A part of `enemy_death.tres`. After S3 (puffs become motes there) |
| 7 | Possession: the rings and sound on the possessed body (`possess_started`, `possess_ended`) | Cues `possess_start` and `possess_end` |
| 8 | Lightning arcs: a discharge's arc and a zap's spark (`discharge_arc`, `form_shown` for zap) | An `arc` effect part (its length the cue's size); the discharge's colour leaves `reaction_colors` |
| 9 | The staff swap's poof that follows the body (`_on_staff_shown`, `POOF_*`) | A cue `staff_swap`, once `CueContext` can follow a node with an offset. Its timing is tied to `StaffLook`'s swap, so it is checked frame by frame |
| 10 | Particles in the other shot shaders: the swing's sparks and card particles (`shot_swing.gdshader`) and a beam's splash and card particles at its end (`shot_beam.gdshader`) | Motes through the births, like the trails' (P1d); the swing's line and the beam stay shapes. They give off every frame, so after S4 |
| 11 | A status's particles around a body (`shot_status.gdshader`'s loop) and the status colours and looks (`FeelPreset.status_order`, `status_looks`) | The glow that follows the body stays code; a status's colour and look come from its element card (`tint`, `look_layer`), and its particles become that card's motes from a slow emitter. Freeze and chill must still read apart |
| 12 | The torch's painted glow, drawn as well as its light with Spell light on | Hidden while Spell light is on (the `light_spot` is the torch's light); a "mote spot" for embers rising from a torch, if wanted |
| 13 | Moments with no look at all: a horde level-up, a gem picked up, a revive, a wizard's shield blocking a hit, a magnet pull, a wave starting | Cues, each one `cue_shown` from its area, so content can give them a look. A gem pickup can happen hundreds of times a second in a horde: throttled |
| 14 | Hardcoded colours: `FeelPreset.enemy_hit_color`, the horde gems' colours | Data (an enemy's ramp, the gems' as content) |

**Stays code (not moments):** the telegraphs (exact readability: reach, lane width and progress; at most their numbers move into enemy data), beams while they last, shot bodies and the swing's line, the hit flash and squash, body looks (dash afterimages, faces, the decoy), text (reaction names, the downed note), UI drawn in the world (the reticle, revive and protect rings, possession bars, damage numbers), the large batches (the swarm, the gems), and hit-stop and shake (already cue and preset data).

**Built** (owner/cues-moments): item 1 (reactions: `reaction_<id>` cues with the cue's own `color` and `power`; docs/DECISIONS.md).

**Order inside S6:** 1, 2, 7 and 8 need only parts that exist (plus an `arc` entry); then 5, 6, 13 and 14; 4 is a new part type; 9 needs a following `CueContext`; 3, 10 and 11 come after S4, which sets what a mote row costs. S3's own new special case (spray and puff thrown as motes inside `show_effect`) goes when hit flashes become cues (`hit`, and a puff for a hit with no way), under the same storm check as 2.

## Order

```
S1 ─┬─ S2 ──────────┐
    └─ S3 ─┬─ S4 ─── S6 (3, 10, 11)
           ├─ S5      │
           └──────── S6 (the rest, after S2 and S3)
```

S1 first, because S2 and S3 both change what Feel does with motes. S2 and S3 can be built side by side after it (S2 is the kinds and their lookup, S3 the old effects and the trail shader). S4 and S5 after S3 (S5's first steps are quick and come first). S6 after S2 and S3; its particle items after S4. Each is one session with tests, a screenshot sheet where anything is drawn, and `tools/check.sh` plus the suite passing.
