# content/motes: kinds of motes

A mote is a single pixel (or a small shape) with no game logic that Feel throws where things happen. A kind is one `MoteKind` file (`core/base/mote_kind.gd` documents every field), named `<id>.tres`; the registry finds it by `id` under `motes`. A new kind is a new file; no list is edited.

## Contract

- **Kinds come from the spells' cards.** A kind names the cards it belongs to by id (`cards`) or by look (`look_ids`, names from `core/base/look_names.gd`; `plain` for none). A card's motes are the kinds naming it by id, else those of its look. A shot sheds every kind of its spell's cards (found through its tag, `gameplay/feel/card_kinds.gd`); cards with none shed layer 0's.
- **A `surface` kind** is what a struck wall sheds (a room may name its own: `RoomBase.surface_kinds`).
- **A `dash_path` kind** is given off along every dash's path.
- **A `tail` kind** lays flying shots' tails (`_lay_tail` in the projectile manager); each shot picks one of the first three tail kinds by id (`TAIL_KINDS`).
- **A still card's own**: `CarrierCard.look_motes`, a list of `CardMoteStream` (`core/base/card_mote_stream.gd`), given off by `gameplay/feel/still_motes.gd`.
- **A kind may name nothing**: then only a cue's `motes` part, a room's `surface_kinds` or a `MoteSource` throws it.
- **`settles`**: a mark kind's id in `content/marks/` left where each mote comes to rest (at most `Motes.SETTLE_ROWS` a frame).
- **`lit_only`**: drawn only where light falls (`gameplay/feel/mote.gdshader`); never settles, never glows, not drawn with "Dynamic lighting" off; choose colours whose shadow shade reads on the floor. A room's air names one (`RoomBase.air`).
- **`stirred`** (0 to 1): dragged by passing shots and blasts (`stirs.gd`).
- **No colours here.** Spell motes cool through the shot's ramp, surface kinds through the room's wall colours (`RoomBase.surface_colors`). A kind says only `shade_from` and how strongly it glows.
- **Shape is data, as text.** `shape`: one row a line, up to 5x5, `#` a pixel, `o` a hotter one, `.` none; frames apart by a blank line. `shape_2x`: the same at the art's detail, up to 11x11 (`MoteKind.SHAPE_CELL`), as many frames in the same order; drawn by hand, lit from the top-left, never `shape` doubled. Every kind a spell, hit, death or cue throws has a `shape_2x`. `shape_play`: `life`, `loop` (`shape_rate`) or `pick`; `shape_turns` turns it with its flight. A new look is a new shape string, not a shader edit.
- **The numbers** say how it flies and how a burst throws it; they go to the shader in `kind_table`, up to `Motes.MAX_KINDS` (256) kinds, so a new kind needs no shader edit.

```
shape = "
#

.o.
o#o
.o.
"
```

## Kinds

By look layer: `spark` (0, 5), `ember` (1), `fleck` (2), `wisp` (3), `murk` (4), `glimmer` (6), `droplet` (22), `oil_drip` (23). By card: `grit` (`heavy`). Surface: `chip`. Dash: `streak`. Tails: `tail`, `tail_streak` (default), `tail_long`. Named by cues: `dust`, `bit`, `ash`, `glob`, `drain`. Still cards: `rising`, `seam`, `drip`. Barriers: `ward`. `MoteSource`s and rooms: `rim_ember`, `pit_dust`, `falling_dust`, `rim_drip`, `air_dust`, `air_glimmer` (lit only), `void_drift`. Cover: `smoke`. Each file says what it is.

## How to make something in the world give off motes

| What gives them off | How | Where it is described |
|---|---|---|
| A thing that stands in the world: a room's art, a prop in one of its states | a **`MoteSource`** on a node (below) | here; `core/base/mote_source.gd` |
| A still spell's shots (a wall, a pool, a rune) | its card's `look_motes`, a list of `CardMoteStream` | "A still card's own", above |
| A moment (a hit, a blast, a cast) | a `motes` part of its cue | `core/base/cue_base.gd`, content/cues |
| Ground cover in a state | its state's `motes` (`MoteSource`s, a cell's rate) | content/cover/README.md; `gameplay/feel/cover_motes.gd` |

### A `MoteSource`

One stream of one kind, given off while its node is in the tree (`gameplay/feel/source_motes.gd`; nothing in the game reads it). Fields (`core/base/mote_source.gd`): `kind` (required), `rate` (4/s at Full particles), `colours` (palette materials by name, `core/base/palette.gd`; never a player's colour nor Blight; empty: its art's colours), `band_length`, `from` (`point`, `line`, `area`, `rim`, `mask`), `way`, `spread`, `reach`, `height`, `spacing`, `start`, `stop`, `stand`, `life` (`stand` on a few dozen pixels only).

**On a room's art** (rooms carry no scripts): a `Node2D` in the group `mote_source`, the resource as metadata `mote_source`, and for a mask or art colours the metadata `mote_art` (a `Sprite2D` path); see `content/rooms/hub/hub.tscn`'s `Rim`. In code: `MoteSource.put(node, source, art_path)` before the node is added; `MoteSource.put(node, source, art, true)` (`mote_follow`) for a node that moves. **On a prop**: `PropLayer.motes` (content/props/README.md).

- A source is read once, the frame after its node appears; it follows its node only with `mote_follow`.
- Only sources within `VIEW_MARGIN` (64 px) of the view give off.
- **Nothing fails silently**: a source that gives off nothing logs once, naming its node.
- A card's stream is not a `MoteSource` (different units); both pick places from `gameplay/feel/mote_places.gd`.
- **A new kind of place** (`from`): a value of `MoteSource.From`, a class in `gameplay/feel/mote_places.gd` (`read`, `pick`) and a line in its `make`.

## Allowed files

`.tres` and `.uid` files. Limit: 1 MB per file.

## How to give a card motes of its own

Copy `grit.tres`, give it a new `id` and file name, put the card's id in `cards`, change its numbers. The card's own file is not touched.

## Example to copy

`ember.tres`: new `id` and file name, its look layers (or cards), its numbers.

Tests: `tests/gameplay/feel/test_motes.gd` (every file's `problems()`; the spells' kinds have `shape_2x`), `tests/content/test_mote_sources.gd`, `tests/content/props/test_prop_data.gd`, `tests/gameplay/feel/test_native_motes.gd`; sheet `tests/screenshots/shot_motes.gd`.

History and reasons: [docs/history/content-motes-README.md](../../docs/history/content-motes-README.md).
