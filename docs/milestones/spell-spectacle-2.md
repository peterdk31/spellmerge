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

## S4: A burst a row (an experiment, measured)

Today a mote is a row and every row is a GDScript write. Instead, one row could hold a whole burst: where, which way, the kind, the count, the seed, the source and the time. A burst's batch draws a mesh of `BURST_QUADS` quads (16) a row, and the vertex shader works out each mote from the row, its quad's index and the seed, as the trails already work out their particles. A burst of 40 is three rows instead of 40, and the quads past the count are folded away.

- The CPU cost becomes a write per burst, not per mote, so `FRAME_ROWS` could go up or away and a blast could throw hundreds.
- Settled motes still need each mote's resting point. Either the CPU works it out for the settling kinds only (as now, from the same seed), or the mark layer draws the frame's resting motes from the burst rows itself (one draw into its viewport on frames when motes come to rest).
- The cost moves to the GPU's vertices: 16 quads a row drawn or folded. That is measured against the CPU it saves.

Merged only if the storm's CPU drops and the GPU time on llvmpipe and the Intel UHD does not grow more than that; the result goes in DECISIONS either way. After S3, so fewer callers write rows.

## Order

```
S1 ─┬─ S2
    └─ S3 ─── S4
```

S1 first, because S2 and S3 both change what Feel does with motes. S2 and S3 can be built side by side after it (S2 is the kinds and their lookup, S3 the old effects and the trail shader). S4 after S3. Each is one session with tests, a screenshot sheet where anything is drawn, and `tools/check.sh` plus the suite passing.
