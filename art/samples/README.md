# Art direction samples

The record of the art direction choice (M2 part 27). The owner picked **N** (round five), and the game's wizard was redrawn in it. **Nothing in the game uses these files;** they stay as the record. The sheet scripts (`tests/screenshots/shot_art_direction*.gd`) were removed on 2026-10-26 and are in the git history.

## Rules

- Do not use these samples in the game, and do not extend them; new art goes under `art/` or a content folder, in the chosen style (docs/STYLE.md).
- They are 32×32 rect SVGs in the shared palette, checked by `tests/core/test_svg_art.gd` like any SVG.
- Exceptions the test allows here only: E's icon is outlined in Fire's dark red instead of `#14121f` (`e_soft/`); I's proposed colours (vivid player ramps, warm floor) are allowed only in `i_warm/` and `hats_vivid/`.
- `tests/core/test_svg_art.gd` names sample files that must be found (`KNOWN`) and the per-folder outlines (`SAMPLE_OUTLINES`): moving or deleting a sample changes that test with it.
- Every sample is listed in `art/manifest.json`.

## The folders

Each sample is a wizard (from round three on, a `body.svg` plus a hat layer per player), and in early rounds a crypt floor tile and a fire icon.

| Round | Folders | What they tried |
| --- | --- | --- |
| 1 (#190) | `a_chunky/`, `c_grim/` (B was the then placeholder) | Chunky cartoon; grim hooded cloak |
| 2 (#190) | `d_hood/`, `e_soft/`, `f_bighat/` | A's face in C's hood; no black outline; a hat as big as the body |
| 3 (#192) | `g_brown/`, `h_cream/`, `i_warm/`, `hats_std/`, `hats_vivid/` | Only the hat in the player's colour; a warm palette proposal (I) |
| 4 (#206) | `j_tiny/`, `k_bean/`, `l_gold/` | A smaller body and a big cute face |
| 5 (#206) | `m_cream/`, `n_dusk/`, `o_teal/` | A robe and a face of two big eyes, no mouth; **N chosen** |

History and reasons (each round's comparison tables and notes): [docs/history/art-samples-README.md](../../docs/history/art-samples-README.md).
