# Flash kinds: a flash's look as data, and effects renamed flashes

**Status: the owner's direction of 2026-11-05.** The owner answered the questions below: (1) the rename: "Yes"; (2) "Effect slots": "Then keep it"; (3) port exactly, then tune: "yes"; (4) new drawings: "Add them" (the star, rays, the dotted ring and the spiral, F4). Written as a proposal after the owner asked whether effects and motes should be one system. The answer was no: a mote is a particle that flies by itself after one row write, and a flash is one shaped glow (a cross, a ring, a column) whose shader draws it whole, so neither can become the other without losing what it is for (`content/cues/README.md`, `content/motes/README.md`). But one gap stands out: a mote kind, a mark kind and a cue are each a new file, while a new flash shape is code. The owner's goal for spell spectacle 2 was "It should be easy to add new effects, and when adding new content, there should be minimal coupling to this code." Flashes are the one look that still does not meet it.

Like spell spectacle 2, this changes no damage, hit, rule or card behaviour. Everything here is drawn.

## What is wrong today

- **A flash is code in four places.** A new look needs a `KIND_*` and its seconds in `gameplay/feel/feel.gd`, a row in `CUE_EFFECTS` (its step in pixels, its seconds, look bits), a branch in `shot_effect.gdshader`'s vertex stage (its sizes and colours over its life), a name in `CueBase.EFFECTS`, and a row in `SpellLight.EFFECT_LIGHT` (how much it lights the room; a test names each code).
- **Only 16 kind codes.** The kind travels beside its age in one float (`1 - (kind + age) / 16`, `coded_kind` in `shot_palette.gdshaderinc`), so each shader knows 16 kinds at most. The effect batch uses 9, the floor batch 1, the blast batch 2, the arc and status batches 1 each.
- **One look is a bit trick.** The staff's `poof` is a puff with the `POOF` look bit (`CUE_EFFECTS`' fifth column), because a kind of its own had no clean home.
- **The name says less than it should.** "Effect" also means a status effect, a card's effect and a modifier's behaviour going off, and `effect_slots` covers flashes, arcs and statuses together. The newer code and docs already say "flash": `cue_plan.gd`'s `Flash`, the cues README ("A flash draws its shape and its light only"), the shader's own header ("Feel's flashes").

## The idea

**The shaped flashes are already built from a few parts.** Every flash the effect batch draws (`burst`, `cast`, `spray`, `puff`, `ring_out`, `ring_in`, `rune_burst`, `rise`, `fall`) is some of the same five parts, drawn by one small fragment stage that has no per-kind code:

| Part | Its numbers |
|---|---|
| a cross | arm length (pixels) |
| a dotted disc | reach |
| a ring | radius; round, diamond or flat on the floor; how it frays with age; its hash salt |
| a column | half width, top, foot, dotted or not |
| its light | brightness, a falloff round the ring (strength, reach), a falloff round the middle (strength, reach) |

and two colours (the first and second), each a shade of the shot's ramp (white-hot, light, base, shadow). Only the **vertex stage** knows the kinds: per kind, it works out those numbers from the age. So a kind is a set of curves over its life, which is data.

**A `FlashKind` per file** (`core/base/flash_kind.gd`, `content/flashes/<id>.tres`, found by the registry under `flashes`, like `MoteKind` and `MarkKind`):

- `id`, `seconds`, `step` (pixels a zoom step is, for a cue part's `reach`), `light` (how much it lights the room; replaces `EFFECT_LIGHT` and `BLAST_LIGHT`), `floor` (drawn under the bodies, as the quake is).
- One **curve** per number above, over the flash's life (0 to 1): up to four keys, each an age and a value, with the way between two keys (`linear`, `out`, `in`, `hold`). A value is in zoom steps unless the curve says `px`; a part with no keys is not drawn. `out` is today's `ease` (1 - (1 - t)^2), `in` is t^2, `hold` a step: between them they give every curve the vertex stage has today (the burst's arm shrinking to nothing by 40%, the fall's streak striking the floor in its first 18%, the rise's foot lifting off after 50%).
- The two **colours** as shade keys over its life (`hot` until 0.15, then `hi`, as `ramp_of` does).
- `problems()`, as `MoteKind`'s: keys in order, ages within 0 to 1, ways known, at least one part drawn.

**The shader reads them from a table,** as the motes do (`kind_table`): a texture of a row a kind, each curve's keys a few texels, handed over when the batch is made, room for 256 kinds. The vertex stage evaluates each curve (a fixed four keys, no open loops, so it stays small for ANGLE and Direct3D: the WebGL crash of #359 came from a huge shader); the fragment stage is unchanged. The flash batch gets a kind code of its own with room for 256 (its kind as a whole number, its age beside it), and spell light reads the same.

**Some flashes stay drawn by code,** because they are not those parts: the quake's cracks, the poof's bone clouds, the blast's shell and the fireball (`shot_blast.gdshader`, 22 pieces), the lightning arc. Each still gets a `FlashKind` file with its seconds, step, light and layer, and names its drawing (`draw = &"quake"`), so every flash a cue can name is a file, `CUE_EFFECTS` and `CueBase.EFFECTS` go, and the poof is a kind of its own instead of a look bit. A new drawing (a star with n points, rays, a spiral) is code once, a few lines of shader; after that any number of looks use it by data.

**Statuses are not flashes.** A status's glow lasts as long as the status and follows its body. It keeps its own shader and batch, and keeps sharing the slots.

## The rename: effect to flash

Recommended, as its own commit before the rest, with no change to the look. It matches what the newer code and docs already say, and it frees "effect" for the meanings players see (a status effect, what a card does).

- The cue part: `"effect": &"burst"` becomes `"flash": &"burst"` in the 60 cue files that have one, `CueBase` and `cue_plan.gd`, and the part type `effect` becomes `flash` (the default when a part names none). Cue files are content, not saves, so nothing old has to load.
- In Feel: `show_effect` to `show_flash`, `_effect_*` to `_flash_*`, `effect_mesh` to `flash_mesh`, `live_effects`, `effects_of`, `effect_dress`, `effect_info` likewise, and the tests that call them (about 20 files). `shot_effect.gdshader` becomes `shot_flash.gdshader` (its `.uid` moves with it, and `ShaderWarmup` names it).
- **"Flash" already means the hit flash** (a sprite turning white when hit: `FLASH_SHADER`, `FeelPreset.flash_seconds`, `flashing()`, the horde's `SwarmLook`). Feel's become `HIT_FLASH_SHADER`, `_hit_flash_material` and `hit_flash_seconds`, so "flash" alone in Feel always means a flash kind. No `.tres` sets `flash_seconds` today. **Built:** `SwarmLook` keeps its own row arrays and `flashing()` (its hit flash, inside its own file).
- **The "Effect slots" setting:** its slots hold flashes, arcs and statuses, so the player-facing name and the saved key can stay as they are, or become "Flash slots" (the saved key read under both names for one release). The owner picks.

## Steps

Each is one PR with tests, `tools/check.sh` and the suite passing.

| # | What | Size |
|---|---|---|
| F1 | **The rename.** Mechanical, no look change: the cue trace (S1's: every mote, mark and flash slot hashed over a fixed list of events) the same before and after | about 90 files, most of them one-word edits (60 cues, about 20 tests); low risk |
| F2 | **The shaped flashes as data.** `FlashKind`, its table, the vertex stage reading it; the nine shaped kinds as files; `EFFECT_LIGHT` into the kinds; `content/flashes/README.md` with an example to copy | the real work: the vertex stage's 120 lines of branches become about 60 of table reading; `flash_kind.gd` about 200 lines; nine `.tres` |
| F3 | **Built with F2** (DECISIONS, 2026-11-05). **The coded flashes as kinds.** Quake, poof, shell, fireball and arc as files naming their drawing; `CUE_EFFECTS`, `CueBase.EFFECTS`, the `POOF` bit and the KIND_* codes the cues use go; `BLAST_LIGHT` into the kinds | small to medium |
| F4 | **Optional, the owner's call:** new drawings (a star, rays, a dotted ring) and a pick sheet of new flash looks made from them as data | per drawing, small |

**F2 must look the same, pixel for pixel.** The screenshot sheets are not the same from run to run (real-time clocks), so the check is a test that draws every shaped kind both ways at fixed ages (eight points of its life, zoom 1, 2 and 4, two aims, one hat ramp and the enemy ramp), the old vertex stage kept beside the new one while the PR is built, and compares the pixels exactly; the DECISIONS entry records it, and the old stage is deleted before merging. A rounding left out (the burst's arm is `round()`ed, a column's width `floor(x + 0.5)`) shows up there.

**Measured before F2 merges** (the owner's rule: the web storm on a real GPU, `~/spellmerge-gpu-harness/webstorm.sh`): the vertex stage reads more texels (about 15 curves of up to four keys, for each of an instance's six quads), against today's per-kind branches. At 256 slots that is small, but Intel UHD and the web are where it shows. The shader's first compile time is checked on the real-GPU harness too.

## Questions for the owner

1. **Do the rename (F1)?** Recommended.
2. **"Effect slots" stays, or becomes "Flash slots"?** Recommended: it stays (it also holds the statuses and arcs, and players already know the word).
3. **Port exactly, then tune?** Recommended: F2 looks exactly as today, and new looks or tuning come after as data, on a pick sheet.
4. **New drawings (F4)?** Which, if any: a star with n points (the parry's star is a big burst today), rays, a dotted ring, a spiral.

**Built:** F1 (the rename) and F2 with F3 folded in (the kinds as data; DECISIONS, 2026-11-05, "Flash kinds are data").

## Order

```
F1 ── F2 ── F3 ── F4 (optional)
```

F1 first, so the new files and code are born with the new name. F2 before F3, because F3's kinds are the same files with a `draw` named.
