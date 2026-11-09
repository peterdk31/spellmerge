# content/marks: kinds of floor marks

A floor mark is a scorch, a crack, a frost rime, a burn ring, a rune's scar, ichor, char or a settled mote's speck that a cue (or a mote that comes to rest) stamps into the room's mark layer once and that stays until the room ends (docs/milestones/spell-spectacle.md, P2). A kind is one `MarkKind` file (`core/base/mark_kind.gd` documents every field), named `<id>.tres`; the registry finds it by its `id` under `marks`, so a new mark is a new file and no list is edited.

## Contract

- **A cue stamps it.** A cue's part `{"part": &"mark", "mark": &"scorch", "reach": 0.9}` (core/base/cue_base.gd) stamps the mark where the cue plays, `size` x `reach` pixels round (or `radius` pixels), turned at random (or with `"rot": &"aim"` along the cue's way).
- **Marks can come from the spells' cards.** A kind may name the cards it is the mark of by id (`cards`) or by their look layer (`look_layers`), like a mote kind: a card a kind names by id takes no kind by its layer (docs/milestones/spell-spectacle-2.md, S2). A mark part with `"cards": true` stamps the marks of the cue's spell's cards instead of its own when they have any: a frost blast leaves frost, a fire or plain blast its scorch. A card gets a mark of its own with one new file naming it in `cards`.
- **Settled motes.** A mote kind that names a mark (`MoteKind.settles`, content/motes) leaves it where each of its motes comes to rest, once it lies still, at most `SETTLED_PER_FRAME` (512) a frame (the rest fade with their motes).
- **No colours here** (docs/STYLE.md: a mark is at most the shadow and base shades of its material). Its body and its edge each say where their colour comes from: `floor`, the room floor's own art as it is shown (`RoomBase.floor_colors`: sampled from the `Floor` sprite times its modulate, or the room's `floor_mark_colors`), `spell`, what made it (the shot's own ramp, the caster's colours or its card's tint as the shot shaders pick them; a settled mote's own ramp), or `surface`, the surface the cue is about (a dying body's own art, else the room's walls; the ramp table's row, as the surface motes take it); and which shade, `base` or `shadow`. Pixels are hard: a pixel is its colour or nothing.
- **Its shape is worked out by `gameplay/feel/mark.gdshader`** from `form` and its numbers, at any size, one pixel a line: `blot` (a ragged patch, solid in its middle, its rim speckled in the edge colour; `rough`, `fill`), `crack` (`lines` jagged lines out of a crushed middle, each forking once; `rough`), `rime` (a patch of film specks with small crosses in the edge colour; `rough`, `fill`), `ring` (a ragged band at its rim, specks thrown in and out of it in the edge colour; `rough`, `fill`), `rune` (a circle at its rim and one inside it in the edge colour, `lines` hooked strokes between them) or `speck` (one pixel). The shader holds at most 16 kinds (`Marks.MAX_KINDS`).
- Marks stay off the walls (the shader is clipped by the projectile manager's wall grid) and lie on the floor under every body.
- `tests/gameplay/feel/test_marks.gd` checks every file (`problems()`) and that every mark a cue names exists; `tests/screenshots/shot_marks.gd` draws each in the crypt arena at 1x and 4x.

| Mark | Form | Look layers | Body | Edge | Stamped by |
|---|---|---|---|---|---|
| `scorch` | blot | none | floor shadow | spell shadow | `blast`, `fireball` |
| `crack` | crack | none | floor shadow | floor shadow | `slam`, `quake` |
| `frost` | rime | 2 (frost) | spell shadow | spell base | a frost card's `blast` or `fireball` (`cards`) |
| `char` | crack | 5 (lightning) | spell shadow | floor shadow | a lightning card's `blast` or `fireball` (`cards`) |
| `burn_ring` | ring | none | floor shadow | spell shadow | `nova` (the Nova card's cue), round its caster |
| `rune_scar` | rune | none | spell shadow | floor shadow | `rune_burst`, where a rune goes off |
| `ichor` | blot | none | surface shadow | surface base | `enemy_death`, `boss_death`: the body's own colours, a dull sap |
| `speck` | speck | none | spell shadow | spell shadow | a settled mote (`chip`, `fleck`), in its own colours |

## Allowed files

`.tres` and `.uid` files. Limit: 1 MB per file.

## Example to copy

`scorch.tres`: copy it, give it a new `id` and file name, pick its form and colours, and name it in a cue's mark part.
