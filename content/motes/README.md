# content/motes: kinds of motes

A mote is a single pixel (or a 2x2 chunk) with no game logic that Feel throws where things happen (docs/milestones/spell-spectacle.md, P1). A kind is one `MoteKind` file (`core/base/mote_kind.gd` documents every field), named `<id>.tres`; the registry finds it by its `id` under `motes`, so a new kind is a new file and no list is edited.

## Contract

- **Kinds come from the spells' cards** (docs/milestones/spell-spectacle-2.md, S2). A kind names the cards it is the motes of, by id (`cards`: a form, an element or a modifier), or by their look (`look_ids`: the `look_id` of an element or modifier, by name, `core/base/look_names.gd`; `plain` for a shot with none). A card's motes are the kinds that name it by id; a card no kind names takes the kinds of its look. A shot sheds every kind of its spell's cards, its burst split between them, so a combination sheds a mix. A shot whose cards have none sheds the kinds of layer 0. A swing and a beam give off theirs the same way (a swing's sparks and a beam's splash are layer 0's, their card particles their cards'; S6 item 10), and a character with a status gives off its element card's round it (S6 item 11). The spell is found through the shot's tag (`gameplay/feel/card_kinds.gd`), so nothing is added to the shot; an enemy's shot, which has no spell, sheds by its look layers.
- **A `surface` kind** belongs to no card: it is what a struck wall sheds. A room may name its own instead (`RoomBase.surface_kinds`: a wooden room's splinters).
- **A `dash_path` kind** belongs to no card either: every dash gives it off along its path (its speed streaks; spell-spectacle-2.md, S5), in the dasher's colours, beside its cards' kinds.
- **A `tail` kind** belongs to nothing else either: every flying shot lays its tail in one tail kind, by distance (about one every 2 px of its path, the projectile manager's `_lay_tail`), in the shot's own colours (a quarter of an infused shot's in its caster's), beside its cards' kinds (spell-spectacle-2.md, S5 step 4: tails as motes). Which one is the shot's own: each shot picks one of the tail kinds by its sequence (A, B, C: the first three by id; the owner, 2026-11-05: "keep all three and make the shots randomly pick one"), so a new tail kind beyond three is never laid until `TAIL_KINDS` grows. A tail mote barely moves, starts light and cools to shadow, so a tail cools where the shot was.
- **A still card's own** (`FormBase.look_motes`, `look_mote_rate`, `look_motes_from`; the owner, 2026-11-09: "use motes for everything you can"): a still carrier's shots give off the kind the card names all the time while they stand, from the oval of their hit size or along their piece of a row (`gameplay/feel/still_motes.gd`, from the rows the projectile manager draws them by), in the shot's colours, its infusions in turn, a share of them its infusions' own kinds.
- **A kind may name nothing:** then it is thrown only where something names it, a cue's `motes` part (`{"part": &"motes", "kind": &"ash", "colours": &"surface"}`: the fireball's ash, in the colours of what burned) or a room's `surface_kinds`.
- **A kind that falls can settle** (`settles`, a mark kind's id in `content/marks/`; docs/milestones/spell-spectacle.md, P2b): each of its motes leaves that mark in the floor mark layer where it comes to rest, in its own colours, once it lies still. Chips and frost's flecks settle as a `speck`, so debris stays on the floor after it has cooled. However it was thrown (a hit, a cue, a trail): a frost bolt's trail leaves specks where its flecks rest. In a flood at most `Motes.SETTLE_ROWS` settle a frame; the rest just fade.
- **No colours here.** A spell's motes cool through the shot's own ramp (its caster's colours or its card's tint, as the shot shaders pick them); a surface kind's through the room's wall colours (`RoomBase.surface_colors`, sampled from the room's art). A kind says only how many shades it skips at first (`shade_from`) and how strongly it glows while hot.
- **Its shape is data too, drawn as text.** `shape` is a picture: one row a line, up to 5x5 pixels, centred on the mote (rows start at the left as written); `#` a pixel in its shade, `o` one in the shade hotter (a highlight), `.` none. Several frames are pictures apart by a blank line. In the inspector it is a text box; in the `.tres` it reads like this (fleck's: three plain frames, then a glint):

  ```
  shape = "
  #

  #

  #

  .o.
  o#o
  .o.
  "
  ```
 `shape_play` says how the frames go: `life` through them over its life (a streak that shortens as it slows), `loop` round them `shape_rate` a second (a flicker, a glint), `pick` one for each mote (mixed sizes). With `shape_turns` the shape turns with the way the mote flies (8 ways; +x of the shape is ahead). A new look is a new shape string, not a shader edit.
- **The numbers** say how one flies (gravity on a fake height, drag along the floor, one bounce, a sway) and how a burst throws it (count, speed, spread, up, life, height). The shader is handed them when the pool is made, a row of a texture a kind (`kind_table`), so there is room for 256 kinds (`Motes.MAX_KINDS`) and a new kind needs no shader edit.
- `tests/gameplay/feel/test_motes.gd` checks every file (`problems()`), and `tests/screenshots/shot_motes.gd` draws each element's motes and a wall's.

| Kind | Look layers | What it is | Shape |
|---|---|---|---|
| `spark` | 0 (a shot with none), 5 (lightning) | fast and short, glowing | a streak along its flight that shortens over its life (`##o`, then `#o`, then `o`) |
| `ember` | 1 (fire) | rises, sways and cools | a flickering pixel (`o`, `o`, `#`, `.` looping) |
| `fleck` | 2 (frost) | falls, glints and lies; settles as a `speck` | a pixel that glints into a plus now and then |
| `wisp` | 3 (storm) | blown along, swaying | a dash along its drift |
| `murk` | 4 (void) | slow, sinking specks | a pixel or a 2x2 chunk |
| `glimmer` | 6 (mend) | drifts up softly, glowing | a plus that shrinks to a pixel |
| `chip` | surface | knocked off a struck wall; bounces once and lies; settles as a `speck` | a pixel, or now and then a 2x2 chunk |
| `grit` | card `heavy` | heavy's own: falls hard, bounces a little and lies (a demo of a card's own motes) | a pixel or two across |
| `streak` | none (`dash_path`: every dash's path, S5) | a dash's speed streaks, flung back from beside the body in the dasher's colours, short and quick | a line along its flight (`##o`, then `#o`) |
| `dust` | none (named by the `dash_start` cue) | kicked up off the floor where a dash leaves, in the room's colours; drifts and settles | a pixel |
| `ash` | none (named by the `fireball` cue) | drifts up, sways and settles slowly, light at first and cooling grey, in the colours of what burned | a pixel, or two on a slant |
| `tail` | none (`tail`, A) | a shot's tail as single pixels, as the tail shader drew it: a thin line that cools where the shot was | a pixel |
| `tail_streak` | none (`tail`, B, the default) | a shot's tail as short streaks along its way, overlapping into one line | a line along its way that shortens over its life (`###`, `##`, `#`) |
| `tail_long` | none (`tail`, C) | a longer, smoky tail: lives twice as long, drifts up and sways | a pixel |
| `rising` | none (named by still cards: `look_motes` of the wall and the pool, gameplay/feel/still_motes.gd) | given off all the time by a still carrier's shots while they stand: a wall's stream rising off its seam, a pool's motes rising off its mire; climbs slowly, white-hot at first and cooling, twinkling | a pixel, now and then a hotter one, now and then a little plus |
| `ward` | none (the barriers' shells, gameplay/feel/barriers.gd) | a barrier's bubble: standing still on its shell, twinkling white-hot to light; knocked off by a block, it flies out and slows, cooling | a pixel, now and then a hotter one |

## Allowed files

`.tres` and `.uid` files. Limit: 1 MB per file.

## How to give a card motes of its own

One new file: copy `grit.tres`, give it a new `id` and file name, put the card's id in `cards`, and change its numbers. The card's own file is not touched. A spell with that card sheds it (on a hit, at its end, off a wall, along its trail, and in its cues' `spell` parts) besides its other cards' kinds; every other card on the same look layer keeps that layer's.

## Example to copy

`ember.tres`: copy it, give it a new `id` and file name, name the look layers (or the cards) it is the motes of, and change its numbers.
