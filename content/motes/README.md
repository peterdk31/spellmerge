# content/motes: kinds of motes

A mote is a single pixel (or a 2x2 chunk) with no game logic that Feel throws where things happen (docs/milestones/spell-spectacle.md, P1). A kind is one `MoteKind` file (`core/base/mote_kind.gd` documents every field), named `<id>.tres`; the registry finds it by its `id` under `motes`, so a new kind is a new file and no list is edited.

## Contract

- **Kinds come from the spells.** A kind names the cards' look layers it is the motes of (`look_layers`: the `look_layer` of an element or modifier, the LOOK_* kinds of core/projectiles). A shot sheds every kind of its cards' layers, its burst split between them, so a combination sheds a mix and a new card brings its motes through the look layer it already has. A shot whose layers have no kind sheds the kinds of layer 0.
- **A `surface` kind** belongs to no card: it is what a struck wall sheds.
- **No colours here.** A spell's motes cool through the shot's own ramp (its caster's colours or its card's tint, as the shot shaders pick them); a surface kind's through the room's wall colours (`RoomBase.surface_colors`, sampled from the room's art). A kind says only how many shades it skips at first (`shade_from`) and how strongly it glows while hot.
- **The numbers** say how one flies (gravity on a fake height, drag along the floor, one bounce, a sway) and how a burst throws it (count, speed, spread, up, life, height). The shader is handed them when the pool is made; it holds at most 16 kinds (`Motes.MAX_KINDS`).
- `tests/gameplay/feel/test_motes.gd` checks every file (`problems()`), and `tests/screenshots/shot_motes.gd` draws each element's motes and a wall's.

| Kind | Look layers | What it is |
|---|---|---|
| `spark` | 0 (a shot with none), 5 (lightning) | fast and short, glowing |
| `ember` | 1 (fire) | rises, sways and cools |
| `fleck` | 2 (frost) | falls, glints and lies |
| `wisp` | 3 (storm) | blown along, swaying |
| `murk` | 4 (void) | slow, sinking specks |
| `glimmer` | 6 (mend) | drifts up softly, glowing |
| `chip` | surface | knocked off a struck wall; bounces once and lies |

## Allowed files

`.tres` and `.uid` files. Limit: 1 MB per file.

## Example to copy

`ember.tres`: copy it, give it a new `id` and file name, name the look layers it is the motes of, and change its numbers.
